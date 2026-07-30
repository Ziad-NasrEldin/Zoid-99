ALTER TABLE single_user_settings
  ADD COLUMN digest_hour smallint NOT NULL DEFAULT 18 CHECK (digest_hour BETWEEN 0 AND 23),
  ADD COLUMN quiet_hours_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN quiet_hours_start text NOT NULL DEFAULT '22:00'
    CHECK (quiet_hours_start ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  ADD COLUMN quiet_hours_end text NOT NULL DEFAULT '08:00'
    CHECK (quiet_hours_end ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  ADD COLUMN locale text NOT NULL DEFAULT 'en' CHECK (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  ADD COLUMN time_zone text NOT NULL DEFAULT 'Africa/Cairo'
    CHECK (time_zone = 'UTC' OR time_zone ~ '^[A-Za-z_]+(/[A-Za-z0-9_+.-]+)+$'),
  ADD COLUMN version bigint NOT NULL DEFAULT 1 CHECK (version > 0);

CREATE TABLE mutation_idempotency (
  scope text NOT NULL CHECK (length(scope) BETWEEN 1 AND 300),
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 255),
  request_hash text NOT NULL CHECK (length(request_hash) = 64),
  status_code smallint NOT NULL CHECK (status_code BETWEEN 200 AND 599),
  response_body jsonb NOT NULL,
  response_headers jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  PRIMARY KEY (scope, idempotency_key)
);

CREATE INDEX mutation_idempotency_expiry_idx ON mutation_idempotency (expires_at);
