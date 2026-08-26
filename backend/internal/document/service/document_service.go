package service

import (
	"context"
	"crypto/sha256"
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourusername/docassist/config"
	"github.com/yourusername/docassist/internal/document/model"
	"github.com/yourusername/docassist/internal/document/repository"
	"github.com/yourusername/docassist/pkg/logger"
)

// ─── Interface ────────────────────────────────────────────────────────────────

type DocumentService interface {
	Upload(ctx context.Context, userID uuid.UUID, fileHeader *multipart.FileHeader, req model.UploadDocumentRequest) (*model.Document, error)
	UploadVersion(ctx context.Context, userID, parentID uuid.UUID, fileHeader *multipart.FileHeader) (*model.Document, error)
	GetByID(ctx context.Context, userID uuid.UUID, docID uuid.UUID, isAdmin bool) (*model.Document, error)
	List(ctx context.Context, userID uuid.UUID, req *model.ListDocumentsRequest) (*model.DocumentListResponse, error)
	ListAll(ctx context.Context, req *model.ListDocumentsRequest) (*model.DocumentListResponse, error)
	Update(ctx context.Context, userID, docID uuid.UUID, req model.UpdateDocumentRequest) (*model.Document, error)
	Delete(ctx context.Context, userID, docID uuid.UUID, isAdmin bool) error
	GetDownloadPath(ctx context.Context, userID, docID uuid.UUID, isAdmin bool) (string, string, error)
	GetVersions(ctx context.Context, userID, docID uuid.UUID) ([]model.DocumentVersion, error)
}

// ─── Implementation ───────────────────────────────────────────────────────────

type documentService struct {
	repo repository.DocumentRepository
	cfg  *config.Config
}

func NewDocumentService(repo repository.DocumentRepository, cfg *config.Config) DocumentService {
	return &documentService{repo: repo, cfg: cfg}
}

// ─── Upload ───────────────────────────────────────────────────────────────────

func (s *documentService) Upload(
	ctx context.Context,
	userID uuid.UUID,
	fileHeader *multipart.FileHeader,
	req model.UploadDocumentRequest,
) (*model.Document, error) {

	// 1. Validate file size
	maxSize := s.cfg.Storage.MaxFileSize
	if fileHeader.Size > maxSize {
		return nil, fmt.Errorf("file size %d exceeds maximum %d bytes", fileHeader.Size, maxSize)
	}

	// 2. Validate file type
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(fileHeader.Filename), "."))
	if !s.isAllowedType(ext) {
		return nil, fmt.Errorf("file type .%s is not allowed", ext)
	}

	// 3. Open file
	file, err := fileHeader.Open()
	if err != nil {
		return nil, fmt.Errorf("failed to open uploaded file: %w", err)
	}
	defer file.Close()

	// 4. Compute checksum
	checksum, err := computeChecksum(file)
	if err != nil {
		return nil, fmt.Errorf("failed to compute checksum: %w", err)
	}
	// Seek back to start after checksum read
	if seeker, ok := file.(io.Seeker); ok {
		_, _ = seeker.Seek(0, io.SeekStart)
	}

	// 5. Build storage path: storage/<userID>/<year>/<month>/<uuid>.<ext>
	now := time.Now()
	docID := uuid.New()
	relPath := filepath.Join(
		userID.String(),
		fmt.Sprintf("%d", now.Year()),
		fmt.Sprintf("%02d", now.Month()),
		fmt.Sprintf("%s.%s", docID.String(), ext),
	)
	absPath := filepath.Join(s.cfg.Storage.LocalPath, relPath)

	// 6. Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(absPath), 0755); err != nil {
		return nil, fmt.Errorf("failed to create storage directory: %w", err)
	}

	// 7. Write file to disk
	dst, err := os.Create(absPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create destination file: %w", err)
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		_ = os.Remove(absPath)
		return nil, fmt.Errorf("failed to save file: %w", err)
	}

	// 8. Determine title
	title := req.Title
	if title == "" {
		title = strings.TrimSuffix(fileHeader.Filename, filepath.Ext(fileHeader.Filename))
	}

	lang := req.Language
	if lang == "" {
		lang = "en"
	}

	// 9. Persist document record
	doc := &model.Document{
		ID:          docID,
		UserID:      userID,
		Title:       title,
		FileName:    fileHeader.Filename,
		FilePath:    absPath,
		FileSize:    fileHeader.Size,
		FileType:    model.FileType(ext),
		MimeType:    fileHeader.Header.Get("Content-Type"),
		Status:      model.DocumentStatusPending,
		Language:    lang,
		OcrStatus:   "pending",
		Tags:        req.Tags,
		Description: req.Description,
		Version:     1,
		Checksum:    checksum,
	}

	if err := s.repo.Create(ctx, doc); err != nil {
		_ = os.Remove(absPath)
		return nil, fmt.Errorf("failed to save document record: %w", err)
	}

	logger.Info("Document uploaded",
		logger.Str("doc_id", docID.String()),
		logger.Str("user_id", userID.String()),
		logger.Str("file_name", fileHeader.Filename),
	)

	return doc, nil
}

