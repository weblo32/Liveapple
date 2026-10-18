import { prisma } from '../utils/prisma.js';
import { AppError } from '../errors/AppError.js';
import { logAudit } from './audit.service.js';
import { LiveKitService } from './livekit.service.js';
import { NotificationService } from './notification.service.js';
import { emitToUser, emitToInstitute } from '../gateway/socket.js';
import { env, getLiveKitStatus } from '../config/env.js';

export interface CreateClassInput {
  batchId: string;
  title: string;
  scheduledAt: string | Date;
}

export interface ListClassesQuery {
  batchId?: string;
  status?: string;
  fromDate?: string;
  toDate?: string;
}

export class LiveClassService {
  /**
   * Automatically generate LiveClass records for upcoming days from recurring TimetableSlots
   */
  static async generateUpcomingFromSlots(
    instituteId: string,
    teacherId: string,
    daysAhead: number = 7
  ) {
    const institute = await prisma.institute.findUnique({
      where: { id: instituteId },
    });

    if (!institute) {
      throw new AppError('NOT_FOUND', 'Institute not found', 404);
    }

    const slots = await prisma.timetableSlot.findMany({
      where: {
        instituteId,
        teacherId,
        recurring: true,
      },
      include: {
        batch: true,
      },
    });

    const generatedClasses: any[] = [];
    const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000; // 5 hours 30 mins in milliseconds

    for (let dayOffset = 0; dayOffset < daysAhead; dayOffset++) {
      // Calculate target day in IST
      const targetIst = new Date(Date.now() + IST_OFFSET_MS + dayOffset * 24 * 60 * 60 * 1000);
      const istYear = targetIst.getUTCFullYear();
      const istMonth = targetIst.getUTCMonth();
      const istDate = targetIst.getUTCDate();
      const currentDayOfWeek = targetIst.getUTCDay(); // 0 (Sun) to 6 (Sat) in IST

      const matchingSlots = slots.filter((s) => s.dayOfWeek === currentDayOfWeek);

      for (const slot of matchingSlots) {
        const hours = Math.floor(slot.startMin / 60);
        const minutes = slot.startMin % 60;
        
        // Exact UTC timestamp for this slot's time in IST
        const scheduledUtcMs = Date.UTC(istYear, istMonth, istDate, hours, minutes, 0, 0) - IST_OFFSET_MS;
        const scheduledTime = new Date(scheduledUtcMs);

        // Do not generate if class already ended more than 15 mins ago
        if (scheduledTime.getTime() < Date.now() - 15 * 60 * 1000) {
          continue;
        }

        const windowStart = new Date(scheduledTime.getTime() - 30 * 60 * 1000);
        const windowEnd = new Date(scheduledTime.getTime() + 30 * 60 * 1000);

        const existingClass = await prisma.liveClass.findFirst({
          where: {
            instituteId,
            OR: [
              { slotId: slot.id, scheduledAt: scheduledTime },
              {
                batchId: slot.batchId,
                scheduledAt: {
                  gte: windowStart,
                  lte: windowEnd,
                },
              },
            ],
          },
        });

        if (!existingClass) {
          const roomSuffix = `${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 6)}`;
          const livekitRoom = `room_${institute.slug}_b${slot.batchId.slice(-4)}_${roomSuffix}`;

          const newClass = await prisma.liveClass.create({
            data: {
              instituteId,
              batchId: slot.batchId,
              teacherId: slot.teacherId,
              slotId: slot.id,
              title: `${slot.batch.subject}: ${slot.batch.name}`,
              scheduledAt: scheduledTime,
              status: 'SCHEDULED',
              livekitRoom,
            },
            include: {
              batch: { select: { id: true, name: true, subject: true } },
              teacher: { select: { id: true, name: true } },
            },
          });

          generatedClasses.push(newClass);
        }
      }
    }

    return {
      generatedCount: generatedClasses.length,
      classes: generatedClasses,
    };
  }

