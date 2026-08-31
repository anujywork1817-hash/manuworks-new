import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/ai_history_service.dart';
import '../../../shared/widgets/feature_history_sheet.dart';

class OcrScanScreen extends StatefulWidget {
  const OcrScanScreen({super.key});

  @override
  State<OcrScanScreen> createState() => _OcrScanScreenState();
}

class _OcrScanScreenState extends State<OcrScanScreen> {
  PlatformFile? _image;
  bool _isPdf = false; // true when the picked file is a PDF/DOCX rather than an image
  bool _scanning = false;
  String? _text;      // AI-generated summary shown to the user (clean, readable)
  int _wordCount = 0;
  int _pageCount = 0;
  double _confidence = 0;
  String? _error;
  final String _language = 'en'; // language auto-detection handled server-side

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
      withData: true, // required on mobile/desktop to get bytes for web-style upload; web always includes bytes
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final ext = file.extension?.toLowerCase() ?? '';
    setState(() {
      _image = file;
      _isPdf = ext == 'pdf' || ext == 'doc' || ext == 'docx';
      _text = null;
      _error = null;
    });
  }

  Future<void> _extract() async {
    if (_image == null) return;
    setState(() { _scanning = true; _error = null; _text = null; });

    try {
      final multipartFile = _image!.bytes != null
          ? MultipartFile.fromBytes(_image!.bytes!, filename: _image!.name)
          : await MultipartFile.fromFile(_image!.path!, filename: _image!.name);

      final formData = FormData.fromMap({
        'file': multipartFile,
        'language': _language,
      });

      final response = await DioClient.uploadFile('/ocr/scan', formData);
      final body = response.data as Map<String, dynamic>;
      if (body['success'] != true) {
        throw ApiException(message: body['message'] ?? 'OCR failed');
      }
      final data = body['data'] as Map<String, dynamic>;

      final rawText = (data['text'] as String?) ?? '';
      final summary = (data['summary'] as String?) ?? '';

      if (mounted) {
        setState(() {
          // Show the AI-cleaned summary when we have one; only fall back to
          // raw (often garbled) OCR text if summarization wasn't available.
          _text = summary.trim().isNotEmpty ? summary.trim() : rawText;
          _wordCount = (data['word_count'] as num?)?.toInt() ?? 0;
          _pageCount = (data['page_count'] as num?)?.toInt() ?? 1;
          _confidence = (data['confidence'] as num?)?.toDouble() ?? 0;
          _scanning = false;
        });
      }
      try {
        await AiHistoryService.save(
          featureId: 'ocr',
          title: 'OCR Scan · ${DateTime.now().toString().split('.').first}',
          subtitle: '$_pageCount page(s), ${(_confidence).toStringAsFixed(0)}% confidence',
          content: _text ?? '',
        );
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Extraction failed: ${e.toString()}';
          _scanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      appBar: AppBar(
        
        elevation: 0,
        leading: BackButton(
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('OCR Scanner',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'OCR history',
            icon: const Icon(Icons.history_rounded, color: AppColors.textPrimary),
            onPressed: () => showFeatureHistorySheet(
                context, featureId: 'ocr', featureLabel: 'OCR Scanner'),
          ),
          if (_text != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _text = null; _image = null; _isPdf = false;
              }),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('New Scan'),
            ),
        ],
      ),
      body: _text != null ? _buildResult() : _buildScanView(),
    );
  }

  Widget _buildScanView() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('OCR Scanner',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
              color: AppColors.textPrimary)),
      const SizedBox(height: 6),
      const Text('Convert scanned documents and images into editable, searchable text',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 20),

      // Upload box — same style/flow as every other AI tool's document picker.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _image != null ? AppColors.primary : AppColors.outline,
            width: _image != null ? 1.5 : 1,
          ),
          boxShadow: AppShadows.sm,
        ),
        child: Column(children: [
          if (_image == null) ...[
            const Icon(Icons.cloud_upload_outlined, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            const Text('Choose a file, drag and drop, or paste',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            const Text('Supports JPG, PNG, PDF, DOCX',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textDisabled)),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Browse'),
            ),
          ] else ...[
            Icon(
              _isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
              size: 40, color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(_image!.name,
                maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('Ready to extract', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() {
                _image = null; _isPdf = false; _text = null; _error = null;
              }),
              child: const Text('Change file'),
            ),
          ],
        ]),
      ),

      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.errorContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13))),
          ]),
        ),
      ],

      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_image == null || _scanning) ? null : _extract,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _scanning
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Submit'),
        ),
      ),
      const SizedBox(height: 24),
    ]),
  );

  Widget _buildResult() => Column(children: [
    // Stats bar
    Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        _stat('Words', '$_wordCount', AppColors.secondary),
        _statDivider(),
        _stat('Pages', '$_pageCount', AppColors.info),
        _statDivider(),
        _stat('Confidence', '${_confidence.toStringAsFixed(0)}%',
            _confidence >= 80 ? AppColors.success : AppColors.warning),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _text!));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Text copied to clipboard'),
              behavior: SnackBarBehavior.floating,
            ));
          },
          icon: const Icon(Icons.copy, size: 15),
          label: const Text('Copy'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ]),
    ),

    // Extracted text
    Expanded(child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8, left: 4),
          child: Text('AI Summary',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary, letterSpacing: 0.4)),
        ),
        Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppShadows.sm,
        ),
        child: _text!.isEmpty
            ? const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No text could be extracted from this image.\n'
                    'Try a clearer image with better lighting.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 14)),
              ))
            : SelectableText(_text!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.75,
                  color: AppColors.primaryLight,
                )),
        ),
      ]),
    )),
  ]);

  Widget _stat(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
    ],
  );

  Widget _statDivider() => Container(
    height: 28, width: 1,
    margin: const EdgeInsets.symmetric(horizontal: 14),
    color: AppColors.outline,
  );
}