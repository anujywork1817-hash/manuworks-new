import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/ai_history_service.dart';
import '../../core/services/document_export_service.dart';

/// Opens this feature's saved history as a side panel that slides in from
/// the left — mirroring the "History" sidebar on the manuworks.ai web app
/// (search box, Recent/Archive tabs, dates listed down the side, tap one
/// to view/export that entry).
/// Call from any AI feature screen, e.g.:
///
///   IconButton(
///     icon: const Icon(Icons.history_rounded),
///     onPressed: () => showFeatureHistorySheet(
///       context, featureId: 'summarize', featureLabel: 'Summarize'),
///   )
Future<void> showFeatureHistorySheet(
  BuildContext context, {
  required String featureId,
  required String featureLabel,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) =>
          _FeatureHistoryPanel(featureId: featureId, featureLabel: featureLabel),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

class _FeatureHistoryPanel extends StatefulWidget {
  final String featureId;
  final String featureLabel;
  const _FeatureHistoryPanel({required this.featureId, required this.featureLabel});

  @override
  State<_FeatureHistoryPanel> createState() => _FeatureHistoryPanelState();
}

class _FeatureHistoryPanelState extends State<_FeatureHistoryPanel> {
  List<AiHistoryEntry>? _entries;
  String? _openDay;
  String? _openEntryId;
  String _query = '';
  int _tab = 0; // 0 = Recent (last 30 days), 1 = Archive (older)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await AiHistoryService.getAll(widget.featureId);
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _delete(AiHistoryEntry e) async {
    await AiHistoryService.delete(widget.featureId, e.id);
    _load();
  }

  String _dayKey(DateTime d) => DateFormat('MMM d, yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.84;
    final cutoff = DateTime.now().subtract(const Duration(days: 30));

    // Apply search filter (title, subtitle or content) + Recent/Archive split.
    var filtered = _entries ?? [];
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      filtered = filtered.where((e) =>
          e.title.toLowerCase().contains(q) ||
          e.subtitle.toLowerCase().contains(q) ||
          e.content.toLowerCase().contains(q)).toList();
    }
    filtered = filtered.where((e) =>
        _tab == 0 ? e.createdAt.isAfter(cutoff) : e.createdAt.isBefore(cutoff)).toList();

    // Group entries by day, newest day first (entries already newest-first).
    final byDay = <String, List<AiHistoryEntry>>{};
    for (final e in filtered) {
      byDay.putIfAbsent(_dayKey(e.createdAt), () => []).add(e);
    }
    final days = byDay.keys.toList();

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: AppColors.background,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: SafeArea(
            child: Column(children: [
              // ── Panel header ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(children: [
                  const Icon(Icons.history_rounded, size: 18, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('History',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ]),
              ),

              // ── Search box ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textSecondary),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              // ── Recent / Archive tabs ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(children: [
                  Expanded(child: _TabChip(
                    label: 'Recent',
                    selected: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _TabChip(
                    label: 'Archive',
                    selected: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  )),
                ]),
              ),
              const Divider(height: 1),

              // ── Day list / entries ────────────────────────────────────
              Expanded(
                child: _entries == null
                    ? const Center(child: CircularProgressIndicator())
                    : days.isEmpty
                        ? _buildEmpty()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: days.length,
                            itemBuilder: (context, i) {
                              final day = days[i];
                              final dayEntries = byDay[day]!;
                              final isOpen = _openDay == day;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap: () => setState(
                                        () => _openDay = isOpen ? null : day),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Row(children: [
                                        const Icon(Icons.calendar_today_outlined,
                                            size: 14, color: AppColors.textSecondary),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(day,
                                              style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textPrimary)),
                                        ),
                                        Text('${dayEntries.length}',
                                            style: const TextStyle(
                                                fontSize: 11, color: AppColors.textSecondary)),
                                        const SizedBox(width: 6),
                                        Icon(
                                          isOpen
                                              ? Icons.keyboard_arrow_up_rounded
                                              : Icons.keyboard_arrow_down_rounded,
                                          size: 18, color: AppColors.textSecondary,
                                        ),
                                      ]),
                                    ),
                                  ),
                                  if (isOpen)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Column(
                                        children: dayEntries
                                            .map((e) => Padding(
                                                  padding: const EdgeInsets.fromLTRB(
                                                      12, 0, 12, 8),
                                                  child: _HistoryTile(
                                                    entry: e,
                                                    expanded: _openEntryId == e.id,
                                                    onToggle: () => setState(() =>
                                                        _openEntryId =
                                                            _openEntryId == e.id ? null : e.id),
                                                    onDelete: () => _delete(e),
                                                  ),
                                                ))
                                            .toList(),
                                      ),
                                    ),
                                  const Divider(height: 1, indent: 16, endIndent: 16),
                                ],
                              );
                            },
                          ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.inbox_outlined, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 10),
            Text(
                _query.trim().isNotEmpty
                    ? 'No results for "$_query"'
                    : _tab == 0
                        ? 'No recent ${widget.featureLabel.toLowerCase()} history'
                        : 'Nothing archived yet',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('Results you generate here will be saved automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
      );
}

// ── Recent / Archive tab chip ───────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.textOnPrimary : AppColors.textSecondary,
              )),
        ),
      );
}

class _HistoryTile extends StatefulWidget {
  final AiHistoryEntry entry;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  const _HistoryTile({
    required this.entry,
    required this.expanded,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _exportingPdf = false;
  bool _exportingDocx = false;

  Future<void> _exportPdf() async {
    setState(() => _exportingPdf = true);
    try {
      await DocumentExportService.exportToPdf(
          title: widget.entry.title, content: widget.entry.content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportDocx() async {
    setState(() => _exportingDocx = true);
    try {
      await DocumentExportService.exportToDocx(
          title: widget.entry.title, content: widget.entry.content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Word export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportingDocx = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          dense: true,
          onTap: widget.onToggle,
          title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          subtitle: Text(
            [
              if (e.subtitle.isNotEmpty) e.subtitle,
              DateFormat('h:mm a').format(e.createdAt),
            ].join(' · '),
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') widget.onDelete();
              if (v == 'copy') {
                Clipboard.setData(ClipboardData(text: e.content));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'copy', child: Text('Copy text')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
        if (widget.expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(e.content,
                style: const TextStyle(fontSize: 12.5, height: 1.6, fontFamily: 'monospace')),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _exportingPdf ? null : _exportPdf,
                icon: _exportingPdf
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined, size: 15),
                label: const Text('PDF'),
              ),
              OutlinedButton.icon(
                onPressed: _exportingDocx ? null : _exportDocx,
                icon: _exportingDocx
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.description_outlined, size: 15),
                label: const Text('Word'),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}