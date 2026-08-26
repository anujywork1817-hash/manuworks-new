package groq

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"

	"github.com/yourusername/docassist/pkg/logger"
)

const (
	baseURL            = "https://api.groq.com/openai/v1/chat/completions"
	defaultModel       = "llama-3.1-8b-instant" // 500K TPD vs 100K for 70b-versatile
	defaultClaudeModel = "claude-opus-5"
	defaultTimeout     = 60 * time.Second

	// indiaDocEngRule is appended to every document-analysis system prompt so
	// the model always replies in English even when the source document is
	// written in Marathi, Hindi, or another Indian regional language.
	indiaDocEngRule = " The document may be in any Indian language (Marathi, Hindi, etc.) — always respond ENTIRELY IN ENGLISH."
)

// groqKeySlot tracks one Groq API key and its daily-limit cooldown.
type groqKeySlot struct {
	key           string
	cooldownUntil time.Time
}

// Client talks to Claude (primary) and Groq (secondary/fallback). Every
// public method tries Claude first; if Claude is unset, rate-limited, or
// out of quota, it transparently falls back to Groq until Claude's limit
// is expected to have reset.
//
// Multiple Groq keys are supported. When one key exhausts its daily token
// quota it is marked cooling-down and the next key is used automatically —
// so one key hitting its daily limit does NOT block every user in the app.
type Client struct {
	groqKeys   []groqKeySlot // All Groq API keys; first is primary
	model      string
	httpClient *http.Client

	claudeClient *anthropic.Client
	claudeModel  string
	claudeOn     bool

	mu                  sync.Mutex
	claudeCooldownUntil time.Time
}

// Config holds Groq + Claude configuration
type Config struct {
	APIKey  string   // Primary Groq API key
	APIKeys []string // Additional Groq keys for rotation (GROQ_API_KEY_2 … _5)
	Model   string
	Timeout time.Duration

	ClaudeAPIKey string
	ClaudeModel  string
}

// --- Request/Response types ---

type message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatRequest struct {
	Model       string    `json:"model"`
	Messages    []message `json:"messages"`
	MaxTokens   int       `json:"max_tokens"`
	Temperature float64   `json:"temperature"`
}

type chatResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
		Code    string `json:"code,omitempty"`
	} `json:"error,omitempty"`
}

// --- Output types ---

type SummaryResponse struct {
	Summary   string   `json:"summary"`
	KeyPoints []string `json:"key_points"`
	WordCount int      `json:"word_count"`
}

type KeyPointsResponse struct {
	KeyPoints []string `json:"key_points"`
	Category  string   `json:"category"`
}

type TimelineResponse struct {
	Events []TimelineEvent `json:"events"`
}

type TimelineEvent struct {
	Date         string `json:"date"`
	Event        string `json:"event"`
	Significance string `json:"significance"`
}

type ActionItemsResponse struct {
	ActionItems []ActionItem `json:"action_items"`
}

type ActionItem struct {
	Action   string `json:"action"`
	Priority string `json:"priority"`
	Deadline string `json:"deadline"`
	Owner    string `json:"owner"`
}

type AnalysisResponse struct {
	DocumentType string            `json:"document_type"`
	Sentiment    string            `json:"sentiment"`
	RiskLevel    string            `json:"risk_level"`
	Insights     []string          `json:"insights"`
	Metadata     map[string]string `json:"metadata"`
}

type TranslationResponse struct {
	TranslatedText string `json:"translated_text"`
	SourceLanguage string `json:"source_language"`
	TargetLanguage string `json:"target_language"`
}

type QAResponse struct {
	Answer     string   `json:"answer"`
	Confidence string   `json:"confidence"`
	Sources    []string `json:"sources"`
}

type ReportResponse struct {
	Title   string `json:"title"`
	Content string `json:"content"`
	Format  string `json:"format"`
}

type ChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// --- Constructor ---

func NewClient(cfg *Config) *Client {
	model := cfg.Model
	if model == "" {
		model = defaultModel
	}
	claudeModel := cfg.ClaudeModel
	if claudeModel == "" {
		claudeModel = defaultClaudeModel
	}
	timeout := cfg.Timeout
	if timeout == 0 {
		timeout = defaultTimeout
	}
	// Build key pool: primary key first, then extras. Skip blank entries.
	var slots []groqKeySlot
	if cfg.APIKey != "" {
		slots = append(slots, groqKeySlot{key: cfg.APIKey})
	}
	for _, k := range cfg.APIKeys {
		if k != "" {
			slots = append(slots, groqKeySlot{key: k})
		}
	}
	// Force IPv4 to avoid IPv6 connectivity issues on networks where
	// IPv6 routing to Groq's CDN (Cloudflare) is broken.
	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, addr string) (net.Conn, error) {
			return (&net.Dialer{Timeout: 30 * time.Second, KeepAlive: 30 * time.Second}).DialContext(ctx, "tcp4", addr)
		},
	}
	var claudeClient *anthropic.Client
	if cfg.ClaudeAPIKey != "" {
		cc := anthropic.NewClient(option.WithAPIKey(cfg.ClaudeAPIKey))
		claudeClient = &cc
	}

	return &Client{
		groqKeys:     slots,
		model:        model,
		claudeClient: claudeClient,
		claudeModel:  claudeModel,
		claudeOn:     cfg.ClaudeAPIKey != "",
		httpClient:   &http.Client{Timeout: timeout, Transport: transport},
	}
}

// activeGroqKey returns the first Groq key that is not in a daily-limit
// cooldown, and its index. Returns "", -1 if all keys are exhausted.
func (c *Client) activeGroqKey() (string, int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := time.Now()
	for i, slot := range c.groqKeys {
		if now.After(slot.cooldownUntil) {
			return slot.key, i
		}
	}
	return "", -1
}

// cooldownGroqKey marks key at index i as exhausted until `until`.
func (c *Client) cooldownGroqKey(i int, until time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if i >= 0 && i < len(c.groqKeys) {
		c.groqKeys[i].cooldownUntil = until
	}
}

