-- ============================================================
--  DocAssist — Initial Database Schema
--  Migration: 001_init.sql
--  Run: psql -U docassist -d docassist_db -f 001_init.sql
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";      -- UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";       -- Crypto functions
CREATE EXTENSION IF NOT EXISTS "pg_trgm";        -- Trigram fuzzy search

-- ============================================================
--  ENUMS
-- ============================================================

CREATE TYPE user_status AS ENUM ('active', 'inactive', 'banned', 'pending_verification');
CREATE TYPE user_role AS ENUM ('admin', 'user');
CREATE TYPE document_status AS ENUM ('uploading', 'processing', 'ready', 'failed', 'deleted');
CREATE TYPE document_type AS ENUM ('pdf', 'docx', 'doc', 'txt', 'image');
CREATE TYPE ai_request_type AS ENUM (
    'summarize',
    'qa',
    'translate',
    'key_points',
    'timeline',
    'legal_analysis',
    'business_analysis',
    'action_items',
    'generate_report',
    'chat'
);
CREATE TYPE ai_request_status AS ENUM ('pending', 'processing', 'completed', 'failed');
CREATE TYPE audit_action AS ENUM (
    'login', 'logout', 'register',
    'password_reset_request', 'password_reset_complete',
    'document_upload', 'document_delete', 'document_download',
    'ai_request', 'profile_update',
    'admin_action'
);

-- ============================================================
--  TABLE: roles
--  Stores role definitions with permissions (JSON)
-- ============================================================

CREATE TABLE roles (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        user_role NOT NULL UNIQUE,
    description TEXT,
    permissions JSONB NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed default roles
INSERT INTO roles (name, description, permissions) VALUES
(
    'admin',
    'Full system access',
    '{
        "documents": ["create","read","update","delete","download"],
        "users":     ["create","read","update","delete"],
        "ai":        ["all"],
        "analytics": ["read"]
    }'
),
(
    'user',
    'Standard user access',
    '{
        "documents": ["create","read","delete","download"],
        "users":     ["read_own","update_own"],
        "ai":        ["summarize","qa","translate","key_points","chat"],
        "analytics": []
    }'
);

-- ============================================================
--  TABLE: users
--  Core user accounts
-- ============================================================

CREATE TABLE users (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email                   VARCHAR(255) NOT NULL UNIQUE,
    password_hash           VARCHAR(255) NOT NULL,
    full_name               VARCHAR(255) NOT NULL,
    avatar_url              TEXT,
    role                    user_role NOT NULL DEFAULT 'user',
    status                  user_status NOT NULL DEFAULT 'active',
    email_verified          BOOLEAN NOT NULL DEFAULT FALSE,
    email_verify_token      VARCHAR(255),
    email_verify_expires_at TIMESTAMPTZ,
    last_login_at           TIMESTAMPTZ,
    last_login_ip           INET,
    failed_login_attempts   INTEGER NOT NULL DEFAULT 0,
    locked_until            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at              TIMESTAMPTZ      -- Soft delete
);

-- ============================================================
--  TABLE: refresh_tokens
--  JWT refresh token store (rotated on each use)
-- ============================================================

CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(255) NOT NULL UNIQUE,   -- Store hash, not raw token
    device_info TEXT,                            -- e.g. "Chrome/Windows"
    ip_address  INET,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked     BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
--  TABLE: password_reset_tokens
--  One-time tokens for password reset flow
-- ============================================================

CREATE TABLE password_reset_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(255) NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used        BOOLEAN NOT NULL DEFAULT FALSE,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
--  TABLE: documents
--  Uploaded document metadata
-- ============================================================

CREATE TABLE documents (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title            VARCHAR(500) NOT NULL,
    original_name    VARCHAR(500) NOT NULL,        -- Original filename
    file_path        TEXT NOT NULL,                -- Storage path
    file_size        BIGINT NOT NULL,              -- Bytes
    file_type        document_type NOT NULL,
    mime_type        VARCHAR(100) NOT NULL,
    status           document_status NOT NULL DEFAULT 'uploading',
    page_count       INTEGER,
    word_count       INTEGER,
    language         VARCHAR(10) DEFAULT 'en',
    is_ocr_processed BOOLEAN NOT NULL DEFAULT FALSE,
    ocr_text         TEXT,                         -- Extracted OCR text
    summary          TEXT,                         -- AI-generated summary
    tags             TEXT[] DEFAULT '{}',
    metadata         JSONB DEFAULT '{}',           -- Extra metadata (author, etc.)
    version          INTEGER NOT NULL DEFAULT 1,
    parent_id        UUID REFERENCES documents(id), -- For version history
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at       TIMESTAMPTZ                   -- Soft delete
);

