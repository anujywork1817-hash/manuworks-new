import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/dio_client.dart';
import '../providers/matter_provider.dart';
import '../../documents/providers/document_provider.dart';

class MatterDetailScreen extends ConsumerStatefulWidget {
  final String matterId;
  const MatterDetailScreen({super.key, required this.matterId});
  @override
  ConsumerState<MatterDetailScreen> createState() => _MatterDetailScreenState();
}

class _MatterDetailScreenState extends ConsumerState<MatterDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(matterDetailProvider(widget.matterId));

    return Scaffold(
      
      appBar: AppBar(
        
        elevation: 0,
        leading: BackButton(
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: detailAsync.when(
          data: (d) {
            final m = d['matter'] as Map<String, dynamic>? ?? {};
            return Text(m['title'] ?? 'Case',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary));
          },
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Case'),
        ),
        actions: [
          detailAsync.whenOrNull(
            data: (d) {
              final m = d['matter'] as Map<String, dynamic>? ?? {};
              return IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showEditDialog(m),
              );
            },
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final m = data['matter'] as Map<String, dynamic>? ?? {};
          final docs = (data['documents'] as List? ?? [])
              .map((e) => MatterDoc.fromJson(e as Map<String, dynamic>))
              .toList();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(matterDetailProvider(widget.matterId).future),
            child: CustomScrollView(
              slivers: [
                // ── Info card ────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppShadows.sm,
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.folder_special_rounded,
                              color: AppColors.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m['title'] ?? '',
                              style: const TextStyle(fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary)),
                          if ((m['matter_no'] ?? '').isNotEmpty)
                            Text(m['matter_no'],
                                style: const TextStyle(fontSize: 12,
                                    color: AppColors.textSecondary)),
                        ])),
                        _StatusChip(status: m['status'] ?? 'active'),
                      ]),
                      if ((m['client'] ?? '').isNotEmpty ||
                          (m['court'] ?? '').isNotEmpty ||
                          (m['description'] ?? '').isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        if ((m['client'] ?? '').isNotEmpty)
                          _InfoRow(Icons.person_outline_rounded, 'Client', m['client']),
                        if ((m['court'] ?? '').isNotEmpty)
                          _InfoRow(Icons.account_balance_outlined, 'Court', m['court']),
                        if ((m['description'] ?? '').isNotEmpty)
                          _InfoRow(Icons.notes_outlined, 'Notes', m['description']),
                      ],
                    ]),
                  ),
                ),

                // ── Documents header ─────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Row(children: [
                      Text('Documents (${docs.length})',
                          style: const TextStyle(fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _loadAndShowDocumentSheet,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add'),
                      ),
                    ]),
                  ),
                ),

                // ── Documents list ───────────────────────────────────────
                docs.isEmpty
                    ? SliverToBoxAdapter(child: _emptyDocs(context))
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _DocTile(
                              doc: docs[i],
                              onTap: () =>
                                  context.push('/documents/${docs[i].id}'),
                              onRemove: () =>
                                  _removeDocument(docs[i].id),
                            ),
                            childCount: docs.length,
                          ),
                        ),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptyDocs(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(children: [
            const Icon(Icons.insert_drive_file_outlined,
                size: 48, color: AppColors.textDisabled),
            const SizedBox(height: 12),
            const Text('No documents yet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            const Text('Tap "Add" to link documents to this case.',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadAndShowDocumentSheet,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Document'),
            ),
          ]),
        ),
      );

  Future<void> _loadAndShowDocumentSheet() async {
    List<Document> allDocs = [];
    try {
      final res = await DioClient.get('/documents', queryParams: {'limit': 50});
      final list = res['data']['documents'] as List? ?? [];
      allDocs = list
          .map((e) => Document.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    if (!mounted) return;
    _openDocumentSheet(allDocs);
  }

  void _openDocumentSheet(List<Document> allDocs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Column(children: [
          const SizedBox(height: 12),
          Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Add Document to Case',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Divider(),
          Expanded(
            child: allDocs.isEmpty
                ? const Center(child: Text('No documents found'))
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: allDocs.length,
                    itemBuilder: (_, i) {
                      final doc = allDocs[i];
                      return ListTile(
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(doc.fileType.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary)),
                          ),
                        ),
                        title: Text(doc.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(doc.status,
                            style: const TextStyle(fontSize: 12)),
                        onTap: () async {
                          Navigator.pop(sheetCtx);
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await ref
                              .read(matterProvider.notifier)
                              .addDocument(widget.matterId, doc.id);
                          if (ok && mounted) {
                            ref.invalidate(matterDetailProvider(widget.matterId));
                            messenger.showSnackBar(
                              const SnackBar(
                                  content: Text('Document added to case'),
                                  behavior: SnackBarBehavior.floating),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  Future<void> _removeDocument(String docId) async {
    final ok = await ref
        .read(matterProvider.notifier)
        .removeDocument(widget.matterId, docId);
    if (ok && mounted) {
      ref.invalidate(matterDetailProvider(widget.matterId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Document removed from case'),
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> m) async {
    final titleCtrl = TextEditingController(text: m['title'] ?? '');
    final matterNoCtrl = TextEditingController(text: m['matter_no'] ?? '');
    final clientCtrl = TextEditingController(text: m['client'] ?? '');
    final courtCtrl = TextEditingController(text: m['court'] ?? '');
    final descCtrl = TextEditingController(text: m['description'] ?? '');
    String status = m['status'] ?? 'active';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Edit Case',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(titleCtrl, 'Case Title *', Icons.folder_outlined),
              const SizedBox(height: 12),
              _field(matterNoCtrl, 'Case No.', Icons.tag),
              const SizedBox(height: 12),
              _field(clientCtrl, 'Client Name', Icons.person_outlined),
              const SizedBox(height: 12),
              _field(courtCtrl, 'Court / Forum', Icons.account_balance_outlined),
              const SizedBox(height: 12),
              _field(descCtrl, 'Description', Icons.notes_outlined, maxLines: 2),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                  DropdownMenuItem(value: 'archived', child: Text('Archived')),
                ],
                onChanged: (v) => setS(() => status = v ?? status),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                final ok = await ref.read(matterProvider.notifier).update(
                      widget.matterId,
                      title: titleCtrl.text.trim(),
                      matterNo: matterNoCtrl.text.trim(),
                      client: clientCtrl.text.trim(),
                      court: courtCtrl.text.trim(),
                      status: status,
                      description: descCtrl.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
                if (ok && mounted) {
                  ref.invalidate(matterDetailProvider(widget.matterId));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon,
      {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

// ── Doc tile ──────────────────────────────────────────────────────────────────

class _DocTile extends StatelessWidget {
  final MatterDoc doc;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _DocTile(
      {required this.doc, required this.onTap, required this.onRemove});

  Color get _typeColor {
    switch (doc.fileType.toLowerCase()) {
      case 'pdf':
        return AppColors.pdfColor;
      case 'docx':
      case 'doc':
        return AppColors.docxColor;
      default:
        return AppColors.txtColor;
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppShadows.sm,
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(doc.fileType.toUpperCase(),
                    style: TextStyle(
                        color: _typeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(doc.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(doc.status,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ])),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  color: AppColors.textTertiary, size: 20),
              onPressed: onRemove,
              tooltip: 'Remove from case',
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
          ]),
        ),
      );
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary))),
        ]),
      );
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? AppColors.successContainer : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isActive ? 'Active' : status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive ? AppColors.success : AppColors.textSecondary,
        ),
      ),
    );
  }
}