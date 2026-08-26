import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../providers/matter_provider.dart';

class MattersScreen extends ConsumerStatefulWidget {
  final bool autoOpenAdd;
  const MattersScreen({super.key, this.autoOpenAdd = false});
  @override
  ConsumerState<MattersScreen> createState() => _MattersScreenState();
}

class _MattersScreenState extends ConsumerState<MattersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(matterProvider.notifier).load();
      if (widget.autoOpenAdd) _showCreateDialog();
    });
  }

  Future<void> _showCreateDialog() async {
    final titleCtrl = TextEditingController();
    final matterNoCtrl = TextEditingController();
    final clientCtrl = TextEditingController();
    final courtCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Case', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field(titleCtrl, 'Case Title *', Icons.folder_outlined),
            const SizedBox(height: 12),
            _field(matterNoCtrl, 'Case No. (e.g. CRL/2024/001)', Icons.tag),
            const SizedBox(height: 12),
            _field(clientCtrl, 'Client Name', Icons.person_outlined),
            const SizedBox(height: 12),
            _field(courtCtrl, 'Court / Forum', Icons.account_balance_outlined),
            const SizedBox(height: 12),
            _field(descCtrl, 'Description', Icons.notes_outlined, maxLines: 3),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              final m = await ref.read(matterProvider.notifier).create(
                    title: titleCtrl.text.trim(),
                    matterNo: matterNoCtrl.text.trim(),
                    client: clientCtrl.text.trim(),
                    court: courtCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                  );
              if (ctx.mounted) Navigator.pop(ctx, m != null);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Case created'), behavior: SnackBarBehavior.floating),
      );
    }
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matterProvider);

    return Scaffold(
      
      appBar: AppBar(
        
        elevation: 0,
        title: const Text('Cases',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => ref.read(matterProvider.notifier).load(),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tooltip: 'New Case',
        child: const Icon(Icons.add),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.matters.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: () => ref.read(matterProvider.notifier).load(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: state.matters.length,
                    itemBuilder: (_, i) => _MatterCard(
                      matter: state.matters[i],
                      onTap: () => context.push('/matters/${state.matters[i].id}'),
                      onDelete: () => _confirmDelete(state.matters[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _emptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.folder_special_outlined,
                color: cs.onPrimaryContainer, size: 40),
          ),
          const SizedBox(height: 20),
          Text('No Cases Yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(
            'Create a case to group related\ndocuments for a case or client.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.6), height: 1.5),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create Case'),
          ),
        ]),
      ),
    );
  }

  void _confirmDelete(Matter matter) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Case'),
        content: Text('Delete "${matter.title}"? Documents will not be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(matterProvider.notifier).delete(matter.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Matter card ───────────────────────────────────────────────────────────────

class _MatterCard extends StatelessWidget {
  final Matter matter;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MatterCard({
    required this.matter,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = matter.status == 'active';
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline, width: 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: isActive ? cs.primaryContainer : cs.outlineVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.folder_special_rounded,
                  color: isActive ? cs.onPrimaryContainer : cs.onSurface.withValues(alpha: 0.4),
                  size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(matter.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              if (matter.matterNo.isNotEmpty)
                Text(matter.matterNo,
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
            ])),
            _StatusChip(status: matter.status),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.delete_outline_rounded,
                  color: cs.onSurface.withValues(alpha: 0.4), size: 18),
            ),
          ]),
          if (matter.client.isNotEmpty || matter.court.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(children: [
              if (matter.client.isNotEmpty)
                _Meta(Icons.person_outline_rounded, matter.client),
              if (matter.client.isNotEmpty && matter.court.isNotEmpty)
                const SizedBox(width: 16),
              if (matter.court.isNotEmpty)
                _Meta(Icons.account_balance_outlined, matter.court),
            ]),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
            const SizedBox(width: 4),
            Text('${matter.docCount} document${matter.docCount == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
            const Spacer(),
            Text(timeago.format(matter.updatedAt),
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: 0.4), size: 16),
          ]),
        ]),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta(this.icon, this.text);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 13, color: cs.onSurface.withValues(alpha: 0.4)),
      const SizedBox(width: 4),
      Text(text,
          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
    ]);
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? AppColors.successContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isActive ? 'Active' : status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive ? AppColors.success : cs.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}