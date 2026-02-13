-- Clocked-In Backend Database Initialization
-- PostgreSQL 15+

-- =============================================================================
-- USERS TABLE
-- =============================================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE,
    username VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100),
    avatar_url TEXT,
    status_message VARCHAR(280),
    apple_user_id VARCHAR(255) UNIQUE,
    settings JSONB NOT NULL DEFAULT '{
        "nudge_shake": true,
        "nudge_sound": true,
        "nudge_notification": true,
        "invisible": false,
        "hidden_apps": [],
        "share_window_title": true,
        "share_browser_domain": true
    }'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- FRIENDSHIPS TABLE
-- =============================================================================
CREATE TABLE friendships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id_1 UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_id_2 UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT friendships_ordered_pair CHECK (user_id_1 < user_id_2),
    CONSTRAINT friendships_unique_pair UNIQUE (user_id_1, user_id_2)
);

-- =============================================================================
-- FRIEND REQUESTS TABLE
-- =============================================================================
CREATE TABLE friend_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    CONSTRAINT friend_requests_no_self CHECK (sender_id != recipient_id)
);

-- =============================================================================
-- INDEXES
-- =============================================================================
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_apple_user_id ON users(apple_user_id);
CREATE INDEX idx_friendships_user1 ON friendships(user_id_1);
CREATE INDEX idx_friendships_user2 ON friendships(user_id_2);
CREATE INDEX idx_friend_requests_recipient ON friend_requests(recipient_id, status);
CREATE INDEX idx_friend_requests_sender ON friend_requests(sender_id, status);

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Returns all friend IDs for a given user
CREATE OR REPLACE FUNCTION get_friend_ids(uid UUID)
RETURNS SETOF UUID
LANGUAGE sql
STABLE
AS $$
    SELECT user_id_2 AS friend_id
    FROM friendships
    WHERE user_id_1 = uid
    UNION
    SELECT user_id_1 AS friend_id
    FROM friendships
    WHERE user_id_2 = uid;
$$;

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- Auto-update updated_at on users table
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
