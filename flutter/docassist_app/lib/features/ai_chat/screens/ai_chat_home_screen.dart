import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../../../core/network/dio_client.dart';
import '../../documents/providers/document_provider.dart';

final _recentDocsProvider = FutureProvider<List<Document>>((ref) async {
  try {
    final res = await DioClient.get('/documents',
        queryParams: {'limit': 20, 'status': 'ready'});
    final list = res['data']['documents'] as List? ?? [];
    return list.map((d) => Document.fromJson(d as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

class AiChatHomeScreen extends ConsumerStatefulWidget {
  const AiChatHomeScreen({super.key});
  @override
  ConsumerState<AiChatHomeScreen> createState() => _AiChatHomeScreenState();
}

class _AiChatHomeScreenState extends ConsumerState<AiChatHomeScreen> {
  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(_recentDocsProvider);

    final cs = Theme.of(context).colorScheme;
    return Scaffold(

      body: SafeArea(
        child: Column(children: [

          // ── Header ──────────────────────────────────────────────────────
          Container(
            color: cs.surface,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome_rounded,
                    color: cs.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI Chat',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                    color: cs.onSurface)),
                Text('Chat with your documents',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
              ]),
            ]),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Expanded(
            child: docsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _EmptyState(onUpload: () => context.go('/documents')),
              data: (docs) {
                if (docs.isEmpty) {
                  return _EmptyState(onUpload: () => context.go('/documents'));
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(_recentDocsProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [

                      // Start new chat card
                      GestureDetector(
                        onTap: () => context.go('/documents'),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppShadows.lg,
                          ),
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.add_rounded,
                                  color: AppColors.surface, size: 26),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Start New Chat',
                                  style: TextStyle(color: AppColors.surface,
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                                SizedBox(height: 2),
                                Text('Select a document to begin',
                                  style: TextStyle(color: Colors.white70,
                                    fontSize: 12)),
                              ],
                            )),
                            const Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.white70, size: 16),
                          ]),
                        ),
                      ),

                      // Recent conversations label
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('Recent Documents',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                            color: cs.onSurface.withValues(alpha: 0.6), letterSpacing: 0.5)),
                      ),

                      // Document list
                      ...docs.map((doc) => _ChatDocTile(
                        doc: doc,
                        onTap: () => context.push('/documents/${doc.id}/chat'),
                      )),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Chat document tile ────────────────────────────────────────────────────────

class _ChatDocTile extends StatelessWidget {
  final Document doc;
  final VoidCallback onTap;
  const _ChatDocTile({required this.doc, required this.onTap});

  Color get _typeColor {
    switch (doc.fileType.toLowerCase()) {
      case 'pdf': return AppColors.pdfColor;
      case 'docx': case 'doc': return AppColors.docxColor;
      default: return AppColors.txtColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline, width: 1),
        ),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: _typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(doc.fileType.toUpperCase(),
                style: TextStyle(color: _typeColor,
                  fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(doc.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
              const SizedBox(height: 3),
              Text(timeago.format(doc.updatedAt),
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
            ],
          )),
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.chat_bubble_outline_rounded,
                color: cs.onPrimaryContainer, size: 16),
          ),
        ]),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onUpload;
  const _EmptyState({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.chat_bubble_outline_rounded,
              color: cs.onPrimaryContainer, size: 40),
        ),
        const SizedBox(height: 20),
        Text('No chats yet',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
            color: cs.onSurface)),
        const SizedBox(height: 8),
        Text(
          'Upload and process a document first,\nthen come back here to chat with it.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.6), height: 1.5)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onUpload,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Upload Document'),
        ),
      ]),
    ));
  }
}
