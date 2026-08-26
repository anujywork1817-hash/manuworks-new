package ocr

import (
	"archive/zip"
	"bytes"
	"fmt"
	"strings"
)

// CreateDocx builds a minimal, valid .docx file from plain text using only
// the standard library (archive/zip). Each newline becomes a paragraph.
func CreateDocx(text string) ([]byte, error) {
	var buf bytes.Buffer
	w := zip.NewWriter(&buf)

	entries := map[string]string{
		"[Content_Types].xml":          docxContentTypes,
		"_rels/.rels":                  docxRels,
		"word/_rels/document.xml.rels": docxDocRels,
		"word/document.xml":            buildDocxBody(text),
	}

	for name, content := range entries {
		f, err := w.Create(name)
		if err != nil {
			return nil, fmt.Errorf("docx: create entry %q: %w", name, err)
		}
		if _, err := f.Write([]byte(content)); err != nil {
			return nil, fmt.Errorf("docx: write entry %q: %w", name, err)
		}
	}

	if err := w.Close(); err != nil {
		return nil, fmt.Errorf("docx: close zip: %w", err)
	}
	return buf.Bytes(), nil
}

const docxContentTypes = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>`

const docxRels = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>`

const docxDocRels = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>`

func buildDocxBody(text string) string {
	const wNS = `xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"`
	var sb strings.Builder
	sb.WriteString(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`)
	sb.WriteString(`<w:document ` + wNS + `><w:body>`)

	for _, line := range strings.Split(text, "\n") {
		sb.WriteString(`<w:p>`)
		trimmed := strings.TrimSpace(line)
		if trimmed != "" {
			// Bold lines that look like section headings (ALL CAPS or ending with colon)
			isBold := trimmed == strings.ToUpper(trimmed) && len(trimmed) > 3
			sb.WriteString(`<w:r>`)
			if isBold {
				sb.WriteString(`<w:rPr><w:b/></w:rPr>`)
			}
			sb.WriteString(`<w:t xml:space="preserve">`)
			sb.WriteString(xmlEscape(line))
			sb.WriteString(`</w:t></w:r>`)
		}
		sb.WriteString(`</w:p>`)
	}

	sb.WriteString(`</w:body></w:document>`)
	return sb.String()
}

func xmlEscape(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	s = strings.ReplaceAll(s, "\"", "&quot;")
	return s
}
