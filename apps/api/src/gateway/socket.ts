import { Server, Socket } from 'socket.io';
import { verifyAccessToken } from '../utils/jwt.js';
import { prisma } from '../utils/prisma.js';
import { LiveKitService } from '../services/livekit.service.js';
import { TrackSource } from 'livekit-server-sdk';

interface ChatMessage {
  id: string;
  senderId: string;
  senderName: string;
  senderRole: string;
  text: string;
  timestamp: string;
}

interface Poll {
  id: string;
  question: string;
  options: Array<{ id: number; text: string; votes: number }>;
  createdBy: string;
  active: boolean;
  votedUserIds: string[];
}

interface RaisedHand {
  userId: string;
  userName: string;
  userRole: string;
  raisedAt: string;
}

// In-memory room state stores
const roomHandQueues = new Map<string, RaisedHand[]>();
const roomActivePolls = new Map<string, Poll[]>();
const roomBoardGrantedStudents = new Map<string, Set<string>>();
const roomBoardStates = new Map<string, boolean>();
const roomChatHistory = new Map<string, ChatMessage[]>();
const hostDisconnectTimers = new Map<string, NodeJS.Timeout>();
const roomStages = new Map<string, 'VIDEO' | 'SCREEN' | 'BOARD' | 'SLIDES'>();
const roomBoardStrokes = new Map<string, any[]>();
export interface RoomDocState {
  isOpen: boolean;
  deckId?: string;
  classId?: string;
  title?: string;
  fileName?: string;
  url?: string;
  streamUrl?: string;
  page?: number;
  currentPage?: number;
  totalPages?: number;
  fileHash?: string;
  stage?: 'SLIDES';
  zoom?: number;
  laser?: { x: number; y: number; visible: boolean };
  annotationsPerPage?: Record<number, any[]>;
}

const roomDocStates = new Map<string, RoomDocState>();
const roomMediaModes = new Map<string, 'OPEN' | 'HAND_RAISE_ONLY'>();
const roomMicLocked = new Map<string, boolean>();
const userClassSockets = new Map<string, string>(); // userId -> socketId

let ioInstance: Server | null = null;

export function getSocketIO(): Server | null {
  return ioInstance;
}

export function emitToUser(userId: string, event: string, data: unknown): void {
  if (ioInstance) {
    ioInstance.to(`user:${userId}`).emit(event, data);
  }
}

export function emitToInstitute(instituteId: string, event: string, data: unknown): void {
  if (ioInstance) {
    ioInstance.to(`institute:${instituteId}`).emit(event, data);
  }
}

