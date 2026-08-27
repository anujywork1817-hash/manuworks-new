import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/services/usage_tracker.dart';
import '../../../core/services/ai_history_service.dart';
import '../../../core/services/document_export_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/fun_loading_word.dart';
import '../../../core/network/dio_client.dart';
import '../../documents/providers/document_provider.dart';
import '../../ai_chat/providers/ai_provider.dart';
import '../../../shared/widgets/feature_history_sheet.dart';

/// Title + one-line subtitle shown at the top of each AI feature screen,
/// mirroring the "Generate Summary — Summarize documents in seconds and
/// gain insights faster" pattern.
const Map<String, List<String>> kAiFeatureCopy = {
  'summarize': ['Generate Summary', 'Summarize documents in seconds and gain insights faster'],
  'keypoints': ['Extract Key Points', 'Pull out the most important points from any document instantly'],
  'timeline': ['Build a Timeline', 'Turn case events into a clear chronological timeline'],
  'actions': ['Extract Action Items', 'Identify tasks and next steps hiding in your documents'],
  'analyze': ['Analyze Document', 'Get a deep AI analysis of your document in seconds'],
  'translate': ['Translate Document', 'Translate your document into the language you need'],
  'citations': ['Extract Citations', 'Find every legal citation referenced in your document'],
  'risks': ['Scan for Risks', 'Spot risky clauses and red flags before they become a problem'],
  'deadlines': ['Extract Deadlines', 'Never miss a date — pull out every deadline automatically'],
  'autotags': ['Auto-Tag Document', 'Automatically tag and categorize your document'],
  'grammar': ['Check Grammar', 'Catch grammar and drafting issues before you file'],
};

/// Icon + label lookup for every AI feature, shared with the AiFeaturesScreen
/// grid so both stay in sync.
class AiFeatureInfo {
  final String id;
  final IconData icon;
  final String label;
  const AiFeatureInfo(this.id, this.icon, this.label);
}

const kAiFeatures = [
  AiFeatureInfo('summarize', Icons.summarize_outlined, 'Summarize'),
  AiFeatureInfo('keypoints', Icons.list_outlined, 'Key Points'),
  AiFeatureInfo('timeline', Icons.timeline_outlined, 'Timeline'),
  AiFeatureInfo('actions', Icons.task_alt_outlined, 'Actions'),
  AiFeatureInfo('analyze', Icons.analytics_outlined, 'Analyze'),
  AiFeatureInfo('translate', Icons.translate_outlined, 'Translate'),
  AiFeatureInfo('citations', Icons.gavel_outlined, 'Citations'),
  AiFeatureInfo('risks', Icons.warning_amber_outlined, 'Risk Scan'),
  AiFeatureInfo('deadlines', Icons.event_outlined, 'Deadlines'),
  AiFeatureInfo('autotags', Icons.label_outlined, 'Auto-Tags'),
  AiFeatureInfo('grammar', Icons.spellcheck_outlined, 'Grammar'),
];

/// A screen dedicated to ONE AI feature (e.g. just "Summarize").
/// It shows that feature's own heading, lets the user pick an existing
/// document or upload a new one, then runs that specific feature and
/// shows the result.
class AiFeatureDetailScreen extends ConsumerStatefulWidget {
  final String featureId;
  const AiFeatureDetailScreen({super.key, required this.featureId});

  @override
  ConsumerState<AiFeatureDetailScreen> createState() => _AiFeatureDetailScreenState();
}

class _AiFeatureDetailScreenState extends ConsumerState<AiFeatureDetailScreen> {
  Document? _selectedDoc;
  bool _running = false;
  String? _result;
  String? _error;

  AiFeatureInfo get _feature =>
      kAiFeatures.firstWhere((f) => f.id == widget.featureId,
          orElse: () => kAiFeatures.first);

  // ── Persisted result storage ────────────────────────────────────────────
  // Key includes both the feature and the document id, so each doc keeps
  // its own saved result per feature (e.g. Summarize result for doc A is
  // separate from the Summarize result for doc B).
  String _resultKey(String docId) => 'ai_result_${_feature.id}_$docId';

