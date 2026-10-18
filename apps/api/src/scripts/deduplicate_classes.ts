import { deduplicateLiveClasses } from '../services/deduplicate.service.js';
import { prisma } from '../utils/prisma.js';

async function run() {
  console.log('[Dedup] Starting LiveClass deduplication check...');
  const report = await deduplicateLiveClasses();
  console.log('[Dedup] Result:');
  console.log(`  - Duplicate groups found: ${report.duplicateGroupsFound}`);
  console.log(`  - Duplicate classes removed: ${report.classesRemovedCount}`);
  console.log(`  - Attendances relinked: ${report.attendancesRelinkedCount}`);
  console.log(`  - Recordings relinked: ${report.recordingsRelinkedCount}`);
  if (report.details.length > 0) {
    console.log('  - Details:', JSON.stringify(report.details, null, 2));
  } else {
    console.log('  - No duplicates detected.');
  }
}

run()
  .catch((err) => {
    console.error('[Dedup] Failed:', err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
