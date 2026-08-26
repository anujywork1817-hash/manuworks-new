package service

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"

	docModel "github.com/yourusername/docassist/internal/document/model"
	docRepo "github.com/yourusername/docassist/internal/document/repository"
	"github.com/yourusername/docassist/pkg/gemini"
    "github.com/yourusername/docassist/pkg/groq"
	"github.com/yourusername/docassist/pkg/logger"
	"github.com/yourusername/docassist/pkg/ocr"
	"github.com/yourusername/docassist/pkg/qdrant"
)

// ─── Request / Response types ─────────────────────────────────────────────────

type ProcessDocumentResult struct {
	DocumentID string `json:"document_id"`
	ChunkCount int    `json:"chunk_count"`
	WordCount  int    `json:"word_count"`
	PageCount  int    `json:"page_count"`
	OcrUsed    bool   `json:"ocr_used"`
	Duration   string `json:"duration"`
}

type SummarizeRequest struct {
	DocumentID string `json:"document_id"`
}

type QARequest struct {
	DocumentID string `json:"document_id"`
	Question   string `json:"question" binding:"required,min=3,max=1000"`
}

type ChatRequest struct {
	DocumentID string               `json:"document_id"`
	Message    string               `json:"message" binding:"required,min=1,max=2000"`
	History    []groq.ChatMessage `json:"history"`
}

type ChatResponse struct {
	Answer    string    `json:"answer"`
	SessionID string    `json:"session_id"`
	CreatedAt time.Time `json:"created_at"`
}

type TranslateRequest struct {
	DocumentID     string `json:"document_id"`
	TargetLanguage string `json:"target_language" binding:"required"`
}

type ReportRequest struct {
	DocumentID string `json:"document_id"`
	ReportType string `json:"report_type" binding:"required,oneof=executive technical legal financial summary"`
}

type AIRequestLog struct {
	UserID     uuid.UUID `json:"user_id"`
	DocumentID uuid.UUID `json:"document_id"`
	Feature    string    `json:"feature"`
	Success    bool      `json:"success"`
	TokensUsed int       `json:"tokens_used"`
	Duration   string    `json:"duration"`
	Error      string    `json:"error,omitempty"`
}

// ─── Interface ────────────────────────────────────────────────────────────────

type AIService interface {
	// Document processing pipeline
	ProcessDocument(ctx context.Context, userID, docID uuid.UUID) (*ProcessDocumentResult, error)

	// AI features — all require document to be processed first
	Summarize(ctx context.Context, userID, docID uuid.UUID) (*groq.SummaryResponse, error)
	AnswerQuestion(ctx context.Context, userID, docID uuid.UUID, question string) (*groq.QAResponse, error)
	Chat(ctx context.Context, userID, docID uuid.UUID, req ChatRequest) (*ChatResponse, error)
	ExtractKeyPoints(ctx context.Context, userID, docID uuid.UUID) ([]string, error)
	ExtractTimeline(ctx context.Context, userID, docID uuid.UUID) (*groq.TimelineResponse, error)
	ExtractActionItems(ctx context.Context, userID, docID uuid.UUID) ([]string, error)
	AnalyzeDocument(ctx context.Context, userID, docID uuid.UUID) (*groq.AnalysisResponse, error)
	Translate(ctx context.Context, userID, docID uuid.UUID, targetLanguage string) (*groq.TranslationResponse, error)
	GenerateReport(ctx context.Context, userID, docID uuid.UUID, reportType string) (*groq.ReportResponse, error)
	ExtractCitations(ctx context.Context, userID, docID uuid.UUID) (*groq.CitationsResponse, error)
	ScanRisks(ctx context.Context, userID, docID uuid.UUID) (*groq.RiskScanResponse, error)
	ExtractDeadlines(ctx context.Context, userID, docID uuid.UUID) (*groq.DeadlineResponse, error)
	AutoTag(ctx context.Context, userID, docID uuid.UUID) (*groq.AutoTagsResponse, error)
	CheckGrammar(ctx context.Context, userID, docID uuid.UUID) (*groq.GrammarCheckResponse, error)
	DraftLegalDoc(ctx context.Context, userID uuid.UUID, req groq.LegalDraftRequest) (*groq.LegalDraftResponse, error)
	CompareDocuments(ctx context.Context, userID, docID1, docID2 uuid.UUID) (*groq.CompareResponse, error)
	HelpChat(ctx context.Context, history []groq.ChatMessage, message string) (string, error)
	GenerateComplaintReply(ctx context.Context, userID uuid.UUID, complaintText, existingReplyText string) (*ComplaintReplyResult, error)

	// SummarizeText cleans up / summarizes raw text (e.g. from OCR) directly,
	// without needing a document to already be saved+processed in the DB.
	SummarizeText(ctx context.Context, text string) (*groq.SummaryResponse, error)
}

