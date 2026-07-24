ALTER TABLE watchlist_entries
  DROP CONSTRAINT watchlist_entries_kind_check;

ALTER TABLE watchlist_entries
  ADD CONSTRAINT watchlist_entries_kind_check
  CHECK (kind IN ('Creator', 'Official source', 'Company', 'Keyword', 'Topic', 'Country', 'Language'));