export function setupSocketGateway(io: Server) {
  ioInstance = io;

  // 1. JWT Authentication Middleware
  io.use((socket, next) => {
    try {
      const token =
        socket.handshake.auth?.token ||
        socket.handshake.headers?.authorization?.replace('Bearer ', '');

      if (!token) {
        return next(new Error('Authentication token required'));
      }

      const decoded = verifyAccessToken(token);
      socket.data.user = decoded;
      next();
    } catch {
      next(new Error('Invalid authentication token'));
    }
  });

  io.on('connection', (socket: Socket) => {
    const user = socket.data.user;
    const isHost = user.role === 'TEACHER' || user.role === 'ADMIN';

    // Automatically join user personal room and institute room for push/realtime updates
    if (user?.userId) {
      socket.join(`user:${user.userId}`);
    }
    if (user?.instituteId) {
      socket.join(`institute:${user.instituteId}`);
    }

    // Join classroom room
    socket.on('class:join', (data: { classId: string }) => {
      const roomKey = `class:${data.classId}`;
      socket.join(roomKey);
      socket.data.currentClassId = data.classId;

      // If host rejoins, cancel any pending abandonment timer
      if (isHost && hostDisconnectTimers.has(data.classId)) {
        clearTimeout(hostDisconnectTimers.get(data.classId)!);
        hostDisconnectTimers.delete(data.classId);
      }

      // 2.4 One device per user takeover: if same user already in class, disconnect previous device
      const existingSocketId = userClassSockets.get(user.userId);
      if (existingSocketId && existingSocketId !== socket.id) {
        const oldSocket = io.sockets.sockets.get(existingSocketId);
        if (oldSocket) {
          oldSocket.emit('class:takeover', { reason: 'Aap dusre device se join ho gaye' });
          oldSocket.leave(roomKey);
          oldSocket.disconnect(true);
        }
      }
      userClassSockets.set(user.userId, socket.id);

      // Send existing state to joined user
      const hands = roomHandQueues.get(data.classId) || [];
      const polls = roomActivePolls.get(data.classId) || [];
      const chatHistory = roomChatHistory.get(data.classId) || [];
      const isBoardOpen = roomBoardStates.get(data.classId) || false;
      const canDraw = isHost || (roomBoardGrantedStudents.get(data.classId)?.has(user.userId) ?? false);
      const currentStage = roomStages.get(data.classId) || (isBoardOpen ? 'BOARD' : 'VIDEO');
      const docState = roomDocStates.get(data.classId) || null;
      const strokes = roomBoardStrokes.get(data.classId) || [];
      const mediaMode = roomMediaModes.get(data.classId) || 'OPEN';
      const isMicLocked = roomMicLocked.get(data.classId) || false;

      socket.emit('classroom:snapshot', {
        stage: currentStage,
        mode: currentStage,
        mediaMode,
        isMicLocked,
        board: {
          isOpen: isBoardOpen,
          canDraw,
          strokes,
        },
        doc: docState,
      });

      socket.emit('hand:queue', { hands });
      socket.emit('poll:list', { polls });
      socket.emit('chat:history', { messages: chatHistory });
      socket.emit('board:state', { isOpen: isBoardOpen, canDraw, strokes });
      socket.emit('stage:state', { stage: currentStage, mode: currentStage });
      socket.emit('stage:changed', { stage: currentStage, mode: currentStage });
      if (docState) socket.emit('doc:present', docState);

      // Notify others in room
      socket.to(roomKey).emit('peer:joined', {
        userId: user.userId,
        name: user.name,
        role: user.role,
      });
    });

    // Leave classroom room
    socket.on('class:leave', (data: { classId: string }) => {
      const roomKey = `class:${data.classId}`;
      socket.leave(roomKey);
      socket.to(roomKey).emit('peer:left', { userId: user.userId, name: user.name });

      // If host leaves an active room, start 10-minute auto-end timeout
      if (isHost && !hostDisconnectTimers.has(data.classId)) {
        const timer = setTimeout(async () => {
          try {
            await prisma.liveClass.updateMany({
              where: { id: data.classId, status: 'LIVE' },
              data: { status: 'ENDED' },
            });
            io.to(`class:${data.classId}`).emit('class:ended', { reason: 'HOST_TIMEOUT' });
          } catch (err) {
            console.error('Error auto-ending class on host timeout:', err);
          } finally {
            hostDisconnectTimers.delete(data.classId);
          }
        }, 10 * 60 * 1000);
        timer.unref();
        hostDisconnectTimers.set(data.classId, timer);
      }
    });

    /* -------------------------------------------------------------------------- */
    /* DIGITAL WHITEBOARD SYNCHRONIZATION & PERMISSION ENFORCEMENT                */
    /* -------------------------------------------------------------------------- */
    socket.on('whiteboard:draw', (data: { classId: string; stroke: any }) => {
      const canDraw = isHost || (roomBoardGrantedStudents.get(data.classId)?.has(user.userId) ?? false);
      if (!canDraw) return; // Enforce: reject unauthorized draw attempts

      let strokes = roomBoardStrokes.get(data.classId);
      if (!strokes) {
        strokes = [];
        roomBoardStrokes.set(data.classId, strokes);
      }
      if (strokes.length < 2000) {
        strokes.push(data.stroke);
      }

      socket.to(`class:${data.classId}`).emit('whiteboard:draw', data.stroke);
    });

    socket.on('whiteboard:clear', (data: { classId: string }) => {
      const canDraw = isHost || (roomBoardGrantedStudents.get(data.classId)?.has(user.userId) ?? false);
      if (!canDraw) return; // Enforce: reject unauthorized clear attempts

      roomBoardStrokes.set(data.classId, []);
      socket.to(`class:${data.classId}`).emit('whiteboard:clear');
    });

    socket.on('whiteboard:cursor', (data: { classId: string; x: number; y: number }) => {
      socket.to(`class:${data.classId}`).emit('whiteboard:cursor', {
        userId: user.userId,
        userName: user.name,
        x: data.x,
        y: data.y,
      });
    });

    // Stage sync: Teacher sets stage (VIDEO | SCREEN | BOARD | SLIDES)
    socket.on('stage:set', (data: { classId: string; stage?: 'VIDEO' | 'SCREEN' | 'BOARD' | 'SLIDES'; mode?: 'VIDEO' | 'SCREEN' | 'BOARD' | 'SLIDES' }) => {
      if (!isHost) return;
      const targetStage = (data.mode || data.stage || 'VIDEO') as 'VIDEO' | 'SCREEN' | 'BOARD' | 'SLIDES';
      roomStages.set(data.classId, targetStage);
      const isBoard = targetStage === 'BOARD';
      roomBoardStates.set(data.classId, isBoard);
      io.to(`class:${data.classId}`).emit('board:state', { isOpen: isBoard, canDraw: isBoard ? isHost : false });
      io.to(`class:${data.classId}`).emit('stage:state', { stage: targetStage, mode: targetStage });
      io.to(`class:${data.classId}`).emit('stage:changed', { stage: targetStage, mode: targetStage });
    });

    // Host toggles board open/close for all students
    socket.on('board:toggle', (data: { classId: string; isOpen: boolean }) => {
      if (!isHost) return;
      const targetStage = data.isOpen ? 'BOARD' : 'VIDEO';
      roomBoardStates.set(data.classId, data.isOpen);
      roomStages.set(data.classId, targetStage);
      io.to(`class:${data.classId}`).emit('board:state', { isOpen: data.isOpen, canDraw: isHost });
      io.to(`class:${data.classId}`).emit('stage:state', { stage: targetStage, mode: targetStage });
      io.to(`class:${data.classId}`).emit('stage:changed', { stage: targetStage, mode: targetStage });
    });

    // Host presents PPT/PDF document slides to all students
    socket.on('doc:present', (data: {
      classId: string;
      isOpen: boolean;
      deckId?: string;
      title?: string;
      fileName?: string;
      url?: string;
      streamUrl?: string;
      page?: number;
      currentPage?: number;
      totalPages?: number;
      fileHash?: string;
      zoom?: number;
    }) => {
      if (!isHost) return;
      const existing = roomDocStates.get(data.classId) || { isOpen: false };
      const curPage = data.currentPage ?? data.page ?? existing.currentPage ?? existing.page ?? 1;
      const totalP = data.totalPages ?? existing.totalPages ?? 1;
      const deckUrl = data.url || data.streamUrl || existing.url || existing.streamUrl;
      const name = data.fileName || data.title || existing.fileName || existing.title || '';

      const updatedState: RoomDocState = {
        ...existing,
        ...data,
        deckId: data.deckId || existing.deckId,
        isOpen: data.isOpen,
        title: name,
        fileName: name,
        url: deckUrl,
        streamUrl: deckUrl,
        page: curPage,
        currentPage: curPage,
        totalPages: totalP,
        fileHash: data.fileHash || existing.fileHash,
        stage: 'SLIDES',
        zoom: data.zoom ?? existing.zoom ?? 1.0,
      };
      roomDocStates.set(data.classId, updatedState);
      if (data.isOpen) {
        roomStages.set(data.classId, 'SLIDES');
        io.to(`class:${data.classId}`).emit('stage:state', { stage: 'SLIDES', mode: 'SLIDES' });
        io.to(`class:${data.classId}`).emit('stage:changed', { stage: 'SLIDES', mode: 'SLIDES' });
      } else if (roomStages.get(data.classId) === 'SLIDES') {
        roomStages.set(data.classId, 'VIDEO');
        io.to(`class:${data.classId}`).emit('stage:state', { stage: 'VIDEO', mode: 'VIDEO' });
        io.to(`class:${data.classId}`).emit('stage:changed', { stage: 'VIDEO', mode: 'VIDEO' });
      }
      io.to(`class:${data.classId}`).emit('doc:present', updatedState);
    });

    // Page navigation (next/prev/jump)
    socket.on('doc:page', (data: { classId: string; page?: number; currentPage?: number }) => {
      if (!isHost) return;
      const targetPage = data.currentPage ?? data.page ?? 1;
      const docState = roomDocStates.get(data.classId);
      if (docState) {
        docState.page = targetPage;
        docState.currentPage = targetPage;
        roomDocStates.set(data.classId, docState);
      }
      io.to(`class:${data.classId}`).emit('doc:page', { page: targetPage, currentPage: targetPage });
    });

    // Zoom level sync
    socket.on('doc:zoom', (data: { classId: string; zoom: number }) => {
      if (!isHost) return;
      const docState = roomDocStates.get(data.classId);
      if (docState) {
        docState.zoom = data.zoom;
        roomDocStates.set(data.classId, docState);
      }
      io.to(`class:${data.classId}`).emit('doc:zoom', { zoom: data.zoom });
    });

    // Laser pointer broadcast
    socket.on('doc:laser', (data: { classId: string; x: number; y: number; visible: boolean }) => {
      if (!isHost) return;
      const docState = roomDocStates.get(data.classId);
      if (docState) {
        docState.laser = { x: data.x, y: data.y, visible: data.visible };
      }
      socket.to(`class:${data.classId}`).emit('doc:laser', { x: data.x, y: data.y, visible: data.visible });
    });

    // Pen annotations per page
    socket.on('doc:annotate', (data: { classId: string; page: number; stroke: any }) => {
      if (!isHost) return;
      const docState = roomDocStates.get(data.classId);
      if (docState) {
        if (!docState.annotationsPerPage) docState.annotationsPerPage = {};
        if (!docState.annotationsPerPage[data.page]) docState.annotationsPerPage[data.page] = [];
        if (docState.annotationsPerPage[data.page].length < 1000) {
          docState.annotationsPerPage[data.page].push(data.stroke);
        }
        roomDocStates.set(data.classId, docState);
      }
      socket.to(`class:${data.classId}`).emit('doc:annotate', { page: data.page, stroke: data.stroke });
    });

    // Clear annotations for a page
    socket.on('doc:clear_annotations', (data: { classId: string; page: number }) => {
      if (!isHost) return;
      const docState = roomDocStates.get(data.classId);
      if (docState && docState.annotationsPerPage) {
        docState.annotationsPerPage[data.page] = [];
        roomDocStates.set(data.classId, docState);
      }
      io.to(`class:${data.classId}`).emit('doc:clear_annotations', { page: data.page });
    });

    // Helper to get LiveKit room name for a class
    async function getRoomNameForClass(classId: string): Promise<string> {
      try {
        const room = await prisma.liveClass.findUnique({
          where: { id: classId },
          select: { livekitRoom: true },
        });
        return room?.livekitRoom || `room-${classId}`;
      } catch {
        return `room-${classId}`;
      }
    }

    // Media mode & mic locks (OPEN | HAND_RAISE_ONLY)
    socket.on('media:mode:set', async (data: { classId: string; mode: 'OPEN' | 'HAND_RAISE_ONLY' }) => {
      if (!isHost) return;
      roomMediaModes.set(data.classId, data.mode);
      io.to(`class:${data.classId}`).emit('media:mode:state', { mode: data.mode });

      const isLocked = data.mode === 'HAND_RAISE_ONLY';
      roomMicLocked.set(data.classId, isLocked);
      io.to(`class:${data.classId}`).emit('host:muted', { isLocked });

      try {
        const roomName = await getRoomNameForClass(data.classId);
        const participants = await LiveKitService.listParticipants(roomName);
        for (const p of participants) {
          const meta = p.metadata ? JSON.parse(p.metadata) : {};
          if (meta.role !== 'TEACHER' && meta.role !== 'ADMIN') {
            await LiveKitService.updateParticipantPermissions(roomName, p.identity, !isLocked);
          }
        }
      } catch {
        // ignore in dev/offline
      }
    });

    socket.on('host:muteAll', async (data: { classId: string; lock?: boolean }) => {
      if (!isHost) return;
      if (data.lock) {
        roomMicLocked.set(data.classId, true);
      }
      io.to(`class:${data.classId}`).emit('host:muted', { isLocked: !!data.lock });

      try {
        const roomName = await getRoomNameForClass(data.classId);
        await LiveKitService.muteAll(roomName);
        if (data.lock) {
          const participants = await LiveKitService.listParticipants(roomName);
          for (const p of participants) {
            const meta = p.metadata ? JSON.parse(p.metadata) : {};
            if (meta.role !== 'TEACHER' && meta.role !== 'ADMIN') {
              await LiveKitService.updateParticipantPermissions(roomName, p.identity, false);
            }
          }
        }
      } catch {
        // ignore in dev
      }
    });

    socket.on('host:unlockMic', async (data: { classId: string }) => {
      if (!isHost) return;
      roomMicLocked.set(data.classId, false);
      io.to(`class:${data.classId}`).emit('host:unlocked');

      try {
        const roomName = await getRoomNameForClass(data.classId);
        const participants = await LiveKitService.listParticipants(roomName);
        for (const p of participants) {
          const meta = p.metadata ? JSON.parse(p.metadata) : {};
          if (meta.role !== 'TEACHER' && meta.role !== 'ADMIN') {
            await LiveKitService.updateParticipantPermissions(roomName, p.identity, true);
          }
        }
      } catch {
        // ignore in dev
      }
    });

    socket.on('host:allowSpeak', async (data: { classId: string; studentId: string }) => {
      if (!isHost) return;
      emitToUser(data.studentId, 'host:allowSpeak', { classId: data.classId });
      try {
        const roomName = await getRoomNameForClass(data.classId);
        await LiveKitService.updateParticipantPermissions(roomName, data.studentId, true);
      } catch {
        // ignore in dev
      }
    });

    socket.on('host:student:action', async (data: {
      classId: string;
      studentId: string;
      action: 'MUTE_MIC' | 'ALLOW_MIC' | 'STOP_CAM' | 'REMOVE';
    }) => {
      if (!isHost) return;
      try {
        const roomName = await getRoomNameForClass(data.classId);
        if (data.action === 'MUTE_MIC') {
          await LiveKitService.muteParticipantTrack(roomName, data.studentId, TrackSource.MICROPHONE);
          emitToUser(data.studentId, 'host:muted', { isLocked: true });
        } else if (data.action === 'ALLOW_MIC') {
          await LiveKitService.updateParticipantPermissions(roomName, data.studentId, true);
          emitToUser(data.studentId, 'host:allowSpeak', { classId: data.classId });
        } else if (data.action === 'STOP_CAM') {
          await LiveKitService.muteParticipantTrack(roomName, data.studentId, TrackSource.CAMERA);
          emitToUser(data.studentId, 'host:stopCamera', { classId: data.classId });
        } else if (data.action === 'REMOVE') {
          await LiveKitService.removeParticipant(roomName, data.studentId);
          emitToUser(data.studentId, 'class:removed', { reason: 'Teacher ne aapko class se remove kiya' });
        }
      } catch {
        // ignore in dev
      }
    });

    // Host grants student drawing permission
    socket.on('board:permission:grant', (data: { classId: string; studentId: string }) => {
      if (!isHost) return;
      let grantedSet = roomBoardGrantedStudents.get(data.classId);
      if (!grantedSet) {
        grantedSet = new Set<string>();
        roomBoardGrantedStudents.set(data.classId, grantedSet);
      }
      grantedSet.add(data.studentId);
      io.to(`class:${data.classId}`).emit('board:permission', {
        studentId: data.studentId,
        canDraw: true,
      });
    });

    // Host revokes student drawing permission
    socket.on('board:permission:revoke', (data: { classId: string; studentId: string }) => {
      if (!isHost) return;
      const grantedSet = roomBoardGrantedStudents.get(data.classId);
      if (grantedSet) {
        grantedSet.delete(data.studentId);
      }
      io.to(`class:${data.classId}`).emit('board:permission', {
        studentId: data.studentId,
        canDraw: false,
      });
    });

    /* -------------------------------------------------------------------------- */
    /* PARTICIPANT MEDIA STATE BROADCAST (CAM/MIC/SPEAKING)                       */
    /* -------------------------------------------------------------------------- */
    socket.on('media:state', (data: { classId: string; isMicMuted: boolean; isCameraOff: boolean }) => {
      socket.to(`class:${data.classId}`).emit('peer:media:state', {
        userId: user.userId,
        isMicMuted: data.isMicMuted,
        isCameraOff: data.isCameraOff,
      });
    });

    /* -------------------------------------------------------------------------- */
    /* WEBRTC P2P SIGNALING RELAY (FALLBACK / DIRECT SFU STREAMING)               */
    /* -------------------------------------------------------------------------- */
    socket.on('signal:offer', (data: { classId: string; sdp: any; targetUserId?: string }) => {
      if (data.targetUserId) {
        socket.to(`user:${data.targetUserId}`).emit('signal:offer', {
          senderId: user.userId,
          senderName: user.name,
          sdp: data.sdp,
        });
      } else {
        socket.to(`class:${data.classId}`).emit('signal:offer', {
          senderId: user.userId,
          senderName: user.name,
          sdp: data.sdp,
        });
      }
    });

    socket.on('signal:answer', (data: { classId: string; sdp: any; targetUserId?: string }) => {
      if (data.targetUserId) {
        socket.to(`user:${data.targetUserId}`).emit('signal:answer', {
          senderId: user.userId,
          senderName: user.name,
          sdp: data.sdp,
        });
      } else {
        socket.to(`class:${data.classId}`).emit('signal:answer', {
          senderId: user.userId,
          senderName: user.name,
          sdp: data.sdp,
        });
      }
    });

    socket.on('signal:candidate', (data: { classId: string; candidate: any; targetUserId?: string }) => {
      if (data.targetUserId) {
        socket.to(`user:${data.targetUserId}`).emit('signal:candidate', {
          senderId: user.userId,
          candidate: data.candidate,
        });
      } else {
        socket.to(`class:${data.classId}`).emit('signal:candidate', {
          senderId: user.userId,
          candidate: data.candidate,
        });
      }
    });

    /* -------------------------------------------------------------------------- */
    /* IN-CLASS REALTIME CHAT (PERSISTED LAST 50 MESSAGES)                        */
    /* -------------------------------------------------------------------------- */
    socket.on('chat:send', (data: { classId: string; text: string }) => {
      if (!data.text || data.text.trim().length === 0) return;

      const message: ChatMessage = {
        id: `msg_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
        senderId: user.userId,
        senderName: user.name,
        senderRole: user.role,
        text: data.text.trim(),
        timestamp: new Date().toISOString(),
      };

      // Persist last 50 messages per class
      const history = roomChatHistory.get(data.classId) || [];
      history.push(message);
      if (history.length > 50) history.shift();
      roomChatHistory.set(data.classId, history);

      io.to(`class:${data.classId}`).emit('chat:message', message);
    });

    /* -------------------------------------------------------------------------- */
    /* HAND RAISE QUEUE                                                           */
    /* -------------------------------------------------------------------------- */
    socket.on('hand:raise', (data: { classId: string }) => {
      const classId = data.classId;
      const current = roomHandQueues.get(classId) || [];

      if (!current.some((h) => h.userId === user.userId)) {
        current.push({
          userId: user.userId,
          userName: user.name,
          userRole: user.role,
          raisedAt: new Date().toISOString(),
        });
        roomHandQueues.set(classId, current);
        io.to(`class:${classId}`).emit('hand:queue', { hands: current });
      }
    });

    socket.on('hand:lower', (data: { classId: string; targetUserId?: string }) => {
      const classId = data.classId;
      let current = roomHandQueues.get(classId) || [];

      // If host lowering a student's hand, or student lowering their own
      const targetId =
        user.role === 'TEACHER' || user.role === 'ADMIN'
          ? data.targetUserId || user.userId
          : user.userId;

      current = current.filter((h) => h.userId !== targetId);
      roomHandQueues.set(classId, current);
      io.to(`class:${classId}`).emit('hand:queue', { hands: current });
    });

    /* -------------------------------------------------------------------------- */
    /* LIVE POLLS                                                                 */
    /* -------------------------------------------------------------------------- */
    socket.on(
      'poll:create',
      (data: { classId: string; question: string; options: string[] }) => {
        if (user.role !== 'TEACHER' && user.role !== 'ADMIN') return;

        const classId = data.classId;
        const newPoll: Poll = {
          id: `poll_${Date.now()}`,
          question: data.question.trim(),
          options: data.options.map((opt, idx) => ({ id: idx, text: opt.trim(), votes: 0 })),
          createdBy: user.name,
          active: true,
          votedUserIds: [],
        };

        const currentPolls = roomActivePolls.get(classId) || [];
        currentPolls.unshift(newPoll);
        roomActivePolls.set(classId, currentPolls);

        io.to(`class:${classId}`).emit('poll:started', newPoll);
      }
    );

    socket.on('poll:vote', (data: { classId: string; pollId: string; optionId: number }) => {
      const classId = data.classId;
      const polls = roomActivePolls.get(classId) || [];
      const poll = polls.find((p) => p.id === data.pollId);

      if (poll && poll.active && !poll.votedUserIds.includes(user.userId)) {
        poll.votedUserIds.push(user.userId);
        const option = poll.options.find((o) => o.id === data.optionId);
        if (option) {
          option.votes += 1;
        }
        io.to(`class:${classId}`).emit('poll:updated', poll);
      }
    });

    socket.on('poll:close', (data: { classId: string; pollId: string }) => {
      if (user.role !== 'TEACHER' && user.role !== 'ADMIN') return;

      const classId = data.classId;
      const polls = roomActivePolls.get(classId) || [];
      const poll = polls.find((p) => p.id === data.pollId);

      if (poll) {
        poll.active = false;
        io.to(`class:${classId}`).emit('poll:ended', poll);
      }
    });

    /* -------------------------------------------------------------------------- */
    /* DOUBTS BOX                                                                 */
    /* -------------------------------------------------------------------------- */
    socket.on('doubt:submit', (data: { classId: string; question: string }) => {
      const doubt = {
        id: `dbt_${Date.now()}`,
        studentId: user.userId,
        studentName: user.name,
        question: data.question.trim(),
        resolved: false,
        timestamp: new Date().toISOString(),
      };

      io.to(`class:${data.classId}`).emit('doubt:new', doubt);
    });

    socket.on('doubt:resolve', (data: { classId: string; doubtId: string }) => {
      if (user.role !== 'TEACHER' && user.role !== 'ADMIN') return;

      io.to(`class:${data.classId}`).emit('doubt:resolved', {
        doubtId: data.doubtId,
        resolvedBy: user.name,
      });
    });

    socket.on('disconnect', () => {
      if (socket.data.currentClassId) {
        const classId = socket.data.currentClassId;
        // Clean up hand raise if student leaves
        let hands = roomHandQueues.get(classId) || [];
        hands = hands.filter((h) => h.userId !== user.userId);
        roomHandQueues.set(classId, hands);
        io.to(`class:${classId}`).emit('hand:queue', { hands });

        // Emit peer:left
        io.to(`class:${classId}`).emit('peer:left', { userId: user.userId, name: user.name });

        // If host disconnected from active class, schedule 10-min timeout
        if (isHost && !hostDisconnectTimers.has(classId)) {
          const timer = setTimeout(async () => {
            try {
              await prisma.liveClass.updateMany({
                where: { id: classId, status: 'LIVE' },
                data: { status: 'ENDED' },
              });
              io.to(`class:${classId}`).emit('class:ended', { reason: 'HOST_TIMEOUT' });
            } catch (err) {
              console.error('Error auto-ending class on host disconnect timeout:', err);
            } finally {
              hostDisconnectTimers.delete(classId);
            }
          }, 10 * 60 * 1000);
          timer.unref();
          hostDisconnectTimers.set(classId, timer);
        }
      }
    });
  });
}

export function resetSocketGatewayState(): void {
  for (const timer of hostDisconnectTimers.values()) {
    clearTimeout(timer);
  }
  hostDisconnectTimers.clear();
  roomHandQueues.clear();
  roomActivePolls.clear();
  roomBoardGrantedStudents.clear();
  roomBoardStates.clear();
  roomChatHistory.clear();
  roomStages.clear();
  roomBoardStrokes.clear();
  roomDocStates.clear();
  roomMediaModes.clear();
  roomMicLocked.clear();
  userClassSockets.clear();
}
