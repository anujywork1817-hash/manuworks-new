package repository

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/yourusername/docassist/internal/document/model"
)

// ─── Sentinel errors ──────────────────────────────────────────────────────────

var (
	ErrNotFound  = errors.New("document not found")
	ErrForbidden = errors.New("access denied")
)

// ─── Interface ────────────────────────────────────────────────────────────────

type DocumentRepository interface {
	// CRUD
	Create(ctx context.Context, doc *model.Document) error
	GetByID(ctx context.Context, id uuid.UUID) (*model.Document, error)
	GetByIDAndUserID(ctx context.Context, id, userID uuid.UUID) (*model.Document, error)
	Update(ctx context.Context, doc *model.Document) error
	SoftDelete(ctx context.Context, id, userID uuid.UUID) error
	HardDelete(ctx context.Context, id uuid.UUID) error

	// Listing
	List(ctx context.Context, userID uuid.UUID, req *model.ListDocumentsRequest) ([]model.Document, int64, error)
	ListAll(ctx context.Context, req *model.ListDocumentsRequest) ([]model.Document, int64, error) // admin

	// Versioning
	GetVersions(ctx context.Context, parentID uuid.UUID) ([]model.DocumentVersion, error)
	GetLatestVersion(ctx context.Context, parentID uuid.UUID) (int, error)

	// OCR / processing
	UpdateOCRText(ctx context.Context, id uuid.UUID, text string, wordCount int) error
	UpdateStatus(ctx context.Context, id uuid.UUID, status model.DocumentStatus) error
	UpdateOCRStatus(ctx context.Context, id uuid.UUID, status string) error
	SaveAICache(ctx context.Context, id uuid.UUID, summary, keyPoints, timeline, actionItems, analysis string) error
	UpdateFields(ctx context.Context, id uuid.UUID, fields map[string]interface{}) error

	// Chunks (for RAG)
	CreateChunks(ctx context.Context, chunks []model.DocumentChunk) error
	GetChunksByDocumentID(ctx context.Context, docID uuid.UUID) ([]model.DocumentChunk, error)
	UpdateChunkEmbedding(ctx context.Context, chunkID uuid.UUID, qdrantID string) error
	MarkDocumentEmbedded(ctx context.Context, id uuid.UUID) error
	DeleteChunksByDocumentID(ctx context.Context, docID uuid.UUID) error

	// Stats
	CountByUserID(ctx context.Context, userID uuid.UUID) (int64, error)
	TotalSizeByUserID(ctx context.Context, userID uuid.UUID) (int64, error)
}

// ─── Implementation ───────────────────────────────────────────────────────────

type documentRepository struct {
	db *gorm.DB
}

func NewDocumentRepository(db *gorm.DB) DocumentRepository {
	return &documentRepository{db: db}
}

// ─── CRUD ─────────────────────────────────────────────────────────────────────

func (r *documentRepository) Create(ctx context.Context, doc *model.Document) error {
	return r.db.WithContext(ctx).Create(doc).Error
}

func (r *documentRepository) GetByID(ctx context.Context, id uuid.UUID) (*model.Document, error) {
	var doc model.Document
	err := r.db.WithContext(ctx).
		Where("id = ? AND deleted_at IS NULL", id).
		First(&doc).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	return &doc, err
}

func (r *documentRepository) GetByIDAndUserID(ctx context.Context, id, userID uuid.UUID) (*model.Document, error) {
	var doc model.Document
	err := r.db.WithContext(ctx).
		Where("id = ? AND user_id = ? AND deleted_at IS NULL", id, userID).
		First(&doc).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	return &doc, err
}

func (r *documentRepository) Update(ctx context.Context, doc *model.Document) error {
	return r.db.WithContext(ctx).Save(doc).Error
}

