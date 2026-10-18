import { prisma } from '../utils/prisma.js';

async function main() {
  const classes = await prisma.liveClass.findMany({
    include: {
      attendances: true,
      recordings: true,
    },
    orderBy: { createdAt: 'asc' },
  });

  console.log(`Total live classes in DB: ${classes.length}`);
  const groupMap = new Map<string, typeof classes>();

  for (const c of classes) {
    const key = `${c.batchId}_${c.scheduledAt.toISOString()}`;
    if (!groupMap.has(key)) {
      groupMap.set(key, []);
    }
    groupMap.get(key)!.push(c);
  }

  let dupCount = 0;
  for (const [key, group] of groupMap.entries()) {
    if (group.length > 1) {
      dupCount++;
      console.log(`\nDuplicate Group [${key}]: ${group.length} rows`);
      group.forEach((row, idx) => {
        console.log(`  #${idx + 1}: ID=${row.id}, title="${row.title}", status=${row.status}, room=${row.livekitRoom}, attendances=${row.attendances.length}, recordings=${row.recordings.length}, createdAt=${row.createdAt.toISOString()}`);
      });
    }
  }

  console.log(`\nTotal duplicate groups found: ${dupCount}`);
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