// claudeAvailable reports whether Claude is configured and not currently
// in a rate-limit cooldown.
func (c *Client) claudeAvailable() bool {
	if !c.claudeOn {
		return false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return time.Now().After(c.claudeCooldownUntil)
}

// setClaudeCooldown skips Claude for the given duration, e.g. after it
// returns a rate-limit/quota error, so subsequent calls go straight to
// Groq instead of failing against Claude first every time.
func (c *Client) setClaudeCooldown(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.claudeCooldownUntil = time.Now().Add(d)
}

// parseRetryAfter parses "try again in 33m14.976s" or "try again in 1.5s".
var retryAfterMinRe = regexp.MustCompile(`try again in (\d+)m([0-9.]+)s`)
var retryAfterSecRe = regexp.MustCompile(`try again in ([0-9.]+)s`)

func parseRetryAfter(msg string) time.Duration {
	if m := retryAfterMinRe.FindStringSubmatch(msg); len(m) == 3 {
		mins, _ := strconv.ParseFloat(m[1], 64)
		secs, _ := strconv.ParseFloat(m[2], 64)
		return time.Duration((mins*60+secs)*1000) * time.Millisecond
	}
	if m := retryAfterSecRe.FindStringSubmatch(msg); len(m) == 2 {
		if secs, err := strconv.ParseFloat(m[1], 64); err == nil {
			return time.Duration(secs*1000) * time.Millisecond
		}
	}
	return 5 * time.Second
}

func formatWait(d time.Duration) string {
	if d >= time.Hour {
		return fmt.Sprintf("%.0f hour(s)", d.Hours())
	}
	if d >= time.Minute {
		return fmt.Sprintf("%.0f minute(s)", d.Minutes())
	}
	return fmt.Sprintf("%.0f second(s)", d.Seconds())
}

// --- Core API call ---

// generate tries Claude (primary) first, then falls back to Groq
// (secondary) if Claude is unset, rate-limited, or out of quota.
func (c *Client) generate(ctx context.Context, systemPrompt, userPrompt string, maxTokens int) (string, error) {
	msgs := []message{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	if c.claudeAvailable() {
		result, retryAfter, err := c.doClaudeRequest(ctx, systemPrompt, msgs, maxTokens)
		if err == nil {
			logger.Debug("AI request served by Claude")
			return result, nil
		}
		if retryAfter > 0 {
			c.setClaudeCooldown(retryAfter)
			logger.Warn("Claude rate-limited, switching to Groq until it resets",
				logger.Err(err), logger.Str("resume_at", time.Now().Add(retryAfter).Format(time.RFC3339)))
		} else {
			logger.Warn("Claude request failed, falling back to Groq for this request", logger.Err(err))
		}
		// Fall through to Groq for this request.
	}

	return c.generateGroq(ctx, msgs, maxTokens)
}

// generateGroq calls Groq with retry/backoff and automatic key rotation.
// When a key hits its daily token quota it is marked cooling-down and the
// next available key is tried — so a single exhausted key does NOT surface
// "Daily AI limit" to every user in the app.
func (c *Client) generateGroq(ctx context.Context, msgs []message, maxTokens int) (string, error) {
	const maxRetries = 2

	for attempt := 0; attempt <= maxRetries; attempt++ {
		key, idx := c.activeGroqKey()
		if key == "" {
			return "", fmt.Errorf("AI service is temporarily unavailable (all API keys have reached their daily quota). Please try again in a few hours.")
		}

		result, retryAfter, err := c.doRequest(ctx, baseURL, key, c.model, msgs, maxTokens, 0.3)
		if err == nil {
			return result, nil
		}

		if retryAfter > 0 {
			if retryAfter > 2*time.Minute {
				// Daily token quota on this key — cool it down and try the next key.
				c.cooldownGroqKey(idx, time.Now().Add(retryAfter))
				logger.Warn("Groq key daily limit hit, rotating to next key",
					logger.Int("key_index", idx),
					logger.Str("retry_in", formatWait(retryAfter)),
				)
				// Don't increment attempt — immediately retry with the next key.
				continue
			}
			if attempt < maxRetries {
				// Short rate-limit (per-minute): wait and retry same key.
				select {
				case <-ctx.Done():
					return "", ctx.Err()
				case <-time.After(retryAfter):
					continue
				}
			}
		}
		return "", err
	}
	return "", fmt.Errorf("AI service is busy, please try again in a moment.")
}

// doClaudeRequest performs a single Messages API call against Claude via the
// official Anthropic SDK. systemPrompt is sent as the top-level system
// field; msgs[1:] (skipping the leading system-role entry callers build for
// the Groq/OpenAI-style message list) becomes the conversation turns. The
// returned duration is non-zero only when Claude signalled a rate limit,
// so callers know how long to skip Claude and use Groq instead.
func (c *Client) doClaudeRequest(ctx context.Context, systemPrompt string, msgs []message, maxTokens int) (string, time.Duration, error) {
	var turns []anthropic.MessageParam
	for _, m := range msgs {
		if m.Role == "system" {
			continue
		}
		block := anthropic.NewTextBlock(m.Content)
		if m.Role == "assistant" {
			turns = append(turns, anthropic.NewAssistantMessage(block))
		} else {
			turns = append(turns, anthropic.NewUserMessage(block))
		}
	}

	resp, err := c.claudeClient.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     anthropic.Model(c.claudeModel),
		MaxTokens: int64(maxTokens),
		System:    []anthropic.TextBlockParam{{Text: systemPrompt}},
		Messages:  turns,
	})
	if err != nil {
		var apiErr *anthropic.Error
		if errors.As(err, &apiErr) && apiErr.StatusCode == 429 {
			return "", 60 * time.Second, fmt.Errorf("claude rate limit: %w", err)
		}
		return "", 0, fmt.Errorf("claude request: %w", err)
	}

	var text strings.Builder
	for _, block := range resp.Content {
		if tb, ok := block.AsAny().(anthropic.TextBlock); ok {
			text.WriteString(tb.Text)
		}
	}
	if text.Len() == 0 {
		return "", 0, fmt.Errorf("claude: empty response")
	}
	return text.String(), 0, nil
}

