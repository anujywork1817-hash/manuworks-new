package gemini

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"

	"github.com/yourusername/docassist/config"
	"github.com/yourusername/docassist/pkg/logger"
)

// ─── Types ────────────────────────────────────────────────────────────────────

type SummaryResponse struct {
	Summary   string   `json:"summary"`
	KeyPoints []string `json:"key_points"`
	WordCount int      `json:"word_count"`
	ReadTime  string   `json:"read_time"` // e.g. "3 min read"
}

type QAResponse struct {
	Answer     string   `json:"answer"`
	Confidence string   `json:"confidence"` // high / medium / low
	Sources    []string `json:"sources"`    // relevant excerpts used
}

type TimelineEvent struct {
	Date         string `json:"date"`
	Event        string `json:"event"`
	Significance string `json:"significance"`
}

type TimelineResponse struct {
	Events  []TimelineEvent `json:"events"`
	Summary string          `json:"summary"`
}

type TranslationResponse struct {
	TranslatedText string `json:"translated_text"`
	SourceLanguage string `json:"source_language"`
	TargetLanguage string `json:"target_language"`
}

type DocumentAnalysis struct {
	DocumentType string   `json:"document_type"` // Contract, Invoice, Report, etc.
	Parties      []string `json:"parties"`       // involved parties
	KeyDates     []string `json:"key_dates"`
	Obligations  []string `json:"obligations"`
	Risks        []string `json:"risks"`
	ActionItems  []string `json:"action_items"`
	Summary      string   `json:"summary"`
}

type ReportSection struct {
	Title   string `json:"title"`
	Content string `json:"content"`
}

type ReportResponse struct {
	Title       string          `json:"title"`
	Sections    []ReportSection `json:"sections"`
	GeneratedAt time.Time       `json:"generated_at"`
}

type EmbeddingResponse struct {
	Embeddings []float32 `json:"embeddings"`
	Dimensions int       `json:"dimensions"`
}

// ─── Rate limiter ─────────────────────────────────────────────────────────────
// Free tier: 15 requests/min. We use a token bucket approach.

type rateLimiter struct {
	mu       sync.Mutex
	tokens   int
	max      int
	interval time.Duration
	lastFill time.Time
}

func newRateLimiter(maxPerMin int) *rateLimiter {
	return &rateLimiter{
		tokens:   maxPerMin,
		max:      maxPerMin,
		interval: time.Minute,
		lastFill: time.Now(),
	}
}

func (r *rateLimiter) Wait(ctx context.Context) error {
	for {
		r.mu.Lock()
		now := time.Now()
		// Refill tokens every interval
		if now.Sub(r.lastFill) >= r.interval {
			r.tokens = r.max
			r.lastFill = now
		}
		if r.tokens > 0 {
			r.tokens--
			r.mu.Unlock()
			return nil
		}
		// Calculate wait time until next refill
		waitUntil := r.lastFill.Add(r.interval)
		r.mu.Unlock()

		waitDuration := time.Until(waitUntil)
		logger.Info("Gemini rate limit reached, waiting", logger.Str("wait", waitDuration.String()))

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(waitDuration):
			// Loop and try again
		}
	}
}

// ─── Client ───────────────────────────────────────────────────────────────────

type Client struct {
	genaiClient    *genai.Client
	flashModel     *genai.GenerativeModel // gemini-1.5-flash  — fast, cheap
	proModel       *genai.GenerativeModel // gemini-1.5-pro    — complex tasks
	embeddingModel *genai.EmbeddingModel  // text-embedding-004
	rateLimiter    *rateLimiter
	cfg            *config.GeminiConfig
}

func NewClient(ctx context.Context, cfg *config.GeminiConfig) (*Client, error) {
	client, err := genai.NewClient(ctx, option.WithAPIKey(cfg.APIKey))
	if err != nil {
		return nil, fmt.Errorf("failed to create Gemini client: %w", err)
	}

	flash := client.GenerativeModel(cfg.Model)
	flash.SetTemperature(0.3) // Low temp = more factual, less creative
	flash.SetMaxOutputTokens(int32(cfg.MaxTokensPerRequest))
	flash.SetTopP(0.8)

	pro := client.GenerativeModel(cfg.ProModel)
	pro.SetTemperature(0.2)
	pro.SetMaxOutputTokens(int32(cfg.MaxTokensPerRequest))

	embedding := client.EmbeddingModel(cfg.EmbeddingModel)

	return &Client{
		genaiClient:    client,
		flashModel:     flash,
		proModel:       pro,
		embeddingModel: embedding,
		rateLimiter:    newRateLimiter(cfg.MaxRequestsPerMin),
		cfg:            cfg,
	}, nil
}

