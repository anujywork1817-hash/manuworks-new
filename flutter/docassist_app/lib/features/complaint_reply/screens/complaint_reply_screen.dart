import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/services/ai_history_service.dart';
import '../../../shared/widgets/feature_history_sheet.dart';

class ComplaintReplyScreen extends ConsumerStatefulWidget {
  const ComplaintReplyScreen({super.key});

  @override
  ConsumerState<ComplaintReplyScreen> createState() =>
      _ComplaintReplyScreenState();
}

class _ComplaintReplyScreenState extends ConsumerState<ComplaintReplyScreen> {
  PlatformFile? _complaintFile;
  PlatformFile? _replyFile;
  bool _generating = false;
  bool _downloading = false;
  bool _downloadingPdf = false;

  String? _replyText;
  List<String> _modifiedSections = [];
  String? _summary;
  String? _error;

  late TextEditingController _editCtrl;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickComplaintPDF() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      // Web has no file paths, so we must read the bytes to be able to upload.
      // Mobile keeps path-based access to avoid loading large scans into memory.
      withData: kIsWeb,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() { _complaintFile = result.files.first; _error = null; });
    }
  }

  Future<void> _pickReplyDOCX() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
      withData: kIsWeb,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() { _replyFile = result.files.first; _error = null; });
    }
  }

  /// Builds a Dio upload part from a picked file. Uses the in-memory bytes when
  /// available (web) and falls back to the file path (mobile/desktop).
  Future<MultipartFile> _toMultipart(PlatformFile f) async {
    if (f.bytes != null) {
      return MultipartFile.fromBytes(f.bytes!, filename: f.name);
    }
    return MultipartFile.fromFile(f.path!, filename: f.name);
  }

  bool _isUsable(PlatformFile f) => f.bytes != null || f.path != null;

  // Status message shown under the spinner while OCR / AI generation runs.
  String _statusMsg = 'Uploading files…';

  Future<void> _generate() async {
    if (_complaintFile == null || _replyFile == null) return;
    if (!_isUsable(_complaintFile!) || !_isUsable(_replyFile!)) {
      setState(() => _error = 'Cannot access the selected file. Please pick it again.');
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
      _replyText = null;
      _statusMsg = 'Uploading files…';
    });

    try {
      // ── Step 1: Upload files and start the async job ────────────────────────
      final formData = FormData.fromMap({
        'complaint_pdf': await _toMultipart(_complaintFile!),
        'reply_docx': await _toMultipart(_replyFile!),
      });

      final startResponse = await DioClient.instance.post(
        '/ai/complaint-reply',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      final startBody = startResponse.data as Map<String, dynamic>;
      final jobId = (startBody['data'] as Map<String, dynamic>?)?['job_id'] as String?;
      if (jobId == null) throw Exception('Server did not return a job_id');

      if (mounted) setState(() => _statusMsg = 'Reading PDF… this may take a minute for scanned documents');

      // ── Step 2: Poll until the job finishes ─────────────────────────────────
      const maxWait = Duration(minutes: 8);
      final deadline = DateTime.now().add(maxWait);

      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(seconds: 4));
        if (!mounted) return;

        final statusResponse = await DioClient.instance.get(
          '/ai/complaint-reply/status/$jobId',
        );
        final statusBody = statusResponse.data as Map<String, dynamic>;
        final msg = statusBody['message'] as String? ?? '';

        if (msg == 'completed') {
          final data = statusBody['data'] as Map<String, dynamic>;
          final replyText = (data['reply_text'] as String?) ?? '';
          final sections = (data['modified_sections'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .where((s) => s.isNotEmpty)
                  .toList() ??
              [];
          final summary = (data['summary'] as String?) ?? '';

          if (mounted) {
            setState(() {
              _replyText = replyText;
              _modifiedSections = sections;
              _summary = summary;
              _editCtrl.text = replyText;
              _generating = false;
            });
          }
          try {
            await AiHistoryService.save(
              featureId: 'complaint_reply',
              title: 'Complaint Reply · ${_complaintFile?.name ?? ''}',
              subtitle: summary,
              content: replyText,
            );
          } catch (_) {}
          return;
        }

        if (!(statusBody['success'] as bool? ?? true)) {
          throw Exception(msg.isNotEmpty ? msg : 'Generation failed');
        }

        // Still processing — update the status message periodically.
        if (mounted) {
          setState(() {
            _statusMsg = msg == 'processing'
                ? 'Generating reply… please wait'
                : 'Processing…';
          });
        }
      }

      throw Exception('Timed out waiting for reply generation. Please try again.');
    } catch (e) {
      if (mounted) {
        setState(() {
          final msg = e.toString();
          _error = msg.contains('Daily AI') || msg.contains('daily quota') || msg.contains('temporarily unavailable')
              ? 'AI service is temporarily busy. Please try again in a few hours.'
              : msg.contains('Exception:')
                  ? msg.replaceFirst('Exception: ', '')
                  : 'Generation failed: $msg';
          _generating = false;
        });
      }
    }
  }

  Future<void> _downloadDocx() async {
    final text = _editCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _downloading = true);
    try {
      final response = await DioClient.instance.post(
        '/ai/complaint-reply/download',
        data: {'text': text, 'filename': 'complaint_reply.docx'},
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data as List<int>;
      final Directory dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!dir.existsSync()) await dir.create(recursive: true);
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/complaint_reply_$ts.docx');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('DOCX saved and opened'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Download failed: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _downloadPdf() async {
    final text = _editCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _downloadingPdf = true);
    try {
      final response = await DioClient.instance.post(
        '/ai/complaint-reply/download-pdf',
        data: {'text': text, 'filename': 'complaint_reply.pdf'},
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data as List<int>;
      final Directory dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!dir.existsSync()) await dir.create(recursive: true);
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/complaint_reply_$ts.pdf');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('PDF saved and opened'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF download failed: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _downloadingPdf = false);
    }
  }

  void _reset() => setState(() {
        _replyText = null;
        _modifiedSections = [];
        _summary = null;
        _complaintFile = null;
        _replyFile = null;
        _error = null;
        _editCtrl.clear();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: BackButton(
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Complaint Reply Generator',
          style: TextStyle(
              fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            tooltip: 'Complaint reply history',
            icon: const Icon(Icons.history_rounded, color: AppColors.textPrimary),
            onPressed: () => showFeatureHistorySheet(
                context, featureId: 'complaint_reply', featureLabel: 'Complaint Reply'),
          ),
          if (_replyText != null)
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('New'),
            ),
        ],
      ),
      body: _replyText != null ? _buildResult() : _buildForm(),
    );
  }

  // ── Form view ─────────────────────────────────────────────────────────────────

  Widget _buildForm() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.infoContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: AppColors.info, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Upload the complaint PDF and an existing reply DOCX template. AI will generate a new reply adapting the template to the new complaint.',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.info, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Step 1
          _stepLabel('1', 'Upload Complaint PDF'),
          const SizedBox(height: 8),
          _fileCard(
            file: _complaintFile,
            hint: 'Tap to select the complaint PDF',
            icon: Icons.picture_as_pdf_outlined,
            accentColor: AppColors.error,
            onTap: _pickComplaintPDF,
          ),
          const SizedBox(height: 16),

          // Step 2
          _stepLabel('2', 'Upload Existing Reply Template (.docx)'),
          const SizedBox(height: 8),
          _fileCard(
            file: _replyFile,
            hint: 'Tap to select the existing reply Word document',
            icon: Icons.description_outlined,
            accentColor: AppColors.info,
            onTap: _pickReplyDOCX,
          ),
          const SizedBox(height: 24),

          // Error
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 13))),
              ]),
            ),

          // Generate button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_complaintFile != null &&
                      _replyFile != null &&
                      !_generating)
                  ? _generate
                  : null,
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.surface))
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                  _generating ? _statusMsg : 'Generate Complaint Reply'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      );

  // ── Result view ───────────────────────────────────────────────────────────────

  Widget _buildResult() => Column(children: [
        // Action toolbar
        Container(
          color: AppColors.surface,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const Expanded(
              child: Text('Generated Reply',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _editCtrl.text));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                ));
              },
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Copy'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _downloading ? null : _downloadDocx,
              icon: _downloading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.surface))
                  : const Icon(Icons.description_outlined, size: 15),
              label: const Text('DOCX'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _downloadingPdf ? null : _downloadPdf,
              icon: _downloadingPdf
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.surface))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 15),
              label: const Text('PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ]),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Summary card
              if (_summary != null && _summary!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.successContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.check_circle_outline,
                              color: AppColors.success, size: 15),
                          SizedBox(width: 6),
                          Text('Reply Generated',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success)),
                        ]),
                        const SizedBox(height: 6),
                        Text(_summary!,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.success,
                                height: 1.4)),
                      ]),
                ),
                const SizedBox(height: 14),
              ],

              // Modified sections chips
              if (_modifiedSections.isNotEmpty) ...[
                const Text('Modified Sections',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _modifiedSections
                      .map((s) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.warningContainer,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppColors.warning
                                      .withValues(alpha: 0.35)),
                            ),
                            child: Text(s,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w500)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Editable reply text
              const Text('Reply Text (Editable)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.outline),
                  boxShadow: AppShadows.sm,
                ),
                child: TextField(
                  controller: _editCtrl,
                  maxLines: null,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.7,
                    color: AppColors.primaryLight,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ]);

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _stepLabel(String number, String label) => Row(children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(number,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textOnPrimary)),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ]);

  Widget _fileCard({
    required PlatformFile? file,
    required String hint,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: file != null
                ? accentColor.withValues(alpha: 0.06)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: file != null
                  ? accentColor.withValues(alpha: 0.45)
                  : AppColors.outline,
              width: file != null ? 1.5 : 1,
            ),
          ),
          child: file != null
              ? Row(children: [
                  Icon(icon, color: accentColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(file.name,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: accentColor)),
                        if (file.size > 0)
                          Text(
                              '${(file.size / 1024).toStringAsFixed(1)} KB',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary)),
                      ])),
                  Icon(Icons.check_circle_rounded,
                      color: accentColor, size: 20),
                ])
              : Row(children: [
                  const Icon(Icons.upload_outlined,
                      color: AppColors.textTertiary, size: 22),
                  const SizedBox(width: 12),
                  Text(hint,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ]),
        ),
      );
}