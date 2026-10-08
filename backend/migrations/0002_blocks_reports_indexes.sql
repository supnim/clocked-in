-- 0002: blocks, reports, friend-request race protection, search index.

-- =============================================================================
-- BLOCKS
-- =============================================================================
CREATE TABLE IF NOT EXISTS blocks (
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT blocks_no_self CHECK (blocker_id <> blocked_id)
);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_id);

-- =============================================================================
-- REPORTS (moderation queue; reviewed out-of-band)
-- =============================================================================
CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason VARCHAR(500) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_reports_reported ON reports(reported_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_created ON reports(created_at DESC);

-- =============================================================================
-- FRIEND REQUESTS: at most one pending request per unordered pair
-- =============================================================================
-- Resolve any pre-existing duplicates (keep the oldest pending request).
UPDATE friend_requests fr
SET status = 'declined', updated_at = NOW()
WHERE fr.status = 'pending'
  AND EXISTS (
      SELECT 1 FROM friend_requests older
      WHERE older.status = 'pending'
        AND LEAST(older.sender_id, older.recipient_id) = LEAST(fr.sender_id, fr.recipient_id)
        AND GREATEST(older.sender_id, older.recipient_id) = GREATEST(fr.sender_id, fr.recipient_id)
        AND (older.created_at, older.id) < (fr.created_at, fr.id)
  );

CREATE UNIQUE INDEX IF NOT EXISTS uq_friend_requests_pending_pair
    ON friend_requests (LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id))
    WHERE status = 'pending';

-- =============================================================================
-- USER SEARCH: prefix match on lower(username)
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_users_username_lower_prefix
    ON users (lower(username) text_pattern_ops);