  /**
   * Start a class directly from a timetable slot (idempotent).
   * Finds existing class for slotId + target date, or creates one, and starts it.
   */
  static async startFromSlot(
    instituteId: string,
    user: { id: string; role: string },
    slotId: string,
    targetDate: Date = new Date()
  ) {
    const slot = await prisma.timetableSlot.findFirst({
      where: { id: slotId, instituteId },
      include: { batch: true },
    });

    if (!slot) {
      throw new AppError('NOT_FOUND', 'Timetable slot not found', 404);
    }

    if (user.role === 'TEACHER' && slot.teacherId !== user.id) {
      throw new AppError('FORBIDDEN', 'Only the assigned teacher can start this slot', 403);
    }

    const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
    const targetIst = new Date(targetDate.getTime() + IST_OFFSET_MS);
    const istYear = targetIst.getUTCFullYear();
    const istMonth = targetIst.getUTCMonth();
    const istDate = targetIst.getUTCDate();
    const hours = Math.floor(slot.startMin / 60);
    const minutes = slot.startMin % 60;
    const scheduledUtcMs = Date.UTC(istYear, istMonth, istDate, hours, minutes, 0, 0) - IST_OFFSET_MS;
    const scheduledTime = new Date(scheduledUtcMs);

    const windowStart = new Date(scheduledTime.getTime() - 45 * 60 * 1000);
    const windowEnd = new Date(scheduledTime.getTime() + 45 * 60 * 1000);

    // Look for existing class
    let liveClass = await prisma.liveClass.findFirst({
      where: {
        instituteId,
        OR: [
          { slotId: slot.id, scheduledAt: scheduledTime },
          {
            slotId: slot.id,
            status: { in: ['SCHEDULED', 'LIVE'] },
            scheduledAt: { gte: windowStart, lte: windowEnd },
          },
        ],
      },
    });

    if (!liveClass) {
      const institute = await prisma.institute.findUnique({ where: { id: instituteId } });
      const roomSuffix = `${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 6)}`;
      const livekitRoom = `room_${institute?.slug || 'inst'}_b${slot.batchId.slice(-4)}_${roomSuffix}`;

      liveClass = await prisma.liveClass.create({
        data: {
          instituteId,
          batchId: slot.batchId,
          teacherId: slot.teacherId,
          slotId: slot.id,
          title: `${slot.batch.subject}: ${slot.batch.name}`,
          scheduledAt: scheduledTime,
          status: 'SCHEDULED',
          livekitRoom,
        },
      });
    }

    // Start class idempotently (ends other LIVE classes for this teacher)
    return await this.startClass(instituteId, user, liveClass.id);
  }