// doRequest performs a single chat-completion call against the given
// provider endpoint (Groq). The returned duration is non-zero only when the
// provider signalled a rate limit (HTTP 429), so callers know how long to
// back off before retrying.
func (c *Client) doRequest(ctx context.Context, url, apiKey, model string, msgs []message, maxTokens int, temperature float64) (string, time.Duration, error) {
	reqBody := chatRequest{
		Model:       model,
		Messages:    msgs,
		MaxTokens:   maxTokens,
		Temperature: temperature,
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return "", 0, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
	if err != nil {
		return "", 0, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", 0, fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", 0, fmt.Errorf("read response: %w", err)
	}

	var chatResp chatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return "", 0, fmt.Errorf("unmarshal response: %w", err)
	}

	if chatResp.Error != nil {
		msg := chatResp.Error.Message
		if resp.StatusCode == 429 {
			wait := parseRetryAfter(msg)
			// Hard billing/quota limit — no "try again in Xs" hint in the
			// message, so don't hammer it; recheck again in an hour.
			if chatResp.Error.Code == "insufficient_quota" {
				wait = time.Hour
			}
			return "", wait, fmt.Errorf("rate limit: %s", msg)
		}
		return "", 0, fmt.Errorf("api error: %s", msg)
	}

	if len(chatResp.Choices) == 0 {
		return "", 0, fmt.Errorf("empty response")
	}

	return chatResp.Choices[0].Message.Content, 0, nil
}

// chatCompletion is like generate but for callers that build their own
// full message list (Chat, HelpChat) instead of a single system+user pair.
// Same Claude-first, Groq-fallback behavior, single attempt on each side.
func (c *Client) chatCompletion(ctx context.Context, msgs []message, maxTokens int, temperature float64) (string, error) {
	if c.claudeAvailable() {
		systemPrompt := ""
		if len(msgs) > 0 && msgs[0].Role == "system" {
			systemPrompt = msgs[0].Content
		}
		result, retryAfter, err := c.doClaudeRequest(ctx, systemPrompt, msgs, maxTokens)
		if err == nil {
			logger.Debug("AI request served by Claude")
			return result, nil
		}
		if retryAfter > 0 {
			c.setClaudeCooldown(retryAfter)
			logger.Warn("Claude rate-limited, switching to Groq until it resets",
				logger.Err(err), logger.Str("resume_at", time.Now().Add(retryAfter).Format(time.RFC3339)))
		} else {
			logger.Warn("Claude request failed, falling back to Groq for this request", logger.Err(err))
		}
	}
	key, _ := c.activeGroqKey()
	if key == "" && len(c.groqKeys) > 0 {
		key = c.groqKeys[0].key // last resort: use first key even if cooled down
	}
	result, _, err := c.doRequest(ctx, baseURL, key, c.model, msgs, maxTokens, temperature)
	return result, err
}

// parseJSON extracts JSON from response, handling markdown code blocks
func parseJSON(text string) string {
	start := -1
	for i := 0; i < len(text); i++ {
		if text[i] == '{' || text[i] == '[' {
			start = i
			break
		}
	}
	end := -1
	for i := len(text) - 1; i >= 0; i-- {
		if text[i] == '}' || text[i] == ']' {
			end = i
			break
		}
	}
	if start >= 0 && end > start {
		return text[start : end+1]
	}
	return text
}

// --- AI Methods ---

func (c *Client) Summarize(ctx context.Context, text string) (*SummaryResponse, error) {
	system := `You are a document analysis assistant. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
	prompt := fmt.Sprintf(`Summarize this document and extract key points. Respond ONLY with this JSON:
{"summary":"<2-3 sentence summary>","key_points":["point1","point2","point3"],"word_count":%d}

Document:
%s`, len(text)/5, text)

	raw, err := c.generate(ctx, system, prompt, 1000)
	if err != nil {
		return nil, fmt.Errorf("summarize: %w", err)
	}

	var result SummaryResponse
	if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
		return &SummaryResponse{Summary: raw, KeyPoints: []string{}, WordCount: len(text) / 5}, nil
	}
	return &result, nil
}

func (c *Client) ExtractKeyPoints(ctx context.Context, text string) (*KeyPointsResponse, error) {
	system := `You are a document analysis assistant. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
	prompt := fmt.Sprintf(`Extract the key points from this document. Respond ONLY with this JSON:
{"key_points":["point1","point2","point3","point4","point5"],"category":"<document category>"}

Document:
%s`, text)

	raw, err := c.generate(ctx, system, prompt, 800)
	if err != nil {
		return nil, fmt.Errorf("key points: %w", err)
	}

	var result KeyPointsResponse
	if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
		return &KeyPointsResponse{KeyPoints: []string{raw}, Category: "General"}, nil
	}
	return &result, nil
}

func (c *Client) ExtractTimeline(ctx context.Context, text string) (*TimelineResponse, error) {
	system := `You are a document analysis assistant. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
	prompt := fmt.Sprintf(`Extract all dates and timeline events from this document.
Sort events STRICTLY in chronological order from the earliest date to the latest date.
Use the most specific date format available (e.g. "15 March 1996", "June 2003", "2019").
Respond ONLY with this JSON:
{"events":[{"date":"<specific date>","event":"<what happened>","significance":"<why it matters>"}]}
If no dates found, return {"events":[{"date":"Not specified","event":"No timeline events found","significance":""}]}

Document:
%s`, text)

	raw, err := c.generate(ctx, system, prompt, 1200)
	if err != nil {
		return nil, fmt.Errorf("timeline: %w", err)
	}

	var result TimelineResponse
	if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
		return &TimelineResponse{Events: []TimelineEvent{}}, nil
	}

	sortTimelineEvents(result.Events)
	return &result, nil
}

// sortTimelineEvents sorts events chronologically by parsing the year from date strings.
func sortTimelineEvents(events []TimelineEvent) {
	extractYear := func(date string) int {
		// find a 4-digit year anywhere in the string
		for i := 0; i <= len(date)-4; i++ {
			y := 0
			valid := true
			for j := 0; j < 4; j++ {
				c := date[i+j]
				if c < '0' || c > '9' {
					valid = false
					break
				}
				y = y*10 + int(c-'0')
			}
			if valid && y >= 1000 && y <= 2100 {
				return y
			}
		}
		return 9999 // undated events go last
	}

	monthOrder := map[string]int{
		"jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
		"jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
	}
	extractMonth := func(date string) int {
		lower := strings.ToLower(date)
		for abbr, num := range monthOrder {
			if strings.Contains(lower, abbr) {
				return num
			}
		}
		return 0
	}

	// stable sort: year first, then month
	for i := 1; i < len(events); i++ {
		for j := i; j > 0; j-- {
			yi, yj := extractYear(events[j].Date), extractYear(events[j-1].Date)
			if yi < yj || (yi == yj && extractMonth(events[j].Date) < extractMonth(events[j-1].Date)) {
				events[j], events[j-1] = events[j-1], events[j]
			} else {
				break
			}
		}
	}
}

func (c *Client) ExtractActionItems(ctx context.Context, text string) (*ActionItemsResponse, error) {
	system := `You are a document analysis assistant. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
	prompt := fmt.Sprintf(`Extract all action items and tasks from this document. Respond ONLY with this JSON:
{"action_items":[{"action":"<task>","priority":"high/medium/low","deadline":"<deadline or Not specified>","owner":"<owner or Not specified>"}]}

Document:
%s`, text)

	raw, err := c.generate(ctx, system, prompt, 800)
	if err != nil {
		return nil, fmt.Errorf("action items: %w", err)
	}

	var result ActionItemsResponse
	if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
		return &ActionItemsResponse{ActionItems: []ActionItem{}}, nil
	}
	return &result, nil
}

