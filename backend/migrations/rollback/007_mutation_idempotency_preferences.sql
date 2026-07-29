DROP INDEX IF EXISTS mutation_idempotency_expiry_idx;
DROP TABLE IF EXISTS mutation_idempotency;

ALTER TABLE single_user_settings
  DROP COLUMN IF EXISTS version,
  DROP COLUMN IF EXISTS time_zone,
  DROP COLUMN IF EXISTS locale,
  DROP COLUMN IF EXISTS quiet_hours_end,
  DROP COLUMN IF EXISTS quiet_hours_start,
  DROP COLUMN IF EXISTS quiet_hours_enabled,
  DROP COLUMN IF EXISTS digest_hour;
