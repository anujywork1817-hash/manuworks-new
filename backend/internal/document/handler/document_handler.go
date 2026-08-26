package handler

import (
	"errors"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/yourusername/docassist/internal/document/model"
	"github.com/yourusername/docassist/internal/document/repository"
	"github.com/yourusername/docassist/internal/document/service"
    "github.com/yourusername/docassist/pkg/middleware"
)

// ─── Handler ──────────────────────────────────────────────────────────────────

type DocumentHandler struct {
	svc service.DocumentService
}

func NewDocumentHandler(svc service.DocumentService) *DocumentHandler {
	return &DocumentHandler{svc: svc}
}

// ─── Routes ───────────────────────────────────────────────────────────────────

func (h *DocumentHandler) RegisterRoutes(rg *gin.RouterGroup) {
	docs := rg.Group("/documents")
	{
		docs.POST("", h.Upload)
		docs.GET("", h.List)
		docs.GET("/:id", h.GetByID)
		docs.PATCH("/:id", h.Update)
		docs.DELETE("/:id", h.Delete)
		docs.GET("/:id/download", h.Download)
		docs.GET("/:id/versions", h.GetVersions)
		docs.POST("/:id/versions", h.UploadVersion)
	}
}

// ─── Upload ───────────────────────────────────────────────────────────────────

// @Summary      Upload a document
// @Description  Upload PDF, DOCX, DOC, TXT, or image file
// @Tags         Documents
// @Accept       multipart/form-data
// @Produce      json
// @Param        file         formData  file    true  "Document file"
// @Param        title        formData  string  false "Document title"
// @Param        description  formData  string  false "Document description"
// @Param        language     formData  string  false "Language code (e.g. en)"
// @Security     BearerAuth
// @Success      201  {object}  SuccessResponse
// @Failure      400  {object}  ErrorResponse
// @Failure      413  {object}  ErrorResponse
// @Router       /documents [post]
func (h *DocumentHandler) Upload(c *gin.Context) {
	userIDStr := middleware.GetUserID(c)
    userID, _ := uuid.Parse(userIDStr)

	var req model.UploadDocumentRequest
	if err := c.ShouldBind(&req); err != nil {
		respondValidation(c, err)
		return
	}

	fileHeader, err := c.FormFile("file")
	if err != nil {
		respondError(c, http.StatusBadRequest, "FILE_REQUIRED", "No file provided")
		return
	}

	doc, err := h.svc.Upload(c.Request.Context(), userID, fileHeader, req)
	if err != nil {
		respondServiceError(c, err)
		return
	}

	respondSuccess(c, http.StatusCreated, "Document uploaded successfully", doc.ToResponse())
}

// ─── List ─────────────────────────────────────────────────────────────────────

// @Summary      List documents
// @Description  Get paginated list of user's documents
// @Tags         Documents
// @Produce      json
// @Param        page       query  int     false  "Page number (default 1)"
// @Param        page_size  query  int     false  "Page size (default 20, max 100)"
// @Param        search     query  string  false  "Search by title or filename"
// @Param        file_type  query  string  false  "Filter by type: pdf, docx, etc."
// @Param        status     query  string  false  "Filter by status: pending, ready, failed"
// @Param        sort_by    query  string  false  "Sort field: created_at, title, file_size"
// @Param        sort_dir   query  string  false  "Sort direction: asc, desc"
// @Security     BearerAuth
// @Success      200  {object}  SuccessResponse
// @Router       /documents [get]
func (h *DocumentHandler) List(c *gin.Context) {
	userIDStr := middleware.GetUserID(c)
    userID, _ := uuid.Parse(userIDStr)

	var req model.ListDocumentsRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		respondValidation(c, err)
		return
	}

	result, err := h.svc.List(c.Request.Context(), userID, &req)
	if err != nil {
		respondServiceError(c, err)
		return
	}

	respondSuccess(c, http.StatusOK, "", result)
}

// ─── Get by ID ────────────────────────────────────────────────────────────────

