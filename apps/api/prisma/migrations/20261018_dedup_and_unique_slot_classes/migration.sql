-- Migration: 20261018_dedup_and_unique_slot_classes
-- Purpose: Deduplicate LiveClass rows, link attendances/recordings to the winner, and enforce unique(slotId, scheduledAt)

-- 1. Deduplicate existing LiveClass rows before adding unique constraint
WITH ranked_classes AS (
  SELECT 
    lc.id,
    lc."slotId",
    lc."scheduledAt",
    ROW_NUMBER() OVER (
      PARTITION BY lc."slotId", lc."scheduledAt" 
      ORDER BY 
        CASE WHEN lc.status = 'LIVE' THEN 1 ELSE 2 END,
        (SELECT COUNT(*) FROM "Attendance" a WHERE a."liveClassId" = lc.id) DESC,
        (SELECT COUNT(*) FROM "Recording" r WHERE r."liveClassId" = lc.id) DESC,
        lc."createdAt" DESC
    ) as rn,
    FIRST_VALUE(lc.id) OVER (
      PARTITION BY lc."slotId", lc."scheduledAt" 
      ORDER BY 
        CASE WHEN lc.status = 'LIVE' THEN 1 ELSE 2 END,
        (SELECT COUNT(*) FROM "Attendance" a WHERE a."liveClassId" = lc.id) DESC,
        (SELECT COUNT(*) FROM "Recording" r WHERE r."liveClassId" = lc.id) DESC,
        lc."createdAt" DESC
    ) as winner_id
  FROM "LiveClass" lc
  WHERE lc."slotId" IS NOT NULL
)
-- Reassign attendances & recordings to winner
UPDATE "Attendance" SET "liveClassId" = rc.winner_id
FROM ranked_classes rc
WHERE "Attendance"."liveClassId" = rc.id AND rc.rn > 1;

UPDATE "Recording" SET "liveClassId" = rc.winner_id
FROM ranked_classes rc
WHERE "Recording"."liveClassId" = rc.id AND rc.rn > 1;

-- Delete loser duplicate classes
DELETE FROM "LiveClass"
WHERE id IN (
  SELECT id FROM (
    SELECT lc.id, ROW_NUMBER() OVER (
      PARTITION BY lc."slotId", lc."scheduledAt" 
      ORDER BY 
        CASE WHEN lc.status = 'LIVE' THEN 1 ELSE 2 END,
        (SELECT COUNT(*) FROM "Attendance" a WHERE a."liveClassId" = lc.id) DESC,
        (SELECT COUNT(*) FROM "Recording" r WHERE r."liveClassId" = lc.id) DESC,
        lc."createdAt" DESC
    ) as rn
    FROM "LiveClass" lc
    WHERE lc."slotId" IS NOT NULL
  ) ranked WHERE rn > 1
);

-- 2. Add column slotId if it doesn't already exist
ALTER TABLE "LiveClass" ADD COLUMN IF NOT EXISTS "slotId" TEXT;

-- 3. Add foreign key constraint to TimetableSlot if not exists
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'LiveClass_slotId_fkey'
  ) THEN
    ALTER TABLE "LiveClass" ADD CONSTRAINT "LiveClass_slotId_fkey" 
      FOREIGN KEY ("slotId") REFERENCES "TimetableSlot"("id") 
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

-- 4. Create unique index on (slotId, scheduledAt)
CREATE UNIQUE INDEX IF NOT EXISTS "LiveClass_slotId_scheduledAt_key" 
  ON "LiveClass"("slotId", "scheduledAt");
