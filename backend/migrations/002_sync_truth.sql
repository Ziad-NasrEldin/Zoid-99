ALTER TABLE source_health
  ADD COLUMN data_truth text NOT NULL DEFAULT 'Missing'
  CHECK (data_truth IN ('Live', 'Cached', 'Missing', 'Delayed', 'Unavailable', 'Rate limited'));

ALTER TABLE notifications
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