// @Summary      Get document by ID
// @Tags         Documents
// @Produce      json
// @Param        id   path  string  true  "Document UUID"
// @Security     BearerAuth
// @Success      200  {object}  SuccessResponse
// @Failure      404  {object}  ErrorResponse
// @Router       /documents/{id} [get]
func (h *DocumentHandler) GetByID(c *gin.Context) {
	userIDStr := middleware.GetUserID(c)
    userID, _ := uuid.Parse(userIDStr)
	isAdmin := middleware.GetUserRole(c) == "admin"

	docID, err := parseUUID(c, "document_id")
	if err != nil {
		return
	}

	doc, err := h.svc.GetByID(c.Request.Context(), userID, docID, isAdmin)
	if err != nil {
		respondServiceError(c, err)
		return
	}

	respondSuccess(c, http.StatusOK, "", doc.ToResponse())
}

// ─── Update ───────────────────────────────────────────────────────────────────

// @Summary      Update document metadata
// @Tags         Documents
// @Accept       json
// @Produce      json
// @Param        id   path  string                       true  "Document UUID"
// @Param        req  body  model.UpdateDocumentRequest  true  "Fields to update"
// @Security     BearerAuth
// @Success      200  {object}  SuccessResponse
// @Router       /documents/{id} [patch]
func (h *DocumentHandler) Update(c *gin.Context) {
	userIDStr := middleware.GetUserID(c)
    userID, _ := uuid.Parse(userIDStr)

	docID, err := parseUUID(c, "document_id")
	if err != nil {
		return
	}

	var req model.UpdateDocumentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondValidation(c, err)
		return
	}

	doc, err := h.svc.Update(c.Request.Context(), userID, docID, req)
	if err != nil {
		respondServiceError(c, err)
		return
	}

	respondSuccess(c, http.StatusOK, "Document updated", doc.ToResponse())
}

// ─── Delete ───────────────────────────────────────────────────────────────────

// @Summary      Delete a document
// @Tags         Documents
// @Produce      json
// @Param        id  path  string  true  "Document UUID"
// @Security     BearerAuth
// @Success      200  {object}  SuccessResponse
// @Failure      404  {object}  ErrorResponse
// @Router       /documents/{id} [delete]
func (h *DocumentHandler) Delete(c *gin.Context) {
	userIDStr := middleware.GetUserID(c)
    userID, _ := uuid.Parse(userIDStr)
	isAdmin := middleware.GetUserRole(c) == "admin"

	docID, err := parseUUID(c, "document_id")
	if err != nil {
		return
	}

	if err := h.svc.Delete(c.Request.Context(), userID, docID, isAdmin); err != nil {
		respondServiceError(c, err)
		return
	}

	respondSuccess(c, http.StatusOK, "Document deleted successfully", nil)
}

// ─── Download ─────────────────────────────────────────────────────────────────

// @Summary      Download a document
// @Tags         Documents
// @Produce      application/octet-stream
// @Param        id  path  string  true  "Document UUID"
// @Security     BearerAuth
// @Success      200  {file}  binary
// @Failure      404  {object}  ErrorResponse
// @Router       /documents/{id}/download [get]
func (h *DocumentHandler) Download(c *gin.Context) {
	userIDStr := middleware.GetUserID(c)
    userID, _ := uuid.Parse(userIDStr)
	isAdmin := middleware.GetUserRole(c) == "admin"

	docID, err := parseUUID(c, "document_id")
	if err != nil {
		return
	}

	filePath, fileName, err := h.svc.GetDownloadPath(c.Request.Context(), userID, docID, isAdmin)
	if err != nil {
		respondServiceError(c, err)
		return
	}

	// Set proper headers for download
	c.Header("Content-Disposition", `attachment; filename="`+fileName+`"`)
	c.Header("Content-Description", "File Transfer")
	c.Header("Content-Transfer-Encoding", "binary")
	c.Header("Cache-Control", "no-cache")

	ext := strings.ToLower(filepath.Ext(fileName))
	mimeTypes := map[string]string{
		".pdf":  "application/pdf",
		".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
		".doc":  "application/msword",
		".txt":  "text/plain",
		".png":  "image/png",
		".jpg":  "image/jpeg",
		".jpeg": "image/jpeg",
	}
	if mime, ok := mimeTypes[ext]; ok {
		c.Header("Content-Type", mime)
	}

	c.File(filePath)
}