// ─── Implementation ───────────────────────────────────────────────────────────

type aiService struct {
    geminiClient *gemini.Client
	docRepo      docRepo.DocumentRepository
	groqClient *groq.Client
	qdrantClient *qdrant.Client
	ocrService   *ocr.Service
}

func NewAIService(
    docRepo docRepo.DocumentRepository,
    geminiClient *gemini.Client,
    groqClient *groq.Client,
	qdrantClient *qdrant.Client,
	ocrService *ocr.Service,
) AIService {
	return &aiService{
        docRepo:      docRepo,
        geminiClient: geminiClient,
        groqClient:   groqClient,
		qdrantClient: qdrantClient,
		ocrService:   ocrService,
	}
}

// ─── Document Processing Pipeline ────────────────────────────────────────────
//
// Flow:
//  1. Load document record from DB
//  2. Extract text (OCR for scanned, direct for digital)
//  3. Save OCR text to PostgreSQL
//  4. Split text into overlapping chunks
//  5. Generate embeddings for each chunk via Gemini
//  6. Store vectors in Qdrant
//  7. Save chunk records to PostgreSQL
//  8. Mark document as ready

func (s *aiService) ProcessDocument(ctx context.Context, userID, docID uuid.UUID) (*ProcessDocumentResult, error) {
	start := time.Now()

	// 1. Load document
	doc, err := s.docRepo.GetByIDAndUserID(ctx, docID, userID)
	if err != nil {
		return nil, fmt.Errorf("load document: %w", err)
	}

	// Mark as processing
	_ = s.docRepo.UpdateStatus(ctx, docID, docModel.DocumentStatusProcessing)
	_ = s.docRepo.UpdateOCRStatus(ctx, docID, "processing")

	logger.Info("Starting document processing",
		logger.Str("doc_id", docID.String()),
		logger.Str("file_type", string(doc.FileType)),
	)

	// 2. Extract text — priority order:
	//    a) user-edited text  (never overwrite)
	//    b) previously extracted text cached in DB  (avoids hitting disk on Render redeploys)
	//    c) extract fresh from file
	var (
		extractedText string
		ocrWordCount  int
		ocrPageCount  int
		ocrUsed       bool
	)

	switch {
	case doc.OcrStatus == "edited" && doc.OcrText != "":
		// User manually corrected the text — preserve it exactly.
		extractedText = doc.OcrText
		ocrWordCount = doc.WordCount
		ocrPageCount = doc.PageCount
		ocrUsed = false
		logger.Info("Using user-edited OCR text (skipping file extraction)",
			logger.Str("doc_id", docID.String()),
			logger.Int("chars", len(extractedText)),
		)

	case doc.OcrStatus == "completed" && doc.OcrText != "":
		// Text already extracted and stored in PostgreSQL — reuse it.
		// This is the normal path after a server redeploy when the ephemeral
		// /app/storage volume is gone but the DB text is still available.
		extractedText = doc.OcrText
		ocrWordCount = doc.WordCount
		ocrPageCount = doc.PageCount
		ocrUsed = false
		logger.Info("Reusing cached OCR text from DB (skipping file extraction)",
			logger.Str("doc_id", docID.String()),
			logger.Int("chars", len(extractedText)),
		)

	default:
		// First-time processing — file must exist on disk.
		if _, statErr := os.Stat(doc.FilePath); os.IsNotExist(statErr) {
			_ = s.docRepo.UpdateStatus(ctx, docID, docModel.DocumentStatusFailed)
			_ = s.docRepo.UpdateOCRStatus(ctx, docID, "failed")
			return nil, fmt.Errorf("document file is no longer available on the server (the server was redeployed and the upload was lost — please re-upload the document)")
		}

		// Use multilingual OCR — all documents in this app may be in Indian
		// regional languages (Marathi, Hindi, etc.) so always load eng+mar+hin.
		// For digital PDFs this lang param is ignored (pdftotext handles Unicode).
		// For scanned PDFs it controls which Tesseract language models are loaded.
		ocrLang := indiaOCRLang(doc.Language)
		// No page limit — ProcessDocument always runs in a background goroutine.
		ocrResult, err := s.ocrService.ExtractTextWithLang(ctx, doc.FilePath, ocrLang)
		if err != nil {
			_ = s.docRepo.UpdateStatus(ctx, docID, docModel.DocumentStatusFailed)
			_ = s.docRepo.UpdateOCRStatus(ctx, docID, "failed")
			return nil, fmt.Errorf("text extraction: %w", err)
		}
		extractedText = ocrResult.Text
		ocrWordCount = ocrResult.WordCount
		ocrPageCount = ocrResult.PageCount
		ocrUsed = ocrResult.Confidence < 100.0

		// 3. Save OCR text to PostgreSQL so future calls can skip the file.
		if err := s.docRepo.UpdateOCRText(ctx, docID, ocrResult.Text, ocrResult.WordCount); err != nil {
			logger.Warn("Failed to save OCR text", logger.Str("error", err.Error()))
		}
		doc.OcrText = ocrResult.Text
		doc.OcrStatus = "completed"
	}

	// 4. Split into chunks
	// Limit text size to prevent OOM on large documents
	const maxTextLen = 5000
	processText := extractedText
	if len(processText) > maxTextLen {
		processText = processText[:maxTextLen]
		if idx := strings.LastIndex(processText, " "); idx > 100 {
			processText = processText[:idx]
		}
	}
	chunks := chunkTextSafe(processText, 400, 80)
	if len(chunks) == 0 {
		_ = s.docRepo.UpdateStatus(ctx, docID, docModel.DocumentStatusFailed)
		return nil, fmt.Errorf("no text content found in document")
	}

	// 5. Generate embeddings + store in Qdrant
	dbChunks := make([]docModel.DocumentChunk, 0, len(chunks))
	qdrantPoints := make([]qdrant.Point, 0, len(chunks))

	embeddingOK := false // temporarily disabled until correct model confirmed
        for i, chunk := range chunks {
                if !embeddingOK {
                        break
                }
                select {
                case <-ctx.Done():
                        return nil, ctx.Err()
                default:
                }
                embedding, err := s.geminiClient.GenerateEmbedding(ctx, chunk.text)
                if err != nil {
                        logger.Warn("Embedding failed, skipping all chunks",
                                logger.Int("chunk", i),
                                logger.Str("error", err.Error()),
                        )
                        embeddingOK = false
                        break
                }

		chunkID := uuid.New()
		qdrantID := uuid.New().String()

		dbChunks = append(dbChunks, docModel.DocumentChunk{
			ID:          chunkID,
			DocumentID:  docID,
			ChunkIndex:  i,
			Content:     chunk.text,
			TokenCount:  estimateTokens(chunk.text),
			QdrantID:    qdrantID,
			IsEmbedded:  true,
			PageNumber:  chunk.page,
			StartOffset: chunk.start,
			EndOffset:   chunk.end,
		})

		qdrantPoints = append(qdrantPoints, qdrant.Point{
			ID:         qdrantID,
			Vector:     embedding.Embeddings,
			DocumentID: docID.String(),
			ChunkID:    chunkID.String(),
			ChunkIndex: i,
			PageNumber: chunk.page,
			Content:    chunk.text,
			UserID:     userID.String(),
		})
	}

	// 6. Batch upsert to Qdrant
	if len(qdrantPoints) > 0 {
		if err := s.qdrantClient.UpsertPoints(ctx, qdrantPoints); err != nil {
			logger.Warn("Qdrant upsert failed", logger.Str("error", err.Error()))
			// Non-fatal — document is still usable without semantic search
		}
	}

	// 7. Save chunks to PostgreSQL
	if len(dbChunks) > 0 {
		// Delete old chunks if reprocessing
		_ = s.docRepo.DeleteChunksByDocumentID(ctx, docID)
		if err := s.docRepo.CreateChunks(ctx, dbChunks); err != nil {
			logger.Warn("Failed to save chunks to DB", logger.Str("error", err.Error()))
		}
		_ = s.docRepo.MarkDocumentEmbedded(ctx, docID)
	}

	// 8. Pre-compute AI features and cache them so feature taps return instantly
	summaryRes, _ := s.groqClient.Summarize(ctx, truncate(extractedText, 15000))
	keyPointsRes, _ := s.groqClient.ExtractKeyPoints(ctx, truncate(extractedText, 12000))
	timelineRes, _ := s.groqClient.ExtractTimeline(ctx, truncate(extractedText, 15000))
	actionRes, _ := s.groqClient.ExtractActionItems(ctx, truncate(extractedText, 12000))
	analysisRes, _ := s.groqClient.AnalyzeDocument(ctx, truncate(extractedText, 12000))

	var (
		cachedSummary     string
		cachedKeyPoints   string
		cachedTimeline    string
		cachedActionItems string
		cachedAnalysis    string
	)
	if summaryRes != nil {
		cachedSummary = summaryRes.Summary
	}
	if keyPointsRes != nil {
		cachedKeyPoints = strings.Join(keyPointsRes.KeyPoints, "\n")
	}
	if timelineRes != nil {
		parts := make([]string, len(timelineRes.Events))
		for i, e := range timelineRes.Events {
			parts[i] = e.Date + ": " + e.Event
		}
		cachedTimeline = strings.Join(parts, "\n")
	}
	if actionRes != nil {
		parts := make([]string, len(actionRes.ActionItems))
		for i, a := range actionRes.ActionItems {
			parts[i] = a.Action
		}
		cachedActionItems = strings.Join(parts, "\n")
	}
	if analysisRes != nil {
		cachedAnalysis = fmt.Sprintf("Type: %s\nSentiment: %s\nRisk: %s\nInsights: %s",
			analysisRes.DocumentType, analysisRes.Sentiment, analysisRes.RiskLevel,
			strings.Join(analysisRes.Insights, "; "))
	}
	_ = s.docRepo.SaveAICache(ctx, docID, cachedSummary, cachedKeyPoints, cachedTimeline, cachedActionItems, cachedAnalysis)

	// 9. Mark document ready — use UpdateFields to avoid touching missing columns
	_ = s.docRepo.UpdateFields(ctx, docID, map[string]interface{}{
		"status":     docModel.DocumentStatusReady,
		"page_count": ocrPageCount,
		"word_count": ocrWordCount,
		"ocr_status": doc.OcrStatus,
	})

	result := &ProcessDocumentResult{
		DocumentID: docID.String(),
		ChunkCount: len(dbChunks),
		WordCount:  ocrWordCount,
		PageCount:  ocrPageCount,
		OcrUsed:    ocrUsed,
		Duration:   time.Since(start).String(),
	}

	logger.Info("Document processing complete",
		logger.Str("doc_id", docID.String()),
		logger.Int("chunks", len(dbChunks)),
		logger.Int("words", ocrWordCount),
		logger.Str("duration", result.Duration),
	)

	return result, nil
}