-- ============================================================
--  TABLE: document_chunks
--  Text chunks for RAG (Retrieval Augmented Generation)
--  Each chunk maps to a vector in Qdrant
-- ============================================================

CREATE TABLE document_chunks (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id   UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index   INTEGER NOT NULL,               -- Order within document
    content       TEXT NOT NULL,                  -- The actual text chunk
    page_number   INTEGER,                        -- Source page
    token_count   INTEGER,                        -- Approx tokens in chunk
    qdrant_id     UUID,                           -- Corresponding vector ID in Qdrant
    is_embedded   BOOLEAN NOT NULL DEFAULT FALSE, -- Has been vectorized?
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(document_id, chunk_index)
);

-- ============================================================
--  TABLE: ai_requests
--  Tracks all AI operations (for usage analytics & history)
-- ============================================================

CREATE TABLE ai_requests (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id     UUID REFERENCES documents(id) ON DELETE SET NULL,
    request_type    ai_request_type NOT NULL,
    status          ai_request_status NOT NULL DEFAULT 'pending',
    prompt          TEXT,                          -- User's input/question
    response        TEXT,                          -- AI response
    model_used      VARCHAR(100),                  -- e.g. gemini-1.5-flash
    input_tokens    INTEGER DEFAULT 0,
    output_tokens   INTEGER DEFAULT 0,
    processing_ms   INTEGER,                       -- Time taken in milliseconds
    error_message   TEXT,
    metadata        JSONB DEFAULT '{}',            -- Extra data (language, etc.)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

-- ============================================================
--  TABLE: chat_sessions
--  Groups chat messages per document per user
-- ============================================================

CREATE TABLE chat_sessions (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    title       VARCHAR(255),                      -- Auto-generated from first message
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
--  TABLE: chat_messages
--  Individual messages within a chat session
-- ============================================================

CREATE TABLE chat_messages (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id   UUID NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
    role         VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant')),
    content      TEXT NOT NULL,
    tokens_used  INTEGER DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
--  TABLE: audit_logs
--  Immutable record of all important system actions
-- ============================================================

CREATE TABLE audit_logs (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    action      audit_action NOT NULL,
    resource    VARCHAR(100),                      -- e.g. "document", "user"
    resource_id UUID,                              -- ID of affected resource
    ip_address  INET,
    user_agent  TEXT,
    metadata    JSONB DEFAULT '{}',               -- Extra context
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
--  TABLE: user_settings
--  Per-user preferences and configuration
-- ============================================================

CREATE TABLE user_settings (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id              UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    default_language     VARCHAR(10) DEFAULT 'en',
    ai_model_preference  VARCHAR(50) DEFAULT 'gemini-1.5-flash',
    notifications_email  BOOLEAN DEFAULT TRUE,
    theme                VARCHAR(20) DEFAULT 'system',   -- light | dark | system
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
--  UPDATED_AT AUTO-UPDATE TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to all tables with updated_at
CREATE TRIGGER trg_roles_updated_at
    BEFORE UPDATE ON roles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_documents_updated_at
    BEFORE UPDATE ON documents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_chat_sessions_updated_at
    BEFORE UPDATE ON chat_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_user_settings_updated_at
    BEFORE UPDATE ON user_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
--  AUTO-CREATE USER SETTINGS ON USER INSERT
-- ============================================================

CREATE OR REPLACE FUNCTION create_user_settings()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO user_settings (user_id) VALUES (NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_create_user_settings
    AFTER INSERT ON users
    FOR EACH ROW EXECUTE FUNCTION create_user_settings();

-- ============================================================
--  VIEWS
-- ============================================================

-- Active users (not soft-deleted)
CREATE VIEW v_active_users AS
    SELECT * FROM users
    WHERE deleted_at IS NULL;

-- Active documents (not soft-deleted)
CREATE VIEW v_active_documents AS
    SELECT * FROM documents
    WHERE deleted_at IS NULL;

-- AI usage summary per user
CREATE VIEW v_ai_usage_summary AS
    SELECT
        user_id,
        COUNT(*)                                    AS total_requests,
        SUM(input_tokens + output_tokens)           AS total_tokens,
        COUNT(*) FILTER (WHERE status = 'completed') AS successful_requests,
        COUNT(*) FILTER (WHERE status = 'failed')    AS failed_requests,
        MAX(created_at)                              AS last_request_at
    FROM ai_requests
    GROUP BY user_id;