func (c *Client) AnalyzeDocument(ctx context.Context, text string) (*AnalysisResponse, error) {
	system := `You are a document analysis assistant. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
	prompt := fmt.Sprintf(`Analyze this document. Respond ONLY with this JSON:
{"document_type":"<type>","sentiment":"positive/negative/neutral","risk_level":"low/medium/high","insights":["insight1","insight2","insight3"],"metadata":{"language":"English"}}

Document:
%s`, text)

	raw, err := c.generate(ctx, system, prompt, 1000)
	if err != nil {
		return nil, fmt.Errorf("analyze: %w", err)
	}

	var result AnalysisResponse
	if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
		return &AnalysisResponse{DocumentType: "Unknown", Sentiment: "neutral", RiskLevel: "low", Insights: []string{raw}, Metadata: map[string]string{}}, nil
	}
	return &result, nil
}

// TranslateDocument returns the document translated to targetLanguage.
// Plain-text prompt (no JSON wrapping) — JSON wrapping was unreliable for
// long documents because the model would truncate mid-JSON and break parsing.
func (c *Client) TranslateDocument(ctx context.Context, text, targetLanguage string) (*TranslationResponse, error) {
	system := "You are a professional translator. Respond with ONLY the translated text. No JSON, no preamble, no explanations, no quotation marks around the output."
	prompt := "Translate the following document into " + targetLanguage + ".\n\nDocument:\n" + text

	raw, err := c.generate(ctx, system, prompt, 7000)
	if err != nil {
		return nil, fmt.Errorf("translate: %w", err)
	}

	cleaned := strings.TrimSpace(raw)
	if len(cleaned) > 1 && cleaned[0] == '"' && cleaned[len(cleaned)-1] == '"' {
		cleaned = cleaned[1 : len(cleaned)-1]
	}

	return &TranslationResponse{
		TranslatedText: cleaned,
		SourceLanguage: "auto",
		TargetLanguage: targetLanguage,
	}, nil
}

func (c *Client) Translate(ctx context.Context, text, targetLanguage string) (*TranslationResponse, error) {
	return c.TranslateDocument(ctx, text, targetLanguage)
}

func (c *Client) AnswerQuestion(ctx context.Context, text, question string) (*QAResponse, error) {
	system := `You are a document Q&A assistant. Answer based only on the provided document. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
	prompt := fmt.Sprintf(`Answer this question based on the document. Respond ONLY with this JSON:
{"answer":"<detailed answer>","confidence":"high/medium/low","sources":["<relevant quote>"]}

Question: %s

Document:
%s`, question, text)

	raw, err := c.generate(ctx, system, prompt, 1000)
	if err != nil {
		return nil, fmt.Errorf("answer question: %w", err)
	}

	var result QAResponse
	if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
		return &QAResponse{Answer: raw, Confidence: "medium", Sources: []string{}}, nil
	}
	return &result, nil
}

