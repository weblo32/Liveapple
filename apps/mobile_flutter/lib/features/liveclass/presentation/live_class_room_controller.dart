import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../data/live_class_repository.dart';
import '../domain/live_class_model.dart';
import '../domain/class_participant.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/network/api_client.dart';
import 'package:dio/dio.dart';
import '../../../core/errors/app_exception.dart';
import '../../../models/slide_deck_model.dart';
import 'live_class_controller.dart';

class ChatMessageItem {
  final String id;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String text;
  final DateTime timestamp;
  final bool isSystem;

  ChatMessageItem({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.text,
    required this.timestamp,
    this.isSystem = false,
  });

  factory ChatMessageItem.fromJson(Map<String, dynamic> json) {
    return ChatMessageItem(
      id: json['id'] as String? ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? 'User',
      senderRole: json['senderRole'] as String? ?? 'STUDENT',
      text: json['text'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      isSystem: json['senderRole'] == 'SYSTEM',
    );
  }
}

class InClassPollItem {
  final String id;
  final String question;
  final List<PollOptionItem> options;
  final bool active;
  final bool userVoted;

  InClassPollItem({
    required this.id,
    required this.question,
    required this.options,
    required this.active,
    this.userVoted = false,
  });
}

class PollOptionItem {
  final int id;
  final String text;
  final int votes;

  PollOptionItem({required this.id, required this.text, required this.votes});
}

class RaisedHandItem {
  final String userId;
  final String userName;
  final String userRole;
  final DateTime raisedAt;

  RaisedHandItem({
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.raisedAt,
  });
}

class LiveClassRoomState {
  final LiveClassModel? liveClass;
  final bool isConnecting;
  final bool isConnected;
  final String connectionState; // 'connecting', 'connected', 'reconnecting', 'disconnected'
  final String? errorMessage;
  final bool isHost;
  final bool isMicMuted;
  final bool isCameraOff;
  final bool isScreenSharing;
  final bool isWhiteboardOpen;
  final bool isBoardAllowed;
  final bool isDocPresenting;
  final String docTitle;
  final int docPage;
  final String? docPath;
  final String? docUrl;
  final int docTotalPages;
  final String? activeSpeakerName;
  final List<ClassParticipant> participants;
  final List<ChatMessageItem> chatMessages;
  final int unreadChatCount;
  final List<RaisedHandItem> handsQueue;
  final List<InClassPollItem> polls;
  final bool isHandRaised;
  final bool isClassEnded;
  final bool isRoomLocked;
  final lk.LocalVideoTrack? localVideoTrack;
  final lk.LocalAudioTrack? localAudioTrack;
  final Map<String, lk.VideoTrack> remoteVideoTracks;
  final lk.VideoTrack? remoteScreenShareTrack;
  final String? serverBuildCommit;
  final String? serverBuildTime;
  final Map<String, dynamic>? tokenGrants;
  final String? lastLiveKitError;
  final bool isMicLocked;
  final String stage;
  final bool isSocketConnected;
  final bool isRoomJoined;
  final String? lastStageEventSent;
  final String? lastStageEventReceived;
  final int boardEventsSent;
  final int boardEventsReceived;
  final bool snapshotReceived;
  final String? slidesDeckId;
  final String? slidesFileHash;
  final String? slidesFetchStatus;
  final int? slidesBytesLoaded;
  final String? slidesReceiveSource;
  final String? slidesRenderError;
  final bool isSlidesUploading;
  final double? slidesUploadProgress;
  final bool isSharedWithStudents;

  LiveClassRoomState({
    this.liveClass,
    this.isConnecting = true,
    this.isConnected = false,
    this.connectionState = 'connecting',
    this.errorMessage,
    this.isHost = false,
    this.isMicMuted = true,
    this.isCameraOff = true,
    this.isScreenSharing = false,
    this.isWhiteboardOpen = false,
    this.isBoardAllowed = false,
    this.isDocPresenting = false,
    this.docTitle = '',
    this.docPage = 1,
    this.docPath,
    this.docUrl,
    this.docTotalPages = 1,
    this.activeSpeakerName,
    this.participants = const [],
    this.chatMessages = const [],
    this.unreadChatCount = 0,
    this.handsQueue = const [],
    this.polls = const [],
    this.isHandRaised = false,
    this.isClassEnded = false,
    this.isRoomLocked = false,
    this.localVideoTrack,
    this.localAudioTrack,
    this.remoteVideoTracks = const {},
    this.remoteScreenShareTrack,
    this.serverBuildCommit,
    this.serverBuildTime,
    this.tokenGrants,
    this.lastLiveKitError,
    this.isMicLocked = false,
    this.stage = 'VIDEO',
    this.isSocketConnected = false,
    this.isRoomJoined = false,
    this.lastStageEventSent,
    this.lastStageEventReceived,
    this.boardEventsSent = 0,
    this.boardEventsReceived = 0,
    this.snapshotReceived = false,
    this.slidesDeckId,
    this.slidesFileHash,
    this.slidesFetchStatus,
    this.slidesBytesLoaded,
    this.slidesReceiveSource,
    this.slidesRenderError,
    this.isSlidesUploading = false,
    this.slidesUploadProgress,
    this.isSharedWithStudents = false,
  });

