package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	docRepo "github.com/yourusername/docassist/internal/document/repository"
	matterSvc "github.com/yourusername/docassist/internal/matter/service"
	"github.com/yourusername/docassist/pkg/middleware"
)

type MatterHandler struct {
	svc     matterSvc.MatterService
	docRepo docRepo.DocumentRepository
}

func NewMatterHandler(svc matterSvc.MatterService, docRepo docRepo.DocumentRepository) *MatterHandler {
	return &MatterHandler{svc: svc, docRepo: docRepo}
}

func respond(c *gin.Context, code int, success bool, message string, data interface{}) {
	c.JSON(code, gin.H{"success": success, "code": code, "message": message, "data": data})
}

func (h *MatterHandler) userID(c *gin.Context) (uuid.UUID, bool) {
	id, err := uuid.Parse(middleware.GetUserID(c))
	if err != nil {
		respond(c, http.StatusUnauthorized, false, "invalid token", nil)
		return uuid.Nil, false
	}
	return id, true
}

func (h *MatterHandler) matterID(c *gin.Context) (uuid.UUID, bool) {
	id, err := uuid.Parse(c.Param("matter_id"))
	if err != nil {
		respond(c, http.StatusBadRequest, false, "invalid matter_id", nil)
		return uuid.Nil, false
	}
	return id, true
}

// POST /matters
func (h *MatterHandler) Create(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	var req matterSvc.CreateMatterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respond(c, http.StatusBadRequest, false, "title is required", nil)
		return
	}
	m, err := h.svc.CreateMatter(c.Request.Context(), userID, req)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusCreated, true, "Matter created", m)
}

// GET /matters
func (h *MatterHandler) List(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	matters, err := h.svc.ListMatters(c.Request.Context(), userID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}

	type item struct {
		ID          string `json:"id"`
		Title       string `json:"title"`
		MatterNo    string `json:"matter_no"`
		Client      string `json:"client"`
		Court       string `json:"court"`
		Status      string `json:"status"`
		Description string `json:"description"`
		DocCount    int64  `json:"doc_count"`
		CreatedAt   string `json:"created_at"`
		UpdatedAt   string `json:"updated_at"`
	}

	result := make([]item, len(matters))
	for i, m := range matters {
		count, _ := h.svc.CountDocuments(c.Request.Context(), m.ID)
		result[i] = item{
			ID:          m.ID.String(),
			Title:       m.Title,
			MatterNo:    m.MatterNo,
			Client:      m.Client,
			Court:       m.Court,
			Status:      m.Status,
			Description: m.Description,
			DocCount:    count,
			CreatedAt:   m.CreatedAt.Format("2006-01-02T15:04:05Z"),
			UpdatedAt:   m.UpdatedAt.Format("2006-01-02T15:04:05Z"),
		}
	}
	respond(c, http.StatusOK, true, "Matters retrieved", gin.H{"matters": result, "total": len(result)})
}

// GET /matters/:matter_id
func (h *MatterHandler) Get(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	matterID, ok := h.matterID(c)
	if !ok {
		return
	}
	m, err := h.svc.GetMatter(c.Request.Context(), userID, matterID)
	if err != nil {
		respond(c, http.StatusNotFound, false, "Matter not found", nil)
		return
	}

	// Fetch documents in this matter
	docIDs, err := h.svc.GetDocumentIDs(c.Request.Context(), matterID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}

	type docItem struct {
		ID        string `json:"id"`
		Title     string `json:"title"`
		FileType  string `json:"file_type"`
		Status    string `json:"status"`
		UpdatedAt string `json:"updated_at"`
	}
	docs := make([]docItem, 0, len(docIDs))
	for _, docID := range docIDs {
		doc, err := h.docRepo.GetByIDAndUserID(c.Request.Context(), docID, userID)
		if err != nil {
			continue // document may have been deleted or belongs to another user
		}
		docs = append(docs, docItem{
			ID:        doc.ID.String(),
			Title:     doc.Title,
			FileType:  string(doc.FileType),
			Status:    string(doc.Status),
			UpdatedAt: doc.UpdatedAt.Format("2006-01-02T15:04:05Z"),
		})
	}

	respond(c, http.StatusOK, true, "Matter retrieved", gin.H{"matter": m, "documents": docs})
}

// PATCH /matters/:matter_id
func (h *MatterHandler) Update(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	matterID, ok := h.matterID(c)
	if !ok {
		return
	}
	var req matterSvc.UpdateMatterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respond(c, http.StatusBadRequest, false, "invalid request body", nil)
		return
	}
	m, err := h.svc.UpdateMatter(c.Request.Context(), userID, matterID, req)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Matter updated", m)
}

// DELETE /matters/:matter_id
func (h *MatterHandler) Delete(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	matterID, ok := h.matterID(c)
	if !ok {
		return
	}
	if err := h.svc.DeleteMatter(c.Request.Context(), userID, matterID); err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Matter deleted", nil)
}

// POST /matters/:matter_id/documents
func (h *MatterHandler) AddDocument(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	matterID, ok := h.matterID(c)
	if !ok {
		return
	}
	var body struct {
		DocumentID string `json:"document_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		respond(c, http.StatusBadRequest, false, "document_id is required", nil)
		return
	}
	docID, err := uuid.Parse(body.DocumentID)
	if err != nil {
		respond(c, http.StatusBadRequest, false, "invalid document_id", nil)
		return
	}
	if err := h.svc.AddDocument(c.Request.Context(), userID, matterID, docID); err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Document added to matter", nil)
}

// DELETE /matters/:matter_id/documents/:doc_id
func (h *MatterHandler) RemoveDocument(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	matterID, ok := h.matterID(c)
	if !ok {
		return
	}
	docID, err := uuid.Parse(c.Param("doc_id"))
	if err != nil {
		respond(c, http.StatusBadRequest, false, "invalid doc_id", nil)
		return
	}
	if err := h.svc.RemoveDocument(c.Request.Context(), userID, matterID, docID); err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Document removed from matter", nil)
}