// ─── AI Features ──────────────────────────────────────────────────────────────

func (s *aiService) Summarize(ctx context.Context, userID, docID uuid.UUID) (*groq.SummaryResponse, error) {
	doc, err := s.getDocument(ctx, userID, docID)
	if err != nil {
		return nil, err
	}
	if doc.AiSummary != "" {
		return &groq.SummaryResponse{Summary: doc.AiSummary, KeyPoints: []string{}, WordCount: doc.WordCount}, nil
	}
	return s.groqClient.Summarize(ctx, truncate(doc.OcrText, 15000))
}

// SummarizeText summarizes raw text directly (used for OCR results that
// aren't tied to a saved document) instead of returning the raw, often
// messy/garbled OCR output straight to the user.
func (s *aiService) SummarizeText(ctx context.Context, text string) (*groq.SummaryResponse, error) {
	text = strings.TrimSpace(text)
	if text == "" {
		return &groq.SummaryResponse{Summary: "", KeyPoints: []string{}, WordCount: 0}, nil
	}
	return s.groqClient.Summarize(ctx, truncate(text, 15000))
}

func (s *aiService) AnswerQuestion(ctx context.Context, userID, docID uuid.UUID, question string) (*groq.QAResponse, error) {
	// Use RAG: find the most relevant chunks first, then send only those to Gemini
	// This is more accurate and uses fewer tokens than sending the whole document
	relevant, err := s.retrieveRelevantChunks(ctx, docID, userID, question, 8)
	if err != nil || len(relevant) == 0 {
		// Fallback: use full document text
		text, err := s.getDocumentText(ctx, userID, docID, 12000)
		if err != nil {
			return nil, err
		}
		return s.groqClient.AnswerQuestion(ctx, text, question)
	}

	// Build context from retrieved chunks
	var sb strings.Builder
	for i, chunk := range relevant {
		sb.WriteString(fmt.Sprintf("[Chunk %d, Page %d, Relevance: %.2f]\n", i+1, chunk.PageNumber, chunk.Score))
		sb.WriteString(chunk.Content)
		sb.WriteString("\n\n")
	}

	return s.groqClient.AnswerQuestion(ctx, sb.String(), question)
}