func (c *Client) GenerateReport(ctx context.Context, text, reportType string) (*ReportResponse, error) {
	system := `You are a professional report writer. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
	prompt := fmt.Sprintf(`Generate a %s report for this document. Respond ONLY with this JSON:
{"title":"<report title>","content":"<full report>","format":"%s"}

Document:
%s`, reportType, reportType, text)

	raw, err := c.generate(ctx, system, prompt, 2000)
	if err != nil {
		return nil, fmt.Errorf("generate report: %w", err)
	}

	var result ReportResponse
	if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
		return &ReportResponse{Title: reportType + " Report", Content: raw, Format: reportType}, nil
	}
	return &result, nil
}

// Chat answers a freeform question about the document, optionally using
// prior conversation history for context.
func (c *Client) Chat(ctx context.Context, text string, history []ChatMessage, userMessage string) (string, error) {
	msgs := []message{{Role: "system", Content: "You are a document assistant. Answer questions based on this document." + indiaDocEngRule + "\n\n" + text}}
	for _, h := range history {
		msgs = append(msgs, message{Role: h.Role, Content: h.Content})
	}
	msgs = append(msgs, message{Role: "user", Content: userMessage})

	return c.chatCompletion(ctx, msgs, 1000, 0.3)
}

type DraftResponse struct {
    Title   string `json:"title"`
    Content string `json:"content"`
}

type CitationsResponse struct {
    Cases    []string `json:"cases"`
    Sections []string `json:"sections"`
    Acts     []string `json:"acts"`
    Articles []string `json:"articles"`
    Rules    []string `json:"rules"`
}

type Deadline struct {
    Title      string `json:"title"`
    Date       string `json:"date"`
    DaysLeft   string `json:"days_left"`
    Party      string `json:"party"`
    Obligation string `json:"obligation"`
    Priority   string `json:"priority"`
}

type DeadlineResponse struct {
    Deadlines []Deadline `json:"deadlines"`
}

type LegalDraftRequest struct {
    DocumentType    string `json:"document_type"`
    CourtName       string `json:"court_name"`
    PetitionerName  string `json:"petitioner_name"`
    RespondentName  string `json:"respondent_name"`
    CaseNumber      string `json:"case_number"`
    Subject         string `json:"subject"`
    Facts           string `json:"facts"`
    ReliefSought    string `json:"relief_sought"`
    ActsAndSections string `json:"acts_and_sections"`
    AdditionalInfo  string `json:"additional_info"`
}

type LegalDraftResponse struct {
    Title   string `json:"title"`
    Content string `json:"content"`
    DocType string `json:"doc_type"`
}

type GrammarIssue struct {
    Type        string `json:"type"`
    Original    string `json:"original"`
    Correction  string `json:"correction"`
    Explanation string `json:"explanation"`
}

type GrammarCheckResponse struct {
    Score      int            `json:"score"`
    IssueCount int            `json:"issue_count"`
    Issues     []GrammarIssue `json:"issues"`
    Summary    string         `json:"summary"`
}

type AutoTagsResponse struct {
    Tags         []string `json:"tags"`
    PracticeArea string   `json:"practice_area"`
    DocumentType string   `json:"document_type"`
    Complexity   string   `json:"complexity"`
}

type RiskClause struct {
    Title          string `json:"title"`
    RiskLevel      string `json:"risk_level"`
    ClauseText     string `json:"clause_text"`
    Concern        string `json:"concern"`
    Recommendation string `json:"recommendation"`
}

type RiskScanResponse struct {
    OverallRisk string       `json:"overall_risk"`
    Clauses     []RiskClause `json:"clauses"`
}

// DraftDocument generates a new legal/business document from a description.
func (c *Client) DraftDocument(ctx context.Context, docType, details string) (*DraftResponse, error) {
    system := "You are an expert legal and business document drafter. Draft professional, properly formatted documents following standard conventions for the requested document type. Respond with ONLY the document content. No JSON, no preamble, no markdown formatting symbols like ** or ##, just plain formatted text as it would appear in the final document."
    prompt := "Draft a " + docType + " with the following details:\n\n" + details + "\n\nWrite the complete, ready-to-use document now."

    raw, err := c.generate(ctx, system, prompt, 4000)
    if err != nil {
        return nil, fmt.Errorf("draft document: %w", err)
    }

    return &DraftResponse{
        Title:   docType,
        Content: strings.TrimSpace(raw),
    }, nil
}

func (c *Client) DraftLegalDocument(ctx context.Context, req LegalDraftRequest) (*LegalDraftResponse, error) {
    system := "You are a senior Indian advocate with 20 years of experience drafting court documents. Draft professional, complete, properly formatted Indian legal documents. Output ONLY the document text — no JSON, no markdown symbols like ** or ##, no preamble."

    caseRef := ""
    if req.CaseNumber != "" {
        caseRef = "\nCase/Application No.: " + req.CaseNumber
    }
    acts := ""
    if req.ActsAndSections != "" {
        acts = "\nRelevant Acts/Sections: " + req.ActsAndSections
    }
    extra := ""
    if req.AdditionalInfo != "" {
        extra = "\nAdditional Details: " + req.AdditionalInfo
    }

    prompt := fmt.Sprintf(`Draft a complete, ready-to-file %s for Indian court following all legal conventions.

DETAILS:
Court: %s%s
Petitioner/Applicant: %s
Respondent/Opposite Party: %s
Subject Matter: %s
Facts: %s
Relief/Prayer Sought: %s%s%s

FORMATTING RULES:
- Proper court heading: IN THE [COURT NAME]
- Correct case title with VERSUS and ... after party names
- All paragraphs numbered sequentially
- Formal language: "Most Respectfully Sheweth", "It is therefore prayed", "Your Lordship/Honour"
- For petitions/applications: include Facts, Legal Grounds, Prayer sections
- For plaints: include Cause of Action, Jurisdiction, Valuation, Relief
- For replies/written statements: Preliminary Objections, then Para-wise Reply
- For notices: subject line, demand, consequence of non-compliance, time limit
- For affidavits: numbered paragraphs, Deponent details, Verification clause
- For bail applications: grounds, antecedents, surety offer
- End with proper signature block: Date, Place, Advocate for [party]
- Include VERIFICATION/AFFIDAVIT if required for this document type
- Write the complete document, do not truncate or abbreviate

Write the full document now:`, req.DocumentType, req.CourtName, caseRef, req.PetitionerName, req.RespondentName, req.Subject, req.Facts, req.ReliefSought, acts, extra)

    raw, err := c.generate(ctx, system, prompt, 4000)
    if err != nil {
        return nil, fmt.Errorf("draft legal document: %w", err)
    }

    title := req.DocumentType
    if req.PetitionerName != "" && req.RespondentName != "" {
        title = req.DocumentType + " — " + req.PetitionerName + " vs " + req.RespondentName
    }

    return &LegalDraftResponse{
        Title:   title,
        Content: strings.TrimSpace(raw),
        DocType: req.DocumentType,
    }, nil
}

func (c *Client) CheckGrammar(ctx context.Context, text string) (*GrammarCheckResponse, error) {
    system := `You are a professional English language editor specializing in legal documents. Identify grammatical errors precisely. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
    prompt := fmt.Sprintf(`Check this legal document for grammatical errors and language mistakes.
Respond ONLY with this exact JSON:
{"score":<0-100>,"issue_count":<number>,"issues":[{"type":"<category>","original":"<exact wrong text from document>","correction":"<corrected text>","explanation":"<brief reason>"}],"summary":"<1-2 sentence overall assessment>"}

Rules:
- score: 100 = perfect grammar, 0 = very poor
- type must be one of: grammar, spelling, punctuation, tense, subject-verb, article, preposition, sentence-structure
- original: copy the exact incorrect phrase/sentence from the document (keep it short, max 15 words)
- correction: the corrected version of that phrase
- explanation: short reason (max 10 words)
- DO NOT flag: Latin legal terms (prima facie, ex parte, inter alia, etc.), Indian legal terminology, proper nouns, deliberate formal/archaic legal phrasing ("hereinafter", "whereas", "aforesaid")
- List up to 15 most important errors only
- If no errors found: {"score":100,"issue_count":0,"issues":[],"summary":"The document is grammatically correct."}

Document:
%s`, text)

    raw, err := c.generate(ctx, system, prompt, 2000)
    if err != nil {
        return nil, fmt.Errorf("grammar check: %w", err)
    }

    var result GrammarCheckResponse
    if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
        return &GrammarCheckResponse{Score: 0, IssueCount: 0, Issues: []GrammarIssue{}, Summary: "Could not parse grammar results."}, nil
    }
    if result.Issues == nil {
        result.Issues = []GrammarIssue{}
    }
    result.IssueCount = len(result.Issues)
    return &result, nil
}

