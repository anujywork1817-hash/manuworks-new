package ocr

import (
	"archive/zip"
	"encoding/xml"
	"fmt"
	"io"
	"strings"
)

// ─── DOCX XML structures ──────────────────────────────────────────────────────

type docxBody struct {
	Paragraphs []docxParagraph `xml:"body>p"`
}

type docxParagraph struct {
	Runs []docxRun `xml:"r"`
}

type docxRun struct {
	Text    string `xml:"t"`
	DelText string `xml:"delText"`
}

// extractDocxGoNative reads word/document.xml from a .docx zip archive
// and returns plain text. No external dependencies required.
func extractDocxGoNative(filePath string) (string, error) {
	r, err := zip.OpenReader(filePath)
	if err != nil {
		return "", fmt.Errorf("open docx zip: %w", err)
	}
	defer r.Close()

	// Find word/document.xml inside the zip
	var docFile *zip.File
	for _, f := range r.File {
		if f.Name == "word/document.xml" {
			docFile = f
			break
		}
	}

	if docFile == nil {
		return "", fmt.Errorf("word/document.xml not found in docx archive")
	}

	rc, err := docFile.Open()
	if err != nil {
		return "", fmt.Errorf("open document.xml: %w", err)
	}
	defer rc.Close()

	return parseDocumentXML(rc)
}

// parseDocumentXML extracts plain text from the OOXML word/document.xml stream.
// Handles paragraph breaks correctly.
func parseDocumentXML(r io.Reader) (string, error) {
	var sb strings.Builder
	decoder := xml.NewDecoder(r)

	inParagraph := false
	inRun := false
	inText := false

	for {
		tok, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return sb.String(), nil // Return what we have so far
		}

		switch t := tok.(type) {
		case xml.StartElement:
			localName := t.Name.Local
			switch localName {
			case "p": // paragraph
				inParagraph = true
			case "r": // run
				inRun = true
			case "t": // text
				if inParagraph && inRun {
					inText = true
				}
			case "br", "cr": // line break
				sb.WriteString("\n")
			}

		case xml.EndElement:
			localName := t.Name.Local
			switch localName {
			case "p":
				if inParagraph {
					sb.WriteString("\n")
					inParagraph = false
				}
			case "r":
				inRun = false
			case "t":
				inText = false
			}

		case xml.CharData:
			if inText {
				sb.Write(t)
			}
		}
	}

	return strings.TrimSpace(sb.String()), nil
}
