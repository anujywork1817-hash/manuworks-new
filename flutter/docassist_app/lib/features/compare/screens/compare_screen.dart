import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../documents/providers/document_provider.dart';
import '../../../core/services/ai_history_service.dart';
import '../../../shared/widgets/feature_history_sheet.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  Document? _doc1;
  Document? _doc2;
  bool _comparing = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The document list is loaded lazily by the Documents tab. If the user
    // opens Compare directly (e.g. from the dashboard) that list is still
    // empty, leaving both pickers with nothing to select — so load it here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(documentProvider).documents.isEmpty) {
        ref.read(documentProvider.notifier).loadDocuments();
      }
    });
  }

  Future<void> _compare() async {
    if (_doc1 == null || _doc2 == null) return;
    if (_doc1!.id == _doc2!.id) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select two different documents'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() { _comparing = true; _result = null; _error = null; });
    try {
      final res = await DioClient.post<Map<String, dynamic>>('/ai/compare', data: {
        'doc1_id': _doc1!.id,
        'doc2_id': _doc2!.id,
      });
      final data = res['data'] as Map<String, dynamic>;
      if (mounted) {
        setState(() { _result = data; _comparing = false; });
      }
      try {
        final summary = data['summary'] as String? ?? '';
        final verdict = data['verdict'] as String? ?? '';
        await AiHistoryService.save(
          featureId: 'compare',
          title: 'Compare · ${_doc1!.title} vs ${_doc2!.title}',
          subtitle: verdict,
          content: [
            if (summary.isNotEmpty) summary,
            if (verdict.isNotEmpty) 'Verdict: $verdict',
          ].join('\n\n'),
        );
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().contains('Daily AI')
              ? 'Daily AI limit reached. Try again later.'
              : 'Comparison failed: ${e.toString()}';
          _comparing = false;
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
        title: const Text('Document Comparison',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Compare history',
            icon: const Icon(Icons.history_rounded, color: AppColors.textPrimary),
            onPressed: () => showFeatureHistorySheet(
                context, featureId: 'compare', featureLabel: 'Document Comparison'),
          ),
          if (_result != null)
            TextButton.icon(
              onPressed: () => setState(() { _result = null; _doc1 = null; _doc2 = null; }),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('New'),
            ),
        ],
      ),
      body: _result != null ? _buildResult() : _buildSelector(),
    );
  }

  // ── Document selector ────────────────────────────────────────────────────────

  Widget _buildSelector() {
    final state = ref.watch(documentProvider);

    if (state.isLoading && state.documents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.documents.isEmpty) {
      return Center(child: Text('Failed to load documents: ${state.error}'));
    }
    final docs = state.documents;
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(children: [
              Icon(Icons.compare_arrows_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text(
                'Select two documents to compare. AI will identify all meaningful differences between them.',
                style: TextStyle(fontSize: 12, color: AppColors.primary),
              )),
            ]),
          ),

          const SizedBox(height: 20),

          // Document A
          _DocSelector(
            label: 'Document A',
            color: AppColors.secondary,
            selected: _doc1,
            docs: docs,
            excludeId: _doc2?.id,
            onSelected: (d) => setState(() => _doc1 = d),
          ),

          const SizedBox(height: 12),

          // VS divider
          Row(children: [
            Expanded(child: Divider(color: Colors.grey.shade300)),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppShadows.sm,
              ),
              child: const Text('VS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary)),
            ),
            Expanded(child: Divider(color: Colors.grey.shade300)),
          ]),

          const SizedBox(height: 12),

          // Document B
          _DocSelector(
            label: 'Document B',
            color: AppColors.info,
            selected: _doc2,
            docs: docs,
            excludeId: _doc1?.id,
            onSelected: (d) => setState(() => _doc2 = d),
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

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_doc1 == null || _doc2 == null || _comparing) ? null : _compare,
              icon: _comparing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                  : const Icon(Icons.compare_arrows_rounded),
              label: Text(_comparing ? 'Comparing documents...' : 'Compare Documents'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      );
  }

  // ── Result view ──────────────────────────────────────────────────────────────

  Widget _buildResult() {
    final diffs = (_result!['differences'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final summary = _result!['summary'] as String? ?? '';
    final verdict = _result!['verdict'] as String? ?? '';
    final totalChanges = _result!['total_changes'] as int? ?? diffs.length;

    return CustomScrollView(slivers: [

      // Summary card
      SliverToBoxAdapter(child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Doc titles row
          Row(children: [
            Expanded(child: _DocPill(_doc1!.title, AppColors.secondary)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.compare_arrows_rounded, color: AppColors.textTertiary, size: 20),
            ),
            Expanded(child: _DocPill(_doc2!.title, AppColors.info)),
          ]),

          const SizedBox(height: 14),

          // Change count badge
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: totalChanges == 0
                    ? AppColors.successContainer
                    : const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$totalChanges difference${totalChanges == 1 ? '' : 's'} found',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: totalChanges == 0
                        ? AppColors.success
                        : AppColors.warning,
                  )),
            ),
          ]),

          const SizedBox(height: 10),
          Text(summary, style: const TextStyle(fontSize: 13, height: 1.6,
              color: Color(0xFF374151))),
        ]),
      )),

      // Differences list
      if (diffs.isNotEmpty) ...[
        const SliverToBoxAdapter(child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Differences',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
        )),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _DiffCard(diff: diffs[i],
                  docATitle: _doc1!.title, docBTitle: _doc2!.title),
              childCount: diffs.length,
            ),
          ),
        ),
      ],

      // Verdict
      if (verdict.isNotEmpty)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.successContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.successContainer),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  color: AppColors.success, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Key Takeaway',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        color: AppColors.success)),
                const SizedBox(height: 4),
                Text(verdict, style: const TextStyle(fontSize: 13, height: 1.5,
                    color: AppColors.success)),
              ])),
            ]),
          ),
        )),

      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]);
  }
}