func (s *aiService) Chat(ctx context.Context, userID, docID uuid.UUID, req ChatRequest) (*ChatResponse, error) {
	// RAG: find relevant chunks for the user's message
	relevant, err := s.retrieveRelevantChunks(ctx, docID, userID, req.Message, 5)

	var contextText string
	if err != nil || len(relevant) == 0 {
		// Fallback to full document
		contextText, err = s.getDocumentText(ctx, userID, docID, 12000)
		if err != nil {
			return nil, err
		}
	} else {
		var sb strings.Builder
		for _, chunk := range relevant {
			sb.WriteString(chunk.Content)
			sb.WriteString("\n\n")
		}
		contextText = sb.String()
	}

	logger.Info("Chat debug", logger.Str("message", req.Message), logger.Int("context_len", len(contextText)), logger.Str("context_preview", contextText[:min(200, len(contextText))]))
    answer, err := s.groqClient.Chat(ctx, contextText, req.History, req.Message)
	if err != nil {
		return nil, err
	}

	return &ChatResponse{
		Answer:    answer,
		SessionID: req.DocumentID,
		CreatedAt: time.Now(),
	}, nil
}

func (s *aiService) ExtractKeyPoints(ctx context.Context, userID, docID uuid.UUID) ([]string, error) {
	doc, err := s.getDocument(ctx, userID, docID)
	if err != nil {
		return nil, err
	}
	if doc.AiKeyPoints != "" {
		return strings.Split(doc.AiKeyPoints, "\n"), nil
	}
	result, err := s.groqClient.ExtractKeyPoints(ctx, truncate(doc.OcrText, 12000))
	if err != nil {
		return nil, err
	}
	return result.KeyPoints, nil
}

