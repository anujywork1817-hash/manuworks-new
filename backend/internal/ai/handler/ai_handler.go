package handler

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/yourusername/docassist/internal/ai/service"
	"github.com/yourusername/docassist/pkg/groq"
	"github.com/yourusername/docassist/pkg/logger"
	"github.com/yourusername/docassist/pkg/middleware"
	"github.com/yourusername/docassist/pkg/ocr"
)

// ── Async complaint-reply job store ──────────────────────────────────────────
// Render.com free tier kills HTTP requests after ~30 s. OCR on a scanned
// multi-page PDF takes 2-5 minutes. Solution: return a job_id immediately,
// process in a background goroutine, Flutter polls for the result.

type complaintJobStatus string

const (
	jobProcessing complaintJobStatus = "processing"
	jobDone       complaintJobStatus = "completed"
	jobFailed     complaintJobStatus = "failed"
)

type complaintJob struct {
	Status    complaintJobStatus
	Result    *service.ComplaintReplyResult
	ErrMsg    string
	CreatedAt time.Time
}

var (
	jobsMu sync.RWMutex
	jobs   = map[string]*complaintJob{}
)

func storeJob(id string, j *complaintJob) {
	jobsMu.Lock()
	jobs[id] = j
	jobsMu.Unlock()
}

func readJob(id string) (*complaintJob, bool) {
	jobsMu.RLock()
	defer jobsMu.RUnlock()
	j, ok := jobs[id]
	return j, ok
}

func deleteJob(id string) {
	jobsMu.Lock()
	delete(jobs, id)
	jobsMu.Unlock()
}

func init() {
	// Purge stale jobs older than 30 minutes every 10 minutes.
	go func() {
		for {
			time.Sleep(10 * time.Minute)
			jobsMu.Lock()
			cutoff := time.Now().Add(-30 * time.Minute)
			for id, j := range jobs {
				if j.CreatedAt.Before(cutoff) {
					delete(jobs, id)
				}
			}
			jobsMu.Unlock()
		}
	}()
}

type AIHandler struct {
	aiService  service.AIService
	ocrService *ocr.Service
}

func NewAIHandler(aiService service.AIService, ocrService *ocr.Service) *AIHandler {
	return &AIHandler{aiService: aiService, ocrService: ocrService}
}

func respond(c *gin.Context, code int, success bool, message string, data interface{}) {
	c.JSON(code, gin.H{"success": success, "code": code, "message": message, "data": data})
}

func parseIDs(c *gin.Context) (docID uuid.UUID, userID uuid.UUID, ok bool) {
	var err error
	docID, err = uuid.Parse(c.Param("document_id"))
	if err != nil {
		respond(c, http.StatusBadRequest, false, "invalid document_id", nil)
		return uuid.Nil, uuid.Nil, false
	}
	userID, err = uuid.Parse(middleware.GetUserID(c))
	if err != nil {
		respond(c, http.StatusBadRequest, false, "invalid user_id in token", nil)
		return uuid.Nil, uuid.Nil, false
	}
	return docID, userID, true
}

func (h *AIHandler) ProcessDocument(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	go func() {
		_, err := h.aiService.ProcessDocument(context.Background(), userID, docID)
		if err != nil {
			logger.Error("Document processing failed",
				logger.Str("doc_id", docID.String()),
				logger.Str("error", err.Error()),
			)
		}
	}()
	respond(c, http.StatusOK, true, "Document processing started", map[string]string{"status": "processing"})
}