// ─── Versions ─────────────────────────────────────────────────────────────────

// @Summary      List document versions
// @Tags         Documents
// @Produce      json
// @Param        id  path  string  true  "Document UUID"
// @Security     BearerAuth
// @Success      200  {object}  SuccessResponse
// @Router       /documents/{id}/versions [get]
func (h *DocumentHandler) GetVersions(c *gin.Context) {
	userIDStr := middleware.GetUserID(c)
    userID, _ := uuid.Parse(userIDStr)

	docID, err := parseUUID(c, "document_id")
	if err != nil {
		return
	}

	versions, err := h.svc.GetVersions(c.Request.Context(), userID, docID)
	if err != nil {
		respondServiceError(c, err)
		return
	}

	respondSuccess(c, http.StatusOK, "", versions)
}

// @Summary      Upload new document version
// @Tags         Documents
// @Accept       multipart/form-data
// @Produce      json
// @Param        id    path      string  true  "Parent Document UUID"
// @Param        file  formData  file    true  "New version file"
// @Security     BearerAuth
// @Success      201  {object}  SuccessResponse
// @Router       /documents/{id}/versions [post]
func (h *DocumentHandler) UploadVersion(c *gin.Context) {
	userIDStr := middleware.GetUserID(c)
    userID, _ := uuid.Parse(userIDStr)

	parentID, err := parseUUID(c, "document_id")
	if err != nil {
		return
	}

	fileHeader, err := c.FormFile("file")
	if err != nil {
		respondError(c, http.StatusBadRequest, "FILE_REQUIRED", "No file provided")
		return
	}

	doc, err := h.svc.UploadVersion(c.Request.Context(), userID, parentID, fileHeader)
	if err != nil {
		respondServiceError(c, err)
		return
	}

	respondSuccess(c, http.StatusCreated, "New version uploaded", doc.ToResponse())
}

// ─── Shared response helpers ──────────────────────────────────────────────────

type SuccessResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message,omitempty"`
	Data    interface{} `json:"data,omitempty"`
}

type ErrorResponse struct {
	Success bool   `json:"success"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

func respondSuccess(c *gin.Context, status int, message string, data interface{}) {
	c.JSON(status, SuccessResponse{Success: true, Message: message, Data: data})
}

func respondError(c *gin.Context, status int, code, message string) {
	c.AbortWithStatusJSON(status, ErrorResponse{Success: false, Code: code, Message: message})
}

func respondValidation(c *gin.Context, err error) {
	respondError(c, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
}

func respondServiceError(c *gin.Context, err error) {
	if errors.Is(err, repository.ErrNotFound) {
		respondError(c, http.StatusNotFound, "NOT_FOUND", "Document not found")
		return
	}
	if errors.Is(err, repository.ErrForbidden) {
		respondError(c, http.StatusForbidden, "FORBIDDEN", "Access denied")
		return
	}
	respondError(c, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
}

func parseUUID(c *gin.Context, param string) (uuid.UUID, error) {
	id, err := uuid.Parse(c.Param(param))
	if err != nil {
		respondError(c, http.StatusBadRequest, "INVALID_ID", "Invalid UUID format")
		return uuid.Nil, err
	}
	return id, nil
}







// GetStatus returns lightweight processing status for polling
func (h *DocumentHandler) GetStatus(c *gin.Context) {
    docIDStr := c.Param("document_id")
    docID, err := uuid.Parse(docIDStr)
    if err != nil {
        c.JSON(400, gin.H{"success": false, "message": "invalid document_id"})
        return
    }
    userIDStr := middleware.GetUserID(c)
    userID, err := uuid.Parse(userIDStr)
    if err != nil {
        c.JSON(400, gin.H{"success": false, "message": "invalid user_id"})
        return
    }
    doc, err := h.svc.GetByID(c.Request.Context(), docID, userID, false)
    if err != nil {
        c.JSON(404, gin.H{"success": false, "message": "not found"})
        return
    }
    c.JSON(200, gin.H{
        "success": true,
        "data": gin.H{
            "id":         doc.ID,
            "status":     doc.Status,
            "ocr_status": doc.OcrStatus,
            "updated_at": doc.UpdatedAt,
        },
    })
}


