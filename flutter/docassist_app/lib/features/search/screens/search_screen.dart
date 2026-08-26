import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/dio_client.dart';

class SearchResult {
  final String documentId, documentTitle, chunkText, fileType;
  final double score;
  const SearchResult({required this.documentId, required this.documentTitle,
      required this.chunkText, required this.fileType, required this.score});
  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
    documentId: j['document_id'] ?? '', documentTitle: j['document_title'] ?? '',
    chunkText: j['chunk_text'] ?? '', fileType: j['file_type'] ?? '',
    score: (j['score'] ?? 0).toDouble());
}

class SearchState {
  final List<SearchResult> results;
  final String? ragAnswer;
  final bool isLoading;
  final String? error;
  const SearchState({this.results = const [], this.ragAnswer, this.isLoading = false, this.error});
  SearchState copyWith({List<SearchResult>? results, String? ragAnswer, bool? isLoading, String? error}) =>
      SearchState(results: results ?? this.results, ragAnswer: ragAnswer ?? this.ragAnswer,
          isLoading: isLoading ?? this.isLoading, error: error);
}

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier() : super(const SearchState());

  Future<void> search(String query) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await DioClient.get('/search', queryParams: {'q': query, 'limit': 10});
      final data = response['data'];
      final results = (data['results'] as List).map((r) => SearchResult.fromJson(r)).toList();
      state = state.copyWith(results: results, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> ragQuery(String query) async {
    state = state.copyWith(isLoading: true, error: null, ragAnswer: null);
    try {
      final response = await DioClient.post('/search/ask', data: {'query': query});
      final data = response['data'];
      state = state.copyWith(
        ragAnswer: data['answer'] ?? '', isLoading: false,
        results: (data['sources'] as List? ?? []).map((r) => SearchResult.fromJson(r)).toList());
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) => SearchNotifier());

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  bool _ragMode = false;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _search() {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    if (_ragMode) {
      ref.read(searchProvider.notifier).ragQuery(q);
    } else {
      ref.read(searchProvider.notifier).search(q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final theme = Theme.of(context);

    return Scaffold(
      
      appBar: AppBar(title: const Text('Semantic Search')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(children: [
            Row(children: [
              Expanded(child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: _ragMode ? 'Ask a question...' : 'Search documents...',
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: IconButton(icon: const Icon(Icons.send_rounded), onPressed: _search),
                ),
              )),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              const Text('Search mode:'),
              const SizedBox(width: AppSpacing.sm),
              ChoiceChip(label: const Text('Semantic'), selected: !_ragMode,
                  onSelected: (_) => setState(() => _ragMode = false)),
              const SizedBox(width: AppSpacing.sm),
              ChoiceChip(label: const Text('Ask AI'), selected: _ragMode,
                  onSelected: (_) => setState(() => _ragMode = true)),
            ]),
          ]),
        ),

        if (state.isLoading) const LinearProgressIndicator(),

        if (state.error != null)
          Container(margin: const EdgeInsets.all(AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: const BoxDecoration(color: AppColors.errorContainer, borderRadius: AppRadius.md),
              child: Text(state.error!, style: const TextStyle(color: AppColors.error))),

        if (state.ragAnswer != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Card(child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.auto_awesome, color: AppColors.accent, size: 16),
                  const SizedBox(width: 6),
                  Text('AI Answer', style: theme.textTheme.labelMedium?.copyWith(color: AppColors.accent)),
                ]),
                const Divider(),
                Text(state.ragAnswer!, style: theme.textTheme.bodyMedium),
              ]),
            )),
          ),

        Expanded(
          child: state.results.isEmpty && !state.isLoading
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.search_outlined, size: 64, color: AppColors.textTertiary),
                  const SizedBox(height: AppSpacing.md),
                  Text('Search your documents', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Use semantic search or ask AI questions', style: theme.textTheme.bodyMedium),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  itemCount: state.results.length,
                  itemBuilder: (context, i) {
                    final r = state.results[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryContainer,
                          child: Text('${(r.score * 100).toInt()}%',
                              style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(r.documentTitle, style: theme.textTheme.titleSmall,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(r.chunkText, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                        onTap: () => context.push('/documents/${r.documentId}'),
                      ),
                    );
                  }),
        ),
      ]),
    );
  }
}