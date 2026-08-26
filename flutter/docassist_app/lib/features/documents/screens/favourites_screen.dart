import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../providers/document_provider.dart';
import '../providers/favourites_provider.dart';

class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docState = ref.watch(documentProvider);
    final favIds = ref.watch(favouritesProvider);

    final favDocs = docState.documents.where((d) => favIds.contains(d.id)).toList();

    return Scaffold(
      
      appBar: AppBar(
        
        elevation: 0,
        leading: const BackButton(),
        title: const Text('Favourites',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          if (docState.isLoading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: () => ref.read(documentProvider.notifier).loadDocuments(),
            ),
        ],
      ),
      body: favDocs.isEmpty
          ? Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.warningContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.star_outline_rounded,
                      color: AppColors.warning, size: 40),
                ),
                const SizedBox(height: 20),
                const Text('No favourites yet',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                const Text('Star documents to find them here quickly.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: favDocs.length,
              itemBuilder: (context, i) {
                final doc = favDocs[i];
                return _FavCard(
                  document: doc,
                  onTap: () => context.push('/documents/${doc.id}'),
                  onUnfav: () => ref.read(favouritesProvider.notifier).toggle(doc.id),
                );
              },
            ),
    );
  }
}

class _FavCard extends StatelessWidget {
  final Document document;
  final VoidCallback onTap;
  final VoidCallback onUnfav;

  const _FavCard({required this.document, required this.onTap, required this.onUnfav});

  Color get _typeColor {
    switch (document.fileType.toLowerCase()) {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lg,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                  color: _typeColor.withValues(alpha: 0.1),
                  borderRadius: AppRadius.md),
              child: Center(
                child: Text(document.fileType.toUpperCase(),
                    style: TextStyle(
                        color: _typeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(document.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Text(document.fileSizeHuman, style: theme.textTheme.bodySmall),
                  const Text(' · '),
                  Text(timeago.format(document.createdAt),
                      style: theme.textTheme.bodySmall),
                ]),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.star_rounded, color: AppColors.warning),
              onPressed: onUnfav,
              tooltip: 'Remove from favourites',
            ),
          ]),
        ),
      ),
    );
  }
}
