ALTER TABLE source_health
  DROP CONSTRAINT source_health_connection_state_check;

ALTER TABLE source_health
  ADD CONSTRAINT source_health_connection_state_check
  CHECK (connection_state IN (
    'Connected',
    'Setup required',
    'Unavailable',
    'Rate limited',
    'Delayed'
  ));