func (s *aiService) ExtractTimeline(ctx context.Context, userID, docID uuid.UUID) (*groq.TimelineResponse, error) {
	doc, err := s.getDocument(ctx, userID, docID)
	if err != nil {
		return nil, err
	}
	if doc.AiTimeline != "" {
		events := []groq.TimelineEvent{}
		for _, line := range strings.Split(doc.AiTimeline, "\n") {
			if line == "" {
				continue
			}
			parts := strings.SplitN(line, ": ", 2)
			if len(parts) == 2 {
				events = append(events, groq.TimelineEvent{Date: parts[0], Event: parts[1]})
			} else {
				events = append(events, groq.TimelineEvent{Event: line})
			}
		}
		return &groq.TimelineResponse{Events: events}, nil
	}
	return s.groqClient.ExtractTimeline(ctx, truncate(doc.OcrText, 15000))
}

func (s *aiService) ExtractActionItems(ctx context.Context, userID, docID uuid.UUID) ([]string, error) {
	doc, err := s.getDocument(ctx, userID, docID)
	if err != nil {
		return nil, err
	}
	if doc.AiActionItems != "" {
		return strings.Split(doc.AiActionItems, "\n"), nil
	}
	result, err := s.groqClient.ExtractActionItems(ctx, truncate(doc.OcrText, 12000))
	if err != nil {
		return nil, err
	}
	items := make([]string, len(result.ActionItems))
	for i, a := range result.ActionItems {
		items[i] = a.Action
	}
	return items, nil
}