func (c *Client) AutoTag(ctx context.Context, text string) (*AutoTagsResponse, error) {
    system := `You are an Indian legal document classification expert. Generate precise tags for legal documents. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
    prompt := fmt.Sprintf(`Analyze this legal document and generate classification tags.
Respond ONLY with this exact JSON:
{"tags":["tag1","tag2","tag3"],"practice_area":"<primary area of law>","document_type":"<type>","complexity":"simple/moderate/complex"}

Tag guidelines (pick 5-12 most relevant):
- Document type: Contract, Agreement, Petition, Affidavit, Notice, Order, Judgment, Deed, MOU, NDA, FIR, Complaint, Will, Lease
- Area of law: Criminal Law, Civil Law, Labour Law, Corporate Law, Property Law, Family Law, Constitutional Law, Tax Law, IP Law, Consumer Law
- Specific acts: IPC, CPC, CrPC, Companies Act, IT Act, GST, Income Tax, Arbitration Act, POCSO, Prevention of Corruption
- Court/forum: Supreme Court, High Court, District Court, NCLT, NCLAT, Consumer Forum, Labour Court, NGT, CAT
- Parties: Government, Individual, Company, Partnership Firm, LLP, Trust, NGO
- Key features: Arbitration Clause, Penalty Clause, Non-Compete, Bail Application, Injunction, Stay Order, Anticipatory Bail

practice_area: single primary legal domain
document_type: single most accurate document type
complexity: simple (routine/standard), moderate (some complexity), complex (multi-party/novel issues)

Document:
%s`, text)

    raw, err := c.generate(ctx, system, prompt, 600)
    if err != nil {
        return nil, fmt.Errorf("auto-tag: %w", err)
    }

    var result AutoTagsResponse
    if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
        return &AutoTagsResponse{Tags: []string{}, PracticeArea: "General", DocumentType: "Document", Complexity: "moderate"}, nil
    }
    if result.Tags == nil {
        result.Tags = []string{}
    }
    return &result, nil
}

func (c *Client) ExtractDeadlines(ctx context.Context, text string) (*DeadlineResponse, error) {
    system := `You are a legal deadline tracking expert specializing in Indian law. Extract all time-bound obligations and deadlines. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
    prompt := fmt.Sprintf(`Extract all deadlines, due dates, time limits, and time-bound obligations from this legal document.
Respond ONLY with this exact JSON:
{"deadlines":[{"title":"<short name>","date":"<specific date or period like '30 days from signing'>","days_left":"<calculated days or 'See document'>","party":"<who is responsible>","obligation":"<what must be done>","priority":"high/medium/low"}]}

Include:
- Payment due dates and installment schedules
- Notice periods (termination, breach, renewal)
- Limitation periods for filing suits/appeals under Limitation Act 1963
- Statutory deadlines (filing returns, registrations)
- Performance milestones and delivery dates
- Response/reply deadlines
- Renewal / expiry dates
- Cure periods after breach

Priority: high=legal consequence or financial penalty if missed, medium=contractual obligation, low=procedural
Return {"deadlines":[]} if no time-bound obligations found.

Document:
%s`, text)

    raw, err := c.generate(ctx, system, prompt, 1500)
    if err != nil {
        return nil, fmt.Errorf("deadlines: %w", err)
    }

    var result DeadlineResponse
    if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
        return &DeadlineResponse{Deadlines: []Deadline{}}, nil
    }
    if result.Deadlines == nil {
        result.Deadlines = []Deadline{}
    }
    return &result, nil
}

func (c *Client) ScanRisks(ctx context.Context, text string) (*RiskScanResponse, error) {
    system := `You are a senior Indian contract lawyer. Identify risky clauses in legal documents. Always respond with valid JSON only, no markdown, no explanation.` + indiaDocEngRule
    prompt := fmt.Sprintf(`Analyze this legal document for risky or unfavorable clauses under Indian law.
Respond ONLY with this exact JSON:
{"overall_risk":"high/medium/low","clauses":[{"title":"<clause name>","risk_level":"high/medium/low","clause_text":"<verbatim or paraphrased clause>","concern":"<why it is risky>","recommendation":"<what to do>"}]}

Risk levels:
- high: one-sided, unenforceable, illegal under Indian law, or causes serious financial/legal exposure
- medium: ambiguous, lacks protection, or common but unfavorable
- low: minor concern, standard but worth noting

Focus on: penalty clauses, indemnity, IP ownership, termination rights, jurisdiction, non-compete, arbitration, liability caps, payment terms, force majeure.
List up to 8 most important risks. Return {"overall_risk":"low","clauses":[]} if no significant risks found.

Document:
%s`, text)

    raw, err := c.generate(ctx, system, prompt, 1800)
    if err != nil {
        return nil, fmt.Errorf("risk scan: %w", err)
    }

    var result RiskScanResponse
    if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
        return &RiskScanResponse{OverallRisk: "unknown", Clauses: []RiskClause{}}, nil
    }
    if result.Clauses == nil {
        result.Clauses = []RiskClause{}
    }
    return &result, nil
}

// ─── Document Comparison ─────────────────────────────────────────────────────

type DiffItem struct {
	Category string `json:"category"`
	DocA     string `json:"doc_a"`
	DocB     string `json:"doc_b"`
	Change   string `json:"change"` // added | removed | modified | same
}

type CompareResponse struct {
	Summary      string     `json:"summary"`
	TotalChanges int        `json:"total_changes"`
	Differences  []DiffItem `json:"differences"`
	Verdict      string     `json:"verdict"`
}

