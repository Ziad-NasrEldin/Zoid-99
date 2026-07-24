-- Migration 005 adds Company to the watchlist kind enum.
-- The pre-005 schema cannot represent Company, so preserve those rows in an
-- explicit archive before restoring the older constraint.  Nothing is
-- silently relabeled or discarded.
CREATE TABLE IF NOT EXISTS watchlist_entries_company_archive (
  id uuid PRIMARY KEY,
  kind text NOT NULL CHECK (kind = 'Company'),
  value text NOT NULL CHECK (length(value) BETWEEN 1 AND 500),
  normalized_value text NOT NULL,
  high_priority boolean NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  archived_at timestamptz NOT NULL DEFAULT now(),
  archive_reason text NOT NULL DEFAULT 'Company watchlist entries are unsupported by the pre-005 schema'
);

INSERT INTO watchlist_entries_company_archive (
  id,
  kind,
  value,
  normalized_value,
  high_priority,
  created_at,
  updated_at,
  archived_at
)
SELECT id, kind, value, normalized_value, high_priority, created_at, updated_at, now()
FROM watchlist_entries
WHERE kind = 'Company'
ON CONFLICT (id) DO UPDATE SET
  kind = EXCLUDED.kind,
  value = EXCLUDED.value,
  normalized_value = EXCLUDED.normalized_value,
  high_priority = EXCLUDED.high_priority,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  archived_at = EXCLUDED.archived_at;

DELETE FROM watchlist_entries
WHERE kind = 'Company';

ALTER TABLE watchlist_entries
  DROP CONSTRAINT watchlist_entries_kind_check;

ALTER TABLE watchlist_entries
  ADD CONSTRAINT watchlist_entries_kind_check
  CHECK (kind IN ('Creator', 'Official source', 'Keyword', 'Topic', 'Country', 'Language'));