func (s *aiService) AnalyzeDocument(ctx context.Context, userID, docID uuid.UUID) (*groq.AnalysisResponse, error) {
	doc, err := s.getDocument(ctx, userID, docID)
	if err != nil {
		return nil, err
	}
	if doc.AiAnalysis != "" {
		return &groq.AnalysisResponse{
			DocumentType: "Document",
			Insights:     strings.Split(doc.AiAnalysis, "\n"),
		}, nil
	}
	return s.groqClient.AnalyzeDocument(ctx, truncate(doc.OcrText, 12000))
}

func (s *aiService) Translate(ctx context.Context, userID, docID uuid.UUID, targetLanguage string) (*groq.TranslationResponse, error) {
	text, err := s.getDocumentText(ctx, userID, docID, 30000)
	if err != nil {
		return nil, err
	}
	return s.groqClient.Translate(ctx, text, targetLanguage)
}

func (s *aiService) GenerateReport(ctx context.Context, userID, docID uuid.UUID, reportType string) (*groq.ReportResponse, error) {
	text, err := s.getDocumentText(ctx, userID, docID, 15000)
	if err != nil {
		return nil, err
	}
	return s.groqClient.GenerateReport(ctx, text, reportType)
}

func (s *aiService) ExtractCitations(ctx context.Context, userID, docID uuid.UUID) (*groq.CitationsResponse, error) {
	text, err := s.getDocumentText(ctx, userID, docID, 20000)
	if err != nil {
		return nil, err
	}
	return s.groqClient.ExtractCitations(ctx, text)
}

func (s *aiService) ScanRisks(ctx context.Context, userID, docID uuid.UUID) (*groq.RiskScanResponse, error) {
	text, err := s.getDocumentText(ctx, userID, docID, 20000)
	if err != nil {
		return nil, err
	}
	return s.groqClient.ScanRisks(ctx, text)
}

func (s *aiService) ExtractDeadlines(ctx context.Context, userID, docID uuid.UUID) (*groq.DeadlineResponse, error) {
	text, err := s.getDocumentText(ctx, userID, docID, 20000)
	if err != nil {
		return nil, err
	}
	return s.groqClient.ExtractDeadlines(ctx, text)
}

func (s *aiService) AutoTag(ctx context.Context, userID, docID uuid.UUID) (*groq.AutoTagsResponse, error) {
	text, err := s.getDocumentText(ctx, userID, docID, 15000)
	if err != nil {
		return nil, err
	}
	return s.groqClient.AutoTag(ctx, text)
}

