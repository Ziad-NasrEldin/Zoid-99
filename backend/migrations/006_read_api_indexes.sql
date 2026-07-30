-- Read API indexes support the bounded filters and stable keyset ordering.
-- The source-group index supports opportunity source filters without scanning
-- every source item before joining through story_cluster_items.
CREATE INDEX source_items_source_group_id_idx
  ON source_items (source_group, id);

-- Country and language are exact-match read filters used with the evidence join.
CREATE INDEX source_items_country_id_idx
  ON source_items (country, id);

CREATE INDEX source_items_language_id_idx
  ON source_items (language, id);

-- Notifications use this exact keyset order for paginated history reads.
CREATE INDEX notifications_created_id_idx
  ON notifications (created_at DESC, id ASC);

-- Topic index reads group by topic and inspect recent cluster activity.
CREATE INDEX story_clusters_topic_activity_idx
  ON story_clusters (topic_key, updated_at DESC, earliest_published_at DESC, id);