  /**
   * Create a single one-off scheduled class
   */
  static async createClass(
    instituteId: string,
    user: { id: string; role: string },
    input: CreateClassInput
  ) {
    const { batchId, title, scheduledAt } = input;

    if (!title || title.trim().length < 2) {
      throw new AppError('BAD_REQUEST', 'Class title is required', 400);
    }

    const scheduledDate = new Date(scheduledAt);
    if (isNaN(scheduledDate.getTime())) {
      throw new AppError('BAD_REQUEST', 'Invalid scheduled date/time', 400);
    }

    const batch = await prisma.batch.findFirst({
      where: { id: batchId, instituteId },
    });

    if (!batch) {
      throw new AppError('NOT_FOUND', 'Batch not found', 404);
    }

    if (user.role === 'TEACHER' && batch.teacherId !== user.id) {
      throw new AppError('FORBIDDEN', 'You do not have permission to schedule classes for this batch', 403);
    }

    const institute = await prisma.institute.findUnique({ where: { id: instituteId } });
    const slug = institute?.slug || 'inst';
    const roomSuffix = `${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 6)}`;
    const livekitRoom = `room_${slug}_b${batch.id.slice(-4)}_${roomSuffix}`;

    const liveClass = await prisma.liveClass.create({
      data: {
        instituteId,
        batchId,
        teacherId: batch.teacherId,
        title: title.trim(),
        scheduledAt: scheduledDate,
        status: 'SCHEDULED',
        livekitRoom,
      },
      include: {
        batch: { select: { id: true, name: true, subject: true } },
        teacher: { select: { id: true, name: true, email: true } },
      },
    });

    await logAudit({
      instituteId,
      actorId: user.id,
      action: 'LIVE_CLASS_SCHEDULED',
      entity: `LiveClass:${liveClass.id}`,
      meta: { batchId, title: liveClass.title, scheduledAt: liveClass.scheduledAt },
    });

    // Emit realtime socket events to enrolled students & institute
    try {
      const enrollments = await prisma.enrollment.findMany({
        where: { instituteId, batchId, status: 'ACTIVE' },
        select: { studentId: true },
      });
      const payload = {
        classId: liveClass.id,
        batchId: liveClass.batchId,
        title: liveClass.title,
        scheduledAt: liveClass.scheduledAt.toISOString(),
      };
      for (const e of enrollments) {
        emitToUser(e.studentId, 'class:scheduled', payload);
      }
      emitToInstitute(instituteId, 'class:scheduled', payload);
    } catch (err) {
      console.error('[REALTIME-SOCKET-ERROR] Failed to emit class:scheduled:', err);
    }

    return liveClass;
  }

  /**
   * Teacher starts the live class (Status -> LIVE)
   */
  static async startClass(
    instituteId: string,
    user: { id: string; role: string },
    classId: string
  ) {
    const liveClass = await prisma.liveClass.findFirst({
      where: { id: classId, instituteId },
      include: {
        batch: {
          include: {
            enrollments: {
              where: { status: 'ACTIVE' },
              select: { studentId: true },
            },
          },
        },
      },
    });

    if (!liveClass) {
      throw new AppError('NOT_FOUND', 'Live class not found', 404);
    }

    if (user.role === 'TEACHER' && liveClass.teacherId !== user.id) {
      throw new AppError('FORBIDDEN', 'Only the assigned teacher can start this class', 403);
    }

    // 3.1 Hardening: Starting a class ends the same teacher's other LIVE classes
    await prisma.liveClass.updateMany({
      where: {
        instituteId,
        teacherId: liveClass.teacherId,
        status: 'LIVE',
        id: { not: classId },
      },
      data: { status: 'ENDED' },
    });

    const updated = await prisma.liveClass.update({
      where: { id: classId },
      data: { status: 'LIVE' },
      include: {
        batch: { select: { id: true, name: true, subject: true } },
        teacher: { select: { id: true, name: true, email: true } },
      },
    });

    await logAudit({
      instituteId,
      actorId: user.id,
      action: 'LIVE_CLASS_STARTED',
      entity: `LiveClass:${classId}`,
      meta: { room: updated.livekitRoom, title: updated.title },
    });

    // Send push and in-app notifications to all active enrolled students
    try {
      await NotificationService.notifyClassLive(instituteId, classId);
    } catch (err) {
      console.error('[NOTIFICATION-ERROR] Failed to send live class notifications:', err);
    }

    // Emit real-time socket 'class:live' to all enrolled students for instant UI sync
    try {
      const livepayload = {
        classId: updated.id,
        batchId: updated.batchId,
        title: updated.title,
        livekitRoom: updated.livekitRoom,
        teacherName: updated.teacher.name,
        batchName: updated.batch.name,
      };
      const enrollments = liveClass.batch.enrollments;
      for (const e of enrollments) {
        emitToUser(e.studentId, 'class:live', livepayload);
      }
      emitToInstitute(instituteId, 'class:live', livepayload);
    } catch (err) {
      console.error('[REALTIME-SOCKET-ERROR] Failed to emit class:live:', err);
    }

    return updated;
  }

