CREATE TABLE operator_sessions (
  token_hash text PRIMARY KEY CHECK (length(token_hash) = 64),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX operator_sessions_expires_at_idx ON operator_sessions (expires_at);
