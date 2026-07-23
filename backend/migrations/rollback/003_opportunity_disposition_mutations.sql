DROP INDEX IF EXISTS opportunities_disposition_sync_idx;

ALTER TABLE opportunities
  DROP COLUMN IF EXISTS disposition_mutation_id,
  DROP COLUMN IF EXISTS disposition_updated_at;
