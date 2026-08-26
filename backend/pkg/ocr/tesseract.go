package ocr

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode"


	"github.com/yourusername/docassist/config"
	"github.com/yourusername/docassist/pkg/logger"
)

// ─── Types ────────────────────────────────────────────────────────────────────

type ExtractResult struct {
	Text       string        `json:"text"`
	PageCount  int           `json:"page_count"`
	WordCount  int           `json:"word_count"`
	Language   string        `json:"language"`
	Confidence float64       `json:"confidence"` // 0–100
	Duration   time.Duration `json:"duration"`
}

type PageResult struct {
	PageNumber int     `json:"page_number"`
	Text       string  `json:"text"`
	Confidence float64 `json:"confidence"`
}

// ─── Service ──────────────────────────────────────────────────────────────────

type Service struct {
	cfg *config.OCRConfig
}

func NewService(cfg *config.OCRConfig) *Service {
	return &Service{cfg: cfg}
}

// ExtractFromFile detects the file type and routes to the correct extractor.
// Supported: PDF, PNG, JPG, JPEG, TIFF, BMP
func (s *Service) ExtractFromFile(ctx context.Context, filePath string) (*ExtractResult, error) {
	start := time.Now()

	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(filePath), "."))

	var result *ExtractResult
	var err error

	switch ext {
	case "pdf":
		result, err = s.extractFromPDF(ctx, filePath)
	case "png", "jpg", "jpeg", "tiff", "tif", "bmp", "webp":
		result, err = s.extractFromImage(ctx, filePath, s.cfg.Lang)
	default:
		return nil, fmt.Errorf("unsupported file type for OCR: .%s", ext)
	}

	if err != nil {
		return nil, err
	}

	result.Duration = time.Since(start)
	result.WordCount = countWords(result.Text)

	logger.Info("OCR completed",
		logger.Str("file", filepath.Base(filePath)),
		logger.Int("pages", result.PageCount),
		logger.Int("words", result.WordCount),
		logger.Str("duration", result.Duration.String()),
	)

	return result, nil
}

// ─── PDF Extraction ───────────────────────────────────────────────────────────

// extractFromPDF converts each PDF page to an image then runs Tesseract on each.
// Requires: pdftoppm (from poppler-utils) installed on the system.
func (s *Service) extractFromPDF(ctx context.Context, pdfPath string) (*ExtractResult, error) {
	return s.extractFromPDFWithLang(ctx, pdfPath, s.cfg.Lang)
}

func (s *Service) extractFromPDFWithLang(ctx context.Context, pdfPath, lang string) (*ExtractResult, error) {
	return s.extractFromPDFWithPages(ctx, pdfPath, lang, 0)
}