func (s *aiService) CheckGrammar(ctx context.Context, userID, docID uuid.UUID) (*groq.GrammarCheckResponse, error) {
	text, err := s.getDocumentText(ctx, userID, docID, 15000)
	if err != nil {
		return nil, err
	}
	return s.groqClient.CheckGrammar(ctx, text)
}

func (s *aiService) DraftLegalDoc(ctx context.Context, userID uuid.UUID, req groq.LegalDraftRequest) (*groq.LegalDraftResponse, error) {
	return s.groqClient.DraftLegalDocument(ctx, req)
}

func (s *aiService) CompareDocuments(ctx context.Context, userID, docID1, docID2 uuid.UUID) (*groq.CompareResponse, error) {
	text1, err := s.getDocumentText(ctx, userID, docID1, 10000)
	if err != nil {
		return nil, fmt.Errorf("document 1: %w", err)
	}
	text2, err := s.getDocumentText(ctx, userID, docID2, 10000)
	if err != nil {
		return nil, fmt.Errorf("document 2: %w", err)
	}
	return s.groqClient.CompareDocuments(ctx, text1, text2)
}

func (s *aiService) HelpChat(ctx context.Context, history []groq.ChatMessage, message string) (string, error) {
	return s.groqClient.HelpChat(ctx, history, message)
}

// ─── Private helpers ──────────────────────────────────────────────────────────

// getDocument loads and validates a document is ready for AI processing.
func (s *aiService) getDocument(ctx context.Context, userID, docID uuid.UUID) (*docModel.Document, error) {
	doc, err := s.docRepo.GetByIDAndUserID(ctx, docID, userID)
	if err != nil {
		return nil, err
	}
	if doc.Status == docModel.DocumentStatusReady && doc.OcrText != "" {
		return doc, nil
	}
	// Auto-trigger background processing if not already running.
	if doc.Status != docModel.DocumentStatusProcessing {
		go func() { _, _ = s.ProcessDocument(context.Background(), userID, docID) }()
	}
	return nil, fmt.Errorf("document is being processed — please try again in a moment")
}

// getDocumentText loads OCR text from PostgreSQL, truncated to maxChars.
func (s *aiService) getDocumentText(ctx context.Context, userID, docID uuid.UUID, maxChars int) (string, error) {
	doc, err := s.getDocument(ctx, userID, docID)
	if err != nil {
		return "", err
	}
	text := doc.OcrText
	if maxChars > 0 && len(text) > maxChars {
		text = text[:maxChars]
		if idx := strings.LastIndexAny(text, ".!?\n"); idx > maxChars/2 {
			text = text[:idx+1]
		}
	}
	return text, nil
}

// retrieveRelevantChunks uses RAG to find the most semantically similar
// chunks to the query. Falls back gracefully if embedding fails.
func (s *aiService) retrieveRelevantChunks(ctx context.Context, docID, userID uuid.UUID, query string, limit int) ([]qdrant.SearchResult, error) {
	if s.geminiClient == nil {
		return nil, fmt.Errorf("query embedding: Gemini is not configured (GEMINI_API_KEY not set)")
	}
	// Generate embedding for the query
	embedding, err := s.geminiClient.GenerateEmbedding(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("query embedding: %w", err)
	}

	// Search within this specific document
	results, err := s.qdrantClient.SearchByDocument(ctx, embedding.Embeddings, docID.String(), limit)
	if err != nil {
		return nil, fmt.Errorf("qdrant search: %w", err)
	}

	return results, nil
}

// ─── Text chunking ────────────────────────────────────────────────────────────

type textChunk struct {
	text  string
	page  int
	start int
	end   int
}

