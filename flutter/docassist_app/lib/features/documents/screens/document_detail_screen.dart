import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/document_provider.dart';
import '../../ai_chat/providers/ai_provider.dart';
import '../../../core/services/usage_tracker.dart';
import 'edit_document_screen.dart';

class DocumentDetailScreen extends ConsumerStatefulWidget {
  final String documentId;
  const DocumentDetailScreen({super.key, required this.documentId});
  @override
  ConsumerState<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  String? _aiResult;
  String? _aiError;
  bool _aiLoading = false;
  String _activeFeature = '';
  bool _isProcessing = false;
  Timer? _pollTimer;
  int _pollCount = 0;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollCount = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      _pollCount++;
      // Stop after 3 minutes (60 polls)
      if (_pollCount > 60) {
        timer.cancel();
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
      // Refresh the document data
      ref.invalidate(singleDocumentProvider(widget.documentId));
      // Check status after refresh
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final docAsync = ref.read(singleDocumentProvider(widget.documentId));
      docAsync.whenData((doc) {
        if (doc.isProcessed || doc.status == 'ready' || doc.status == 'failed') {
          timer.cancel();
          if (mounted) setState(() => _isProcessing = false);
        }
      });
    });
  }

  Future<void> _processDocument() async {
    setState(() {
      _isProcessing = true;
      _aiError = null;
      _aiResult = null;
      _activeFeature = 'process';
    });
    try {
      final notifier = ref.read(aiProvider.notifier);
      await notifier.processDocument(widget.documentId);
      // Start polling for status updates
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _aiError = 'Processing failed: ${e.toString()}';
        });
      }
    }
  }

  Future<String?> _pickLanguage() async {
    const languages = [
      ('Hindi', '🇮🇳'),
      ('Marathi', '🇮🇳'),
      ('Tamil', '🇮🇳'),
      ('Telugu', '🇮🇳'),
      ('Bengali', '🇮🇳'),
      ('Gujarati', '🇮🇳'),
      ('Kannada', '🇮🇳'),
      ('Malayalam', '🇮🇳'),
      ('Punjabi', '🇮🇳'),
      ('Urdu', '🇮🇳'),
      ('English', '🇬🇧'),
      ('Spanish', '🇪🇸'),
      ('French', '🇫🇷'),
      ('German', '🇩🇪'),
      ('Arabic', '🇸🇦'),
      ('Chinese', '🇨🇳'),
    ];
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                leading: Text(l.$2, style: const TextStyle(fontSize: 22)),
                title: Text(l.$1),
                onTap: () => Navigator.pop(context, l.$1),
              )).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _runFeature(String feature) async {
    // Translate needs language selection first
    if (feature == 'translate') {
      final lang = await _pickLanguage();
      if (lang == null) return; // user cancelled
      _runTranslate(lang);
      return;
    }

    setState(() {
      _aiLoading = true;
      _aiError = null;
      _aiResult = null;
      _activeFeature = feature;
    });
    try {
      final notifier = ref.read(aiProvider.notifier);
      String result;
      switch (feature) {
        case 'summarize':
          result = await notifier.summarize(widget.documentId);
          break;
        case 'keypoints':
          result = await notifier.extractKeyPoints(widget.documentId);
          break;
        case 'timeline':
          result = await notifier.extractTimeline(widget.documentId);
          break;
        case 'actions':
          result = await notifier.extractActionItems(widget.documentId);
          break;
        case 'analyze':
          result = await notifier.analyzeDocument(widget.documentId);
          break;
        case 'citations':
          result = await notifier.extractCitations(widget.documentId);
          break;
        case 'risks':
          result = await notifier.scanRisks(widget.documentId);
          break;
        case 'deadlines':
          result = await notifier.extractDeadlines(widget.documentId);
          break;
        case 'autotags':
          result = await notifier.autoTag(widget.documentId);
          break;
        case 'grammar':
          result = await notifier.checkGrammar(widget.documentId);
          break;
        default:
          result = '';
      }
      if (mounted) setState(() { _aiResult = result; _aiLoading = false; });
      await UsageTracker.logUsage(feature);
    } catch (e) {
      if (mounted) setState(() { _aiError = _friendlyError(e.toString()); _aiLoading = false; });
    }
  }

  Future<void> _runTranslate(String language) async {
    setState(() {
      _aiLoading = true;
      _aiError = null;
      _aiResult = null;
      _activeFeature = 'translate';
    });
    try {
      final result = await ref.read(aiProvider.notifier).translateDocument(widget.documentId, language);
      if (mounted) setState(() { _aiResult = result; _aiLoading = false; });
      await UsageTracker.logUsage('translate');
    } catch (e) {
      if (mounted) setState(() { _aiError = _friendlyError(e.toString()); _aiLoading = false; });
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('Daily AI token limit') || raw.contains('tokens per day') || raw.contains('TPD')) {
      final match = RegExp(r'try again in ([^.]+)').firstMatch(raw);
      final wait = match?.group(1);
      return 'Daily AI limit reached.${wait != null ? ' Try again in $wait.' : ' Please try again later.'}';
    }
    if (raw.contains('Rate limit') || raw.contains('rate limit') || raw.contains('TPM')) {
      return 'AI is busy right now. Please wait a moment and try again.';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(singleDocumentProvider(widget.documentId));
    final theme = Theme.of(context);

    return Scaffold(
      
      appBar: AppBar(
        leading: const BackButton(),
        title: docAsync.when(
          data: (d) => Text(d.title, overflow: TextOverflow.ellipsis),
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Document'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit document',
            onPressed: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => EditDocumentScreen(documentId: widget.documentId),
                ),
              );
              if (updated == true) {
                ref.invalidate(singleDocumentProvider(widget.documentId));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat_outlined),
            onPressed: () => context.push('/documents/${widget.documentId}/chat'),
            tooltip: 'Chat with document',
          ),
        ],
      ),
      body: docAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')), // ignore: prefer_const_constructors
        data: (doc) {
          final isReady = doc.isProcessed || doc.status == 'ready';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

              // ── Info card ──────────────────────────────────────────────
              Card(child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: AppRadius.sm,
                      ),
                      child: Text(doc.fileType.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          )),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(doc.fileSizeHuman, style: theme.textTheme.bodySmall),
                    const Spacer(),
                    _StatusBadge(
                      isReady: isReady,
                      isProcessing: _isProcessing || doc.status == 'processing',
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  Text(doc.title, style: theme.textTheme.titleMedium),
                ]),
              )),
              const SizedBox(height: AppSpacing.md),

              // ── Processing state ───────────────────────────────────────
              if (_isProcessing || doc.status == 'processing') ...[
                Card(child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: AppSpacing.md),
                    const Text('Processing document with AI...'),
                    const SizedBox(height: 4),
                    Text('OCR + Embeddings · please wait',
                        style: theme.textTheme.bodySmall),
                  ]),
                )),
                const SizedBox(height: AppSpacing.md),
              ],

              // ── Process button (shown when not ready and not processing) ──
              if (!isReady && !_isProcessing && doc.status != 'processing')
                ElevatedButton.icon(
                  onPressed: _processDocument,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Process with AI (OCR + Embeddings)'),
                ),

              // ── AI Feature grid (shown when ready) ─────────────────────
              if (isReady) ...[
                Row(children: [
                  const Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
                  const SizedBox(width: 6),
                  Text('AI Features', style: theme.textTheme.titleMedium),
                ]),
                const SizedBox(height: AppSpacing.sm),
                _AIFeatureGrid(
                  onFeatureTap: _runFeature,
                  activeFeature: _activeFeature,
                  isLoading: _aiLoading,
                ),
                const SizedBox(height: AppSpacing.sm),
                // Re-process option
                TextButton.icon(
                  onPressed: _isProcessing ? null : _processDocument,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Re-process document'),
                ),
              ],

              const SizedBox(height: AppSpacing.md),

              // ── AI Result area ─────────────────────────────────────────
              if (_aiLoading)
                const Card(child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: Column(children: [
                    CircularProgressIndicator(),
                    SizedBox(height: AppSpacing.md),
                    Text('AI is thinking...'),
                  ])),
                )),

              if (_aiError != null)
                Card(child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_aiError!,
                        style: const TextStyle(color: AppColors.error))),
                  ]),
                )),

              if (_aiResult != null && !_aiLoading)
                Card(child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Text(_activeFeature.toUpperCase(),
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: AppColors.accent)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () {
                          // Copy to clipboard
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied to clipboard')));
                        },
                        tooltip: 'Copy result',
                      ),
                    ]),
                    const Divider(),
                    SelectableText(_aiResult!, style: theme.textTheme.bodyMedium),
                  ]),
                )),
            ]),
          );
        },
      ),
    );
  }
}