// extractFromPDFWithPages is the core PDF→OCR pipeline.
// maxPages: 0 = no limit; N > 0 = OCR at most N pages (front pages first).
// DPI strategy: try 150 first — images are 4× smaller than 300 DPI so OCR
// runs 3-4× faster with no meaningful quality loss for typical legal scan
// resolution. Fall back to 300 DPI only if 150 DPI fails (e.g. memory error).
func (s *Service) extractFromPDFWithPages(ctx context.Context, pdfPath, lang string, maxPages int) (*ExtractResult, error) {
	tmpDir, err := os.MkdirTemp("", "ocr_pdf_*")
	if err != nil {
		return nil, fmt.Errorf("failed to create temp dir: %w", err)
	}
	defer func() { os.RemoveAll(tmpDir) }()

	timeoutCtx, cancel := context.WithTimeout(ctx, s.cfg.Timeout)
	defer cancel()

	// Render every page to a PNG. Several renderers are tried in turn because a
	// single tool can silently fail — sometimes exiting 0 with no output — on
	// scans that use JBIG2/JPEG2000 or otherwise unusual PDF structures (common
	// for scanner- and receipt-generated PDFs). See renderPDFToImages.
	// NOTE: Never pass a .pdf path to extractFromImage — Tesseract cannot read PDFs.
	pages, renderErr := renderPDFToImages(timeoutCtx, pdfPath, tmpDir)

	if len(pages) == 0 {
		// Last resort: some "image-only" PDFs still carry a thin text layer that
		// pdftotext can pull out even when no renderer could rasterise a page.
		if text, terr := extractDigitalPDFText(ctx, pdfPath); terr == nil && len(strings.TrimSpace(text)) > 10 {
			logger.Info("pdftotext last-resort succeeded after all renderers produced no images")
			cleaned := cleanText(text)
			return &ExtractResult{
				Text:       cleaned,
				PageCount:  estimatePageCount(cleaned),
				WordCount:  countWords(cleaned),
				Language:   lang,
				Confidence: 90.0,
			}, nil
		}
		logger.Warn("All PDF renderers failed to produce page images",
			logger.Str("error", renderErr))
		return nil, fmt.Errorf("could not extract text from this PDF — it appears to be image-only but the server could not render its pages (the file may be encrypted, corrupted, or in an unsupported PDF format)")
	}

	// Apply page cap before OCR (saves the most time for large scanned docs).
	totalPages := len(pages)
	if maxPages > 0 && len(pages) > maxPages {
		pages = pages[:maxPages]
		logger.Info("Capped OCR to first pages",
			logger.Int("capped_to", maxPages),
			logger.Int("total_pages", totalPages),
		)
	}

	// OCR pages in parallel — Tesseract CLI spawns separate OS processes so
	// there is no shared state between workers. Cap at 3 workers to avoid
	// overloading free-tier CPUs while still getting a 2-3x wall-clock win.
	type ocrResult struct {
		pr  *PageResult
		err error
	}
	results := make([]ocrResult, len(pages))
	sem := make(chan struct{}, 3)
	var wg sync.WaitGroup

	for i, pagePath := range pages {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		wg.Add(1)
		go func(idx int, path string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			pr, err := s.ocrImageFile(path, lang)
			results[idx] = ocrResult{pr, err}
		}(i, pagePath)
	}
	wg.Wait()

	// Collect in original page order.
	var allText strings.Builder
	var totalConfidence float64
	pageResults := make([]PageResult, 0, len(pages))
	for i, r := range results {
		if r.err != nil {
			logger.Warn("OCR failed for page",
				logger.Int("page", i+1),
				logger.Str("error", r.err.Error()),
			)
			continue
		}
		r.pr.PageNumber = i + 1
		pageResults = append(pageResults, *r.pr)
		allText.WriteString(r.pr.Text)
		allText.WriteString("\n\n--- Page ")
		allText.WriteString(fmt.Sprintf("%d", i+2))
		allText.WriteString(" ---\n\n")
		totalConfidence += r.pr.Confidence
	}

	avgConfidence := 0.0
	if len(pageResults) > 0 {
		avgConfidence = totalConfidence / float64(len(pageResults))
	}

	return &ExtractResult{
		Text:       cleanText(allText.String()),
		PageCount:  totalPages, // report true page count even when capped
		Language:   lang,
		Confidence: avgConfidence,
	}, nil
}

// renderPDFToImages converts each page of a PDF into a PNG inside tmpDir and
// returns the image paths in page order. It tries pdftoppm, then pdftocairo,
// then Ghostscript (if installed), at 150 then 300 DPI. Crucially, each attempt
// is judged by the images it actually produced — not just the exit code —
// because these tools can exit 0 without rendering anything on scans using
// JBIG2/JPEG2000 or malformed PDFs, and a tool that chokes on such a file is
// often rescued by a different rendering backend. Returns nil and a diagnostic
// string when no renderer produced output.
func renderPDFToImages(ctx context.Context, pdfPath, tmpDir string) ([]string, string) {
	prefix := filepath.Join(tmpDir, "page")

	attempts := []struct {
		name string
		args func(dpi string) []string
	}{
		{"pdftoppm", func(dpi string) []string {
			return []string{"-r", dpi, "-png", pdfPath, prefix}
		}},
		{"pdftocairo", func(dpi string) []string {
			return []string{"-png", "-r", dpi, pdfPath, prefix}
		}},
		// Ghostscript is the most tolerant of damaged/encrypted PDFs. Zero-pad
		// the page number so lexical sorting keeps pages in order past page 9.
		{"gs", func(dpi string) []string {
			return []string{"-dQUIET", "-dNOPAUSE", "-dBATCH", "-dSAFER",
				"-sDEVICE=png16m", "-r" + dpi,
				"-sOutputFile=" + prefix + "-%03d.png", pdfPath}
		}},
	}

	var lastErr string
	for _, a := range attempts {
		for _, dpi := range []string{"150", "300"} {
			clearPDFPageImages(tmpDir)
			out, err := exec.CommandContext(ctx, a.name, a.args(dpi)...).CombinedOutput()
			if imgs := listPDFPageImages(tmpDir); len(imgs) > 0 {
				if a.name != "pdftoppm" || dpi != "150" {
					logger.Info("PDF rendered via fallback",
						logger.Str("renderer", a.name), logger.Str("dpi", dpi))
				}
				return imgs, ""
			}
			if err != nil {
				lastErr = fmt.Sprintf("%s @ %s DPI: %s", a.name, dpi, strings.TrimSpace(string(out)))
			} else {
				lastErr = fmt.Sprintf("%s @ %s DPI: exited cleanly but produced no images", a.name, dpi)
			}
			logger.Warn("PDF render attempt yielded no images", logger.Str("detail", lastErr))
		}
	}
	return nil, lastErr
}

