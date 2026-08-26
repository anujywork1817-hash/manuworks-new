import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/dio_client.dart';
import '../providers/document_provider.dart';
import '../providers/favourites_provider.dart';

/// Documents tab: upload a file and see your upload history. Tapping a
/// document opens its detail screen (chat / AI features / etc. live there).
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});
  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(documentProvider.notifier).loadDocuments();
    });
  }

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf', 'docx', 'doc', 'txt'],
      withData: true, // required on mobile/desktop to get bytes for web-style upload; web always includes bytes
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final success = await ref.read(documentProvider.notifier).uploadPlatformFile(file);
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Upload failed'), backgroundColor: AppColors.error));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Document uploaded'), behavior: SnackBarBehavior.floating));
  }

  // Tapping a document just shows the document as it was uploaded (title,
  // type, size, status). It no longer navigates to the AI Features screen —
  // it downloads the original uploaded file and opens it with the device's
  // own PDF/DOCX/TXT viewer, i.e. the document exactly as it was uploaded.
  String? _openingId; // guards against double-taps while a download is in flight
  Future<void> _openDocument(Document doc) async {
    if (_openingId == doc.id) return;
    setState(() => _openingId = doc.id);
    try {
      final dir = await getTemporaryDirectory();
      final ext = doc.fileType.isNotEmpty ? doc.fileType.toLowerCase() : 'pdf';
      final savePath = '${dir.path}/${doc.id}.$ext';

      await DioClient.instance.download('/documents/${doc.id}/download', savePath);

      if (!mounted) return;
      final result = await OpenFile.open(savePath);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open document: ${result.message}'),
          backgroundColor: AppColors.error,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not download document: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentProvider);
    final favIds = ref.watch(favouritesProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_outlined, size: 20),
          SizedBox(width: 8),
          Text('Documents'),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.star_outline_rounded),
            tooltip: 'Favourites',
            onPressed: () => context.push('/favourites')),
          IconButton(icon: const Icon(Icons.refresh_outlined),
            onPressed: () => ref.read(documentProvider.notifier).loadDocuments()),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              'Upload a PDF, DOCX, or TXT file. Every document you upload is saved here.',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.isUploading ? null : _pickAndUpload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
                ),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Upload Document',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            if (state.isUploading) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Uploading... ${(state.uploadProgress * 100).toInt()}%',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: state.uploadProgress),
            ],
            if (state.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(color: AppColors.errorContainer, borderRadius: AppRadius.md),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: AppColors.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(state.error!, style: const TextStyle(color: AppColors.error))),
                ]),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            if (!state.isLoading && state.documents.isNotEmpty)
              Text('History', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (state.isLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (state.documents.isEmpty)
              _EmptyState(onUpload: _pickAndUpload)
            else
              ...state.documents.map((doc) => _HistoryTile(
                document: doc,
                isFavourite: favIds.contains(doc.id),
                isOpening: _openingId == doc.id,
                onToggleFav: () => ref.read(favouritesProvider.notifier).toggle(doc.id),
                onTap: () => _openDocument(doc),
                onDelete: () => _confirmDelete(context, doc),
              )),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Document doc) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete Document'),
      content: Text('Delete "${doc.title}"? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await ref.read(documentProvider.notifier).deleteDocument(doc.id);
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Delete'),
        ),
      ],
    ));
  }
}

// ── History row (upload history) ───────────────────────────────────────────
class _HistoryTile extends StatelessWidget {
  final Document document;
  final bool isFavourite;
  final bool isOpening;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleFav;
  const _HistoryTile({
    required this.document,
    required this.isFavourite,
    required this.isOpening,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFav,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: isOpening ? null : onTap,
        borderRadius: AppRadius.lg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
          child: Row(children: [
            isOpening
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.description_outlined, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(document.title, style: theme.textTheme.bodyMedium,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text(timeago.format(document.createdAt), style: theme.textTheme.bodySmall),
            IconButton(
              icon: Icon(
                isFavourite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFavourite ? AppColors.warning : theme.colorScheme.outline,
                size: 20,
              ),
              tooltip: isFavourite ? 'Remove from favourites' : 'Add to favourites',
              onPressed: onToggleFav,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_outlined, size: 20),
              onSelected: (v) { if (v == 'delete') onDelete(); },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'delete', child: Row(children: [
                  Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: AppColors.error)),
                ])),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onUpload;
  const _EmptyState({required this.onUpload});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(child: Column(children: [
      const Icon(Icons.folder_open_outlined, size: 64, color: AppColors.textTertiary),
      const SizedBox(height: AppSpacing.md),
      Text('No documents yet', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      Text('Upload your first PDF or DOCX', style: Theme.of(context).textTheme.bodyMedium),
    ])),
  );
}