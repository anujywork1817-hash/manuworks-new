import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'web_download/web_download.dart';

/// One slide's content for [DocumentExportService.exportToPptx] — a title
/// plus a list of bullet lines.
class PptxSlide {
  final String title;
  final List<String> bullets;
  const PptxSlide({required this.title, required this.bullets});
}

/// Exports a drafted legal document (plain text) to PDF or Word (.docx),
/// saving it into app storage and opening the native share/save sheet.
///
/// Runs entirely on-device — no backend call required.
class DocumentExportService {
  DocumentExportService._();

  static String _safeFileName(String title) {
    final cleaned = title.trim().isEmpty ? 'Document' : title.trim();
    return cleaned.replaceAll(RegExp(r'[^\w\-]+'), '_');
  }

  /// Splits [content] into paragraph widgets instead of one giant [pw.Text].
  /// A single very-long [pw.Text] block can occasionally be taller than one
  /// PDF page's worth of content, and the pdf package can't split such a
  /// block internally (it throws instead of just flowing it across pages).
  /// Breaking the document into one [pw.Text] per paragraph — and further
  /// chunking any unusually long paragraph — guarantees no single widget is
  /// ever too tall to lay out, no matter how long the overall document is.
  static List<pw.Widget> _paragraphWidgets(String content) {
    const style = pw.TextStyle(fontSize: 11, lineSpacing: 3);
    const maxParagraphChars = 1200;

    final rawParagraphs = content.split(RegExp(r'\n\s*\n'));
    final widgets = <pw.Widget>[];

    for (final para in rawParagraphs) {
      final trimmed = para.trimRight();
      if (trimmed.isEmpty) continue;

      if (trimmed.length <= maxParagraphChars) {
        widgets.add(pw.Text(trimmed, style: style));
      } else {
        // Extra-long paragraph (e.g. a huge block with no blank-line
        // breaks) — chunk it further, breaking on line boundaries where
        // possible so we never build a single unsplittable block.
        final lines = trimmed.split('\n');
        final buffer = StringBuffer();
        for (final line in lines) {
          if (buffer.length + line.length > maxParagraphChars &&
              buffer.isNotEmpty) {
            widgets.add(pw.Text(buffer.toString(), style: style));
            buffer.clear();
          }
          buffer.writeln(line);
        }
        if (buffer.isNotEmpty) {
          widgets.add(pw.Text(buffer.toString(), style: style));
        }
      }
      widgets.add(pw.SizedBox(height: 10));
    }

    if (widgets.isEmpty) {
      widgets.add(pw.Text(content, style: style));
    }
    return widgets;
  }

  /// Generates a PDF from [content] and saves/shares/downloads it depending
  /// on platform (mobile/desktop: app storage + share sheet; web: browser
  /// download — neither path_provider nor dart:io File work on web).
  static Future<void> exportToPdf({
    required String title,
    required String content,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        // Default maxPages is 20 — long drafted documents (affidavits,
        // petitions, contracts) can easily exceed that and the package
        // throws TooManyPagesException instead of just adding more pages.
        // Raise the cap so any realistic document-length export works.
        maxPages: 1000,
        header: (context) => pw.Text(
          title,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          ..._paragraphWidgets(content),
        ],
      ),
    );

    final bytes = await doc.save();
    final fileName = '${_safeFileName(title)}.pdf';