func (c *Client) Close() {
	_ = c.genaiClient.Close()
}

// ─── 1. Summarize ─────────────────────────────────────────────────────────────

func (c *Client) Summarize(ctx context.Context, text string) (*SummaryResponse, error) {
	text = truncateText(text, 30000) // stay well under token limit

	prompt := fmt.Sprintf(`You are a professional document analyst. Analyze the following document and provide:
1. A concise executive summary (3-5 sentences)
2. 5-8 key points as a bullet list

Respond ONLY with valid JSON in this exact format:
{
  "summary": "...",
  "key_points": ["point 1", "point 2", "..."],
  "word_count": <number of words in original>,
  "read_time": "<N> min read"
}

DOCUMENT:
%s`, text)

	resp, err := c.generate(ctx, c.flashModel, prompt)
	if err != nil {
		return nil, fmt.Errorf("summarize: %w", err)
	}

	var result SummaryResponse
	if err := parseJSON(resp, &result); err != nil {
		// Fallback: return raw text as summary
		return &SummaryResponse{Summary: resp, KeyPoints: []string{}}, nil
	}
	return &result, nil
}

// ─── 2. Question Answering ────────────────────────────────────────────────────

func (c *Client) AnswerQuestion(ctx context.Context, documentText, question string) (*QAResponse, error) {
	documentText = truncateText(documentText, 28000)

	prompt := fmt.Sprintf(`You are a precise document Q&A assistant. Answer the question based ONLY on the provided document.
If the answer is not in the document, say "This information is not found in the document."

Respond ONLY with valid JSON in this exact format:
{
  "answer": "...",
  "confidence": "high|medium|low",
  "sources": ["relevant quote 1", "relevant quote 2"]
}

DOCUMENT:
%s

QUESTION: %s`, documentText, question)

	resp, err := c.generate(ctx, c.flashModel, prompt)
	if err != nil {
		return nil, fmt.Errorf("answer question: %w", err)
	}

	var result QAResponse
	if err := parseJSON(resp, &result); err != nil {
		return &QAResponse{Answer: resp, Confidence: "medium", Sources: []string{}}, nil
	}
	return &result, nil
}

// ─── 3. Key Points Extraction ─────────────────────────────────────────────────

func (c *Client) ExtractKeyPoints(ctx context.Context, text string) ([]string, error) {
	text = truncateText(text, 30000)

	prompt := fmt.Sprintf(`Extract the most important key points from the following document.
Return ONLY a JSON array of strings, no other text:
["key point 1", "key point 2", "key point 3"]

Provide 8-12 key points ordered by importance.

DOCUMENT:
%s`, text)

	resp, err := c.generate(ctx, c.flashModel, prompt)
	if err != nil {
		return nil, fmt.Errorf("extract key points: %w", err)
	}

	var points []string
	if err := parseJSON(resp, &points); err != nil {
		// Split by newlines as fallback
		lines := strings.Split(resp, "\n")
		for _, l := range lines {
			l = strings.TrimSpace(strings.TrimPrefix(l, "- "))
			if l != "" {
				points = append(points, l)
			}
		}
	}
	return points, nil
}

// ─── 4. Timeline Extraction ───────────────────────────────────────────────────

func (c *Client) ExtractTimeline(ctx context.Context, text string) (*TimelineResponse, error) {
	text = truncateText(text, 28000)

	prompt := fmt.Sprintf(`Extract a chronological timeline of events from the following document.

Respond ONLY with valid JSON in this exact format:
{
  "events": [
    {
      "date": "YYYY-MM-DD or descriptive date",
      "event": "What happened",
      "significance": "Why it matters"
    }
  ],
  "summary": "Brief overview of the timeline"
}

If no dates/events are found, return an empty events array with an appropriate summary.

DOCUMENT:
%s`, text)

	resp, err := c.generate(ctx, c.proModel, prompt)
	if err != nil {
		return nil, fmt.Errorf("extract timeline: %w", err)
	}

	var result TimelineResponse
	if err := parseJSON(resp, &result); err != nil {
		return &TimelineResponse{Events: []TimelineEvent{}, Summary: resp}, nil
	}
	return &result, nil
}

// ─── 5. Translation ───────────────────────────────────────────────────────────

