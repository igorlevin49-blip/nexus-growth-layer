
-- Remove subscription commission duplicates by source_id + level (different source_ref formats)
-- Keep backfill format (subscription_*_s1_level_*) as the canonical one

WITH duplicates_to_remove AS (
  SELECT t.id
  FROM transactions t
  WHERE t.type = 'commission'
    AND t.structure_type = 'primary'
    AND t.source_id IS NOT NULL
    AND t.source_ref IS NOT NULL
    -- This is the OLD format (just subscription_id without prefix)
    AND t.source_ref NOT LIKE 'subscription_%_s1_level_%'
    -- Has a duplicate with the NEW format
    AND EXISTS (
      SELECT 1 FROM transactions t2
      WHERE t2.source_id = t.source_id
        AND t2.level = t.level
        AND t2.user_id = t.user_id
        AND t2.type = 'commission'
        AND t2.structure_type = 'primary'
        AND t2.source_ref LIKE 'subscription_%_s1_level_%'
    )
)
DELETE FROM transactions WHERE id IN (SELECT id FROM duplicates_to_remove);
