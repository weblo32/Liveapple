import { prisma } from '../utils/prisma.js';

export interface DedupReport {
  duplicateGroupsFound: number;
  classesRemovedCount: number;
  attendancesRelinkedCount: number;
  recordingsRelinkedCount: number;
  details: Array<{
    winnerId: string;
    removedIds: string[];
    scheduledAt: string;
    batchId: string;
    slotId?: string | null;
  }>;
}

/**
 * Idempotently merges duplicate LiveClass entries.
 * For any duplicates sharing (slotId + scheduledAt) or (batchId + scheduledAt when slotId is null):
 * - Keeps the row with status 'LIVE', or most attendances, or most recordings, or latest createdAt.
 * - Relinks all Attendances and Recordings from duplicate rows to the winner.
 * - Safely deletes the duplicate rows.
 */
export async function deduplicateLiveClasses(): Promise<DedupReport> {
  const classes = await prisma.liveClass.findMany({
    include: {
      attendances: true,
      recordings: true,
    },
    orderBy: { createdAt: 'desc' },
  });

  const groups = new Map<string, typeof classes>();

  for (const c of classes) {
    // Key by slotId + scheduledAt ISO, or fallback to batchId + scheduledAt ISO
    const key = c.slotId
      ? `slot_${c.slotId}_${c.scheduledAt.toISOString()}`
      : `batch_${c.batchId}_${c.scheduledAt.toISOString()}`;

    if (!groups.has(key)) {
      groups.set(key, []);
    }
    groups.get(key)!.push(c);
  }

  let duplicateGroupsFound = 0;
  let classesRemovedCount = 0;
  let attendancesRelinkedCount = 0;
  let recordingsRelinkedCount = 0;
  const details: DedupReport['details'] = [];

  for (const [, classList] of groups.entries()) {
    if (classList.length <= 1) continue;

    duplicateGroupsFound++;

    // Pick winner: LIVE status first, then highest attendance count, then highest recordings count, then latest createdAt
    classList.sort((a, b) => {
      if (a.status === 'LIVE' && b.status !== 'LIVE') return -1;
      if (b.status === 'LIVE' && a.status !== 'LIVE') return 1;
      const attDiff = b.attendances.length - a.attendances.length;
      if (attDiff !== 0) return attDiff;
      const recDiff = b.recordings.length - a.recordings.length;
      if (recDiff !== 0) return recDiff;
      return b.createdAt.getTime() - a.createdAt.getTime();
    });

    const winner = classList[0];
    const losers = classList.slice(1);
    const removedIds: string[] = [];

    for (const loser of losers) {
      // Relink attendances
      if (loser.attendances.length > 0) {
        const res = await prisma.attendance.updateMany({
          where: { liveClassId: loser.id },
          data: { liveClassId: winner.id },
        });
        attendancesRelinkedCount += res.count;
      }

      // Relink recordings
      if (loser.recordings.length > 0) {
        const res = await prisma.recording.updateMany({
          where: { liveClassId: loser.id },
          data: { liveClassId: winner.id },
        });
        recordingsRelinkedCount += res.count;
      }

      // Delete loser
      await prisma.liveClass.delete({
        where: { id: loser.id },
      });
      removedIds.push(loser.id);
      classesRemovedCount++;
    }

    details.push({
      winnerId: winner.id,
      removedIds,
      scheduledAt: winner.scheduledAt.toISOString(),
      batchId: winner.batchId,
      slotId: winner.slotId,
    });
  }

  return {
    duplicateGroupsFound,
    classesRemovedCount,
    attendancesRelinkedCount,
    recordingsRelinkedCount,
    details,
  };
}