// listPDFPageImages returns the rendered page-image paths in dir, sorted so
// pages stay in order (page-1, page-2, …).
func listPDFPageImages(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var imgs []string
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		switch strings.ToLower(filepath.Ext(e.Name())) {
		case ".png", ".ppm", ".jpg", ".jpeg":
			imgs = append(imgs, filepath.Join(dir, e.Name()))
		}
	}
	sort.Strings(imgs)
	return imgs
}

// clearPDFPageImages removes page images left by a previous render attempt so
// the next renderer starts from a clean directory.
func clearPDFPageImages(dir string) {
	for _, p := range listPDFPageImages(dir) {
		os.Remove(p)
	}
}

// ─── Image Extraction ─────────────────────────────────────────────────────────

func (s *Service) extractFromImage(ctx context.Context, imagePath, lang string) (*ExtractResult, error) {
	if lang == "" {
		lang = s.cfg.Lang
	}
	pr, err := s.ocrImageFile(imagePath, lang)
	if err != nil {
		return nil, err
	}

	cleaned := cleanText(pr.Text)
	return &ExtractResult{
		Text:       cleaned,
		PageCount:  1,
		WordCount:  countWords(cleaned),
		Language:   lang,
		Confidence: pr.Confidence,
	}, nil
}

// ─── Core Tesseract Call ──────────────────────────────────────────────────────

// ocrImageFile runs Tesseract CLI on a single image file.
// If the lang string includes optional packages (mod, san) that are not
// installed, it retries automatically with those packages stripped out so a
// missing tessdata file never silently kills OCR for the whole document.
func (s *Service) ocrImageFile(imagePath, lang string) (*PageResult, error) {
	tessLang := toTesseractLang(lang)

	// --oem 1 = LSTM only: faster than combined mode (--oem 3) and more accurate
	// for Indian scripts. --psm 3 = fully automatic page segmentation.
	cmd := exec.Command("tesseract", imagePath, "stdout", "-l", tessLang, "--oem", "1", "--psm", "3")
	output, err := cmd.Output()
	if err == nil {
		return &PageResult{Text: string(output), Confidence: 85.0}, nil
	}

	// If tessdata for an optional language (mod, san) is missing, Tesseract
	// exits non-zero with "Could not initialize tesseract". Strip those optional
	// langs and retry before giving up.
	errMsg := strings.ToLower(err.Error())
	if strings.Contains(tessLang, "+mod") || strings.Contains(tessLang, "+san") {
		if strings.Contains(errMsg, "tesseract") || strings.Contains(errMsg, "exit") {
			fallback := tessLang
			for _, opt := range []string{"+mod", "mod+", "+san", "san+"} {
				fallback = strings.ReplaceAll(fallback, opt, "")
			}
			if fallback != tessLang {
				logger.Warn("Retrying OCR without optional tessdata",
					logger.Str("dropped_from", tessLang),
					logger.Str("fallback", fallback),
				)
				cmd2 := exec.Command("tesseract", imagePath, "stdout", "-l", fallback, "--oem", "1", "--psm", "3")
				if out2, err2 := cmd2.Output(); err2 == nil {
					return &PageResult{Text: string(out2), Confidence: 85.0}, nil
				}
			}
		}
	}

	return nil, fmt.Errorf("tesseract failed on %s: %w", filepath.Base(imagePath), err)
}

// toTesseractLang maps ISO 639-1 2-letter codes to Tesseract 3-letter codes.
func toTesseractLang(lang string) string {
	mapping := map[string]string{
		"en": "eng",
		"hi": "hin",
		"mr": "mar",
		"gu": "guj",
		"ta": "tam",
		"te": "tel",
		"kn": "kan",
		"ml": "mal",
		"pa": "pan",
		"bn": "ben",
		"or": "ori",
		"ur": "urd",
	}
	if v, ok := mapping[lang]; ok {
		return v
	}
	if len(lang) == 3 {
		return lang
	}
	return "eng"
}