func (h *AIHandler) Summarize(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	result, err := h.aiService.Summarize(c.Request.Context(), userID, docID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Summary generated", result)
}

func (h *AIHandler) AskQuestion(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	var req struct {
		Question string `json:"question" binding:"required,min=3,max=500"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		respond(c, http.StatusBadRequest, false, "Question is required (3-500 chars)", nil)
		return
	}
	result, err := h.aiService.AnswerQuestion(c.Request.Context(), userID, docID, req.Question)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Answer generated", result)
}

func (h *AIHandler) ExtractKeyPoints(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	result, err := h.aiService.ExtractKeyPoints(c.Request.Context(), userID, docID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Key points extracted", result)
}

func (h *AIHandler) ExtractTimeline(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	result, err := h.aiService.ExtractTimeline(c.Request.Context(), userID, docID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Timeline extracted", result)
}

func (h *AIHandler) Translate(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	var req struct {
		TargetLanguage string `json:"target_language" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		respond(c, http.StatusBadRequest, false, "target_language is required", nil)
		return
	}
	result, err := h.aiService.Translate(c.Request.Context(), userID, docID, req.TargetLanguage)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Translation complete", result)
}

func (h *AIHandler) AnalyzeDocument(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	result, err := h.aiService.AnalyzeDocument(c.Request.Context(), userID, docID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Analysis complete", result)
}

func (h *AIHandler) ExtractCitations(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	result, err := h.aiService.ExtractCitations(c.Request.Context(), userID, docID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Citations extracted", result)
}

func (h *AIHandler) ScanRisks(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	result, err := h.aiService.ScanRisks(c.Request.Context(), userID, docID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Risk scan complete", result)
}

func (h *AIHandler) ExtractDeadlines(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	result, err := h.aiService.ExtractDeadlines(c.Request.Context(), userID, docID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Deadlines extracted", result)
}

func (h *AIHandler) AutoTag(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	result, err := h.aiService.AutoTag(c.Request.Context(), userID, docID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Tags generated", result)
}

func (h *AIHandler) CheckGrammar(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	result, err := h.aiService.CheckGrammar(c.Request.Context(), userID, docID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Grammar check complete", result)
}

func (h *AIHandler) DraftLegalDocument(c *gin.Context) {
	userID, err := uuid.Parse(middleware.GetUserID(c))
	if err != nil {
		respond(c, http.StatusUnauthorized, false, "invalid token", nil)
		return
	}
	var req groq.LegalDraftRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.DocumentType == "" {
		respond(c, http.StatusBadRequest, false, "document_type is required", nil)
		return
	}
	result, err := h.aiService.DraftLegalDoc(c.Request.Context(), userID, req)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Draft generated", result)
}

func (h *AIHandler) ExtractActionItems(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	result, err := h.aiService.ExtractActionItems(c.Request.Context(), userID, docID)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Action items extracted", result)
}

func (h *AIHandler) GenerateReport(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}
	var req struct {
		ReportType string `json:"report_type" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		respond(c, http.StatusBadRequest, false, "report_type is required", nil)
		return
	}
	result, err := h.aiService.GenerateReport(c.Request.Context(), userID, docID, req.ReportType)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Report generated", result)
}

// StartChat answers a question about the document directly (single-shot RAG Q&A).
// The Flutter app calls this for every message — there is no real session state.
func (h *AIHandler) StartChat(c *gin.Context) {
	docID, userID, ok := parseIDs(c)
	if !ok {
		return
	}

	var req struct {
		Question string `json:"question"`
		Message  string `json:"message"`
	}
	_ = c.ShouldBindJSON(&req)

	message := req.Question
	if message == "" {
		message = req.Message
	}
	if message == "" {
		respond(c, http.StatusBadRequest, false, "question is required", nil)
		return
	}

	result, err := h.aiService.Chat(c.Request.Context(), userID, docID, service.ChatRequest{Message: message})
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Answer generated", result)
}

func (h *AIHandler) SendMessage(c *gin.Context) {
	userID, err := uuid.Parse(middleware.GetUserID(c))
	if err != nil {
		respond(c, http.StatusBadRequest, false, "invalid user_id", nil)
		return
	}
	sessionID, err := uuid.Parse(c.Param("session_id"))
	if err != nil {
		respond(c, http.StatusBadRequest, false, "invalid session_id", nil)
		return
	}
	var req struct {
		Message string `json:"message" binding:"required,min=1,max=1000"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		respond(c, http.StatusBadRequest, false, "message is required", nil)
		return
	}
	result, err := h.aiService.Chat(c.Request.Context(), userID, sessionID, service.ChatRequest{Message: req.Message})
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Message sent", result)
}

func (h *AIHandler) GetChatHistory(c *gin.Context) {
	respond(c, http.StatusOK, true, "Chat history retrieved", []interface{}{})
}

func (h *AIHandler) GetAIUsage(c *gin.Context) {
	respond(c, http.StatusOK, true, "Usage stats retrieved", gin.H{"total_requests": 0})
}

func (h *AIHandler) CompareDocuments(c *gin.Context) {
	userID, err := uuid.Parse(middleware.GetUserID(c))
	if err != nil {
		respond(c, http.StatusUnauthorized, false, "invalid token", nil)
		return
	}
	var req struct {
		DocID1 string `json:"doc1_id" binding:"required"`
		DocID2 string `json:"doc2_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		respond(c, http.StatusBadRequest, false, "doc1_id and doc2_id are required", nil)
		return
	}
	docID1, err := uuid.Parse(req.DocID1)
	if err != nil {
		respond(c, http.StatusBadRequest, false, "invalid doc1_id", nil)
		return
	}
	docID2, err := uuid.Parse(req.DocID2)
	if err != nil {
		respond(c, http.StatusBadRequest, false, "invalid doc2_id", nil)
		return
	}
	result, err := h.aiService.CompareDocuments(c.Request.Context(), userID, docID1, docID2)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "Comparison complete", result)
}

func (h *AIHandler) HelpChat(c *gin.Context) {
	var req struct {
		Message string             `json:"message"`
		History []groq.ChatMessage `json:"history"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Message == "" {
		respond(c, http.StatusBadRequest, false, "message is required", nil)
		return
	}
	if req.History == nil {
		req.History = []groq.ChatMessage{}
	}
	reply, err := h.aiService.HelpChat(c.Request.Context(), req.History, req.Message)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, err.Error(), nil)
		return
	}
	respond(c, http.StatusOK, true, "ok", gin.H{"reply": reply})
}

// ComplaintReplyGenerator starts an async complaint-reply job and returns a job_id.
//
// Why async: Render.com free tier kills HTTP requests after ~30 s, but OCR on
// a scanned multi-page PDF takes 2-5 min. The HTTP handler saves the uploaded
// files, launches a goroutine, and responds with {job_id} immediately.
// Flutter then polls GET /ai/complaint-reply/status/:job_id every 3 s.
func (h *AIHandler) ComplaintReplyGenerator(c *gin.Context) {
	userID, err := uuid.Parse(middleware.GetUserID(c))
	if err != nil {
		respond(c, http.StatusUnauthorized, false, "invalid token", nil)
		return
	}

	// ── Complaint PDF ──────────────────────────────────────────────────────────
	complaintFile, complaintHeader, err := c.Request.FormFile("complaint_pdf")
	if err != nil {
		respond(c, http.StatusBadRequest, false, "complaint_pdf file is required", nil)
		return
	}
	defer complaintFile.Close()

	// ── Reply DOCX template ────────────────────────────────────────────────────
	replyFile, replyHeader, err := c.Request.FormFile("reply_docx")
	if err != nil {
		respond(c, http.StatusBadRequest, false, "reply_docx file is required", nil)
		return
	}
	defer replyFile.Close()

	// ── Save complaint to temp file ────────────────────────────────────────────
	complaintExt := filepath.Ext(complaintHeader.Filename)
	if complaintExt == "" {
		complaintExt = ".pdf"
	}
	complaintTmp, err := os.CreateTemp("", "complaint-*"+complaintExt)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, "failed to create temp file", nil)
		return
	}
	if _, err := io.Copy(complaintTmp, complaintFile); err != nil {
		complaintTmp.Close()
		os.Remove(complaintTmp.Name())
		respond(c, http.StatusInternalServerError, false, "failed to save complaint file", nil)
		return
	}
	complaintTmp.Close()

	// ── Save reply DOCX to temp file ───────────────────────────────────────────
	replyExt := filepath.Ext(replyHeader.Filename)
	if replyExt == "" {
		replyExt = ".docx"
	}
	replyTmp, err := os.CreateTemp("", "reply-*"+replyExt)
	if err != nil {
		os.Remove(complaintTmp.Name())
		respond(c, http.StatusInternalServerError, false, "failed to create temp file", nil)
		return
	}
	if _, err := io.Copy(replyTmp, replyFile); err != nil {
		replyTmp.Close()
		os.Remove(complaintTmp.Name())
		os.Remove(replyTmp.Name())
		respond(c, http.StatusInternalServerError, false, "failed to save reply file", nil)
		return
	}
	replyTmp.Close()

	// ── Create job record and start goroutine ──────────────────────────────────
	jobID := uuid.New().String()
	job := &complaintJob{Status: jobProcessing, CreatedAt: time.Now()}
	storeJob(jobID, job)

	complaintPath := complaintTmp.Name()
	replyPath := replyTmp.Name()

	go func() {
		defer os.Remove(complaintPath)
		defer os.Remove(replyPath)

		// Use a fresh background context — the HTTP request context is already
		// cancelled by the time this goroutine does meaningful work.
		ctx := context.Background()

		complaintResult, err := h.ocrService.ExtractTextFast(ctx, complaintPath, "eng+mar+hin+mod", 50)
		if err != nil || complaintResult.Text == "" {
			msg := "Failed to extract text from complaint PDF"
			if err != nil {
				msg = fmt.Sprintf("Complaint extraction failed: %v", err)
			}
			jobsMu.Lock()
			job.Status = jobFailed
			job.ErrMsg = msg
			jobsMu.Unlock()
			return
		}

		replyResult, err := h.ocrService.ExtractText(ctx, replyPath)
		if err != nil || replyResult.Text == "" {
			msg := "Failed to extract text from reply DOCX"
			if err != nil {
				msg = fmt.Sprintf("Reply extraction failed: %v", err)
			}
			jobsMu.Lock()
			job.Status = jobFailed
			job.ErrMsg = msg
			jobsMu.Unlock()
			return
		}

		logger.Info("Complaint reply generation started (async)",
			logger.Str("job_id", jobID),
			logger.Str("user_id", userID.String()),
			logger.Int("complaint_chars", len(complaintResult.Text)),
		)

		result, err := h.aiService.GenerateComplaintReply(ctx, userID, complaintResult.Text, replyResult.Text)
		jobsMu.Lock()
		if err != nil {
			job.Status = jobFailed
			job.ErrMsg = err.Error()
		} else {
			job.Status = jobDone
			job.Result = result
		}
		jobsMu.Unlock()
		logger.Info("Complaint reply job finished", logger.Str("job_id", jobID), logger.Str("status", string(job.Status)))
	}()

	respond(c, http.StatusOK, true, "processing", gin.H{"job_id": jobID})
}

// GetComplaintReplyStatus returns the status of an async complaint-reply job.
// Flutter polls this every 3 seconds after calling ComplaintReplyGenerator.
// On completion the result is included in the response and the job is removed.
func (h *AIHandler) GetComplaintReplyStatus(c *gin.Context) {
	jobID := c.Param("job_id")
	job, ok := readJob(jobID)
	if !ok {
		respond(c, http.StatusNotFound, false, "job not found or expired", nil)
		return
	}

	jobsMu.RLock()
	status := job.Status
	result := job.Result
	errMsg := job.ErrMsg
	jobsMu.RUnlock()

	switch status {
	case jobDone:
		deleteJob(jobID)
		respond(c, http.StatusOK, true, "completed", result)
	case jobFailed:
		deleteJob(jobID)
		respond(c, http.StatusOK, false, errMsg, nil)
	default:
		respond(c, http.StatusOK, true, "processing", gin.H{"status": "processing"})
	}
}

// DownloadReplyDocx accepts the generated reply text and returns it as a .docx binary.
func (h *AIHandler) DownloadReplyDocx(c *gin.Context) {
	var req struct {
		Text     string `json:"text" binding:"required"`
		Filename string `json:"filename"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Text == "" {
		respond(c, http.StatusBadRequest, false, "text is required", nil)
		return
	}

	docxBytes, err := ocr.CreateDocx(req.Text)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, "failed to create DOCX file", nil)
		return
	}

	filename := req.Filename
	if filename == "" {
		filename = "complaint_reply.docx"
	}

	c.Header("Content-Disposition", `attachment; filename="`+filename+`"`)
	c.Data(http.StatusOK, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", docxBytes)
}

// DownloadReplyPDF accepts the generated reply text and returns it as a .pdf binary.
func (h *AIHandler) DownloadReplyPDF(c *gin.Context) {
	var req struct {
		Text     string `json:"text" binding:"required"`
		Filename string `json:"filename"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Text == "" {
		respond(c, http.StatusBadRequest, false, "text is required", nil)
		return
	}

	pdfBytes, err := ocr.CreatePDF(req.Text)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, "failed to create PDF file", nil)
		return
	}

	filename := req.Filename
	if filename == "" {
		filename = "complaint_reply.pdf"
	}

	c.Header("Content-Disposition", `attachment; filename="`+filename+`"`)
	c.Data(http.StatusOK, "application/pdf", pdfBytes)
}

func (h *AIHandler) ScanOCR(c *gin.Context) {
	userID, err := uuid.Parse(middleware.GetUserID(c))
	if err != nil {
		respond(c, http.StatusUnauthorized, false, "invalid token", nil)
		return
	}
	_ = userID

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		respond(c, http.StatusBadRequest, false, "file is required", nil)
		return
	}
	defer file.Close()

	ext := filepath.Ext(header.Filename)
	if ext == "" {
		ext = ".jpg"
	}

	tmp, err := os.CreateTemp("", "ocr-*"+ext)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, "failed to create temp file", nil)
		return
	}
	defer os.Remove(tmp.Name())

	buf := make([]byte, 32*1024)
	for {
		n, readErr := file.Read(buf)
		if n > 0 {
			if _, writeErr := tmp.Write(buf[:n]); writeErr != nil {
				tmp.Close()
				respond(c, http.StatusInternalServerError, false, "failed to write temp file", nil)
				return
			}
		}
		if readErr != nil {
			break
		}
	}
	tmp.Close()

	lang := c.PostForm("language")
	if lang == "" {
		lang = "en"
	}
	tessLang := ocr.LangToTess(lang)

	// Cap at 15 pages for synchronous HTTP response on the free-tier server.
	// Single images and short PDFs are unaffected; large scanned books are capped.
	result, err := h.ocrService.ExtractTextFast(c.Request.Context(), tmp.Name(), tessLang, 15)
	if err != nil {
		respond(c, http.StatusInternalServerError, false, fmt.Sprintf("OCR failed: %v", err), nil)
		return
	}

	// Raw OCR output is often messy/garbled (misread characters, broken
	// layout, no punctuation) — especially for photos of screens, diagrams,
	// or low-quality scans. Run it through AI to produce a clean, readable
	// summary instead of dumping the raw text on the user. If summarization
	// fails (e.g. AI provider down) we still fall back to the raw text so
	// the feature doesn't hard-fail.
	summary := ""
	if result.Text != "" {
		if summaryRes, sumErr := h.aiService.SummarizeText(c.Request.Context(), result.Text); sumErr == nil && summaryRes != nil {
			summary = summaryRes.Summary
		}
	}

	respond(c, http.StatusOK, true, "OCR extraction complete", gin.H{
		"text":       result.Text,
		"summary":    summary,
		"word_count": result.WordCount,
		"page_count": result.PageCount,
		"confidence": result.Confidence,
		"language":   lang,
	})
}