    if (kIsWeb) {
      downloadBytes(bytes, fileName, 'application/pdf');
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: title);
  }

  /// Builds the shared [pw.Document] used by every "AI Generated Report"
  /// action below (PDF export, print, e-mail, download) so they always
  /// produce byte-identical output.
  static pw.Document _buildReportPdf({
    required String title,
    required String content,
  }) {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        maxPages: 1000,
        header: (context) => pw.Text(
          title,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          ..._paragraphWidgets(content),
        ],
      ),
    );
    return doc;
  }

  /// Renders an AI-generated report (summary / key points / timeline / …)
  /// to PDF and saves it to app storage, WITHOUT opening the share sheet.
  /// Used by the "Download" toolbar action. On web this just triggers a
  /// browser download — there's no app storage to save into and nothing
  /// meaningful to return, so the "file" return type doesn't apply there.
  static Future<File?> saveReportPdf({
    required String title,
    required String content,
  }) async {
    final doc = _buildReportPdf(title: title, content: content);
    final bytes = await doc.save();
    final fileName = '${_safeFileName(title)}.pdf';

    if (kIsWeb) {
      downloadBytes(bytes, fileName, 'application/pdf');
      return null;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Renders an AI-generated report to PDF and opens the share/save sheet
  /// (mobile/desktop) or triggers a download (web). Used by the "PDF"
  /// toolbar action.
  static Future<void> exportReportToPdf({
    required String title,
    required String content,
  }) async {
    final file = await saveReportPdf(title: title, content: content);
    if (file == null) return; // web: saveReportPdf already downloaded it
    await Share.shareXFiles([XFile(file.path)], text: title);
  }

  /// Opens the native print dialog (or "Save as PDF" on desktop/web) for
  /// an AI-generated report. Used by the "Print" toolbar action.
  static Future<void> printReport({
    required String title,
    required String content,
  }) async {
    final doc = _buildReportPdf(title: title, content: content);
    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: '${_safeFileName(title)}.pdf',
    );
  }

  /// Shares an AI-generated report as a PDF attachment through the native
  /// share sheet, pre-filled so the user can pick their mail app. Used by
  /// the "Email" toolbar action.
  static Future<void> emailReport({
    required String title,
    required String content,
  }) async {
    final file = await saveReportPdf(title: title, content: content);
    if (file == null) return; // web: saveReportPdf already downloaded it — no mail client to hand off to
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: title,
      text: 'Please find the attached report: $title',
    );
  }

  /// Renders an AI-generated report to a minimal .docx and opens the
  /// share/save sheet (or triggers a download on web). Used by the "DOCX"
  /// toolbar action.
  static Future<void> exportReportToDocx({
    required String title,
    required String content,
  }) => exportToDocx(title: title, content: content);

  static const _docxMimeType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  /// Generates a minimal, valid .docx (Word) file from [content] and
  /// saves/shares/downloads it depending on platform.
  ///
  /// A .docx is just a zip archive containing a few required XML parts —
  /// built here directly so no extra native dependency is needed.
  static Future<void> exportToDocx({
    required String title,
    required String content,
  }) async {
    final archive = Archive();

    void addText(String path, String text) {
      final bytes = Uint8List.fromList(utf8.encode(text));
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addText('[Content_Types].xml', _contentTypesXml);
    addText('_rels/.rels', _relsXml);
    addText('word/_rels/document.xml.rels', _documentRelsXml);
    addText('word/document.xml', _documentXml(title, content));

    final zipBytes = ZipEncoder().encode(archive);
    final fileName = '${_safeFileName(title)}.docx';

    if (kIsWeb) {
      downloadBytes(Uint8List.fromList(zipBytes!), fileName, _docxMimeType);
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(zipBytes!);
    await Share.shareXFiles([XFile(file.path)], text: title);
  }

  /// Writes [rows] (first row = header) as a CSV file and saves/shares/
  /// downloads it depending on platform.
  static Future<void> exportToCsv({
    required String title,
    required List<List<String>> rows,
  }) async {
    String esc(String v) {
      if (v.contains(',') || v.contains('"') || v.contains('\n')) {
        return '"${v.replaceAll('"', '""')}"';
      }
      return v;
    }

    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.writeln(row.map(esc).join(','));
    }

    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final fileName = '${_safeFileName(title)}.csv';

    if (kIsWeb) {
      downloadBytes(bytes, fileName, 'text/csv');
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: title);
  }

  static const _pptxMimeType =
      'application/vnd.openxmlformats-officedocument.presentationml.presentation';

  /// Generates a minimal, valid .pptx (PowerPoint) file with one slide per
  /// entry in [slides] — each slide has a heading and a list of bullet
  /// lines — and saves/shares/downloads it depending on platform.
  ///
  /// Like [exportToDocx], a .pptx is just a zip of a few required XML
  /// parts, built directly here so no extra native dependency is needed.
  static Future<void> exportToPptx({
    required String title,
    required List<PptxSlide> slides,
  }) async {
    final archive = Archive();

    void addText(String path, String text) {
      final bytes = Uint8List.fromList(utf8.encode(text));
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addText('[Content_Types].xml', _pptxContentTypesXml(slides.length));
    addText('_rels/.rels', _pptxRelsXml);
    addText('ppt/presentation.xml', _pptxPresentationXml(slides.length));
    addText('ppt/_rels/presentation.xml.rels', _pptxPresentationRelsXml(slides.length));
    for (var i = 0; i < slides.length; i++) {
      addText('ppt/slides/slide${i + 1}.xml', _pptxSlideXml(slides[i]));
      addText('ppt/slides/_rels/slide${i + 1}.xml.rels', _pptxSlideRelsXml);
    }

    final zipBytes = ZipEncoder().encode(archive);
    final fileName = '${_safeFileName(title)}.pptx';

    if (kIsWeb) {
      downloadBytes(Uint8List.fromList(zipBytes!), fileName, _pptxMimeType);
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(zipBytes!);
    await Share.shareXFiles([XFile(file.path)], text: title);
  }

  static String _pptxContentTypesXml(int slideCount) {
    final overrides = List.generate(slideCount, (i) =>
        '<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>')
        .join();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  $overrides
</Types>''';
  }

  static const _pptxRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''';

  static String _pptxPresentationXml(int slideCount) {
    final sldIdLst = List.generate(slideCount, (i) =>
        '<p:sldId id="${256 + i}" r:id="rId${i + 1}"/>').join();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldIdLst>$sldIdLst</p:sldIdLst>
  <p:sldSz cx="9144000" cy="6858000"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>''';
  }

  static String _pptxPresentationRelsXml(int slideCount) {
    final rels = List.generate(slideCount, (i) =>
        '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>')
        .join();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>''';
  }

  static const _pptxSlideRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>''';

  static String _pptxSlideXml(PptxSlide slide) {
    final bulletParas = slide.bullets.map((b) => '''
        <a:p><a:r><a:rPr lang="en-US" sz="2000" dirty="0"/><a:t>${_escapeXml(b)}</a:t></a:r></a:p>''').join();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="457200" y="274638"/><a:ext cx="8229600" cy="1143000"/></a:xfrm>
        </p:spPr>
        <p:txBody>
          <a:bodyPr/><a:lstStyle/>
          <a:p><a:r><a:rPr lang="en-US" sz="3200" b="1" dirty="0"/><a:t>${_escapeXml(slide.title)}</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="3" name="Body"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="457200" y="1600200"/><a:ext cx="8229600" cy="4800600"/></a:xfrm>
        </p:spPr>
        <p:txBody>
          <a:bodyPr/><a:lstStyle/>$bulletParas
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:overrideClrMapping bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/></p:clrMapOvr>
</p:sld>''';
  }

  // ── Minimal OOXML parts ─────────────────────────────────────────────────

  static const _contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

  static const _relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  static const _documentRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>''';

  static String _escapeXml(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _documentXml(String title, String content) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buffer.writeln(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
    buffer.writeln('<w:body>');

    // Title paragraph (bold)
    buffer.writeln('<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
        '<w:r><w:rPr><w:b/><w:sz w:val="28"/></w:rPr>'
        '<w:t xml:space="preserve">${_escapeXml(title)}</w:t></w:r></w:p>');
    buffer.writeln('<w:p/>');

    // Body paragraphs — one <w:p> per line, preserving blank lines.
    for (final line in content.split('\n')) {
      buffer.writeln('<w:p><w:r><w:t xml:space="preserve">'
          '${_escapeXml(line)}</w:t></w:r></w:p>');
    }

    buffer.writeln('<w:sectPr/>');
    buffer.writeln('</w:body>');
    buffer.writeln('</w:document>');
    return buffer.toString();
  }
}