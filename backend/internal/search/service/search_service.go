package service

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/yourusername/docassist/pkg/gemini"
	"github.com/yourusername/docassist/pkg/logger"
	"github.com/yourusername/docassist/pkg/qdrant"
	"gorm.io/gorm"
)

type SearchResult struct {
	DocumentID    string    `json:"document_id"`
	DocumentTitle string    `json:"document_title"`
	ChunkText     string    `json:"chunk_text"`
	Score         float64   `json:"score"`
	PageNumber    int       `json:"page_number"`
	ChunkIndex    int       `json:"chunk_index"`
	FileType      string    `json:"file_type"`
	UploadedAt    time.Time `json:"uploaded_at"`
}

type RAGResponse struct {
	Answer  string         `json:"answer"`
	Sources []SearchResult `json:"sources"`
	Model   string         `json:"model"`
}

type SearchResponse struct {
	Query      string         `json:"query"`
	Results    []SearchResult `json:"results"`
	TotalFound int            `json:"total_found"`
	TookMs     int64          `json:"took_ms"`
}

type SearchService struct {
	db           *gorm.DB
	geminiClient *gemini.Client
	qdrantClient *qdrant.Client
}

func NewSearchService(db *gorm.DB, geminiClient *gemini.Client, qdrantClient *qdrant.Client) *SearchService {
	return &SearchService{db: db, geminiClient: geminiClient, qdrantClient: qdrantClient}
}

func (s *SearchService) Search(ctx context.Context, userID, query string, limit int) (*SearchResponse, error) {
	start := time.Now()
	if limit <= 0 || limit > 20 {
		limit = 10
	}
	if s.geminiClient == nil {
		return nil, fmt.Errorf("semantic search unavailable: Gemini is not configured (GEMINI_API_KEY not set)")
	}
	embResp, err := s.geminiClient.GenerateEmbedding(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to embed query: %w", err)
	}
	// SearchByUser(ctx, queryVector, userID, limit)
	hits, err := s.qdrantClient.SearchByUser(ctx, embResp.Embeddings, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("vector search failed: %w", err)
	}
	results, err := s.enrichResults(ctx, hits)
	if err != nil {
		logger.Warn("Failed to enrich search results", logger.Err(err))
	}
	return &SearchResponse{
		Query: query, Results: results, TotalFound: len(results),
		TookMs: time.Since(start).Milliseconds(),
	}, nil
}

func (s *SearchService) SearchInDocument(ctx context.Context, userID, documentID, query string, limit int) (*SearchResponse, error) {
	start := time.Now()
	if limit <= 0 || limit > 20 {
		limit = 10
	}
	var count int64
	s.db.WithContext(ctx).Table("documents").
		Where("id = ? AND user_id = ? AND deleted_at IS NULL", documentID, userID).Count(&count)
	if count == 0 {
		return nil, fmt.Errorf("document not found or access denied")
	}
	if s.geminiClient == nil {
		return nil, fmt.Errorf("semantic search unavailable: Gemini is not configured (GEMINI_API_KEY not set)")
	}
	embResp, err := s.geminiClient.GenerateEmbedding(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to embed query: %w", err)
	}
	// SearchByDocument(ctx, queryVector, documentID, limit)
	hits, err := s.qdrantClient.SearchByDocument(ctx, embResp.Embeddings, documentID, limit)
	if err != nil {
		return nil, fmt.Errorf("vector search failed: %w", err)
	}
	results, err := s.enrichResults(ctx, hits)
	if err != nil {
		logger.Warn("Failed to enrich search results", logger.Err(err))
	}
	return &SearchResponse{
		Query: query, Results: results, TotalFound: len(results),
		TookMs: time.Since(start).Milliseconds(),
	}, nil
}

func (s *SearchService) RAGQuery(ctx context.Context, userID, query string) (*RAGResponse, error) {
	if s.geminiClient == nil {
		return nil, fmt.Errorf("RAG query unavailable: Gemini is not configured (GEMINI_API_KEY not set)")
	}
	embResp, err := s.geminiClient.GenerateEmbedding(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to embed query: %w", err)
	}
	hits, err := s.qdrantClient.SearchByUser(ctx, embResp.Embeddings, userID, 5)
	if err != nil {
		return nil, fmt.Errorf("vector search failed: %w", err)
	}
	sources, err := s.enrichResults(ctx, hits)
	if err != nil {
		logger.Warn("Enrichment partial failure", logger.Err(err))
	}
	if len(sources) == 0 {
		return &RAGResponse{
			Answer:  "I couldn't find relevant information in your documents to answer this question.",
			Sources: []SearchResult{}, Model: "gemini-1.5-flash",
		}, nil
	}
	var parts []string
	for i, src := range sources {
		parts = append(parts, fmt.Sprintf("[Source %d — %s, page %d]\n%s", i+1, src.DocumentTitle, src.PageNumber, src.ChunkText))
	}
	answer, err := s.geminiClient.AnswerQuestion(ctx, strings.Join(parts, "\n\n---\n\n"), query)
	if err != nil {
		return nil, fmt.Errorf("AI answer generation failed: %w", err)
	}
	return &RAGResponse{Answer: answer.Answer, Sources: sources, Model: "gemini-1.5-flash"}, nil
}

func (s *SearchService) enrichResults(ctx context.Context, hits []qdrant.SearchResult) ([]SearchResult, error) {
	if len(hits) == 0 {
		return []SearchResult{}, nil
	}
	scoreMap := make(map[string]float64)
	qdrantIDs := make([]string, 0, len(hits))
	for _, h := range hits {
		scoreMap[h.ChunkID] = float64(h.Score)
		qdrantIDs = append(qdrantIDs, h.ChunkID)
	}
	type chunkRow struct {
		ID            string
		DocumentID    string
		ChunkText     string
		ChunkIndex    int
		PageNumber    int
		DocumentTitle string
		FileType      string
		CreatedAt     time.Time
	}
	var rows []chunkRow
	err := s.db.WithContext(ctx).Raw(`
		SELECT dc.id, dc.document_id, dc.chunk_text, dc.chunk_index, dc.page_number,
		       d.title AS document_title, d.file_type, d.created_at
		FROM document_chunks dc
		JOIN documents d ON d.id = dc.document_id
		WHERE dc.qdrant_id = ANY(?) AND d.deleted_at IS NULL
	`, qdrantIDs).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	results := make([]SearchResult, 0, len(rows))
	for _, row := range rows {
		results = append(results, SearchResult{
			DocumentID: row.DocumentID, DocumentTitle: row.DocumentTitle,
			ChunkText: row.ChunkText, Score: scoreMap[row.ID],
			PageNumber: row.PageNumber, ChunkIndex: row.ChunkIndex,
			FileType: row.FileType, UploadedAt: row.CreatedAt,
		})
	}
	for i := 0; i < len(results)-1; i++ {
		for j := i + 1; j < len(results); j++ {
			if results[j].Score > results[i].Score {
				results[i], results[j] = results[j], results[i]
			}
		}
	}
	return results, nil
}