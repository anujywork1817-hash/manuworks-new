import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/router.dart';
import '../providers/ai_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String documentId;
  const ChatScreen({super.key, required this.documentId});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider(widget.documentId).notifier).startSession();
    });
  }

  @override
  void dispose() { _controller.dispose(); _scrollController.dispose(); super.dispose(); }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await ref.read(chatProvider(widget.documentId).notifier).sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider(widget.documentId));
    final theme = Theme.of(context);

    return Scaffold(
      
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('${AppRoutes.documents}/${widget.documentId}'),
        ),
        title: const Text('Chat with Document'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: AppSpacing.md),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const BoxDecoration(color: AppColors.accentContainer, borderRadius: AppRadius.full),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.auto_awesome, size: 14, color: AppColors.accent),
              const SizedBox(width: 4),
              Text('Gemini', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.accent)),
            ]),
          ),
        ],
      ),
      body: Column(children: [
        if (state.error != null)
          Container(
            margin: const EdgeInsets.all(AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: const BoxDecoration(color: AppColors.errorContainer, borderRadius: AppRadius.md),
            child: Text(state.error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),

        Expanded(
          child: state.messages.isEmpty
              ? _WelcomeMessage(isLoading: state.isLoading)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: state.messages.length + (state.isLoading ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == state.messages.length) return const _TypingIndicator();
                    return _MessageBubble(message: state.messages[i]);
                  },
                ),
        ),

        // Input
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.outline)),
          ),
          child: SafeArea(
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: 4, minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Ask anything about this document...',
                    border: OutlineInputBorder(), contentPadding: EdgeInsets.all(12)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: state.isLoading ? null : _send,
                icon: state.isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser ? null : Border.all(color: AppColors.outline),
              ),
              child: Text(message.content,
                  style: TextStyle(color: isUser ? Colors.white : AppColors.textPrimary, fontSize: 14)),
            ),
          ),
          if (isUser) const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 32, height: 32,
      decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
      child: const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
    ),
    const SizedBox(width: AppSpacing.sm),
    Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.lg,
          border: Border.all(color: AppColors.outline)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        _Dot(delay: 0), SizedBox(width: 4), _Dot(delay: 200), SizedBox(width: 4), _Dot(delay: 400),
      ]),
    ),
  ]);
}

class _Dot extends StatelessWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  Widget build(BuildContext context) => Container(
    width: 8, height: 8,
    decoration: const BoxDecoration(color: AppColors.textTertiary, shape: BoxShape.circle),
  );
}

class _WelcomeMessage extends StatelessWidget {
  final bool isLoading;
  const _WelcomeMessage({required this.isLoading});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.chat_outlined, size: 64, color: AppColors.textTertiary),
      const SizedBox(height: AppSpacing.md),
      Text('Chat with your document', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      Text('Ask any question and get AI-powered answers based on the document content.',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      if (isLoading) ...[
        const SizedBox(height: AppSpacing.lg),
        const CircularProgressIndicator(),
        const SizedBox(height: AppSpacing.sm),
        const Text('Starting session...'),
      ],
    ]),
  ));
}