func (c *Client) CompareDocuments(ctx context.Context, text1, text2 string) (*CompareResponse, error) {
	system := `You are a senior Indian legal document analyst. Compare two legal documents and identify all meaningful differences. Always respond with valid JSON only, no markdown.` + indiaDocEngRule
	prompt := fmt.Sprintf(`Compare these two legal documents and identify all meaningful differences.
Respond ONLY with this exact JSON:
{"summary":"<2-3 sentence overview of the main differences>","total_changes":<number>,"differences":[{"category":"<clause/section name>","doc_a":"<what Document A says, or 'Not present'>","doc_b":"<what Document B says, or 'Not present'>","change":"added|removed|modified"}],"verdict":"<1-2 sentences: which version is more favorable and why, or what the key implication of the changes is>"}

Guidelines:
- category: name the specific clause, section, or topic being compared (e.g. "Payment Terms", "Termination Clause", "Jurisdiction", "Liability Cap")
- change: "added" if only in B, "removed" if only in A, "modified" if both have it but differently
- Keep doc_a and doc_b short summaries (max 20 words each)
- List up to 15 most significant differences
- Focus on: parties, dates, payment amounts, obligations, rights, penalties, jurisdiction, termination, arbitration clauses
- If documents are largely identical, still list any differences found

DOCUMENT A:
%s

DOCUMENT B:
%s`, text1, text2)

	raw, err := c.generate(ctx, system, prompt, 2000)
	if err != nil {
		return nil, fmt.Errorf("compare documents: %w", err)
	}

	var result CompareResponse
	if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
		return &CompareResponse{Summary: raw, TotalChanges: 0, Differences: []DiffItem{}, Verdict: ""}, nil
	}
	if result.Differences == nil {
		result.Differences = []DiffItem{}
	}
	result.TotalChanges = len(result.Differences)
	return &result, nil
}

// HelpChat answers questions about the DocAssist app with conversation history.
func (c *Client) HelpChat(ctx context.Context, history []ChatMessage, userMessage string) (string, error) {
	const system = `You are OB, a friendly 24/7 AI support assistant built into DocAssist — an AI-powered legal document management app for Indian lawyers and law firms.

APP FEATURES:
• Documents: Upload PDF/DOCX files, view, search, download, delete. AI processes them for analysis.
• AI Summarize: Get a 2-3 sentence summary and key points from any document.
• Key Points: Extract the most important points from a document.
• Timeline: Extract all dates and events in chronological order.
• Action Items: Find tasks, obligations, and who is responsible for them.
• Translate: Translate documents to any language.
• Grammar Check: Find and fix grammatical errors in legal documents.
• Auto-Tag: Automatically classify documents by legal area, type, and complexity.
• Risk Scan: Identify risky or one-sided clauses in contracts and agreements.
• Deadlines: Extract all time-bound obligations and due dates from documents.
• Citations: Extract all case citations, acts, sections, and articles from judgments.
• Reports: Generate executive, legal, technical, or financial reports from documents.
• AI Chat: Ask any question about a specific document in a conversational way.
• OCR / Extract: Scan a photo or image of a physical document and extract its text. Supports 11 Indian languages (English, Hindi, Marathi, Gujarati, Tamil, Telugu, Kannada, Malayalam, Punjabi, Bengali, Urdu).
• Draft: Generate complete Indian legal documents — petitions, affidavits, notices, agreements, bail applications, written statements, plaints, and more — using AI.
• Compare: Upload two documents and get a side-by-side comparison of all differences (added, removed, modified clauses).
• Matters: Organise documents into case folders (matters). Each matter has a title, matter number, client name, court, status, and description.
• Search: Full-text and AI semantic search across all your documents.
• Favourites: Star documents to bookmark them. Find starred documents in the Favourites section of your profile.
• Change Password: In Profile → Account → Change Password. Enter current and new password.
• Profile: View account details, document count, AI engine (OB), and plan (Free).

HOW TO USE KEY FEATURES:
- Upload a document: Go to Documents tab → tap Upload button → choose PDF or DOCX.
- Analyse a document: Open any document → tap the feature card (Summarize, Key Points, etc.).
- OCR scan: Dashboard → Extract → choose Camera or Gallery → pick language → tap Extract.
- Draft a document: Dashboard → Draft → fill in the form → tap Generate.
- Compare documents: Dashboard → Compare → select Document A and Document B → tap Compare.
- Create a matter: Go to Matters tab → tap + button → fill in details.
- Chat with a document: Open document → tap AI Chat → type your question.
- Favourite a document: In Favourites screen (Profile → Documents → Favourites) you can star documents, or untap the star to remove.

Answer questions helpfully and concisely. For how-to questions, give clear numbered steps. Be friendly and conversational. If something is not yet available, say "coming soon". Keep answers short and practical.`

	msgs := []message{{Role: "system", Content: system}}
	for _, h := range history {
		msgs = append(msgs, message{Role: h.Role, Content: h.Content})
	}
	msgs = append(msgs, message{Role: "user", Content: userMessage})

	return c.chatCompletion(ctx, msgs, 600, 0.5)
}

// ─── Complaint Reply Generator ────────────────────────────────────────────────

// ComplaintReplyResponse holds the AI-generated reply and change metadata.
type ComplaintReplyResponse struct {
	ReplyText        string   `json:"reply_text"`
	ModifiedSections []string `json:"modified_sections"`
	Summary          string   `json:"summary"`
}

