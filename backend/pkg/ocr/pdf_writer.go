package ocr

import (
	"bytes"
	"fmt"
	"strings"
)

// CreatePDF generates a minimal valid PDF from plain text using raw PDF syntax.
// No external dependencies. Output uses Helvetica (built-in Type1 font) so the
// text must be Latin-1 compatible — the AI always outputs in English, so this holds.
func CreatePDF(text string) ([]byte, error) {
	lines := wrapLinesForPDF(text, 82) // ~82 chars fits inside 468pt at 11pt Helvetica
	pages := splitPDFPages(lines, 46)  // ~46 lines per page at 14pt leading
	if len(pages) == 0 {
		pages = [][]string{{""}}
	}
	return assemblePDF(pages), nil
}

// wrapLinesForPDF splits each raw line with word-wrap at maxChars.
func wrapLinesForPDF(text string, maxChars int) []string {
	var result []string
	for _, raw := range strings.Split(text, "\n") {
		if len(raw) == 0 {
			result = append(result, "")
			continue
		}
		if len(raw) <= maxChars {
			result = append(result, raw)
			continue
		}
		// word-wrap
		words := strings.Fields(raw)
		if len(words) == 0 {
			result = append(result, "")
			continue
		}
		var line strings.Builder
		for _, w := range words {
			if line.Len() == 0 {
				line.WriteString(w)
			} else if line.Len()+1+len(w) <= maxChars {
				line.WriteByte(' ')
				line.WriteString(w)
			} else {
				result = append(result, line.String())
				line.Reset()
				line.WriteString(w)
			}
		}
		if line.Len() > 0 {
			result = append(result, line.String())
		}
	}
	return result
}

func splitPDFPages(lines []string, lpp int) [][]string {
	if len(lines) == 0 {
		return nil
	}
	var pages [][]string
	for i := 0; i < len(lines); i += lpp {
		end := i + lpp
		if end > len(lines) {
			end = len(lines)
		}
		pages = append(pages, lines[i:end])
	}
	return pages
}

// assemblePDF builds the PDF binary from a slice of pages (each page = []string of lines).
//
// Object layout:
//
//	1 = Catalog
//	2 = Pages
//	3 = Font (Helvetica)
//	4+2*i = Page[i]
//	5+2*i = Content stream for Page[i]
func assemblePDF(pages [][]string) []byte {
	n := len(pages)
	totalObjs := 3 + n*2
	offsets := make([]int, totalObjs+1) // 1-indexed; offsets[0] unused

	var buf bytes.Buffer
	buf.WriteString("%PDF-1.4\n%\xe2\xe3\xcf\xd3\n") // header + binary comment

	// Obj 1: Catalog
	offsets[1] = buf.Len()
	fmt.Fprintf(&buf, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")

	// Obj 2: Pages
	offsets[2] = buf.Len()
	var kids strings.Builder
	for i := 0; i < n; i++ {
		if i > 0 {
			kids.WriteByte(' ')
		}
		fmt.Fprintf(&kids, "%d 0 R", 4+2*i)
	}
	fmt.Fprintf(&buf, "2 0 obj\n<< /Type /Pages /Kids [%s] /Count %d >>\nendobj\n", kids.String(), n)

	// Obj 3: Font
	offsets[3] = buf.Len()
	fmt.Fprintf(&buf, "3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\nendobj\n")

	// One page dict + content stream per page
	for i, pgLines := range pages {
		pageObj := 4 + 2*i
		contentObj := 5 + 2*i

		stream := buildContentStream(pgLines)

		offsets[pageObj] = buf.Len()
		fmt.Fprintf(&buf,
			"%d 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R /Resources << /Font << /F1 3 0 R >> >> >>\nendobj\n",
			pageObj, contentObj,
		)

		offsets[contentObj] = buf.Len()
		fmt.Fprintf(&buf, "%d 0 obj\n<< /Length %d >>\nstream\n%sendstream\nendobj\n",
			contentObj, len(stream), stream,
		)
	}

	// Cross-reference table
	xrefOff := buf.Len()
	fmt.Fprintf(&buf, "xref\n0 %d\n", totalObjs+1)
	fmt.Fprintf(&buf, "0000000000 65535 f \n") // object 0 free-list head (exactly 20 bytes incl. \n)
	for i := 1; i <= totalObjs; i++ {
		fmt.Fprintf(&buf, "%010d 00000 n \n", offsets[i])
	}

	// Trailer
	fmt.Fprintf(&buf, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", totalObjs+1, xrefOff)

	return buf.Bytes()
}

// buildContentStream returns the PDF content stream for one page.
// Text origin: x=72 (left margin), y=720 (top margin from bottom = 792-72).
// Leading: 14pt → fits ~46 lines before hitting y=72 (bottom margin).
func buildContentStream(lines []string) string {
	var sb strings.Builder
	sb.WriteString("BT\n/F1 11 Tf\n72 720 Td\n14 TL\n")
	for _, line := range lines {
		safe := pdfEscapeText(line)
		fmt.Fprintf(&sb, "(%s) Tj T*\n", safe)
	}
	sb.WriteString("ET\n")
	return sb.String()
}

// pdfEscapeText sanitises a string for use inside a PDF string literal (...).
// Strips non-Latin-1 characters (Devanagari etc.) since Helvetica/WinAnsiEncoding
// only covers Latin-1. The AI reply is always in English so this is safe.
func pdfEscapeText(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r == '\\':
			b.WriteString(`\\`)
		case r == '(':
			b.WriteString(`\(`)
		case r == ')':
			b.WriteString(`\)`)
		case r == '\t':
			b.WriteString("    ")
		case r >= 0x20 && r <= 0x7E: // printable ASCII
			b.WriteRune(r)
		case r >= 0xA0 && r <= 0xFF: // Latin-1 supplement (WinAnsiEncoding)
			b.WriteRune(r)
		default:
			// Non-Latin-1 (e.g. Devanagari residue): skip silently
		}
	}
	return b.String()
}