  LiveClassRoomState copyWith({
    LiveClassModel? liveClass,
    bool? isConnecting,
    bool? isConnected,
    String? connectionState,
    String? errorMessage,
    bool? isHost,
    bool? isMicMuted,
    bool? isCameraOff,
    bool? isScreenSharing,
    bool? isWhiteboardOpen,
    bool? isBoardAllowed,
    bool? isDocPresenting,
    String? docTitle,
    int? docPage,
    String? docPath,
    String? docUrl,
    int? docTotalPages,
    String? activeSpeakerName,
    List<ClassParticipant>? participants,
    List<ChatMessageItem>? chatMessages,
    int? unreadChatCount,
    List<RaisedHandItem>? handsQueue,
    List<InClassPollItem>? polls,
    bool? isHandRaised,
    bool? isClassEnded,
    bool? isRoomLocked,
    lk.LocalVideoTrack? localVideoTrack,
    lk.LocalAudioTrack? localAudioTrack,
    Map<String, lk.VideoTrack>? remoteVideoTracks,
    lk.VideoTrack? remoteScreenShareTrack,
    String? serverBuildCommit,
    String? serverBuildTime,
    Map<String, dynamic>? tokenGrants,
    String? lastLiveKitError,
    bool? isMicLocked,
    String? stage,
    bool? isSocketConnected,
    bool? isRoomJoined,
    String? lastStageEventSent,
    String? lastStageEventReceived,
    int? boardEventsSent,
    int? boardEventsReceived,
    bool? snapshotReceived,
    String? slidesDeckId,
    String? slidesFileHash,
    String? slidesFetchStatus,
    int? slidesBytesLoaded,
    String? slidesReceiveSource,
    String? slidesRenderError,
    bool? isSlidesUploading,
    double? slidesUploadProgress,
    bool? isSharedWithStudents,
    bool clearLocalVideo = false,
    bool clearLocalAudio = false,
    bool clearRemoteScreenShare = false,
    bool clearDocPath = false,
    bool clearDocUrl = false,
  }) {
    return LiveClassRoomState(
      liveClass: liveClass ?? this.liveClass,
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      connectionState: connectionState ?? this.connectionState,
      errorMessage: errorMessage,
      isHost: isHost ?? this.isHost,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      isWhiteboardOpen: isWhiteboardOpen ?? this.isWhiteboardOpen,
      isBoardAllowed: isBoardAllowed ?? this.isBoardAllowed,
      isDocPresenting: isDocPresenting ?? this.isDocPresenting,
      docTitle: docTitle ?? this.docTitle,
      docPage: docPage ?? this.docPage,
      docPath: clearDocPath ? null : (docPath ?? this.docPath),
      docUrl: clearDocUrl ? null : (docUrl ?? this.docUrl),
      docTotalPages: docTotalPages ?? this.docTotalPages,
      activeSpeakerName: activeSpeakerName ?? this.activeSpeakerName,
      participants: participants ?? this.participants,
      chatMessages: chatMessages ?? this.chatMessages,
      unreadChatCount: unreadChatCount ?? this.unreadChatCount,
      handsQueue: handsQueue ?? this.handsQueue,
      polls: polls ?? this.polls,
      isHandRaised: isHandRaised ?? this.isHandRaised,
      isClassEnded: isClassEnded ?? this.isClassEnded,
      isRoomLocked: isRoomLocked ?? this.isRoomLocked,
      localVideoTrack: clearLocalVideo ? null : (localVideoTrack ?? this.localVideoTrack),
      localAudioTrack: clearLocalAudio ? null : (localAudioTrack ?? this.localAudioTrack),
      remoteVideoTracks: remoteVideoTracks ?? this.remoteVideoTracks,
      remoteScreenShareTrack: clearRemoteScreenShare ? null : (remoteScreenShareTrack ?? this.remoteScreenShareTrack),
      serverBuildCommit: serverBuildCommit ?? this.serverBuildCommit,
      serverBuildTime: serverBuildTime ?? this.serverBuildTime,
      tokenGrants: tokenGrants ?? this.tokenGrants,
      lastLiveKitError: lastLiveKitError ?? this.lastLiveKitError,
      isMicLocked: isMicLocked ?? this.isMicLocked,
      stage: stage ?? this.stage,
      isSocketConnected: isSocketConnected ?? this.isSocketConnected,
      isRoomJoined: isRoomJoined ?? this.isRoomJoined,
      lastStageEventSent: lastStageEventSent ?? this.lastStageEventSent,
      lastStageEventReceived: lastStageEventReceived ?? this.lastStageEventReceived,
      boardEventsSent: boardEventsSent ?? this.boardEventsSent,
      boardEventsReceived: boardEventsReceived ?? this.boardEventsReceived,
      snapshotReceived: snapshotReceived ?? this.snapshotReceived,
      slidesDeckId: slidesDeckId ?? this.slidesDeckId,
      slidesFileHash: slidesFileHash ?? this.slidesFileHash,
      slidesFetchStatus: slidesFetchStatus ?? this.slidesFetchStatus,
      slidesBytesLoaded: slidesBytesLoaded ?? this.slidesBytesLoaded,
      slidesReceiveSource: slidesReceiveSource ?? this.slidesReceiveSource,
      slidesRenderError: slidesRenderError ?? this.slidesRenderError,
      isSlidesUploading: isSlidesUploading ?? this.isSlidesUploading,
      slidesUploadProgress: slidesUploadProgress ?? this.slidesUploadProgress,
      isSharedWithStudents: isSharedWithStudents ?? this.isSharedWithStudents,
    );
  }
}

class LiveClassRoomNotifier extends StateNotifier<LiveClassRoomState> {
  final LiveClassRepository _repository;
  final SecureStorageService _storage;
  io.Socket? _socket;
  lk.Room? _liveKitRoom;
  String? _currentClassId;
  int _boardEventsSent = 0;
  int _boardEventsReceived = 0;

  final StreamController<Map<String, dynamic>> _drawStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<void> _clearStreamController =
      StreamController<void>.broadcast();

  static const _screenshareChannel = MethodChannel('com.classora.app/screenshare');
  Completer<bool>? _screenshareServiceReadyCompleter;

  Stream<Map<String, dynamic>> get remoteDrawStream => _drawStreamController.stream;
  Stream<void> get remoteClearStream => _clearStreamController.stream;

  LiveClassRoomNotifier({
    LiveClassRepository? repository,
    SecureStorageService? storage,
  })  : _repository = repository ?? LiveClassRepository(),
        _storage = storage ?? SecureStorageService(),
        super(LiveClassRoomState()) {
    _initScreenshareChannel();
  }