func (s *documentService) UploadVersion(
	ctx context.Context,
	userID, parentID uuid.UUID,
	fileHeader *multipart.FileHeader,
) (*model.Document, error) {

	// Verify parent exists and belongs to user
	parent, err := s.repo.GetByIDAndUserID(ctx, parentID, userID)
	if err != nil {
		return nil, err
	}

	// Get next version number
	latestVersion, err := s.repo.GetLatestVersion(ctx, parentID)
	if err != nil {
		return nil, err
	}

	req := model.UploadDocumentRequest{
		Title:       parent.Title,
		Description: parent.Description,
		Tags:        parent.Tags,
		Language:    parent.Language,
	}

	newDoc, err := s.Upload(ctx, userID, fileHeader, req)
	if err != nil {
		return nil, err
	}

	// Link to parent and set version
	newDoc.ParentID = &parentID
	newDoc.Version = latestVersion + 1
	if err := s.repo.Update(ctx, newDoc); err != nil {
		return nil, err
	}

	return newDoc, nil
}

// ─── Read ─────────────────────────────────────────────────────────────────────

func (s *documentService) GetByID(ctx context.Context, userID, docID uuid.UUID, isAdmin bool) (*model.Document, error) {
	if isAdmin {
		return s.repo.GetByID(ctx, docID)
	}
	doc, err := s.repo.GetByIDAndUserID(ctx, docID, userID)
	if err != nil {
		return nil, err
	}
	return doc, nil
}

func (s *documentService) List(ctx context.Context, userID uuid.UUID, req *model.ListDocumentsRequest) (*model.DocumentListResponse, error) {
	docs, total, err := s.repo.List(ctx, userID, req)
	if err != nil {
		return nil, err
	}
	return buildListResponse(docs, total, req), nil
}

func (s *documentService) ListAll(ctx context.Context, req *model.ListDocumentsRequest) (*model.DocumentListResponse, error) {
	docs, total, err := s.repo.ListAll(ctx, req)
	if err != nil {
		return nil, err
	}
	return buildListResponse(docs, total, req), nil
}

// ─── Update ───────────────────────────────────────────────────────────────────

