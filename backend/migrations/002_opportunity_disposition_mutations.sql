ALTER TABLE opportunities
  ADD COLUMN disposition_updated_at timestamptz,
  ADD COLUMN disposition_mutation_id uuid;

UPDATE opportunities
SET disposition_updated_at = updated_at
WHERE disposition_updated_at IS NULL;

ALTER TABLE opportunities
  ALTER COLUMN disposition_updated_at SET DEFAULT now(),
  ALTER COLUMN disposition_updated_at SET NOT NULL;

CREATE INDEX opportunities_disposition_sync_idx
  ON opportunities (disposition_updated_at DESC, disposition_mutation_id);