  void _initScreenshareChannel() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _screenshareChannel.setMethodCallHandler((call) async {
        if (call.method == 'onServiceReady') {
          if (_screenshareServiceReadyCompleter != null && !_screenshareServiceReadyCompleter!.isCompleted) {
            _screenshareServiceReadyCompleter!.complete(true);
          }
        } else if (call.method == 'onServiceError') {
          final err = call.arguments?.toString() ?? 'Service error';
          if (_screenshareServiceReadyCompleter != null && !_screenshareServiceReadyCompleter!.isCompleted) {
            _screenshareServiceReadyCompleter!.completeError(Exception(err));
          }
        }
      });
    }
  }

  Future<void> joinRoom(
    String classId, {
    String? currentUserId,
    String? currentUserName,
    String? currentUserRole,
    bool? initialMicMuted,
    bool? initialCameraOff,
    lk.LocalVideoTrack? prewarmVideoTrack,
    lk.LocalAudioTrack? prewarmAudioTrack,
  }) async {
    _currentClassId = classId;
    state = state.copyWith(isConnecting: true, errorMessage: null, connectionState: 'connecting');

    try {
      final tokenData = await _repository.getToken(classId);
      final isHost = tokenData['isHost'] as bool? ?? false;
      final livekitToken = tokenData['token'] as String? ?? '';
      final livekitServerUrl = tokenData['serverUrl'] as String? ?? '';
      final classDetails = await _repository.getClassById(classId);

      // Decode token payload to inspect grants (canPublish, canPublishSources)
      Map<String, dynamic>? grants;
      try {
        final parts = livekitToken.split('.');
        if (parts.length >= 2) {
          final normalized = base64Url.normalize(parts[1]);
          final decodedPayload = json.decode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
          grants = decodedPayload['video'] as Map<String, dynamic>?;
        }
      } catch (e) {
        debugPrint('[TOKEN] Decode error: $e');
      }

      // Fetch server build info from /health
      String? serverCommit;
      String? serverBuiltAt;
      try {
        final healthRes = await _repository.getHealth();
        final build = healthRes['build'] as Map<String, dynamic>?;
        serverCommit = build?['commit']?.toString();
        serverBuiltAt = build?['builtAt']?.toString();
      } catch (_) {}

      // Initial local participant
      final localUserId = currentUserId ?? (isHost ? (classDetails.teacherId ?? 'local_host') : 'local_student');
      final localUserName = currentUserName ?? (isHost ? (classDetails.teacherName ?? 'Teacher') : 'Student');
      final localRole = currentUserRole ?? (isHost ? 'TEACHER' : 'STUDENT');

      // Use lobby-selected settings (or default: teacher on, student muted)
      final micMuted = initialMicMuted ?? !isHost;
      final cameraOff = initialCameraOff ?? !isHost;

      // Real device video track
      lk.LocalVideoTrack? videoTrack = prewarmVideoTrack;
      if (!cameraOff && videoTrack == null) {
        try {
          videoTrack = await lk.LocalVideoTrack.createCameraTrack();
        } catch (camErr) {
          debugPrint('[CAMERA] Startup note: $camErr');
        }
      }

      // Real device audio track
      lk.LocalAudioTrack? audioTrack = prewarmAudioTrack;
      if (!micMuted && audioTrack == null) {
        try {
          audioTrack = await lk.LocalAudioTrack.create();
        } catch (audErr) {
          debugPrint('[AUDIO] Startup note: $audErr');
        }
      }

      final initialParticipant = ClassParticipant(
        identity: localUserId,
        name: localUserName,
        role: localRole,
        isHost: isHost,
        isLocal: true,
        isMicMuted: micMuted,
        isCameraOff: cameraOff,
      );

      final participantsList = ClassParticipant.deduplicateAndSort([initialParticipant]);

      state = state.copyWith(
        liveClass: classDetails,
        isHost: isHost,
        isConnecting: false,
        isConnected: true,
        connectionState: 'connected',
        isMicMuted: micMuted,
        isCameraOff: cameraOff,
        isBoardAllowed: isHost,
        activeSpeakerName: classDetails.teacherName ?? 'Teacher',
        participants: participantsList,
        localVideoTrack: videoTrack,
        localAudioTrack: audioTrack,
        serverBuildCommit: serverCommit,
        serverBuildTime: serverBuiltAt,
        tokenGrants: grants,
      );

      // Connect to Socket.IO for realtime chat, hand queue, and room events
      await _initSocketConnection(classId, localUserId, localUserName, localRole);

      // Broadcast initial media state to room
      _socket?.emit('media:state', {
        'classId': classId,
        'isMicMuted': micMuted,
        'isCameraOff': cameraOff,
      });

      // Connect to LiveKit SFU (gracefully handle headless/mock environments)
      if (livekitToken.isNotEmpty && livekitServerUrl.isNotEmpty) {
        _initLiveKit(livekitServerUrl, livekitToken);
      }
    } catch (e) {
      final msg = e is AppException ? e.message : e.toString();
      state = state.copyWith(
        isConnecting: false,
        errorMessage: msg,
        connectionState: 'disconnected',
      );
    }
  }

  Future<void> _initSocketConnection(
    String classId,
    String userId,
    String userName,
    String userRole,
  ) async {
    try {
      final baseUrl = await _storage.getBaseUrl() ?? Endpoints.defaultBaseUrl;
      final uri = Uri.parse(baseUrl);
      final socketHost = uri.hasPort && uri.port != 80 && uri.port != 443
          ? '${uri.scheme}://${uri.host}:${uri.port}'
          : '${uri.scheme}://${uri.host}';
      final accessToken = await _storage.getAccessToken();

      _socket = io.io(
        socketHost,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .setAuth({'token': accessToken})
            .enableAutoConnect()
            .enableReconnection()
            .build(),
      );

      void onConnected() {
        debugPrint('[SOCKET] Connected to classroom gateway');
        _socket?.emit('class:join', {'classId': classId});
        state = state.copyWith(
          connectionState: 'connected',
          isSocketConnected: true,
          isRoomJoined: true,
        );
      }

      _socket?.onConnect((_) => onConnected());
      _socket?.on('reconnect', (_) => onConnected());
      if (_socket?.connected == true) {
        onConnected();
      }

      _socket?.on('connect_error', (err) {
        debugPrint('[SOCKET] Connection error: $err');
        state = state.copyWith(isSocketConnected: false, isRoomJoined: false);
      });

      // 1. Chat History (last 50 messages on join)
      _socket?.on('chat:history', (data) {
        if (data is Map && data['messages'] is List) {
          final rawMsgs = data['messages'] as List;
          final messages = rawMsgs
              .map((m) => ChatMessageItem.fromJson(m as Map<String, dynamic>))
              .toList();
          state = state.copyWith(chatMessages: messages);
        }
      });

      // 2. Realtime Chat Message delivery
      _socket?.on('chat:message', (data) {
        if (data is Map) {
          final msg = ChatMessageItem.fromJson(Map<String, dynamic>.from(data));
          // Avoid duplicate local messages
          if (!state.chatMessages.any((m) => m.id == msg.id)) {
            state = state.copyWith(
              chatMessages: [...state.chatMessages, msg],
              unreadChatCount: state.unreadChatCount + 1,
            );
          }
        }
      });

      // 3. Hand Raise Queue updates
      _socket?.on('hand:queue', (data) {
        if (data is Map && data['hands'] is List) {
          final rawHands = data['hands'] as List;
          final queue = rawHands.map((h) {
            final m = h as Map;
            return RaisedHandItem(
              userId: m['userId'] as String? ?? '',
              userName: m['userName'] as String? ?? 'Student',
              userRole: m['userRole'] as String? ?? 'STUDENT',
              raisedAt: DateTime.tryParse(m['raisedAt'] as String? ?? '') ?? DateTime.now(),
            );
          }).toList();

          // Sync participant hand raised status
          final handIds = queue.map((h) => h.userId).toSet();
          final updatedParticipants = state.participants.map((p) {
            return p.copyWith(isHandRaised: handIds.contains(p.identity));
          }).toList();

          final isMyHandRaised = handIds.contains(userId);

          state = state.copyWith(
            handsQueue: queue,
            isHandRaised: isMyHandRaised,
            participants: ClassParticipant.deduplicateAndSort(updatedParticipants),
          );
        }
      });

      // 4. Peer Joined
      _socket?.on('peer:joined', (data) {
        if (data is Map) {
          final peerId = data['userId'] as String? ?? '';
          final peerName = data['name'] as String? ?? 'Student';
          final peerRole = data['role'] as String? ?? 'STUDENT';
          final isHostPeer = peerRole == 'TEACHER' || peerRole == 'ADMIN';

          final newPeer = ClassParticipant(
            identity: peerId,
            name: peerName,
            role: peerRole,
            isHost: isHostPeer,
            isLocal: false,
            isMicMuted: true,
            isCameraOff: true,
          );

          state = state.copyWith(
            participants: ClassParticipant.deduplicateAndSort([...state.participants, newPeer]),
          );
        }
      });

      // 5. Peer Left
      _socket?.on('peer:left', (data) {
        if (data is Map) {
          final peerId = data['userId'] as String? ?? '';
          final filtered = state.participants.where((p) => p.identity != peerId).toList();
          state = state.copyWith(
            participants: ClassParticipant.deduplicateAndSort(filtered),
          );
        }
      });

      // 6. Peer Media State Sync (Mic & Camera)
      _socket?.on('peer:media:state', (data) {
        if (data is Map) {
          final peerId = data['userId'] as String? ?? '';
          final peerMicMuted = data['isMicMuted'] as bool? ?? true;
          final peerCameraOff = data['isCameraOff'] as bool? ?? true;

          final updated = state.participants.map((p) {
            if (p.identity == peerId) {
              final effectiveMic = p.micPubPresent ? p.micPubMuted : peerMicMuted;
              final effectiveCam = p.camPubPresent ? p.camPubMuted : peerCameraOff;
              return p.copyWith(isMicMuted: effectiveMic, isCameraOff: effectiveCam);
            }
            return p;
          }).toList();

          state = state.copyWith(
            participants: ClassParticipant.deduplicateAndSort(updated),
          );
        }
      });

      // 6b. Snapshot on join/reconnect
      _socket?.on('classroom:snapshot', (data) {
        if (data is Map) {
          final st = data['mode']?.toString() ?? data['stage']?.toString() ?? 'VIDEO';
          final isLocked = data['isMicLocked'] == true;
          final boardData = data['board'] as Map?;
          final isBoardOpen = boardData?['isOpen'] == true || st == 'BOARD';
          final canDraw = boardData?['canDraw'] == true;
          final docData = data['doc'] as Map?;

          // Replay strokes from snapshot
          if (boardData?['strokes'] is List && !_drawStreamController.isClosed) {
            final strokesList = boardData!['strokes'] as List;
            for (final stroke in strokesList) {
              if (stroke is Map) {
                _drawStreamController.add(Map<String, dynamic>.from(stroke));
              }
            }
          }

          final docMap = docData is Map ? Map<String, dynamic>.from(docData) : null;
          final slideDeck = docMap != null ? SlideDeckModel.fromJson(docMap) : null;
          final isDocOpen = (docMap != null && docMap['isOpen'] == true) || st == 'SLIDES';

          state = state.copyWith(
            snapshotReceived: true,
            isRoomJoined: true,
            stage: st,
            isMicLocked: isLocked,
            isWhiteboardOpen: isBoardOpen,
            isBoardAllowed: state.isHost || canDraw,
            isDocPresenting: isDocOpen,
            docTitle: slideDeck?.fileName ?? docData?['title']?.toString() ?? '',
            docPage: slideDeck?.currentPage ?? (docData?['page'] as num?)?.toInt() ?? 1,
            docUrl: slideDeck?.url ??
                docData?['url']?.toString() ??
                (slideDeck?.deckId != null && slideDeck!.deckId.isNotEmpty && _currentClassId != null
                    ? '/v1/classes/$_currentClassId/slides/${slideDeck.deckId}'
                    : null),
            docTotalPages: slideDeck?.totalPages ?? (docData?['totalPages'] as num?)?.toInt() ?? 1,
            slidesDeckId: slideDeck?.deckId,
            slidesFileHash: slideDeck?.fileHash,
            slidesReceiveSource: 'snapshot',
            lastStageEventReceived: 'mode: $st (snapshot) at ${DateTime.now().toIso8601String()}',
          );
        }
      });

      // 6c. Device takeover (Stage 2.4)
      _socket?.on('class:takeover', (data) {
        final reason = (data is Map ? data['reason'] : null)?.toString() ?? 'Aap dusre device se join ho gaye';
        state = state.copyWith(errorMessage: reason);
        leaveRoom();
      });

      // 6d. Stage sync (Stage 1.2) - handles stage:state and stage:changed
      void handleStageUpdate(dynamic data) {
        if (data is Map) {
          final st = data['mode']?.toString() ?? data['stage']?.toString() ?? 'VIDEO';
          state = state.copyWith(
            stage: st,
            isWhiteboardOpen: st == 'BOARD',
            isDocPresenting: st == 'SLIDES',
            lastStageEventReceived: 'mode: $st at ${DateTime.now().toIso8601String()}',
          );
        }
      }

      _socket?.on('stage:state', handleStageUpdate);
      _socket?.on('stage:changed', handleStageUpdate);

      // 7. Host Muted All event
      _socket?.on('host:muted', (data) {
        if (!state.isHost) {
          final isLocked = (data is Map && data['isLocked'] == true);
          state = state.copyWith(isMicLocked: isLocked);
          state.localAudioTrack?.stop();
        }
      });

      _socket?.on('host:unlocked', (_) {
        if (!state.isHost) {
          state = state.copyWith(isMicLocked: false);
        }
      });

      _socket?.on('host:allowSpeak', (_) {
        if (!state.isHost) {
          state = state.copyWith(isMicLocked: false);
        }
      });

      // 8. Whiteboard Sync events
      _socket?.on('board:state', (data) {
        if (data is Map) {
          final isOpen = data['isOpen'] == true;
          final canDraw = data['canDraw'] == true;
          _boardEventsReceived++;

          if (data['strokes'] is List && !_drawStreamController.isClosed) {
            final strokesList = data['strokes'] as List;
            for (final s in strokesList) {
              if (s is Map) {
                _drawStreamController.add(Map<String, dynamic>.from(s));
              }
            }
          }

          state = state.copyWith(
            isWhiteboardOpen: isOpen,
            isBoardAllowed: state.isHost || canDraw,
            stage: isOpen ? 'BOARD' : (state.isDocPresenting ? 'SLIDES' : 'VIDEO'),
            boardEventsReceived: _boardEventsReceived,
          );
        }
      });

      _socket?.on('board:granted', (data) {
        if (data is Map && data['studentId'] == userId) {
          state = state.copyWith(isBoardAllowed: true);
        }
      });

      _socket?.on('board:revoked', (data) {
        if (data is Map && data['studentId'] == userId) {
          state = state.copyWith(isBoardAllowed: false);
        }
      });

      // 8b. Realtime Whiteboard strokes sync
      _socket?.on('whiteboard:draw', (data) {
        _boardEventsReceived++;
        state = state.copyWith(boardEventsReceived: _boardEventsReceived);
        if (data is Map && !_drawStreamController.isClosed) {
          _drawStreamController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket?.on('whiteboard:clear', (_) {
        _boardEventsReceived++;
        state = state.copyWith(boardEventsReceived: _boardEventsReceived);
        if (!_clearStreamController.isClosed) {
          _clearStreamController.add(null);
        }
      });

      // 8c. Document Presentation Sync event (Teacher presents to all students)
      _socket?.on('doc:present', (data) {
        if (data is Map) {
          final deck = SlideDeckModel.fromJson(Map<String, dynamic>.from(data));
          final docUrl = deck.url ?? (deck.deckId.isNotEmpty && _currentClassId != null
              ? '/v1/classes/$_currentClassId/slides/${deck.deckId}'
              : state.docUrl);
          state = state.copyWith(
            isDocPresenting: deck.isOpen,
            docTitle: deck.fileName,
            docPage: deck.currentPage,
            docUrl: docUrl,
            docTotalPages: deck.totalPages,
            slidesDeckId: deck.deckId.isNotEmpty ? deck.deckId : state.slidesDeckId,
            slidesFileHash: deck.fileHash ?? state.slidesFileHash,
            slidesReceiveSource: 'event',
            stage: deck.isOpen ? 'SLIDES' : (state.isWhiteboardOpen ? 'BOARD' : 'VIDEO'),
          );
        }
      });

      _socket?.on('doc:page', (data) {
        if (data is Map) {
          final page = (data['currentPage'] ?? data['page'] as num?)?.toInt() ?? 1;
          state = state.copyWith(docPage: page);
        }
      });

      // 9. Class Ended event
      _socket?.on('class:ended', (_) {
        state = state.copyWith(isClassEnded: true, isConnected: false);
      });

      // 10. Class became LIVE event
      _socket?.on('class:live', (data) {
        debugPrint('[SOCKET] class:live received — teacher started the class!');
        _syncExistingRemoteParticipants();
      });

      _socket?.onDisconnect((_) {
        state = state.copyWith(
          connectionState: 'disconnected',
          isSocketConnected: false,
          isRoomJoined: false,
        );
      });
    } catch (e) {
      debugPrint('[SOCKET] Setup error: $e');
    }
  }

  void _initLiveKit(String serverUrl, String token) async {
    try {
      debugPrint('[LIVEKIT] Connecting to LiveKit Cloud: $serverUrl');
      _liveKitRoom = lk.Room();

      // Stage 1.1: Enable loudspeaker by default on devices
      try {
        await lk.Hardware.instance.setSpeakerphoneOn(true);
      } catch (e) {
        debugPrint('[AUDIO] Loudspeaker init note: $e');
      }

      _liveKitRoom?.events.listen((event) {
        debugPrint('[LIVEKIT-EVENT] $event');
        if (event is lk.RoomDisconnectedEvent) {
          state = state.copyWith(
            connectionState: 'disconnected',
            lastLiveKitError: event.reason?.toString(),
          );
        } else if (event is lk.TrackSubscribedEvent) {
          if (event.track is lk.VideoTrack) {
            final vt = event.track as lk.VideoTrack;
            if (vt.source == lk.TrackSource.screenShareVideo) {
              state = state.copyWith(remoteScreenShareTrack: vt);
            } else {
              final updated = Map<String, lk.VideoTrack>.from(state.remoteVideoTracks);
              updated[event.participant.identity] = vt;
              final updatedParticipants = state.participants.map((p) {
                if (p.identity == event.participant.identity) {
                  return p.copyWith(
                    camPubPresent: true,
                    camPubMuted: false,
                    camPubSubscribed: true,
                    isCameraOff: false,
                  );
                }
                return p;
              }).toList();
              state = state.copyWith(
                remoteVideoTracks: updated,
                participants: ClassParticipant.deduplicateAndSort(updatedParticipants),
              );
            }
          } else if (event.track is lk.AudioTrack) {
            final at = event.track as lk.AudioTrack;
            try {
              at.start();
            } catch (_) {}
            final updatedParticipants = state.participants.map((p) {
              if (p.identity == event.participant.identity) {
                return p.copyWith(
                  micPubPresent: true,
                  micPubMuted: false,
                  micPubSubscribed: true,
                  isMicMuted: false,
                );
              }
              return p;
            }).toList();
            state = state.copyWith(
              participants: ClassParticipant.deduplicateAndSort(updatedParticipants),
            );
          }
        } else if (event is lk.TrackUnsubscribedEvent) {
          if (event.track is lk.VideoTrack) {
            final vt = event.track as lk.VideoTrack;
            if (vt.source == lk.TrackSource.screenShareVideo) {
              state = state.copyWith(clearRemoteScreenShare: true);
            } else {
              final updated = Map<String, lk.VideoTrack>.from(state.remoteVideoTracks);
              updated.remove(event.participant.identity);
              final updatedParticipants = state.participants.map((p) {
                if (p.identity == event.participant.identity) {
                  return p.copyWith(camPubSubscribed: false, isCameraOff: true);
                }
                return p;
              }).toList();
              state = state.copyWith(
                remoteVideoTracks: updated,
                participants: ClassParticipant.deduplicateAndSort(updatedParticipants),
              );
            }
          } else if (event.track is lk.AudioTrack) {
            final updatedParticipants = state.participants.map((p) {
              if (p.identity == event.participant.identity) {
                return p.copyWith(micPubSubscribed: false, isMicMuted: true);
              }
              return p;
            }).toList();
            state = state.copyWith(
              participants: ClassParticipant.deduplicateAndSort(updatedParticipants),
            );
          }
        } else if (event is lk.TrackMutedEvent) {
          final p = event.participant;
          final isAudio = event.publication.kind == lk.TrackType.AUDIO;
          final updatedParticipants = state.participants.map((cp) {
            if (cp.identity == p.identity) {
              if (isAudio) {
                return cp.copyWith(micPubMuted: true, isMicMuted: true);
              } else {
                return cp.copyWith(camPubMuted: true, isCameraOff: true);
              }
            }
            return cp;
          }).toList();
          state = state.copyWith(
            participants: ClassParticipant.deduplicateAndSort(updatedParticipants),
          );
        } else if (event is lk.TrackUnmutedEvent) {
          final p = event.participant;
          final isAudio = event.publication.kind == lk.TrackType.AUDIO;
          final updatedParticipants = state.participants.map((cp) {
            if (cp.identity == p.identity) {
              if (isAudio) {
                return cp.copyWith(micPubMuted: false, isMicMuted: false);
              } else {
                return cp.copyWith(camPubMuted: false, isCameraOff: false);
              }
            }
            return cp;
          }).toList();
          state = state.copyWith(
            participants: ClassParticipant.deduplicateAndSort(updatedParticipants),
          );
        } else if (event is lk.TrackPublishedEvent) {
          final p = event.participant;
          final isAudio = event.publication.kind == lk.TrackType.AUDIO;
          final updatedParticipants = state.participants.map((cp) {
            if (cp.identity == p.identity) {
              if (isAudio) {
                return cp.copyWith(
                  micPubPresent: true,
                  micPubMuted: event.publication.muted,
                  isMicMuted: event.publication.muted,
                );
              } else {
                return cp.copyWith(
                  camPubPresent: true,
                  camPubMuted: event.publication.muted,
                  isCameraOff: event.publication.muted,
                );
              }
            }
            return cp;
          }).toList();
          state = state.copyWith(
            participants: ClassParticipant.deduplicateAndSort(updatedParticipants),
          );
        } else if (event is lk.TrackUnpublishedEvent) {
          final p = event.participant;
          final isAudio = event.publication.kind == lk.TrackType.AUDIO;
          final updatedParticipants = state.participants.map((cp) {
            if (cp.identity == p.identity) {
              if (isAudio) {
                return cp.copyWith(micPubPresent: false, isMicMuted: true);
              } else {
                return cp.copyWith(camPubPresent: false, isCameraOff: true);
              }
            }
            return cp;
          }).toList();
          state = state.copyWith(
            participants: ClassParticipant.deduplicateAndSort(updatedParticipants),
          );
        } else if (event is lk.ActiveSpeakersChangedEvent) {
          final speakerIds = event.speakers.map((s) => s.identity).toSet();
          final updatedParticipants = state.participants.map((p) {
            return p.copyWith(isSpeaking: speakerIds.contains(p.identity));
          }).toList();
          final firstSpeaker = event.speakers.isNotEmpty ? event.speakers.first.name : state.activeSpeakerName;
          state = state.copyWith(
            participants: ClassParticipant.deduplicateAndSort(updatedParticipants),
            activeSpeakerName: (firstSpeaker?.isNotEmpty ?? false) ? firstSpeaker : state.activeSpeakerName,
          );
        } else if (event is lk.ParticipantConnectedEvent) {
          final p = event.participant;
          final isHostPeer = (p.metadata?.contains('isHost":true') ?? false) ||
              p.identity.startsWith('teacher') || p.identity.startsWith('admin');
          final newPeer = ClassParticipant(
            identity: p.identity,
            name: p.name.isNotEmpty ? p.name : p.identity,
            role: isHostPeer ? 'TEACHER' : 'STUDENT',
            isHost: isHostPeer,
            isLocal: false,
            isMicMuted: true,
            isCameraOff: true,
          );
          state = state.copyWith(
            participants: ClassParticipant.deduplicateAndSort([...state.participants, newPeer]),
          );
        } else if (event is lk.ParticipantDisconnectedEvent) {
          final filtered = state.participants.where((p) => p.identity != event.participant.identity).toList();
          final updatedVideoTracks = Map<String, lk.VideoTrack>.from(state.remoteVideoTracks);
          updatedVideoTracks.remove(event.participant.identity);
          state = state.copyWith(
            participants: ClassParticipant.deduplicateAndSort(filtered),
            remoteVideoTracks: updatedVideoTracks,
          );
        }
      });

      await _liveKitRoom?.connect(serverUrl, token);
      debugPrint('[LIVEKIT] Connected successfully. Connection state: ${_liveKitRoom?.connectionState}');

      // Process already-connected remote participants
      _syncExistingRemoteParticipants();

      // If local video/audio tracks are ready and active, publish to SFU
      if (!state.isCameraOff) {
        try {
          await _liveKitRoom?.localParticipant?.setCameraEnabled(true);
        } catch (_) {}
      }
      if (!state.isMicMuted) {
        try {
          await _liveKitRoom?.localParticipant?.setMicrophoneEnabled(true);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[LIVEKIT] LiveKit initialization note: $e');
      state = state.copyWith(lastLiveKitError: e.toString());
    }
  }

  /// Sync any already-connected remote participants and their published tracks.
  void _syncExistingRemoteParticipants() {
    try {
      final remoteParticipants = _liveKitRoom?.remoteParticipants;
      if (remoteParticipants == null || remoteParticipants.isEmpty) return;

      final updatedVideoTracks = Map<String, lk.VideoTrack>.from(state.remoteVideoTracks);
      final newParticipants = List<ClassParticipant>.from(state.participants);
      lk.VideoTrack? screenShareTrack;

      for (final entry in remoteParticipants.entries) {
        final p = entry.value;
        final isHostPeer = (p.metadata?.contains('isHost":true') ?? false) ||
            p.identity.startsWith('teacher') || p.identity.startsWith('admin');

        bool hasVideo = false;
        bool camMuted = true;
        bool camSub = false;
        for (final trackPub in p.videoTrackPublications) {
          final vt = trackPub.track;
          if (vt != null) {
            if (vt.source == lk.TrackSource.screenShareVideo) {
              screenShareTrack = vt;
            } else {
              updatedVideoTracks[p.identity] = vt;
              hasVideo = true;
              camMuted = trackPub.muted;
              camSub = trackPub.subscribed;
            }
          }
        }

        bool micPresent = false;
        bool micMuted = true;
        bool micSub = false;
        for (final audioPub in p.audioTrackPublications) {
          micPresent = true;
          micMuted = audioPub.muted;
          micSub = audioPub.subscribed;
        }

        final existingIdx = newParticipants.indexWhere((cp) => cp.identity == p.identity);
        if (existingIdx >= 0) {
          newParticipants[existingIdx] = newParticipants[existingIdx].copyWith(
            isCameraOff: !hasVideo || camMuted,
            camPubPresent: hasVideo,
            camPubMuted: camMuted,
            camPubSubscribed: camSub,
            isMicMuted: !micPresent || micMuted,
            micPubPresent: micPresent,
            micPubMuted: micMuted,
            micPubSubscribed: micSub,
          );
        } else {
          newParticipants.add(ClassParticipant(
            identity: p.identity,
            name: p.name.isNotEmpty ? p.name : p.identity,
            role: isHostPeer ? 'TEACHER' : 'STUDENT',
            isHost: isHostPeer,
            isLocal: false,
            isMicMuted: !micPresent || micMuted,
            isCameraOff: !hasVideo || camMuted,
            micPubPresent: micPresent,
            micPubMuted: micMuted,
            micPubSubscribed: micSub,
            camPubPresent: hasVideo,
            camPubMuted: camMuted,
            camPubSubscribed: camSub,
          ));
        }
      }

      state = state.copyWith(
        remoteVideoTracks: updatedVideoTracks,
        remoteScreenShareTrack: screenShareTrack ?? state.remoteScreenShareTrack,
        participants: ClassParticipant.deduplicateAndSort(newParticipants),
      );
    } catch (e) {
      debugPrint('[LIVEKIT] Error syncing existing participants: $e');
    }
  }

  Future<void> toggleMic() async {
    final newMicState = !state.isMicMuted;
    lk.LocalAudioTrack? audioTrack = state.localAudioTrack;

    try {
      if (newMicState) {
        // Mute
        await audioTrack?.stop();
        if (_liveKitRoom?.connectionState == lk.ConnectionState.connected) {
          await _liveKitRoom?.localParticipant?.setMicrophoneEnabled(false);
        }
      } else {
        // Unmute
        if (_liveKitRoom?.connectionState == lk.ConnectionState.connected) {
          await _liveKitRoom?.localParticipant?.setMicrophoneEnabled(true);
        } else {
          if (audioTrack == null) {
            audioTrack = await lk.LocalAudioTrack.create();
          } else {
            await audioTrack.start();
          }
        }
      }
    } catch (e) {
      debugPrint('[AUDIO] Toggle error: $e');
    }

    state = state.copyWith(
      isMicMuted: newMicState,
      localAudioTrack: audioTrack,
    );

    // Update local participant in participants list
    final updated = state.participants.map((p) {
      if (p.isLocal) return p.copyWith(isMicMuted: newMicState);
      return p;
    }).toList();

    state = state.copyWith(
      participants: ClassParticipant.deduplicateAndSort(updated),
    );

    if (_currentClassId != null) {
      _socket?.emit('media:state', {
        'classId': _currentClassId,
        'isMicMuted': newMicState,
        'isCameraOff': state.isCameraOff,
      });
    }
  }

  Future<void> toggleCamera() async {
    final newCamState = !state.isCameraOff;
    lk.LocalVideoTrack? videoTrack = state.localVideoTrack;

    try {
      if (newCamState) {
        // Turn off camera
        await videoTrack?.stop();
        if (_liveKitRoom?.connectionState == lk.ConnectionState.connected) {
          await _liveKitRoom?.localParticipant?.setCameraEnabled(false);
        }
        videoTrack = null;
      } else {
        // Turn on camera
        if (_liveKitRoom?.connectionState == lk.ConnectionState.connected) {
          await _liveKitRoom?.localParticipant?.setCameraEnabled(true);
          final localPub = _liveKitRoom?.localParticipant?.videoTrackPublications.firstOrNull;
          if (localPub?.track is lk.LocalVideoTrack) {
            videoTrack = localPub!.track as lk.LocalVideoTrack;
          }
        }
        videoTrack ??= await lk.LocalVideoTrack.createCameraTrack();
      }
    } catch (e) {
      debugPrint('[CAMERA] Toggle error: $e');
    }

    state = state.copyWith(
      isCameraOff: newCamState,
      localVideoTrack: videoTrack,
      clearLocalVideo: newCamState,
    );

    // Update local participant in participants list
    final updated = state.participants.map((p) {
      if (p.isLocal) return p.copyWith(isCameraOff: newCamState);
      return p;
    }).toList();

    state = state.copyWith(
      participants: ClassParticipant.deduplicateAndSort(updated),
    );

    if (_currentClassId != null) {
      _socket?.emit('media:state', {
        'classId': _currentClassId,
        'isMicMuted': state.isMicMuted,
        'isCameraOff': newCamState,
      });
    }
  }

  Future<void> toggleScreenShare({void Function(String message)? onError}) async {
    final next = !state.isScreenSharing;
    try {
      if (_liveKitRoom?.connectionState != lk.ConnectionState.connected) {
        throw Exception('LiveKit is not connected');
      }

      if (next) {
        // Turning ON Screen Share
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          // (a) On Android 13+ request POST_NOTIFICATIONS
          try {
            await _screenshareChannel.invokeMethod('requestNotificationPermission');
          } catch (e) {
            debugPrint('[SCREEN_SHARE] Notification permission request error: $e');
          }

          // (b) MediaProjection consent first - exactly ONE dialog (stores token in flutter_webrtc)
          final hasConsent = await rtc.Helper.requestCapturePermission(fullScreenOnly: true);
          if (!hasConsent) {
            debugPrint('[SCREEN_SHARE] User declined MediaProjection consent dialog');
            return;
          }

          // (c) Only after consent returns OK, start the MediaProjection foreground service
          _screenshareServiceReadyCompleter = Completer<bool>();
          await _screenshareChannel.invokeMethod('startService');

          // (d) Dart WAITS for "ready" acknowledgement with timeout (5s)
          try {
            await _screenshareServiceReadyCompleter!.future.timeout(const Duration(seconds: 5));
          } catch (e) {
            debugPrint('[SCREEN_SHARE] Service ready acknowledgement timeout or error: $e');
            try { await _screenshareChannel.invokeMethod('stopService'); } catch (_) {}
            throw Exception('Screen share foreground service initialization failed');
          }
        }

        // Enable screen share track in LiveKit (reuses stored mediaProjectionData)
        await _liveKitRoom?.localParticipant?.setScreenShareEnabled(true);
        const nextStage = 'SCREEN';
        setStage(nextStage);
        state = state.copyWith(isScreenSharing: true, stage: nextStage);
      } else {
        // Turning OFF Screen Share
        await _liveKitRoom?.localParticipant?.setScreenShareEnabled(false);
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          try {
            await _screenshareChannel.invokeMethod('stopService');
          } catch (e) {
            debugPrint('[SCREEN_SHARE] stopService error: $e');
          }
        }
        const nextStage = 'VIDEO';
        setStage(nextStage);
        state = state.copyWith(isScreenSharing: false, stage: nextStage);
      }
    } catch (e) {
      debugPrint('[SCREEN_SHARE] Toggle error: $e');
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _screenshareChannel.invokeMethod('stopService');
        } catch (_) {}
      }
      if (onError != null) {
        onError('Screen share shuru nahi ho paya');
      }
      setStage('VIDEO');
      state = state.copyWith(isScreenSharing: false, stage: 'VIDEO');
    }
  }

  void toggleWhiteboard() {
    final next = !state.isWhiteboardOpen;
    final nextStage = next ? 'BOARD' : 'VIDEO';
    final eventStr = 'mode: $nextStage at ${DateTime.now().toIso8601String()}';
    _boardEventsSent++;
    state = state.copyWith(
      isWhiteboardOpen: next,
      stage: nextStage,
      boardEventsSent: _boardEventsSent,
      lastStageEventSent: eventStr,
    );
    if (_currentClassId != null && state.isHost) {
      _socket?.emit('board:toggle', {'classId': _currentClassId, 'isOpen': next});
      _socket?.emit('stage:set', {'classId': _currentClassId, 'stage': nextStage, 'mode': nextStage});
    }
  }

  void sendDrawStroke(Map<String, dynamic> stroke) {
    if (_currentClassId != null) {
      _boardEventsSent++;
      state = state.copyWith(boardEventsSent: _boardEventsSent);
      _socket?.emit('whiteboard:draw', {
        'classId': _currentClassId,
        'stroke': stroke,
      });
    }
  }

  void sendClearBoard() {
    if (_currentClassId != null) {
      _boardEventsSent++;
      state = state.copyWith(boardEventsSent: _boardEventsSent);
      _socket?.emit('whiteboard:clear', {
        'classId': _currentClassId,
      });
    }
  }

  void setDocPresentation({
    required bool isOpen,
    String title = '',
    int page = 1,
    String? path,
    String? url,
    int? totalPages,
    String? deckId,
    String? fileHash,
  }) {
    state = state.copyWith(
      isDocPresenting: isOpen,
      docTitle: title.isNotEmpty ? title : state.docTitle,
      docPage: page,
      docPath: path ?? (isOpen ? state.docPath : null),
      docUrl: url ?? (isOpen ? state.docUrl : null),
      docTotalPages: totalPages ?? state.docTotalPages,
      slidesDeckId: deckId ?? (isOpen ? state.slidesDeckId : null),
      slidesFileHash: fileHash ?? (isOpen ? state.slidesFileHash : null),
      clearDocPath: !isOpen,
      clearDocUrl: !isOpen,
      stage: isOpen ? 'SLIDES' : (state.isWhiteboardOpen ? 'BOARD' : 'VIDEO'),
    );
    if (_currentClassId != null && state.isHost) {
      _socket?.emit('doc:present', {
        'classId': _currentClassId,
        'isOpen': isOpen,
        'deckId': deckId ?? state.slidesDeckId,
        'title': title.isNotEmpty ? title : state.docTitle,
        'fileName': title.isNotEmpty ? title : state.docTitle,
        'page': page,
        'currentPage': page,
        if (url != null || state.docUrl != null) 'url': url ?? state.docUrl,
        if (url != null || state.docUrl != null) 'streamUrl': url ?? state.docUrl,
        if (totalPages != null || state.docTotalPages > 0) 'totalPages': totalPages ?? state.docTotalPages,
        if (fileHash != null || state.slidesFileHash != null) 'fileHash': fileHash ?? state.slidesFileHash,
        'stage': 'SLIDES',
      });
    }
  }

  void setDocPage(int page) {
    state = state.copyWith(docPage: page);
    if (_currentClassId != null && state.isHost) {
      _socket?.emit('doc:page', {
        'classId': _currentClassId,
        'page': page,
        'currentPage': page,
      });
      _socket?.emit('doc:present', {
        'classId': _currentClassId,
        'isOpen': true,
        'deckId': state.slidesDeckId,
        'title': state.docTitle,
        'fileName': state.docTitle,
        'page': page,
        'currentPage': page,
        if (state.docUrl != null) 'url': state.docUrl,
        if (state.docUrl != null) 'streamUrl': state.docUrl,
        'totalPages': state.docTotalPages,
        if (state.slidesFileHash != null) 'fileHash': state.slidesFileHash,
        'stage': 'SLIDES',
      });
    }
  }

  Future<void> uploadAndPresentSlides({
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
    int? fileSize,
    void Function(String error)? onError,
    void Function(String message)? onSuccess,
  }) async {
    if (_currentClassId == null) {
      onError?.call('Class session active nahi hai');
      return;
    }

    state = state.copyWith(
      isSlidesUploading: true,
      slidesUploadProgress: 0.1,
      isSharedWithStudents: false,
    );

    try {
      MultipartFile multipartFile;
      if (filePath != null && filePath.isNotEmpty && !kIsWeb) {
        multipartFile = await MultipartFile.fromFile(filePath, filename: fileName);
      } else if (fileBytes != null && fileBytes.isNotEmpty) {
        multipartFile = MultipartFile.fromBytes(fileBytes, filename: fileName);
      } else {
        state = state.copyWith(isSlidesUploading: false);
        onError?.call('File select nahi hui');
        return;
      }

      final formData = FormData.fromMap({'file': multipartFile});
      final res = await ApiClient().dio.post(
        '${Endpoints.classes}/$_currentClassId/slides',
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0) {
            state = state.copyWith(slidesUploadProgress: sent / total);
          }
        },
      );

      final resData = res.data;
      final rawDeck = (resData is Map && resData['data'] is Map) ? resData['data'] : resData;
      final deck = (rawDeck is Map) ? SlideDeckModel.fromJson(Map<String, dynamic>.from(rawDeck)) : null;

      final serverUrl = deck?.url ?? (resData is Map ? (resData['streamUrl'] ?? resData['url']) : null);
      final totalPages = deck?.totalPages ?? (resData is Map ? (resData['totalPages'] as num?)?.toInt() : null) ?? 1;
      final deckId = deck?.deckId ?? (resData is Map ? (resData['deckId']?.toString()) : null);
      final fileHash = deck?.fileHash;

      state = state.copyWith(
        isSlidesUploading: false,
        slidesUploadProgress: 1.0,
        isSharedWithStudents: true,
        slidesDeckId: deckId,
        slidesFileHash: fileHash,
      );

      setDocPresentation(
        isOpen: true,
        title: fileName,
        path: filePath,
        url: serverUrl?.toString(),
        totalPages: totalPages,
        deckId: deckId,
        fileHash: fileHash,
        page: 1,
      );

      onSuccess?.call('Shared with students');
    } catch (e) {
      state = state.copyWith(
        isSlidesUploading: false,
        isSharedWithStudents: false,
      );
      const errMsg = 'Upload fail hua, students ko slides nahi dikhengi';
      debugPrint('[SLIDES_UPLOAD] $errMsg: $e');
      onError?.call(errMsg);
    }
  }

  void updateSlidesDiagnostics({
    String? fetchStatus,
    int? bytesLoaded,
    String? renderError,
  }) {
    state = state.copyWith(
      slidesFetchStatus: fetchStatus ?? state.slidesFetchStatus,
      slidesBytesLoaded: bytesLoaded ?? state.slidesBytesLoaded,
      slidesRenderError: renderError ?? state.slidesRenderError,
    );
  }

  void toggleHandRaise(String userName) {
    if (_currentClassId == null) return;
    final next = !state.isHandRaised;
    state = state.copyWith(isHandRaised: next);

    if (next) {
      _socket?.emit('hand:raise', {'classId': _currentClassId});
    } else {
      _socket?.emit('hand:lower', {'classId': _currentClassId});
    }
  }

  void sendChatMessage(String text, String senderName, String senderRole) {
    if (text.trim().isEmpty || _currentClassId == null) return;

    final trimmed = text.trim();
    // Emit through socket for real delivery to all participants
    _socket?.emit('chat:send', {
      'classId': _currentClassId,
      'text': trimmed,
    });
  }

  void markChatRead() {
    state = state.copyWith(unreadChatCount: 0);
  }

  Future<void> muteAll({bool lock = false}) async {
    if (state.liveClass != null && state.isHost) {
      await _repository.muteAll(state.liveClass!.id);
      // Also emit via socket with lock flag
      _socket?.emit('host:muteAll', {'classId': state.liveClass!.id, 'lock': lock});
    }
  }

  void unlockMics() {
    if (_currentClassId != null && state.isHost) {
      _socket?.emit('host:unlockMic', {'classId': _currentClassId});
    }
  }

  void allowStudentToSpeak(String studentId) {
    if (_currentClassId != null && state.isHost) {
      _socket?.emit('host:allowSpeak', {
        'classId': _currentClassId,
        'studentId': studentId,
      });
    }
  }

  void lowerStudentHand(String studentId) {
    if (_currentClassId != null && state.isHost) {
      _socket?.emit('hand:lower', {
        'classId': _currentClassId,
        'studentId': studentId,
      });
    }
  }

  void muteStudentMic(String studentId) {
    if (_currentClassId != null && state.isHost) {
      _socket?.emit('host:student:action', {
        'classId': _currentClassId,
        'studentId': studentId,
        'action': 'MUTE_MIC',
      });
    }
  }

  void stopStudentCamera(String studentId) {
    if (_currentClassId != null && state.isHost) {
      _socket?.emit('host:student:action', {
        'classId': _currentClassId,
        'studentId': studentId,
        'action': 'STOP_CAM',
      });
    }
  }

  void setStage(String newStage) {
    if (_currentClassId != null && state.isHost) {
      final eventStr = 'mode: $newStage at ${DateTime.now().toIso8601String()}';
      _socket?.emit('stage:set', {
        'classId': _currentClassId,
        'stage': newStage,
        'mode': newStage,
      });
      state = state.copyWith(
        stage: newStage,
        isWhiteboardOpen: newStage == 'BOARD',
        isDocPresenting: newStage == 'SLIDES',
        lastStageEventSent: eventStr,
      );
    }
  }

  Future<void> removeParticipant(String participantId) async {
    if (state.liveClass != null && state.isHost) {
      await _repository.removeParticipant(state.liveClass!.id, participantId);
      final updated = state.participants.where((p) => p.identity != participantId).toList();
      state = state.copyWith(
        participants: ClassParticipant.deduplicateAndSort(updated),
      );
    }
  }

  void grantBoardToStudent(String studentId) {
    if (state.isHost && _currentClassId != null) {
      _socket?.emit('board:permission:grant', {'classId': _currentClassId, 'studentId': studentId});
      _socket?.emit('board:grant', {'classId': _currentClassId, 'studentId': studentId});
    }
  }

  void revokeBoardFromStudent(String studentId) {
    if (state.isHost && _currentClassId != null) {
      _socket?.emit('board:permission:revoke', {'classId': _currentClassId, 'studentId': studentId});
      _socket?.emit('board:revoke', {'classId': _currentClassId, 'studentId': studentId});
    }
  }

  void toggleLockRoom() {
    final next = !state.isRoomLocked;
    state = state.copyWith(isRoomLocked: next);
    if (_currentClassId != null && state.isHost) {
      _socket?.emit('room:lock', {'classId': _currentClassId, 'isLocked': next});
    }
  }

  Future<void> endClass() async {
    if (state.liveClass != null && state.isHost) {
      await _repository.endClass(state.liveClass!.id);
    }
    leaveRoom();
  }

  void leaveRoom() {
    try {
      state.localVideoTrack?.stop();
      state.localAudioTrack?.stop();
    } catch (_) {}

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        _screenshareChannel.invokeMethod('stopService');
      } catch (_) {}
    }

    if (_currentClassId != null) {
      _socket?.emit('class:leave', {'classId': _currentClassId});
    }
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;

    _liveKitRoom?.disconnect();
    _liveKitRoom?.dispose();
    _liveKitRoom = null;

    if (!_drawStreamController.isClosed) _drawStreamController.close();
    if (!_clearStreamController.isClosed) _clearStreamController.close();
  }

  @override
  void dispose() {
    leaveRoom();
    super.dispose();
  }
}

final liveClassRoomProvider =
    StateNotifierProvider.autoDispose<LiveClassRoomNotifier, LiveClassRoomState>((ref) {
  final repo = ref.watch(liveClassRepositoryProvider);
  return LiveClassRoomNotifier(repository: repo);
});