  /**
   * Generate signed LiveKit token for authenticated participant
   */
  static async generateParticipantToken(
    instituteId: string,
    user: { id: string; name: string; role: 'ADMIN' | 'TEACHER' | 'STUDENT' },
    classId: string
  ) {
    const liveClass = await prisma.liveClass.findFirst({
      where: { id: classId, instituteId },
      include: {
        batch: {
          include: {
            enrollments: {
              where: { status: 'ACTIVE' },
            },
          },
        },
      },
    });

    if (!liveClass) {
      throw new AppError('NOT_FOUND', 'Live class not found', 404);
    }

    const isHost = user.role === 'ADMIN' || (user.role === 'TEACHER' && liveClass.teacherId === user.id);

    if (user.role === 'STUDENT') {
      const student = await prisma.user.findUnique({
        where: { id: user.id },
        select: { creatorTeacherId: true },
      });
      if (student?.creatorTeacherId && liveClass.teacherId !== student.creatorTeacherId) {
        throw new AppError('FORBIDDEN', 'You do not have access to live classes from other teachers', 403);
      }
      const isEnrolled = liveClass.batch.enrollments.some((e) => e.studentId === user.id);
      if (!isEnrolled) {
        throw new AppError('FORBIDDEN', 'You must be enrolled in this batch to join this class', 403);
      }

      // Record attendance
      await prisma.attendance.create({
        data: {
          instituteId,
          liveClassId: classId,
          studentId: user.id,
        },
      });
    }

    // Verify LiveKit configuration in production
    const lkStatus = getLiveKitStatus();
    if (env.NODE_ENV === 'production' && !lkStatus.configured) {
      throw new AppError('LIVEKIT_NOT_CONFIGURED', 'Video server abhi set nahi hua', 503);
    }

    // Generate signed LiveKit JWT
    const token = await LiveKitService.createParticipantToken({
      roomName: liveClass.livekitRoom,
      participantId: user.id,
      participantName: user.name,
      role: user.role,
      metadata: {
        instituteId,
        batchId: liveClass.batchId,
        isHost,
      },
    });

    return {
      token,
      serverUrl: env.LIVEKIT_URL,
      livekitRoom: liveClass.livekitRoom,
      isHost,
      liveClass: {
        id: liveClass.id,
        title: liveClass.title,
        status: liveClass.status,
        batchName: liveClass.batch.name,
        subject: liveClass.batch.subject,
      },
    };
  }

  /**
   * Teacher ends the live class (Status -> ENDED)
   */
  static async endClass(
    instituteId: string,
    user: { id: string; role: string },
    classId: string
  ) {
    const liveClass = await prisma.liveClass.findFirst({
      where: { id: classId, instituteId },
    });

    if (!liveClass) {
      throw new AppError('NOT_FOUND', 'Live class not found', 404);
    }

    if (user.role === 'TEACHER' && liveClass.teacherId !== user.id) {
      throw new AppError('FORBIDDEN', 'Only the assigned teacher can end this class', 403);
    }

    // Close LiveKit room
    await LiveKitService.deleteRoom(liveClass.livekitRoom);

    // Update attendance leftAt for active sessions
    await prisma.attendance.updateMany({
      where: {
        instituteId,
        liveClassId: classId,
        leftAt: null,
      },
      data: {
        leftAt: new Date(),
      },
    });

    const updated = await prisma.liveClass.update({
      where: { id: classId },
      data: { status: 'ENDED' },
    });

    await logAudit({
      instituteId,
      actorId: user.id,
      action: 'LIVE_CLASS_ENDED',
      entity: `LiveClass:${classId}`,
      meta: { room: liveClass.livekitRoom },
    });

    return updated;
  }

  /**
   * Host control: Mute all students
   */
  static async hostMuteAll(
    instituteId: string,
    user: { id: string; role: string },
    classId: string
  ) {
    const liveClass = await prisma.liveClass.findFirst({
      where: { id: classId, instituteId },
    });

    if (!liveClass) {
      throw new AppError('NOT_FOUND', 'Live class not found', 404);
    }

    if (user.role === 'TEACHER' && liveClass.teacherId !== user.id) {
      throw new AppError('FORBIDDEN', 'Only host can execute room controls', 403);
    }

    await LiveKitService.muteAll(liveClass.livekitRoom);

    return { success: true, message: 'All participants muted' };
  }