// ── Status Badge ────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final bool isReady;
  final bool isProcessing;
  const _StatusBadge({required this.isReady, required this.isProcessing});

  @override
  Widget build(BuildContext context) {
    if (isProcessing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: AppRadius.sm,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 10, height: 10,
            child: CircularProgressIndicator(strokeWidth: 2,
                color: Colors.blue.shade600),
          ),
          const SizedBox(width: 6),
          Text('Processing...', style: TextStyle(
              color: Colors.blue.shade600, fontSize: 12,
              fontWeight: FontWeight.w500)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isReady ? AppColors.accentContainer : AppColors.warningContainer,
        borderRadius: AppRadius.sm,
      ),
      child: Text(
        isReady ? '✓ AI Ready' : 'Not Processed',
        style: TextStyle(
          color: isReady ? AppColors.accent : AppColors.warning,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ── AI Feature Grid ─────────────────────────────────────────────────────────
class _AIFeatureGrid extends StatelessWidget {
  final Function(String) onFeatureTap;
  final String activeFeature;
  final bool isLoading;

  const _AIFeatureGrid({
    required this.onFeatureTap,
    required this.activeFeature,
    required this.isLoading,
  });

  static const features = [
    ('summarize', Icons.summarize_outlined, 'Summarize'),
    ('keypoints', Icons.list_outlined, 'Key Points'),
    ('timeline', Icons.timeline_outlined, 'Timeline'),
    ('actions', Icons.task_alt_outlined, 'Actions'),
    ('analyze', Icons.analytics_outlined, 'Analyze'),
    ('translate', Icons.translate_outlined, 'Translate'),
    ('citations', Icons.gavel_outlined, 'Citations'),
    ('risks', Icons.warning_amber_outlined, 'Risk Scan'),
    ('deadlines', Icons.event_outlined, 'Deadlines'),
    ('autotags', Icons.label_outlined, 'Auto-Tags'),
    ('grammar', Icons.spellcheck_outlined, 'Grammar'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisExtent: 76,
      ),
      itemCount: features.length,
      itemBuilder: (context, index) {
        final f = features[index];
        final isActive = activeFeature == f.$1 && isLoading;
        return InkWell(
          onTap: isLoading ? null : () => onFeatureTap(f.$1),
          borderRadius: AppRadius.md,
          child: Container(
            decoration: BoxDecoration(
              color: isActive ? AppColors.primaryContainer : AppColors.surface,
              borderRadius: AppRadius.md,
              border: Border.all(
                  color: isActive ? AppColors.primary : AppColors.outline),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
              Icon(f.$2,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                  size: 20),
              const SizedBox(height: 4),
              Text(f.$3,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: isActive ? AppColors.primary : AppColors.textSecondary,
                    height: 1.2,
                  )),
            ]),
          ),
        );
      },
    );
  }
}