// LangToTess maps an ISO 639-1 language code (as sent from the Flutter app) to
// the best Tesseract multilingual string for that language. Indian scripts always
// include "eng" so mixed English-vernacular documents are handled correctly.
func LangToTess(lang string) string {
	switch strings.ToLower(lang) {
	case "mr", "marathi":
		return "eng+mar+mod+san"
	case "hi", "hindi":
		return "eng+hin"
	case "gu", "gujarati":
		return "eng+guj"
	case "ta", "tamil":
		return "eng+tam"
	case "te", "telugu":
		return "eng+tel"
	case "kn", "kannada":
		return "eng+kan"
	case "ml", "malayalam":
		return "eng+mal"
	case "pa", "punjabi":
		return "eng+pan"
	case "bn", "bengali":
		return "eng+ben"
	case "ur", "urdu":
		return "eng+urd"
	case "sa", "san", "sanskrit":
		return "eng+san"
	default:
		return "eng+mar+hin" // best default for this app's user base
	}
}

// ─── DOCX Text Extraction ─────────────────────────────────────────────────────

// ExtractFromDOCX extracts plain text from a .docx file without OCR.
// DOCX files contain XML — we extract the text nodes directly.
func (s *Service) ExtractFromDOCX(ctx context.Context, filePath string) (*ExtractResult, error) {
	start := time.Now()

	// Use python-docx via a shell command if available, otherwise use our Go approach
	text, err := extractDOCXText(filePath)
	if err != nil {
		return nil, fmt.Errorf("docx extraction: %w", err)
	}

	result := &ExtractResult{
		Text:       cleanText(text),
		PageCount:  estimatePageCount(text),
		WordCount:  countWords(text),
		Language:   s.cfg.Lang,
		Confidence: 100.0, // DOCX is digital text, not scanned
		Duration:   time.Since(start),
	}

	return result, nil
}

// extractDOCXText reads the word/document.xml inside the .docx zip archive.
func extractDOCXText(filePath string) (string, error) {
	// .docx is a ZIP file containing word/document.xml
	// We use the archive/zip + encoding/xml approach

	// Shell out to python-docx if available (better formatting preservation)
	cmd := exec.Command("python3", "-c", fmt.Sprintf(`
import sys
try:
    from docx import Document
    doc = Document('%s')
    print('\n'.join([p.text for p in doc.paragraphs]))
except ImportError:
    sys.exit(1)
`, filePath))

	output, err := cmd.Output()
	if err == nil {
		return string(output), nil
	}

	// Fallback: parse the XML directly using Go's zip reader
	return extractDOCXViaZip(filePath)
}

func extractDOCXViaZip(filePath string) (string, error) {
	// Import here to avoid circular import at package level
	// This uses archive/zip + encoding/xml
	return extractDocxGoNative(filePath)
}

// ─── Plain Text Extraction ────────────────────────────────────────────────────

// ExtractFromTXT reads a plain text file directly (no OCR needed).
func (s *Service) ExtractFromTXT(ctx context.Context, filePath string) (*ExtractResult, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("read text file: %w", err)
	}

	text := string(data)
	return &ExtractResult{
		Text:       cleanText(text),
		PageCount:  estimatePageCount(text),
		WordCount:  countWords(text),
		Language:   s.cfg.Lang,
		Confidence: 100.0,
		Duration:   0,
	}, nil
}

// ─── Smart Router ─────────────────────────────────────────────────────────────

// ExtractText is the main entry point — routes to the correct extractor
// based on file extension, no OCR for digital text files.
func (s *Service) ExtractText(ctx context.Context, filePath string) (*ExtractResult, error) {
	return s.ExtractTextWithLang(ctx, filePath, s.cfg.Lang)
}

// ExtractTextWithLang is like ExtractText but uses a custom Tesseract language
// for OCR (e.g. "eng+mar+hin" for multilingual documents).
// For digital PDFs the lang only affects the ExtractResult.Language field;
// for scanned PDFs it controls which language model Tesseract loads.
func (s *Service) ExtractTextWithLang(ctx context.Context, filePath, lang string) (*ExtractResult, error) {
	return s.extractText(ctx, filePath, lang, 0)
}

// ExtractTextFast is like ExtractTextWithLang but caps scanned-PDF OCR at
// maxPages (pass 0 for no limit). Use for interactive AI features (Summarize,
// Key Points, etc.) where you need a response within ~30 seconds:
//   - Digital PDFs: instant via pdftotext — page cap is ignored
//   - Scanned PDFs: OCR only the first maxPages pages
//   - DOCX / TXT / images: no cap applied (they are already fast)
func (s *Service) ExtractTextFast(ctx context.Context, filePath, lang string, maxPages int) (*ExtractResult, error) {
	return s.extractText(ctx, filePath, lang, maxPages)
}