// ─── Document selector tile ───────────────────────────────────────────────────

class _DocSelector extends StatelessWidget {
  final String label;
  final Color color;
  final Document? selected;
  final List<Document> docs;
  final String? excludeId;
  final ValueChanged<Document> onSelected;

  const _DocSelector({
    required this.label, required this.color, required this.selected,
    required this.docs, required this.onSelected, this.excludeId,
  });

  @override
  Widget build(BuildContext context) {
    final available = docs.where((d) => d.id != excludeId).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected != null ? color : AppColors.outline,
          width: selected != null ? 1.5 : 1,
        ),
        boxShadow: AppShadows.sm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: color, letterSpacing: 0.5)),
          ]),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(selected!.fileType.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(selected!.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary))),
              GestureDetector(
                onTap: () => _showPicker(context, available),
                child: Icon(Icons.swap_horiz_rounded, color: color, size: 20),
              ),
            ]),
          ),
        if (selected == null)
          InkWell(
            onTap: () => _showPicker(context, available),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(children: [
                Icon(Icons.add_circle_outline, color: color, size: 18),
                const SizedBox(width: 8),
                Text('Tap to select document',
                    style: TextStyle(fontSize: 13, color: color,
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
      ]),
    );
  }

  void _showPicker(BuildContext context, List<Document> available) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DocPickerSheet(
        docs: available,
        color: color,
        label: label,
        onSelected: onSelected,
      ),
    );
  }
}

// ─── Bottom sheet picker ─────────────────────────────────────────────────────

class _DocPickerSheet extends StatefulWidget {
  final List<Document> docs;
  final Color color;
  final String label;
  final ValueChanged<Document> onSelected;
  const _DocPickerSheet({required this.docs, required this.color,
      required this.label, required this.onSelected});

  @override
  State<_DocPickerSheet> createState() => _DocPickerSheetState();
}

class _DocPickerSheetState extends State<_DocPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.docs
        : widget.docs.where((d) =>
            d.title.toLowerCase().contains(_query.toLowerCase())).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFEEEDF8),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('Select ${widget.label}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search documents...',
                prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: widget.color, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(child: ListView.builder(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final doc = filtered[i];
              return GestureDetector(
                onTap: () { Navigator.pop(context); widget.onSelected(doc); },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppShadows.sm,
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(doc.fileType.toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                              color: widget.color)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(doc.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary))),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
                  ]),
                ),
              );
            },
          )),
        ]),
      ),
    );
  }
}

// ─── Diff card ───────────────────────────────────────────────────────────────

class _DiffCard extends StatelessWidget {
  final Map<String, dynamic> diff;
  final String docATitle;
  final String docBTitle;
  const _DiffCard({required this.diff, required this.docATitle, required this.docBTitle});

  Color get _changeColor {
    switch (diff['change'] as String? ?? '') {
      case 'added':    return AppColors.success;
      case 'removed':  return AppColors.error;
      case 'modified': return AppColors.warning;
      default:         return AppColors.textSecondary;
    }
  }

  IconData get _changeIcon {
    switch (diff['change'] as String? ?? '') {
      case 'added':    return Icons.add_circle_outline;
      case 'removed':  return Icons.remove_circle_outline;
      case 'modified': return Icons.change_circle_outlined;
      default:         return Icons.circle_outlined;
    }
  }

  String get _changeLabel {
    switch (diff['change'] as String? ?? '') {
      case 'added':    return 'ADDED IN B';
      case 'removed':  return 'REMOVED IN B';
      case 'modified': return 'MODIFIED';
      default:         return 'CHANGED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final docA = diff['doc_a'] as String? ?? '';
    final docB = diff['doc_b'] as String? ?? '';
    final category = diff['category'] as String? ?? '';
    final change = diff['change'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: _changeColor, width: 3)),
        boxShadow: AppShadows.sm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_changeIcon, color: _changeColor, size: 15),
            const SizedBox(width: 6),
            Text(category,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _changeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_changeLabel,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                      color: _changeColor)),
            ),
          ]),
          if (docA.isNotEmpty && change != 'added') ...[
            const SizedBox(height: 8),
            _Side('A', docA, AppColors.secondary),
          ],
          if (docB.isNotEmpty && change != 'removed') ...[
            const SizedBox(height: 6),
            _Side('B', docB, AppColors.info),
          ],
        ]),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  const _Side(this.label, this.text, this.color);

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 18, height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary))),
    ],
  );
}

// ─── Doc label pill ───────────────────────────────────────────────────────────

class _DocPill extends StatelessWidget {
  final String title;
  final Color color;
  const _DocPill(this.title, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Text(title,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );
}