  Future<void> _saveResult(String docId, String result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_resultKey(docId), result);
  }

  Future<String?> _loadSavedResult(String docId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_resultKey(docId));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(documentProvider.notifier).loadDocuments();
    });
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf', 'docx', 'doc', 'txt'],
      withData: true, // required on mobile/desktop to get bytes for web-style upload; web always includes bytes
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final success =
        await ref.read(documentProvider.notifier).uploadPlatformFile(file);
    if (!mounted) return;
    if (success) {
      final docs = ref.read(documentProvider).documents;
      if (docs.isNotEmpty) {
        setState(() => _selectedDoc = docs.first);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${file.name} uploaded! Processing...')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _processThenRun(Document doc) async {
    setState(() { _running = true; _error = null; _result = null; });
    try {
      // Only kick off processing on the backend if it isn't already
      // running — calling /process again on a doc that's mid-OCR just
      // restarts the job, which is why big files never finished ("Still
      // processing" after retrying was actually retriggering from zero
      // every time).
      if (doc.status != 'processing') {
        await ref.read(aiProvider.notifier).processDocument(doc.id);
      }
      final current = await _pollUntilReady(doc);
      if (!mounted) return;
      if (current.isProcessed || current.status == 'ready') {
        setState(() => _selectedDoc = current);
        // Refresh the cached list once, in the background, so it's up to
        // date next time the picker/repository sheet opens.
        unawaited(ref.read(documentProvider.notifier).loadDocuments());
        await _runFeature(current);
      } else {
        setState(() {
          _running = false;
          _selectedDoc = current; // remember status='processing' so retry doesn't restart it
          _error = 'Still processing large document — this can take a few minutes for '
              'long or scanned files. Tap Submit to keep checking.';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _running = false; _error = 'Processing failed: $e'; });
    }
  }

  /// Polls a single document's status instead of reloading the entire
  /// (potentially large) documents list every few seconds — fetching
  /// everyone's full OCR text repeatedly is what was making this screen
  /// feel stuck on "loading" for big files.
  ///
  /// Waits up to ~6 minutes total, backing off from a 2s to an 8s
  /// interval, so large / scanned PDFs have realistic time to finish OCR
  /// instead of failing after a fixed 80-second window.
  Future<Document> _pollUntilReady(Document doc) async {
    Document current = doc;
    const totalAttempts = 80;
    for (int i = 0; i < totalAttempts; i++) {
      final delay = i < 20
          ? const Duration(seconds: 2)
          : i < 50
              ? const Duration(seconds: 5)
              : const Duration(seconds: 8);
      await Future.delayed(delay);
      try {
        final res = await DioClient.get('/documents/${doc.id}');
        current = Document.fromJson(res['data']);
      } catch (_) {
        continue; // transient network hiccup — just try again next tick
      }
      if (current.isProcessed || current.status == 'ready') break;
      if (current.status == 'failed') {
        throw Exception('Processing failed');
      }
    }
    return current;
  }

  Future<String?> _pickLanguage() async {
    const languages = [
      'Hindi', 'Marathi', 'Tamil', 'Telugu', 'Bengali', 'Gujarati', 'Kannada',
      'Malayalam', 'Punjabi', 'Urdu', 'English', 'Spanish', 'French', 'German',
      'Arabic', 'Chinese',
    ];
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Translate to', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: languages.map((l) => ListTile(
                title: Text(l),
                onTap: () => Navigator.pop(context, l),
              )).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Future<void> _runFeature(Document doc) async {
    if (_feature.id == 'translate') {
      final lang = await _pickLanguage();
      if (lang == null) { setState(() => _running = false); return; }
      setState(() { _running = true; _error = null; _result = null; });
      try {
        final result =
            await ref.read(aiProvider.notifier).translateDocument(doc.id, lang);
        await _saveResult(doc.id, result);
        await AiHistoryService.save(
          featureId: _feature.id,
          title: '${_feature.label} · ${doc.title}',
          subtitle: doc.title,
          content: result,
        );
        await UsageTracker.logUsage(_feature.id);
        if (mounted) setState(() { _result = result; _running = false; });
      } catch (e) {
        if (mounted) setState(() { _error = _friendlyError(e); _running = false; });
      }
      return;
    }

    setState(() { _running = true; _error = null; _result = null; });
    try {
      final notifier = ref.read(aiProvider.notifier);
      String result;
      switch (_feature.id) {
        case 'summarize': result = await notifier.summarize(doc.id); break;
        case 'keypoints': result = await notifier.extractKeyPoints(doc.id); break;
        case 'timeline': result = await notifier.extractTimeline(doc.id); break;
        case 'actions': result = await notifier.extractActionItems(doc.id); break;
        case 'analyze': result = await notifier.analyzeDocument(doc.id); break;
        case 'citations': result = await notifier.extractCitations(doc.id); break;
        case 'risks': result = await notifier.scanRisks(doc.id); break;
        case 'deadlines': result = await notifier.extractDeadlines(doc.id); break;
        case 'autotags': result = await notifier.autoTag(doc.id); break;
        case 'grammar': result = await notifier.checkGrammar(doc.id); break;
        default: result = '';
      }
      // Guard against a technically-successful call that came back empty —
      // never leave the screen silently blank.
      if (result.trim().isEmpty) {
        throw Exception('The AI did not return any content. Please try again.');
      }
      await _saveResult(doc.id, result);
      await AiHistoryService.save(
        featureId: _feature.id,
        title: '${_feature.label} · ${doc.title}',
        subtitle: doc.title,
        content: result,
      );
      await UsageTracker.logUsage(_feature.id);
      if (mounted) setState(() { _result = result; _running = false; });
    } catch (e) {
      if (mounted) setState(() { _error = _friendlyError(e); _running = false; });
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    return msg.isEmpty ? 'Something went wrong. Please try again.' : msg;
  }

  // ── Report toolbar actions (PDF / Print / Email / Download) ─────────────

  String get _reportTitle =>
      '${_feature.label} - ${_selectedDoc?.title ?? 'Report'}';

  Future<void> _handleReportAction(
    Future<void> Function() action, {
    required String busyMessage,
    required String doneMessage,
  }) async {
    if (_result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(busyMessage), duration: const Duration(seconds: 2)),
    );
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(doneMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _exportPdf() => _handleReportAction(
        () => DocumentExportService.exportReportToPdf(
            title: _reportTitle, content: _result!),
        busyMessage: 'Preparing PDF...',
        doneMessage: 'PDF ready to save or share',
      );

  Future<void> _printReport() => _handleReportAction(
        () => DocumentExportService.printReport(
            title: _reportTitle, content: _result!),
        busyMessage: 'Opening print dialog...',
        doneMessage: 'Sent to print',
      );

  Future<void> _emailReport() => _handleReportAction(
        () => DocumentExportService.emailReport(
            title: _reportTitle, content: _result!),
        busyMessage: 'Preparing email...',
        doneMessage: 'Choose your mail app to send',
      );

  Future<void> _exportDocx() => _handleReportAction(
        () => DocumentExportService.exportReportToDocx(
            title: _reportTitle, content: _result!),
        busyMessage: 'Preparing Word file...',
        doneMessage: 'DOCX ready to save or share',
      );

  Future<void> _downloadReport() => _handleReportAction(
        () async {
          final file = await DocumentExportService.saveReportPdf(
              title: _reportTitle, content: _result!);
          _downloadedPath = file?.path;
        },
        busyMessage: 'Downloading...',
        doneMessage: 'Saved to app documents folder',
      );

  String? _downloadedPath;

  List<String> get _copy => kAiFeatureCopy[_feature.id] ?? [_feature.label, ''];

  Future<void> _chooseFromRepository() async {
    final docsState = ref.read(documentProvider);
    final doc = await showModalBottomSheet<Document>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Choose from Repository',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          if (docsState.documents.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No documents yet. Upload one instead.'),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: docsState.documents.map((doc) => ListTile(
                  leading: Text(doc.iconForType, style: const TextStyle(fontSize: 22)),
                  title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(doc.isProcessed || doc.status == 'ready'
                      ? 'AI ready' : 'Not processed yet'),
                  onTap: () => Navigator.pop(context, doc),
                )).toList(),
              ),
            ),
          const SizedBox(height: 16),
        ]),
      ),
    );
    if (doc != null) {
      setState(() { _selectedDoc = doc; _result = null; _error = null; });
    }
  }

  void _submit() {
    if (_selectedDoc == null) return;
    final doc = _selectedDoc!;
    if (doc.isProcessed || doc.status == 'ready') {
      _runFeature(doc);
    } else {
      _processThenRun(doc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docsState = ref.watch(documentProvider);
    final title = _copy[0];
    final subtitle = _copy.length > 1 ? _copy[1] : '';

    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_feature.icon, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          Text(_feature.label),
        ]),
        actions: [
          if (_result != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _result = null; _error = null; _selectedDoc = null;
              }),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('New'),
            ),
          IconButton(
            tooltip: '${_feature.label} history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => showFeatureHistorySheet(
                context, featureId: _feature.id, featureLabel: _feature.label),
          ),
        ],
      ),
      body: SafeArea(
        child: _result != null
            ? _buildResultView(theme)
            : _buildUploadView(theme, docsState, title, subtitle),
      ),
    );
  }

  // ── Upload / submit view ("Generate Summary" style) ─────────────────────────

  Widget _buildUploadView(ThemeData theme, DocumentsState docsState,
      String title, String subtitle) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        if (subtitle.isNotEmpty)
          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 20),

        if (docsState.isUploading) ...[
          LinearProgressIndicator(value: docsState.uploadProgress),
          const SizedBox(height: AppSpacing.md),
        ],

        // Upload box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _selectedDoc != null ? AppColors.primary : AppColors.outline,
              width: _selectedDoc != null ? 1.5 : 1,
            ),
            boxShadow: AppShadows.sm,
          ),
          child: Column(children: [
            if (_selectedDoc == null) ...[
              const Icon(Icons.cloud_upload_outlined, size: 40, color: AppColors.textTertiary),
              const SizedBox(height: 12),
              const Text('Choose a file, drag and drop, or paste',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 18),
              Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                OutlinedButton.icon(
                  onPressed: _pickAndUpload,
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  label: const Text('Browse'),
                ),
                OutlinedButton.icon(
                  onPressed: _chooseFromRepository,
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: const Text('Choose from Repository'),
                ),
              ]),
            ] else ...[
              const Icon(Icons.description_outlined, size: 40, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(_selectedDoc!.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                _selectedDoc!.isProcessed || _selectedDoc!.status == 'ready'
                    ? 'AI ready' : 'Will be processed on submit',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _selectedDoc = null; _result = null; _error = null;
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
              Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
            ]),
          ),
        ],

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_selectedDoc == null || _running) ? null : _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _running
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Submit'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Result view (doc preview + AI Generated Summary) ────────────────────────

  Widget _buildResultView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_feature.icon, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_copy[0],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary))),
        ]),
        const SizedBox(height: 12),

        // Source document card
        Card(
          child: ListTile(
            leading: Text(_selectedDoc?.iconForType ?? '📄', style: const TextStyle(fontSize: 22)),
            title: Text(_selectedDoc?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Source document'),
          ),
        ),
        const SizedBox(height: 16),

        if (_running)
          Card(child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(child: Column(children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              const FunLoadingWord(),
            ])),
          )),

        if (_error != null)
          Card(child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error))),
            ]),
          )),

        if (_result != null && !_running)
          Card(child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(_feature.icon, color: AppColors.accent, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('AI GENERATED ${_feature.label.toUpperCase()}',
                      style: theme.textTheme.labelMedium?.copyWith(color: AppColors.accent)),
                ),
              ]),
              const SizedBox(height: 4),
              // Report actions toolbar — PDF, Print, Email, DOCX, Download, Copy.
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  tooltip: 'Export as PDF',
                  onPressed: _exportPdf,
                ),
                IconButton(
                  icon: const Icon(Icons.print_outlined, size: 18),
                  tooltip: 'Print',
                  onPressed: _printReport,
                ),
                IconButton(
                  icon: const Icon(Icons.email_outlined, size: 18),
                  tooltip: 'Email',
                  onPressed: _emailReport,
                ),
                IconButton(
                  icon: const Icon(Icons.description_outlined, size: 18),
                  tooltip: 'Export as Word (DOCX)',
                  onPressed: _exportDocx,
                ),
                IconButton(
                  icon: const Icon(Icons.download_outlined, size: 18),
                  tooltip: 'Download',
                  onPressed: _downloadReport,
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy result',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _result!));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')));
                  },
                ),
              ]),
              const Divider(),
              MarkdownBody(
                data: _result!,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodyMedium,
                  h1: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  h2: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  strong: const TextStyle(fontWeight: FontWeight.bold),
                  listBullet: theme.textTheme.bodyMedium,
                ),
              ),
            ]),
          )),

        if (!_running)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              onPressed: () => _runFeature(_selectedDoc!),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Run again'),
            ),
          ),
      ]),
    );
  }
}