// extractText is the internal router used by both ExtractTextWithLang and
// ExtractTextFast. maxPages=0 means no limit.
func (s *Service) extractText(ctx context.Context, filePath, lang string, maxPages int) (*ExtractResult, error) {
	if lang == "" {
		lang = s.cfg.Lang
	}
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(filePath), "."))

	switch ext {
	case "txt":
		return s.ExtractFromTXT(ctx, filePath)
	case "docx", "doc":
		return s.ExtractFromDOCX(ctx, filePath)
	case "pdf":
		// Try digital text extraction first — instant, language-agnostic.
		if text, err := extractDigitalPDFText(ctx, filePath); err == nil && len(strings.TrimSpace(text)) > 30 {
			wc := countWords(text)
			logger.Info("Digital PDF text extracted (no OCR needed)",
				logger.Int("chars", len(text)),
				logger.Int("words", wc),
			)
			return &ExtractResult{
				Text:       cleanText(text),
				PageCount:  estimatePageCount(text),
				WordCount:  wc,
				Language:   lang,
				Confidence: 100.0,
			}, nil
		}
		// Scanned PDF — OCR required.
		logger.Info("PDF has no text layer — falling back to Tesseract OCR",
			logger.Str("lang", lang),
			logger.Int("max_pages", maxPages),
		)
		return s.extractFromPDFWithPages(ctx, filePath, lang, maxPages)
	case "png", "jpg", "jpeg", "tiff", "tif", "bmp", "webp":
		return s.extractFromImage(ctx, filePath, lang)
	default:
		return s.ExtractFromFile(ctx, filePath)
	}
}

// digitalPDFTextTimeout bounds each pdftotext pass. Plain text extraction
// should always be near-instant — a hang here (malformed/huge/adversarial
// PDF) previously blocked document processing forever with no timeout and
// no error, leaving the document stuck in "processing" indefinitely.
const digitalPDFTextTimeout = 30 * time.Second

// extractDigitalPDFText tries to extract selectable text from a PDF (not scanned).
// Uses pdftotext from poppler-utils.
// IMPORTANT: try WITHOUT -layout first — the -layout flag preserves visual spacing
// but corrupts complex scripts like Devanagari (Marathi/Hindi), returning near-empty
// output and causing a needless fall-through to slow Tesseract OCR.
func extractDigitalPDFText(ctx context.Context, filePath string) (string, error) {
	// Pass 1: plain extraction — correct for all scripts including Devanagari.
	pass1Ctx, cancel1 := context.WithTimeout(ctx, digitalPDFTextTimeout)
	defer cancel1()
	if out, err := exec.CommandContext(pass1Ctx, "pdftotext", filePath, "-").Output(); err == nil {
		if text := strings.TrimSpace(string(out)); len(text) > 30 {
			return text, nil
		}
	}
	// Pass 2: layout mode — better for columnar/tabular Latin-script PDFs.
	pass2Ctx, cancel2 := context.WithTimeout(ctx, digitalPDFTextTimeout)
	defer cancel2()
	out, err := exec.CommandContext(pass2Ctx, "pdftotext", "-layout", filePath, "-").Output()
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// cleanText normalises whitespace and removes non-printable characters.
func cleanText(text string) string {
	// Remove non-printable characters except newlines and tabs
	text = strings.Map(func(r rune) rune {
		if unicode.IsPrint(r) || r == '\n' || r == '\t' {
			return r
		}
		return -1
	}, text)

	// Collapse multiple blank lines into at most two
	for strings.Contains(text, "\n\n\n") {
		text = strings.ReplaceAll(text, "\n\n\n", "\n\n")
	}

	// Collapse multiple spaces
	for strings.Contains(text, "  ") {
		text = strings.ReplaceAll(text, "  ", " ")
	}

	return strings.TrimSpace(text)
}

func countWords(text string) int {
	if text == "" {
		return 0
	}
	return len(strings.Fields(text))
}

// estimatePageCount estimates page count based on ~500 words per page.
func estimatePageCount(text string) int {
	wc := countWords(text)
	pages := wc / 500
	if pages == 0 {
		return 1
	}
	return pages
}

// IsOCRAvailable checks if Tesseract is installed and working.
func IsOCRAvailable() bool {
	cmd := exec.Command("tesseract", "--version")
	return cmd.Run() == nil
}

// IsPDFToolsAvailable checks if poppler-utils (pdftoppm, pdftotext) are installed.
func IsPDFToolsAvailable() bool {
	return exec.Command("pdftoppm", "-v").Run() == nil ||
		exec.Command("pdftotext", "-v").Run() == nil
}