// chunkText splits text into overlapping chunks for RAG.
//
// chunkSize  — target characters per chunk (~1000 chars ≈ 250 tokens)
// overlap    — characters shared between adjacent chunks (helps context continuity)
//
// Splits at sentence boundaries where possible to avoid cutting mid-sentence.
func chunkTextSafe(text string, chunkSize, overlap int) []textChunk {
	if len(text) == 0 {
		return nil
	}
	var chunks []textChunk
	textLen := len(text)
	start := 0
	for start < textLen {
		end := start + chunkSize
		if end > textLen {
			end = textLen
		}
		for end < textLen && text[end]&0xC0 == 0x80 {
			end--
		}
		if end < textLen && end > start+chunkSize/2 {
			for i := end; i > start+chunkSize/2; i-- {
				ch := text[i]
				if ch == '.' || ch == '!' || ch == '?' || ch == '\n' {
					end = i + 1
					break
				}
			}
		}
		chunk := strings.TrimSpace(text[start:end])
		if len(chunk) > 30 {
			chunks = append(chunks, textChunk{
				text:  chunk,
				page:  (start / 2000) + 1,
				start: start,
				end:   end,
			})
		}
		next := end - overlap
		if next <= start {
			next = start + 1
		}
		start = next
	}
	return chunks
}

// estimateTokens gives a rough token count (1 token ≈ 4 characters for English).
func estimateTokens(text string) int {
	return len(text) / 4
}

// truncate caps text at maxChars, trimming at the last sentence boundary.
func truncate(text string, maxChars int) string {
	if len(text) <= maxChars {
		return text
	}
	t := text[:maxChars]
	if idx := strings.LastIndexAny(t, ".!?\n"); idx > maxChars/2 {
		return t[:idx+1]
	}
	return t
}















// --- Document Drafter ------------------------------------------------------

type DraftResult struct {
	DocumentID string `json:"document_id"`
	Title      string `json:"title"`
	Content    string `json:"content"`
}

// ComplaintReplyResult is the AI-generated reply for a complaint.
type ComplaintReplyResult struct {
	ReplyText        string   `json:"reply_text"`
	ModifiedSections []string `json:"modified_sections"`
	Summary          string   `json:"summary"`
}

func (s *aiService) GenerateComplaintReply(ctx context.Context, userID uuid.UUID, complaintText, existingReplyText string) (*ComplaintReplyResult, error) {
	result, err := s.groqClient.GenerateComplaintReply(
		ctx,
		truncate(complaintText, 12000),
		truncate(existingReplyText, 6000),
	)
	if err != nil {
		return nil, err
	}
	return &ComplaintReplyResult{
		ReplyText:        result.ReplyText,
		ModifiedSections: result.ModifiedSections,
		Summary:          result.Summary,
	}, nil
}

func (s *aiService) DraftDocument(ctx context.Context, userID uuid.UUID, docType, details string) (*DraftResult, error) {
    draft, err := s.groqClient.DraftDocument(ctx, docType, details)
    if err != nil {
        return nil, fmt.Errorf("draft document: %w", err)
    }

    doc := &docModel.Document{
        UserID:     userID,
        Title:      draft.Title,
        FileName:   draft.Title + ".txt",
        FilePath:   "drafted",
        FileSize:   int64(len(draft.Content)),
        FileType:   "txt",
        MimeType:   "text/plain",
        Status:     docModel.DocumentStatusReady,
        WordCount:  len(strings.Fields(draft.Content)),
        PageCount:  1,
        Language:   "en",
        OcrText:    draft.Content,
        OcrStatus:  "completed",
        IsEmbedded: false,
        Description: "AI-drafted document",
    }

    if err := s.docRepo.Create(ctx, doc); err != nil {
        return nil, fmt.Errorf("save drafted document: %w", err)
    }

    return &DraftResult{
        DocumentID: doc.ID.String(),
        Title:      draft.Title,
        Content:    draft.Content,
    }, nil
}

// indiaOCRLang returns the Tesseract language string for a document.
// Since this app handles Indian legal documents, we always include Marathi
// and Hindi alongside English so scanned PDFs in any of these scripts are
// read correctly. For digital PDFs pdftotext handles Unicode natively and
// this param is irrelevant.
// indiaOCRLang delegates to the OCR package's canonical language mapping.
func indiaOCRLang(docLang string) string {
	return ocr.LangToTess(docLang)
}