  /**
   * Host control: Remove/disconnect student
   */
  static async hostRemoveParticipant(
    instituteId: string,
    user: { id: string; role: string },
    classId: string,
    participantId: string
  ) {
    const liveClass = await prisma.liveClass.findFirst({
      where: { id: classId, instituteId },
    });

    if (!liveClass) {
      throw new AppError('NOT_FOUND', 'Live class not found', 404);
    }

    if (user.role === 'TEACHER' && liveClass.teacherId !== user.id) {
      throw new AppError('FORBIDDEN', 'Only host can remove participants', 403);
    }

    await LiveKitService.removeParticipant(liveClass.livekitRoom, participantId);

    return { success: true, message: 'Participant removed' };
  }

  /**
   * List live classes based on user role and filters
   */
  static async listClasses(
    instituteId: string,
    user: { id: string; role: string },
    query: ListClassesQuery = {}
  ) {
    const whereClause: any = { instituteId };

    if (query.batchId) {
      whereClause.batchId = query.batchId;
    }

    if (query.status && ['SCHEDULED', 'LIVE', 'ENDED', 'CANCELLED'].includes(query.status.toUpperCase())) {
      whereClause.status = query.status.toUpperCase();
    }

    if (query.fromDate || query.toDate) {
      whereClause.scheduledAt = {};
      if (query.fromDate) whereClause.scheduledAt.gte = new Date(query.fromDate);
      if (query.toDate) whereClause.scheduledAt.lte = new Date(query.toDate);
    }

    if (user.role === 'STUDENT') {
      const student = await prisma.user.findUnique({
        where: { id: user.id },
        select: { creatorTeacherId: true },
      });
      const activeEnrollments = await prisma.enrollment.findMany({
        where: {
          instituteId,
          studentId: user.id,
          status: 'ACTIVE',
          ...(student?.creatorTeacherId ? { batch: { teacherId: student.creatorTeacherId } } : {}),
        },
        select: { batchId: true },
      });
      const batchIds = activeEnrollments.map((e) => e.batchId);
      if (query.batchId) {
        whereClause.batchId = batchIds.includes(query.batchId) ? query.batchId : { in: [] };
      } else {
        whereClause.batchId = { in: batchIds };
      }
      if (student?.creatorTeacherId) {
        whereClause.teacherId = student.creatorTeacherId;
      }
    } else if (user.role === 'TEACHER') {
      whereClause.teacherId = user.id;
    } else if (user.role === 'ADMIN' && (query as any).teacherId) {
      whereClause.teacherId = (query as any).teacherId;
    }

    const classes = await prisma.liveClass.findMany({
      where: whereClause,
      orderBy: { scheduledAt: 'asc' },
      include: {
        batch: {
          select: {
            id: true,
            name: true,
            subject: true,
            joinCode: true,
          },
        },
        teacher: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
        _count: {
          select: { attendances: true },
        },
      },
    });

    return classes;
  }

  /**
   * Get single class details
   */
  static async getClassById(
    instituteId: string,
    user: { id: string; role: string },
    classId: string
  ) {
    const liveClass = await prisma.liveClass.findFirst({
      where: { id: classId, instituteId },
      include: {
        batch: {
          select: {
            id: true,
            name: true,
            subject: true,
            joinCode: true,
          },
        },
        teacher: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
        attendances: {
          include: {
            student: {
              select: {
                id: true,
                name: true,
                email: true,
              },
            },
          },
        },
        _count: {
          select: { attendances: true },
        },
      },
    });

    if (!liveClass) {
      throw new AppError('NOT_FOUND', 'Live class not found', 404);
    }

    return liveClass;
  }
}
