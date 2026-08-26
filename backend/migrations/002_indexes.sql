-- ============================================================
--  DocAssist — Performance Indexes
--  Migration: 002_indexes.sql
--  Run after: 001_init.sql
-- ============================================================

-- ============================================================
--  users
-- ============================================================

-- Login lookup (most frequent query)
CREATE INDEX idx_users_email
    ON users(email)
    WHERE deleted_at IS NULL;

-- Admin: filter users by status
CREATE INDEX idx_users_status
    ON users(status)
    WHERE deleted_at IS NULL;

-- Admin: filter users by role
CREATE INDEX idx_users_role
    ON users(role)
    WHERE deleted_at IS NULL;

-- Cleanup job: find locked accounts
CREATE INDEX idx_users_locked_until
    ON users(locked_until)
    WHERE locked_until IS NOT NULL;

-- Email verification flow
CREATE INDEX idx_users_email_verify_token
    ON users(email_verify_token)
    WHERE email_verify_token IS NOT NULL;

-- ============================================================
--  refresh_tokens
-- ============================================================

-- Token validation on every authenticated request
CREATE INDEX idx_refresh_tokens_token_hash
    ON refresh_tokens(token_hash);

-- Get all tokens for a user (logout all devices)
CREATE INDEX idx_refresh_tokens_user_id
    ON refresh_tokens(user_id);

-- Cleanup job: delete expired tokens
CREATE INDEX idx_refresh_tokens_expires_at
    ON refresh_tokens(expires_at)
    WHERE revoked = FALSE;

-- ============================================================
--  password_reset_tokens
-- ============================================================

CREATE INDEX idx_password_reset_token_hash
    ON password_reset_tokens(token_hash);

CREATE INDEX idx_password_reset_user_id
    ON password_reset_tokens(user_id);

-- ============================================================
--  documents
-- ============================================================

-- List documents for a user (dashboard, document list page)
CREATE INDEX idx_documents_user_id
    ON documents(user_id)
    WHERE deleted_at IS NULL;

-- Filter by status (processing queue)
CREATE INDEX idx_documents_status
    ON documents(status)
    WHERE deleted_at IS NULL;

-- Filter by file type
CREATE INDEX idx_documents_file_type
    ON documents(file_type)
    WHERE deleted_at IS NULL;

-- Version history: find all versions of a document
CREATE INDEX idx_documents_parent_id
    ON documents(parent_id)
    WHERE parent_id IS NOT NULL;

-- Full-text search on document title
CREATE INDEX idx_documents_title_fts
    ON documents USING gin(to_tsvector('english', title));

-- Full-text search on OCR text
CREATE INDEX idx_documents_ocr_text_fts
    ON documents USING gin(to_tsvector('english', coalesce(ocr_text, '')));

-- Tag search using GIN index
CREATE INDEX idx_documents_tags
    ON documents USING gin(tags);

-- Sort by creation date (default list order)
CREATE INDEX idx_documents_created_at
    ON documents(created_at DESC)
    WHERE deleted_at IS NULL;

-- ============================================================
--  document_chunks
-- ============================================================

-- Get all chunks for a document (RAG retrieval)
CREATE INDEX idx_chunks_document_id
    ON document_chunks(document_id);

-- Find un-embedded chunks (embedding queue)
CREATE INDEX idx_chunks_not_embedded
    ON document_chunks(document_id)
    WHERE is_embedded = FALSE;

-- Lookup chunk by Qdrant vector ID
CREATE INDEX idx_chunks_qdrant_id
    ON document_chunks(qdrant_id)
    WHERE qdrant_id IS NOT NULL;

-- ============================================================
--  ai_requests
-- ============================================================

-- AI history for a user (dashboard)
CREATE INDEX idx_ai_requests_user_id
    ON ai_requests(user_id);

-- AI requests for a specific document
CREATE INDEX idx_ai_requests_document_id
    ON ai_requests(document_id)
    WHERE document_id IS NOT NULL;

-- Filter by request type (analytics)
CREATE INDEX idx_ai_requests_type
    ON ai_requests(request_type);

-- Filter by status (retry failed jobs)
CREATE INDEX idx_ai_requests_status
    ON ai_requests(status)
    WHERE status IN ('pending', 'processing', 'failed');

-- Analytics: requests over time
CREATE INDEX idx_ai_requests_created_at
    ON ai_requests(created_at DESC);

-- ============================================================
--  chat_sessions
-- ============================================================

-- Get all sessions for a user
CREATE INDEX idx_chat_sessions_user_id
    ON chat_sessions(user_id);

-- Get all sessions for a document
CREATE INDEX idx_chat_sessions_document_id
    ON chat_sessions(document_id);

-- ============================================================
--  chat_messages
-- ============================================================

-- Get all messages in a session (chat history)
CREATE INDEX idx_chat_messages_session_id
    ON chat_messages(session_id);

-- Sort messages chronologically
CREATE INDEX idx_chat_messages_created_at
    ON chat_messages(session_id, created_at ASC);

-- ============================================================
--  audit_logs
-- ============================================================

-- Audit trail for a user
CREATE INDEX idx_audit_logs_user_id
    ON audit_logs(user_id)
    WHERE user_id IS NOT NULL;

-- Filter by action type (security monitoring)
CREATE INDEX idx_audit_logs_action
    ON audit_logs(action);

-- Filter by resource (e.g. all actions on documents)
CREATE INDEX idx_audit_logs_resource
    ON audit_logs(resource, resource_id)
    WHERE resource IS NOT NULL;

-- Time-based queries (most common for audit)
CREATE INDEX idx_audit_logs_created_at
    ON audit_logs(created_at DESC);

-- Security: suspicious IP lookups
CREATE INDEX idx_audit_logs_ip
    ON audit_logs(ip_address)
    WHERE ip_address IS NOT NULL;

-- ============================================================
--  VERIFY ALL INDEXES
-- ============================================================

-- Run this query to confirm all indexes were created:
-- SELECT indexname, tablename FROM pg_indexes
-- WHERE schemaname = 'public'
-- ORDER BY tablename, indexname;