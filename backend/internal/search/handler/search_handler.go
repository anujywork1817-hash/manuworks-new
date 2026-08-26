package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/yourusername/docassist/internal/search/service"
	"github.com/yourusername/docassist/pkg/middleware"
)

// SearchHandler handles semantic search HTTP requests
type SearchHandler struct {
	searchService *service.SearchService
}

// NewSearchHandler creates a new SearchHandler
func NewSearchHandler(searchService *service.SearchService) *SearchHandler {
	return &SearchHandler{searchService: searchService}
}

func respond(c *gin.Context, code int, success bool, message string, data interface{}) {
	c.JSON(code, gin.H{
		"success": success,
		"code":    code,
		"message": message,
		"data":    data,
	})
}

// Search godoc
// @Summary      Semantic search across all documents
// @Description  Embeds the query and finds similar content using Qdrant
// @Tags         search
// @Security     BearerAuth
// @Param        q     query string true  "Search query"
// @Param        limit query int    false "Max results (default 10, max 20)"
// @Success      200   {object} map[string]interface{}
// @Router       /search [get]
func (h *SearchHandler) Search(c *gin.Context) {
	userID := middleware.GetUserID(c)
	query := c.Query("q")
	if query == "" {
		respond(c, http.StatusBadRequest, false, "Query parameter 'q' is required", nil)
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))

	result, err := h.searchService.Search(c.Request.Context(), userID, query, limit)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Search complete", result)
}

// SearchInDocument godoc
// @Summary      Semantic search within a single document
// @Tags         search
// @Security     BearerAuth
// @Param        document_id path   string true  "Document ID"
// @Param        q           query  string true  "Search query"
// @Param        limit       query  int    false "Max results"
// @Success      200         {object} map[string]interface{}
// @Router       /documents/{document_id}/search [get]
func (h *SearchHandler) SearchInDocument(c *gin.Context) {
	userID := middleware.GetUserID(c)
	documentID := c.Param("document_id")
	query := c.Query("q")
	if query == "" {
		respond(c, http.StatusBadRequest, false, "Query parameter 'q' is required", nil)
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))

	result, err := h.searchService.SearchInDocument(c.Request.Context(), userID, documentID, query, limit)
	if err != nil {
		if err.Error() == "document not found or access denied" {
			respond(c, http.StatusNotFound, false, err.Error(), nil)
			return
		}
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Search complete", result)
}

// RAGQuery godoc
// @Summary      Ask a question across all documents (RAG)
// @Description  Retrieves relevant chunks then generates a grounded AI answer
// @Tags         search
// @Security     BearerAuth
// @Param        body body object true "Question payload"
// @Success      200  {object} map[string]interface{}
// @Router       /search/ask [post]
func (h *SearchHandler) RAGQuery(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req struct {
		Query string `json:"query" binding:"required,min=3,max=500"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		respond(c, http.StatusBadRequest, false, "query is required (3–500 chars)", nil)
		return
	}

	result, err := h.searchService.RAGQuery(c.Request.Context(), userID, req.Query)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "RAG answer generated", result)
}