func (s *documentService) Update(ctx context.Context, userID, docID uuid.UUID, req model.UpdateDocumentRequest) (*model.Document, error) {
	doc, err := s.repo.GetByIDAndUserID(ctx, docID, userID)
	if err != nil {
		return nil, err
	}

	updates := map[string]interface{}{}

	if req.Title != nil {
		doc.Title = *req.Title
		updates["title"] = *req.Title
	}
	if req.Description != nil {
		doc.Description = *req.Description
		updates["description"] = *req.Description
	}
	if req.Tags != nil {
		doc.Tags = *req.Tags
		updates["tags"] = *req.Tags
	}
	if req.Language != nil {
		doc.Language = *req.Language
		updates["language"] = *req.Language
	}
	if req.OcrText != nil && *req.OcrText != doc.OcrText {
		wc := len(strings.Fields(*req.OcrText))
		doc.OcrText = *req.OcrText
		doc.WordCount = wc
		doc.Status = model.DocumentStatusPending
		doc.OcrStatus = "edited"
		updates["ocr_text"] = *req.OcrText
		updates["word_count"] = wc
		updates["status"] = model.DocumentStatusPending
		updates["ocr_status"] = "edited"
		// Clear AI cache separately — ignore error if columns don't exist yet
		_ = s.repo.SaveAICache(ctx, docID, "", "", "", "", "")
	}

	if len(updates) == 0 {
		return doc, nil
	}

	if err := s.repo.UpdateFields(ctx, docID, updates); err != nil {
		return nil, err
	}
	return doc, nil
}

// ─── Delete ───────────────────────────────────────────────────────────────────

func (s *documentService) Delete(ctx context.Context, userID, docID uuid.UUID, isAdmin bool) error {
	var doc *model.Document
	var err error

	if isAdmin {
		doc, err = s.repo.GetByID(ctx, docID)
	} else {
		doc, err = s.repo.GetByIDAndUserID(ctx, docID, userID)
	}
	if err != nil {
		return err
	}

	// Soft delete the DB record
	if err := s.repo.SoftDelete(ctx, docID, doc.UserID); err != nil {
		return err
	}

	// Optionally delete file from disk (only on hard delete in production)
	// For now we keep files for potential restore
	logger.Info("Document deleted",
		logger.Str("doc_id", docID.String()),
		logger.Str("user_id", userID.String()),
	)
	return nil
}

// ─── Download ─────────────────────────────────────────────────────────────────

// GetDownloadPath returns the absolute file path and original filename for serving.
func (s *documentService) GetDownloadPath(ctx context.Context, userID, docID uuid.UUID, isAdmin bool) (string, string, error) {
	doc, err := s.GetByID(ctx, userID, docID, isAdmin)
	if err != nil {
		return "", "", err
	}

	// Verify file still exists on disk
	if _, err := os.Stat(doc.FilePath); os.IsNotExist(err) {
		return "", "", fmt.Errorf("file not found on disk")
	}

	return doc.FilePath, doc.FileName, nil
}

// ─── Versions ─────────────────────────────────────────────────────────────────

func (s *documentService) GetVersions(ctx context.Context, userID, docID uuid.UUID) ([]model.DocumentVersion, error) {
	// Verify ownership
	_, err := s.repo.GetByIDAndUserID(ctx, docID, userID)
	if err != nil {
		return nil, err
	}
	return s.repo.GetVersions(ctx, docID)
}

// ─── Private helpers ──────────────────────────────────────────────────────────

func (s *documentService) isAllowedType(ext string) bool {
	allowed := s.cfg.Storage.AllowedTypes
	for _, a := range allowed {
		if strings.TrimSpace(a) == ext {
			return true
		}
	}
	return false
}

func computeChecksum(r io.Reader) (string, error) {
	h := sha256.New()
	if _, err := io.Copy(h, r); err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", h.Sum(nil)), nil
}

func buildListResponse(docs []model.Document, total int64, req *model.ListDocumentsRequest) *model.DocumentListResponse {
	responses := make([]model.DocumentResponse, len(docs))
	for i, d := range docs {
		responses[i] = d.ToResponse()
	}

	totalPages := int(total) / req.PageSize
	if int(total)%req.PageSize != 0 {
		totalPages++
	}

	return &model.DocumentListResponse{
		Documents:  responses,
		Total:      total,
		Page:       req.Page,
		PageSize:   req.PageSize,
		TotalPages: totalPages,
	}
}