// GenerateComplaintReply generates a new legal reply for a complaint by adapting
// an existing reply template, preserving its structure, legal language, and tone
// while replacing all case-specific facts, parties, and allegations.
func (c *Client) GenerateComplaintReply(ctx context.Context, complaintText, existingReplyText string) (*ComplaintReplyResponse, error) {
	system := `You are a senior Indian advocate with 20 years of experience drafting legal replies, written statements, and counter-affidavits. You specialize in adapting existing reply templates to new complaints while preserving their legal structure and language.

IMPORTANT LANGUAGE RULE: The complaint may be written in any Indian regional language — Marathi, Hindi, Gujarati, Tamil, Telugu, Kannada, Bengali, or any other. Regardless of the complaint's language, you MUST write the complete new reply ENTIRELY IN ENGLISH. Translate and understand the complaint's allegations, facts, parties, and dates, then draft the reply in formal legal English.`

	prompt := fmt.Sprintf(`You are given:
1. A NEW COMPLAINT that requires a reply (may be in Marathi, Hindi, or any Indian language — read and understand it)
2. An EXISTING REPLY (template) for a different but similar complaint

Your task:
- Carefully read the new complaint in its original language: identify parties, allegations, facts, dates, case number, court, relief sought
- Analyze the existing reply: understand its structure, numbered paragraphs, preliminary objections, legal language, tone, and signature block
- Generate a COMPLETE NEW REPLY IN ENGLISH by adapting the existing reply to address the new complaint:
  * Preserve the exact document structure (same sections, heading pattern, paragraph numbering style)
  * Preserve all standard preliminary objections, legal submissions, and formal language patterns
  * Replace case-specific details: party names, dates, allegations, case/complaint number, facts (translated to English)
  * Adapt legal arguments paragraph by paragraph to address the new complaint's specific allegations
  * Do NOT copy verbatim from the complaint text; respond to each allegation in legal terms
  * Maintain the same tone (formal, professional, legally precise)
  * Include proper signature block, verification, and date placeholders
  * THE REPLY MUST BE WRITTEN ENTIRELY IN ENGLISH regardless of the complaint's language

Output format — follow EXACTLY (do not change the markers):
---REPLY---
[Write the complete, ready-to-file reply here. All paragraphs numbered. Proper formal legal language. Do not truncate — write the full document.]
---END_REPLY---
---CHANGES---
[List each change made, one per line starting with "- ", e.g.:
- Parties updated: old names replaced with new complainant/respondent
- Case/complaint number updated throughout
- Paragraphs 3-6: Facts adapted to address new allegations
- Prayer section: Updated to reflect new complaint relief
- Dates: All dates updated per new complaint
]
---END_CHANGES---
---SUMMARY---
[Write a detailed summary of 4-6 paragraphs covering ALL of the following:

Paragraph 1 — Case Overview: Full names of all parties, the forum/authority the complaint is filed before, the complaint/case number, date of complaint, and the subject matter in one or two sentences.

Paragraph 2 — Background & Facts: The complainant's background and connection to the matter, the respondents' roles, the key dates, events, or transactions that led to the complaint.

Paragraph 3 — Allegations: A comprehensive list of every allegation or grievance raised in the complaint — include specific amounts (money, weight, area, etc.), dates, and section numbers of laws cited.

Paragraph 4 — Relief Sought: Exactly what the complainant is asking for (orders, compensation, suspension, injunction, criminal action, etc.).

Paragraph 5 — How the Reply Addresses It: The key legal defences raised in the reply — preliminary objections, denials, counter-facts, and legal submissions paragraph by paragraph.

Paragraph 6 — Status and Key Points: What changes were made from the template, any critical observations about strengths or weaknesses in the complaint, and any urgent actions the respondent should take.]
---END_SUMMARY---

NEW COMPLAINT:
%s

EXISTING REPLY (TEMPLATE — use this structure and language):
%s

Write the complete new reply now:`, complaintText, existingReplyText)

	raw, err := c.generate(ctx, system, prompt, 8000)
	if err != nil {
		return nil, fmt.Errorf("generate complaint reply: %w", err)
	}

	return parseComplaintReply(raw), nil
}

func parseComplaintReply(raw string) *ComplaintReplyResponse {
	result := &ComplaintReplyResponse{ModifiedSections: []string{}}

	if s := strings.Index(raw, "---REPLY---"); s != -1 {
		if e := strings.Index(raw, "---END_REPLY---"); e != -1 && e > s {
			result.ReplyText = strings.TrimSpace(raw[s+len("---REPLY---") : e])
		}
	}
	if s := strings.Index(raw, "---CHANGES---"); s != -1 {
		if e := strings.Index(raw, "---END_CHANGES---"); e != -1 && e > s {
			block := strings.TrimSpace(raw[s+len("---CHANGES---") : e])
			for _, line := range strings.Split(block, "\n") {
				line = strings.TrimSpace(line)
				if line == "" {
					continue
				}
				if strings.HasPrefix(line, "- ") {
					line = strings.TrimPrefix(line, "- ")
				}
				result.ModifiedSections = append(result.ModifiedSections, line)
			}
		}
	}
	if s := strings.Index(raw, "---SUMMARY---"); s != -1 {
		if e := strings.Index(raw, "---END_SUMMARY---"); e != -1 && e > s {
			result.Summary = strings.TrimSpace(raw[s+len("---SUMMARY---") : e])
		}
	}
	if result.ReplyText == "" {
		result.ReplyText = strings.TrimSpace(raw)
	}
	return result
}

func (c *Client) ExtractCitations(ctx context.Context, text string) (*CitationsResponse, error) {
    system := `You are a legal document analysis expert specializing in Indian law. Extract all legal citations. Always respond with valid JSON only, no markdown, no explanation.` + indiaDocEngRule
    prompt := fmt.Sprintf(`Extract all legal citations and references from this Indian legal document.
Respond ONLY with this exact JSON (empty arrays [] if none found for a category, no duplicates):
{"cases":["<case name and citation>"],"sections":["<Section X of Act>"],"acts":["<Full Act name>"],"articles":["<Article X>"],"rules":["<Rule/Order reference>"]}

Categories:
- cases: court judgements like "ABC v. XYZ AIR 1998 SC 100", "State v. Sharma (2020) SCC"
- sections: statutory provisions like "Section 302 IPC", "Section 138 Negotiable Instruments Act 1881"
- acts: legislation like "Indian Penal Code 1860", "Code of Civil Procedure 1908", "Constitution of India 1950"
- articles: constitutional articles like "Article 21", "Article 226", "Article 14"
- rules: procedural rules like "Order VII Rule 1 CPC", "Rule 3 High Court Rules"

Document:
%s`, text)

    raw, err := c.generate(ctx, system, prompt, 1200)
    if err != nil {
        return nil, fmt.Errorf("citations: %w", err)
    }

    var result CitationsResponse
    if err := json.Unmarshal([]byte(parseJSON(raw)), &result); err != nil {
        result = CitationsResponse{}
    }
    if result.Cases == nil {
        result.Cases = []string{}
    }
    if result.Sections == nil {
        result.Sections = []string{}
    }
    if result.Acts == nil {
        result.Acts = []string{}
    }
    if result.Articles == nil {
        result.Articles = []string{}
    }
    if result.Rules == nil {
        result.Rules = []string{}
    }
    return &result, nil
}