func (c *Client) Translate(ctx context.Context, text, targetLanguage string) (*TranslationResponse, error) {
	text = truncateText(text, 20000) // Translation uses more tokens

	prompt := fmt.Sprintf(`Translate the following text to %s.
Preserve the original formatting and structure.

Respond ONLY with valid JSON:
{
  "translated_text": "...",
  "source_language": "detected language name",
  "target_language": "%s"
}

TEXT TO TRANSLATE:
%s`, targetLanguage, targetLanguage, text)

	resp, err := c.generate(ctx, c.flashModel, prompt)
	if err != nil {
		return nil, fmt.Errorf("translate: %w", err)
	}

	var result TranslationResponse
	if err := parseJSON(resp, &result); err != nil {
		return &TranslationResponse{
			TranslatedText: resp,
			TargetLanguage: targetLanguage,
		}, nil
	}
	return &result, nil
}

// ─── 6. Legal / Business Document Analysis ───────────────────────────────────

func (c *Client) AnalyzeDocument(ctx context.Context, text string) (*DocumentAnalysis, error) {
	text = truncateText(text, 28000)

	prompt := fmt.Sprintf(`You are a senior legal and business document analyst.
Analyze the following document and extract structured information.

Respond ONLY with valid JSON in this exact format:
{
  "document_type": "Contract|Invoice|Report|Agreement|Policy|Letter|Other",
  "parties": ["Party 1 name", "Party 2 name"],
  "key_dates": ["Date 1: purpose", "Date 2: purpose"],
  "obligations": ["Obligation 1", "Obligation 2"],
  "risks": ["Risk 1", "Risk 2"],
  "action_items": ["Action 1 - Owner - Due date", "Action 2"],
  "summary": "Executive summary of the document"
}

Use empty arrays [] if a field has no content.

DOCUMENT:
%s`, text)

	resp, err := c.generate(ctx, c.proModel, prompt)
	if err != nil {
		return nil, fmt.Errorf("analyze document: %w", err)
	}

	var result DocumentAnalysis
	if err := parseJSON(resp, &result); err != nil {
		return &DocumentAnalysis{Summary: resp}, nil
	}
	return &result, nil
}

// ─── 7. Action Items Extraction ───────────────────────────────────────────────

func (c *Client) ExtractActionItems(ctx context.Context, text string) ([]string, error) {
	text = truncateText(text, 28000)

	prompt := fmt.Sprintf(`Extract all action items, tasks, and to-dos from the following document.
Include owner and deadline if mentioned.

Return ONLY a JSON array of strings:
["Action item 1 (Owner: X, Due: Y)", "Action item 2"]

If no action items found, return an empty array: []

DOCUMENT:
%s`, text)

	resp, err := c.generate(ctx, c.flashModel, prompt)
	if err != nil {
		return nil, fmt.Errorf("extract action items: %w", err)
	}

	var items []string
	if err := parseJSON(resp, &items); err != nil {
		return []string{}, nil
	}
	return items, nil
}

// ─── 8. Generate Report ───────────────────────────────────────────────────────

func (c *Client) GenerateReport(ctx context.Context, text, reportType string) (*ReportResponse, error) {
	text = truncateText(text, 25000)

	prompt := fmt.Sprintf(`You are a professional report writer. Generate a structured %s report based on the provided document.

Respond ONLY with valid JSON in this exact format:
{
  "title": "Report Title",
  "sections": [
    {"title": "Executive Summary", "content": "..."},
    {"title": "Key Findings", "content": "..."},
    {"title": "Recommendations", "content": "..."},
    {"title": "Conclusion", "content": "..."}
  ]
}

Add additional sections as appropriate for the report type.
Each section content should be 2-4 paragraphs.

DOCUMENT:
%s`, reportType, text)

	resp, err := c.generate(ctx, c.proModel, prompt)
	if err != nil {
		return nil, fmt.Errorf("generate report: %w", err)
	}

	var result ReportResponse
	if err := parseJSON(resp, &result); err != nil {
		return &ReportResponse{
			Title:    reportType + " Report",
			Sections: []ReportSection{{Title: "Content", Content: resp}},
		}, nil
	}
	result.GeneratedAt = time.Now()
	return &result, nil
}

// ─── 9. Chat (streaming-compatible) ──────────────────────────────────────────

type ChatMessage struct {
	Role    string `json:"role"` // "user" or "model"
	Content string `json:"content"`
}

