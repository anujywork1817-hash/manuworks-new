package model

import (
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// ─── Enums ────────────────────────────────────────────────────────────────────

type DocumentStatus string

const (
	DocumentStatusPending    DocumentStatus = "pending"
	DocumentStatusProcessing DocumentStatus = "processing"
	DocumentStatusReady      DocumentStatus = "ready"
	DocumentStatusFailed     DocumentStatus = "failed"
)

type FileType string

const (
	FileTypePDF  FileType = "pdf"
	FileTypeDOCX FileType = "docx"
	FileTypeDOC  FileType = "doc"
	FileTypeTXT  FileType = "txt"
	FileTypePNG  FileType = "png"
	FileTypeJPG  FileType = "jpg"
	FileTypeJPEG FileType = "jpeg"
)

// ─── GORM Models ──────────────────────────────────────────────────────────────

type Document struct {
	ID          uuid.UUID      `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID      uuid.UUID      `gorm:"type:uuid;not null;index"                       json:"user_id"`
	Title       string         `gorm:"type:varchar(500);not null"                     json:"title"`
	FileName    string         `gorm:"type:varchar(255);not null"                     json:"file_name"`
	FilePath    string         `gorm:"type:varchar(1000);not null"                    json:"-"`
	FileSize    int64          `gorm:"not null"                                       json:"file_size"`
	FileType    FileType       `gorm:"type:varchar(10);not null"                      json:"file_type"`
	MimeType    string         `gorm:"type:varchar(100)"                              json:"mime_type"`
	Status      DocumentStatus `gorm:"type:varchar(20);default:'pending'"             json:"status"`
	PageCount   int            `gorm:"default:0"                                      json:"page_count"`
	WordCount   int            `gorm:"default:0"                                      json:"word_count"`
	Language    string         `gorm:"type:varchar(10);default:'en'"                  json:"language"`
	OcrText     string         `gorm:"type:text"                                      json:"-"`
	OcrStatus   string         `gorm:"type:varchar(20);default:'pending'"             json:"ocr_status"`
	IsEmbedded  bool           `gorm:"default:false"                                  json:"is_embedded"`

	// Pre-computed AI cache — populated during /process so feature taps return instantly
	AiSummary     string `gorm:"type:text"  json:"-"`
	AiKeyPoints   string `gorm:"type:text"  json:"-"`
	AiTimeline    string `gorm:"type:text"  json:"-"`
	AiActionItems string `gorm:"type:text"  json:"-"`
	AiAnalysis    string `gorm:"type:text"  json:"-"`
	Tags        []string       `gorm:"type:text[]"                                    json:"tags"`
	Description string         `gorm:"type:text"                                      json:"description"`
	Version     int            `gorm:"default:1"                                      json:"version"`
	ParentID    *uuid.UUID     `gorm:"type:uuid"                                      json:"parent_id,omitempty"`
	Checksum    string         `gorm:"type:varchar(64)"                               json:"-"`
	CreatedAt   time.Time      `                                                      json:"created_at"`
	UpdatedAt   time.Time      `                                                      json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index"                                          json:"-"`

	// Associations
	User     *User             `gorm:"foreignKey:UserID"    json:"user,omitempty"`
	Chunks   []DocumentChunk   `gorm:"foreignKey:DocumentID" json:"-"`
	Versions []DocumentVersion `gorm:"foreignKey:ParentID"  json:"versions,omitempty"`
}

func (Document) TableName() string { return "documents" }

// DocumentVersion is a lightweight view of a past version
type DocumentVersion struct {
	ID        uuid.UUID `gorm:"type:uuid;primaryKey" json:"id"`
	ParentID  uuid.UUID `gorm:"type:uuid"            json:"parent_id"`
	Version   int       `gorm:"default:1"            json:"version"`
	FileName  string    `gorm:"type:varchar(255)"    json:"file_name"`
	FileSize  int64     `                            json:"file_size"`
	CreatedAt time.Time `                            json:"created_at"`
}

func (DocumentVersion) TableName() string { return "documents" }

type DocumentChunk struct {
	ID          uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	DocumentID  uuid.UUID `gorm:"type:uuid;not null;index"                       json:"document_id"`
	ChunkIndex  int       `gorm:"not null"                                       json:"chunk_index"`
	Content     string    `gorm:"type:text;not null"                             json:"content"`
	TokenCount  int       `gorm:"default:0"                                      json:"token_count"`
	QdrantID    string    `gorm:"type:varchar(100)"                              json:"qdrant_id"`
	IsEmbedded  bool      `gorm:"default:false"                                  json:"is_embedded"`
	PageNumber  int       `gorm:"default:0"                                      json:"page_number"`
	StartOffset int       `gorm:"default:0"                                      json:"start_offset"`
	EndOffset   int       `gorm:"default:0"                                      json:"end_offset"`
	CreatedAt   time.Time `                                                      json:"created_at"`
}

func (DocumentChunk) TableName() string { return "document_chunks" }

// Minimal User reference — avoid circular import
type User struct {
	ID        uuid.UUID `gorm:"type:uuid;primaryKey" json:"id"`
	FirstName string    `gorm:"type:varchar(100)"    json:"first_name"`
	LastName  string    `gorm:"type:varchar(100)"    json:"last_name"`
	Email     string    `gorm:"type:varchar(255)"    json:"email"`
}

func (User) TableName() string { return "users" }

// ─── Request / Response DTOs ──────────────────────────────────────────────────

type UploadDocumentRequest struct {
	Title       string   `form:"title"       binding:"omitempty,max=500"`
	Description string   `form:"description" binding:"omitempty,max=2000"`
	Tags        []string `form:"tags"        binding:"omitempty"`
	Language    string   `form:"language"    binding:"omitempty,len=2"`
}

type UpdateDocumentRequest struct {
	Title       *string   `json:"title"       binding:"omitempty,max=500"`
	Description *string   `json:"description" binding:"omitempty,max=2000"`
	Tags        *[]string `json:"tags"        binding:"omitempty"`
	Language    *string   `json:"language"    binding:"omitempty,len=2"`
	OcrText     *string   `json:"ocr_text"    binding:"omitempty"`
}

type ListDocumentsRequest struct {
	Page     int    `form:"page"      binding:"omitempty,min=1"`
	PageSize int    `form:"page_size" binding:"omitempty,min=1,max=100"`
	Search   string `form:"search"    binding:"omitempty,max=200"`
	FileType string `form:"file_type" binding:"omitempty"`
	Status   string `form:"status"    binding:"omitempty"`
	SortBy   string `form:"sort_by"   binding:"omitempty,oneof=created_at title file_size"`
	SortDir  string `form:"sort_dir"  binding:"omitempty,oneof=asc desc"`
}

func (r *ListDocumentsRequest) SetDefaults() {
	if r.Page == 0 {
		r.Page = 1
	}
	if r.PageSize == 0 {
		r.PageSize = 20
	}
	if r.SortBy == "" {
		r.SortBy = "created_at"
	}
	if r.SortDir == "" {
		r.SortDir = "desc"
	}
}

type DocumentResponse struct {
	ID          uuid.UUID      `json:"id"`
	Title       string         `json:"title"`
	FileName    string         `json:"file_name"`
	FileSize    int64          `json:"file_size"`
	FileSizeHR  string         `json:"file_size_hr"` // human readable: "2.5 MB"
	FileType    FileType       `json:"file_type"`
	MimeType    string         `json:"mime_type"`
	Status      DocumentStatus `json:"status"`
	PageCount   int            `json:"page_count"`
	WordCount   int            `json:"word_count"`
	Language    string         `json:"language"`
	OcrStatus   string         `json:"ocr_status"`
	IsEmbedded  bool           `json:"is_embedded"`
	Tags        []string       `json:"tags"`
	Description string         `json:"description"`
	Version     int            `json:"version"`
	ParentID    *uuid.UUID     `json:"parent_id,omitempty"`
	OcrText     string         `json:"ocr_text,omitempty"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
}

type DocumentListResponse struct {
	Documents  []DocumentResponse `json:"documents"`
	Total      int64              `json:"total"`
	Page       int                `json:"page"`
	PageSize   int                `json:"page_size"`
	TotalPages int                `json:"total_pages"`
}

// ToResponse converts a Document model to the API response DTO.
// FilePath is intentionally excluded — clients never get the server-side path.
func (d *Document) ToResponse() DocumentResponse {
	tags := d.Tags
	if tags == nil {
		tags = []string{}
	}
	return DocumentResponse{
		ID:          d.ID,
		Title:       d.Title,
		FileName:    d.FileName,
		FileSize:    d.FileSize,
		FileSizeHR:  humanizeBytes(d.FileSize),
		FileType:    d.FileType,
		MimeType:    d.MimeType,
		Status:      d.Status,
		PageCount:   d.PageCount,
		WordCount:   d.WordCount,
		Language:    d.Language,
		OcrStatus:   d.OcrStatus,
		IsEmbedded:  d.IsEmbedded,
		Tags:        tags,
		Description: d.Description,
		Version:     d.Version,
		ParentID:    d.ParentID,
		OcrText:     d.OcrText,
		CreatedAt:   d.CreatedAt,
		UpdatedAt:   d.UpdatedAt,
	}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func humanizeBytes(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}
