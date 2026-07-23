CREATE TABLE single_user_settings (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  refresh_minutes integer NOT NULL DEFAULT 15 CHECK (refresh_minutes BETWEEN 5 AND 60),
  notifications_enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO single_user_settings (singleton) VALUES (true) ON CONFLICT DO NOTHING;

CREATE TABLE encrypted_configs (
  config_key text PRIMARY KEY CHECK (length(config_key) BETWEEN 1 AND 200),
  encrypted_value text NOT NULL CHECK (encrypted_value LIKE 'v1.%'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE source_health (
  source_group text PRIMARY KEY CHECK (source_group IN (
    'YouTube', 'Google Trends', 'Instagram', 'Comments', 'US & Official', 'X'
  )),
  sort_order smallint NOT NULL UNIQUE CHECK (sort_order BETWEEN 1 AND 6),
  connection_state text NOT NULL CHECK (connection_state IN (
    'Connected', 'Setup required', 'Unavailable', 'Rate limited', 'Delayed'
  )),
  last_activity_at timestamptz,
  evidence text NOT NULL CHECK (length(evidence) > 0),
  repair_action text NOT NULL CHECK (length(repair_action) > 0),
  failure_code text,
  failure_detail text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO source_health (source_group, sort_order, connection_state, evidence, repair_action) VALUES
  ('YouTube', 1, 'Setup required', 'No account or API credential has been connected.', 'Configure'),
  ('Google Trends', 2, 'Setup required', 'No account or API credential has been connected.', 'Configure'),
  ('Instagram', 3, 'Setup required', 'No account or API credential has been connected.', 'Configure'),
  ('Comments', 4, 'Setup required', 'No account or API credential has been connected.', 'Configure'),
  ('US & Official', 5, 'Setup required', 'No account or API credential has been connected.', 'Configure'),
  ('X', 6, 'Setup required', 'No account or API credential has been connected.', 'Configure')
ON CONFLICT DO NOTHING;

CREATE TABLE source_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_group text NOT NULL CHECK (source_group IN (
    'YouTube', 'Google Trends', 'Instagram', 'Comments', 'US & Official', 'X'
  )),
  external_id text NOT NULL CHECK (length(external_id) > 0),
  title text NOT NULL CHECK (length(title) > 0),
  summary text NOT NULL DEFAULT '',
  author text NOT NULL DEFAULT '',
  source_url text NOT NULL CHECK (source_url ~ '^https://'),
  published_at timestamptz NOT NULL,
  collected_at timestamptz NOT NULL,
  language text NOT NULL CHECK (length(language) > 0),
  country text NOT NULL CHECK (length(country) > 0),
  topic_key text NOT NULL CHECK (length(topic_key) > 0),
  is_original_source boolean NOT NULL DEFAULT false,
  credibility numeric(4,3) NOT NULL CHECK (credibility BETWEEN 0 AND 1),
  engagement bigint NOT NULL DEFAULT 0 CHECK (engagement >= 0),
  verification text NOT NULL CHECK (verification IN ('Confirmed', 'Disputed', 'Unverified')),
  raw_payload jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_group, external_id)
);

CREATE INDEX source_items_published_at_idx ON source_items (published_at DESC);
CREATE INDEX source_items_topic_key_idx ON source_items (topic_key);
CREATE INDEX source_items_source_group_idx ON source_items (source_group, collected_at DESC);

CREATE TABLE story_clusters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cluster_key text NOT NULL UNIQUE CHECK (length(cluster_key) > 0),
  topic_key text NOT NULL CHECK (length(topic_key) > 0),
  verification text NOT NULL CHECK (verification IN ('Confirmed', 'Disputed', 'Unverified')),
  origin_state text NOT NULL CHECK (origin_state IN ('Identified', 'Unknown')),
  original_source_item_id uuid REFERENCES source_items(id) ON DELETE SET NULL,
  earliest_published_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (origin_state = 'Identified' AND original_source_item_id IS NOT NULL)
    OR (origin_state = 'Unknown' AND original_source_item_id IS NULL)
  )
);

CREATE INDEX story_clusters_topic_key_idx ON story_clusters (topic_key, earliest_published_at DESC);

CREATE TABLE story_cluster_items (
  story_cluster_id uuid NOT NULL REFERENCES story_clusters(id) ON DELETE CASCADE,
  source_item_id uuid NOT NULL UNIQUE REFERENCES source_items(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_cluster_id, source_item_id)
);

ALTER TABLE story_clusters
  ADD CONSTRAINT story_clusters_original_membership_fk
  FOREIGN KEY (id, original_source_item_id)
  REFERENCES story_cluster_items (story_cluster_id, source_item_id)
  DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE opportunities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_cluster_id uuid NOT NULL UNIQUE REFERENCES story_clusters(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(title) > 0),
  brief text NOT NULL,
  freshness_score smallint NOT NULL CHECK (freshness_score BETWEEN 0 AND 20),
  credibility_score smallint NOT NULL CHECK (credibility_score BETWEEN 0 AND 20),
  momentum_score smallint NOT NULL CHECK (momentum_score BETWEEN 0 AND 20),
  creator_activity_score smallint NOT NULL CHECK (creator_activity_score BETWEEN 0 AND 10),
  arabic_coverage_gap_score smallint NOT NULL CHECK (arabic_coverage_gap_score BETWEEN 0 AND 15),
  regional_relevance_score smallint NOT NULL CHECK (regional_relevance_score BETWEEN 0 AND 15),
  regional_explanation text NOT NULL,
  coverage_explanation text NOT NULL,
  disposition text NOT NULL DEFAULT 'active' CHECK (
    disposition IN ('active', 'saved', 'watched', 'dismissed', 'muted')
  ),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX opportunities_rank_idx ON opportunities (
  (
    freshness_score + credibility_score + momentum_score +
    creator_activity_score + arabic_coverage_gap_score + regional_relevance_score
  ) DESC
);
CREATE INDEX opportunities_disposition_idx ON opportunities (disposition);

CREATE FUNCTION ensure_opportunity_has_evidence() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM story_cluster_items WHERE story_cluster_id = NEW.story_cluster_id
  ) THEN
    RAISE EXCEPTION 'opportunity requires at least one source item'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER opportunities_require_evidence
AFTER INSERT OR UPDATE OF story_cluster_id ON opportunities
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION ensure_opportunity_has_evidence();

CREATE TABLE watchlist_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN (
    'Creator', 'Official source', 'Keyword', 'Topic', 'Country', 'Language'
  )),
  value text NOT NULL CHECK (length(value) BETWEEN 1 AND 500),
  normalized_value text GENERATED ALWAYS AS (lower(btrim(value))) STORED,
  high_priority boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (kind, normalized_value)
);

CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opportunity_id uuid NOT NULL REFERENCES opportunities(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(title) > 0),
  delivery text NOT NULL CHECK (delivery IN ('Immediate', 'Digest')),
  created_at timestamptz NOT NULL DEFAULT now(),
  is_read boolean NOT NULL DEFAULT false,
  UNIQUE (opportunity_id, delivery)
);

CREATE INDEX notifications_unread_idx ON notifications (created_at DESC) WHERE NOT is_read;