func (r *documentRepository) SoftDelete(ctx context.Context, id, userID uuid.UUID) error {
	result := r.db.WithContext(ctx).
		Where("id = ? AND user_id = ?", id, userID).
		Delete(&model.Document{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *documentRepository) HardDelete(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).
		Unscoped().
		Where("id = ?", id).
		Delete(&model.Document{}).Error
}

// ─── Listing ──────────────────────────────────────────────────────────────────

func (r *documentRepository) List(ctx context.Context, userID uuid.UUID, req *model.ListDocumentsRequest) ([]model.Document, int64, error) {
	req.SetDefaults()

	q := r.db.WithContext(ctx).
		Model(&model.Document{}).
		Where("user_id = ? AND deleted_at IS NULL", userID)

	q = applyDocumentFilters(q, req)

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var docs []model.Document
	offset := (req.Page - 1) * req.PageSize
	err := q.
		Order(fmt.Sprintf("%s %s", req.SortBy, strings.ToUpper(req.SortDir))).
		Limit(req.PageSize).
		Offset(offset).
		Find(&docs).Error

	return docs, total, err
}

func (r *documentRepository) ListAll(ctx context.Context, req *model.ListDocumentsRequest) ([]model.Document, int64, error) {
	req.SetDefaults()

	q := r.db.WithContext(ctx).
		Model(&model.Document{}).
		Preload("User").
		Where("deleted_at IS NULL")

	q = applyDocumentFilters(q, req)

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var docs []model.Document
	offset := (req.Page - 1) * req.PageSize
	err := q.
		Order(fmt.Sprintf("%s %s", req.SortBy, strings.ToUpper(req.SortDir))).
		Limit(req.PageSize).
		Offset(offset).
		Find(&docs).Error

	return docs, total, err
}

func applyDocumentFilters(q *gorm.DB, req *model.ListDocumentsRequest) *gorm.DB {
	if req.Search != "" {
		search := "%" + strings.ToLower(req.Search) + "%"
		q = q.Where("LOWER(title) LIKE ? OR LOWER(file_name) LIKE ?", search, search)
	}
	if req.FileType != "" {
		q = q.Where("file_type = ?", req.FileType)
	}
	if req.Status != "" {
		q = q.Where("status = ?", req.Status)
	}
	return q
}

// ─── Versioning ───────────────────────────────────────────────────────────────

func (r *documentRepository) GetVersions(ctx context.Context, parentID uuid.UUID) ([]model.DocumentVersion, error) {
	var versions []model.DocumentVersion
	err := r.db.WithContext(ctx).
		Model(&model.Document{}).
		Select("id, parent_id, version, file_name, file_size, created_at").
		Where("(id = ? OR parent_id = ?) AND deleted_at IS NULL", parentID, parentID).
		Order("version ASC").
		Find(&versions).Error
	return versions, err
}

func (r *documentRepository) GetLatestVersion(ctx context.Context, parentID uuid.UUID) (int, error) {
	var maxVersion int
	err := r.db.WithContext(ctx).
		Model(&model.Document{}).
		Select("COALESCE(MAX(version), 0)").
		Where("(id = ? OR parent_id = ?) AND deleted_at IS NULL", parentID, parentID).
		Scan(&maxVersion).Error
	return maxVersion, err
}

// ─── OCR / Processing ─────────────────────────────────────────────────────────

func (r *documentRepository) UpdateOCRText(ctx context.Context, id uuid.UUID, text string, wordCount int) error {
	return r.db.WithContext(ctx).
		Model(&model.Document{}).
		Where("id = ?", id).
		Updates(map[string]interface{}{
			"ocr_text":   text,
			"word_count": wordCount,
			"ocr_status": "completed",
		}).Error
}

func (r *documentRepository) UpdateStatus(ctx context.Context, id uuid.UUID, status model.DocumentStatus) error {
	return r.db.WithContext(ctx).
		Model(&model.Document{}).
		Where("id = ?", id).
		Update("status", status).Error
}

func (r *documentRepository) UpdateOCRStatus(ctx context.Context, id uuid.UUID, status string) error {
	return r.db.WithContext(ctx).
		Model(&model.Document{}).
		Where("id = ?", id).
		Update("ocr_status", status).Error
}

func (r *documentRepository) SaveAICache(ctx context.Context, id uuid.UUID, summary, keyPoints, timeline, actionItems, analysis string) error {
	return r.db.WithContext(ctx).
		Model(&model.Document{}).
		Where("id = ?", id).
		Updates(map[string]interface{}{
			"ai_summary":      summary,
			"ai_key_points":   keyPoints,
			"ai_timeline":     timeline,
			"ai_action_items": actionItems,
			"ai_analysis":     analysis,
		}).Error
}

func (r *documentRepository) UpdateFields(ctx context.Context, id uuid.UUID, fields map[string]interface{}) error {
	return r.db.WithContext(ctx).
		Model(&model.Document{}).
		Where("id = ?", id).
		Updates(fields).Error
}

// ─── Chunks ───────────────────────────────────────────────────────────────────

func (r *documentRepository) CreateChunks(ctx context.Context, chunks []model.DocumentChunk) error {
	if len(chunks) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).CreateInBatches(chunks, 100).Error
}

func (r *documentRepository) GetChunksByDocumentID(ctx context.Context, docID uuid.UUID) ([]model.DocumentChunk, error) {
	var chunks []model.DocumentChunk
	err := r.db.WithContext(ctx).
		Where("document_id = ?", docID).
		Order("chunk_index ASC").
		Find(&chunks).Error
	return chunks, err
}

func (r *documentRepository) UpdateChunkEmbedding(ctx context.Context, chunkID uuid.UUID, qdrantID string) error {
	return r.db.WithContext(ctx).
		Model(&model.DocumentChunk{}).
		Where("id = ?", chunkID).
		Updates(map[string]interface{}{
			"qdrant_id":   qdrantID,
			"is_embedded": true,
		}).Error
}

func (r *documentRepository) MarkDocumentEmbedded(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).
		Model(&model.Document{}).
		Where("id = ?", id).
		Update("is_embedded", true).Error
}

func (r *documentRepository) DeleteChunksByDocumentID(ctx context.Context, docID uuid.UUID) error {
	return r.db.WithContext(ctx).
		Where("document_id = ?", docID).
		Delete(&model.DocumentChunk{}).Error
}

// ─── Stats ────────────────────────────────────────────────────────────────────

func (r *documentRepository) CountByUserID(ctx context.Context, userID uuid.UUID) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&model.Document{}).
		Where("user_id = ? AND deleted_at IS NULL", userID).
		Count(&count).Error
	return count, err
}

func (r *documentRepository) TotalSizeByUserID(ctx context.Context, userID uuid.UUID) (int64, error) {
	var total int64
	err := r.db.WithContext(ctx).
		Model(&model.Document{}).
		Select("COALESCE(SUM(file_size), 0)").
		Where("user_id = ? AND deleted_at IS NULL", userID).
		Scan(&total).Error
	return total, err
}