func (c *Client) Chat(ctx context.Context, documentText string, history []ChatMessage, userMessage string) (string, error) {
	// Build a chat session with document context injected as system context
	contextPrompt := fmt.Sprintf(
		"You are a helpful document assistant. Answer questions based on this document:\n\n%s\n\nBe concise and accurate. If asked something not in the document, say so.",
		truncateText(documentText, 20000),
	)

	// Build Gemini chat history
	chat := c.flashModel.StartChat()
	chat.History = []*genai.Content{
		{
			Parts: []genai.Part{genai.Text(contextPrompt)},
			Role:  "user",
		},
		{
			Parts: []genai.Part{genai.Text("Understood. I'll answer questions based on this document.")},
			Role:  "model",
		},
	}

	// Append conversation history
	for _, msg := range history {
		role := msg.Role
		if role != "user" && role != "model" {
			continue
		}
		chat.History = append(chat.History, &genai.Content{
			Parts: []genai.Part{genai.Text(msg.Content)},
			Role:  role,
		})
	}

	if err := c.rateLimiter.Wait(ctx); err != nil {
		return "", fmt.Errorf("rate limiter: %w", err)
	}

	resp, err := chat.SendMessage(ctx, genai.Text(userMessage))
	if err != nil {
		return "", fmt.Errorf("chat: %w", err)
	}

	return extractText(resp), nil
}

// ─── 10. Embeddings ───────────────────────────────────────────────────────────

func (c *Client) GenerateEmbedding(ctx context.Context, text string) (*EmbeddingResponse, error) {
	text = truncateText(text, 8000) // embedding model has lower limit

	if err := c.rateLimiter.Wait(ctx); err != nil {
		return nil, fmt.Errorf("rate limiter: %w", err)
	}

	resp, err := c.embeddingModel.EmbedContent(ctx, genai.Text(text))
	if err != nil {
		return nil, fmt.Errorf("generate embedding: %w", err)
	}

	values := resp.Embedding.Values
	return &EmbeddingResponse{
		Embeddings: values,
		Dimensions: len(values),
	}, nil
}

// GenerateEmbeddingsBatch generates embeddings for multiple texts efficiently.
// Processes in batches to stay within rate limits.
func (c *Client) GenerateEmbeddingsBatch(ctx context.Context, texts []string) ([][]float32, error) {
	results := make([][]float32, len(texts))

	for i, text := range texts {
		emb, err := c.GenerateEmbedding(ctx, text)
		if err != nil {
			return nil, fmt.Errorf("embedding batch[%d]: %w", i, err)
		}
		results[i] = emb.Embeddings

		// Small pause between batch calls to avoid bursting
		if i < len(texts)-1 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(100 * time.Millisecond):
			}
		}
	}

	return results, nil
}

// ─── Private helpers ──────────────────────────────────────────────────────────

func (c *Client) generate(ctx context.Context, model *genai.GenerativeModel, prompt string) (string, error) {
	// Apply timeout from config
	timeoutCtx, cancel := context.WithTimeout(ctx, c.cfg.RequestTimeout)
	defer cancel()

	if err := c.rateLimiter.Wait(timeoutCtx); err != nil {
		return "", fmt.Errorf("rate limiter: %w", err)
	}

	resp, err := model.GenerateContent(timeoutCtx, genai.Text(prompt))
	if err != nil {
		return "", fmt.Errorf("gemini generate: %w", err)
	}

	text := extractText(resp)
	if text == "" {
		return "", fmt.Errorf("empty response from Gemini")
	}

	logger.Info("Gemini request completed",
		logger.Str("model", "gemini-1.5-flash"),
		logger.Int("response_len", len(text)),
	)

	return text, nil
}

// extractText pulls the text content from a Gemini response.
func extractText(resp *genai.GenerateContentResponse) string {
	var sb strings.Builder
	for _, candidate := range resp.Candidates {
		if candidate.Content == nil {
			continue
		}
		for _, part := range candidate.Content.Parts {
			if txt, ok := part.(genai.Text); ok {
				sb.WriteString(string(txt))
			}
		}
	}
	return strings.TrimSpace(sb.String())
}

// parseJSON strips markdown code fences then unmarshals JSON.
// Gemini sometimes wraps JSON in ```json ... ``` blocks.
func parseJSON(raw string, target interface{}) error {
	clean := raw

	// Strip ```json ... ``` or ``` ... ``` wrappers
	if idx := strings.Index(clean, "```json"); idx >= 0 {
		clean = clean[idx+7:]
	} else if idx := strings.Index(clean, "```"); idx >= 0 {
		clean = clean[idx+3:]
	}
	if idx := strings.LastIndex(clean, "```"); idx >= 0 {
		clean = clean[:idx]
	}

	clean = strings.TrimSpace(clean)
	return json.Unmarshal([]byte(clean), target)
}

// truncateText cuts text to approximately maxChars characters at a word boundary.
// This prevents exceeding Gemini's context window.
func truncateText(text string, maxChars int) string {
	if len(text) <= maxChars {
		return text
	}
	// Find last space before limit to avoid cutting mid-word
	cut := text[:maxChars]
	if idx := strings.LastIndex(cut, " "); idx > maxChars-200 {
		cut = cut[:idx]
	}
	return cut + "\n\n[Document truncated for processing...]"
}




