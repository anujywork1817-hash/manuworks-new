import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/dio_client.dart';

class _Message {
  final String content;
  final bool isUser;
  _Message({required this.content, required this.isUser});
}

class HelpCenterScreen extends ConsumerStatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  ConsumerState<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends ConsumerState<HelpCenterScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = [];
  bool _isLoading = false;

  static const _quickQuestions = [
    'How do I upload a document?',
    'How does OCR work?',
    'How do I compare two documents?',
    'How do I create a matter?',
    'How do I draft a legal document?',
    'What AI features are available?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _isLoading) return;
    _controller.clear();

    // Snapshot history BEFORE adding the new user message
    final history = _messages
        .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.content})
        .toList();

    setState(() {
      _messages.add(_Message(content: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final res = await DioClient.post('/ai/help', data: {
        'message': text,
        'history': history,
      });

      final data = res is Map ? res['data'] : null;
      final reply = (data is Map ? data['reply'] : null) as String?
          ?? 'I did not receive a response. Please try again.';

      if (mounted) {
        setState(() {
          _messages.add(_Message(content: reply, isUser: false));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('HelpChat error: $e');
      if (mounted) {
        setState(() {
          _messages.add(_Message(
            content: e.toString().replaceFirst('Exception: ', ''),
            isUser: false,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      appBar: AppBar(
        
        elevation: 0,
        leading: const BackButton(),
        title: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.support_agent_rounded, color: AppColors.surface, size: 18),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Help Center',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            Row(children: [
              Container(
                width: 7, height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E), shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              const Text('OB • Online 24/7',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _messages.isEmpty
              ? _WelcomeView(onQuickTap: _send)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _messages.length) return const _TypingIndicator();
                    return _MessageBubble(message: _messages[i]);
                  },
                ),
        ),

        // Quick questions (only visible after first message to save space)
        if (_messages.isNotEmpty && !_isLoading)
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickQuestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ActionChip(
                label: Text(_quickQuestions[i],
                    style: const TextStyle(fontSize: 11)),
                onPressed: () => _send(_quickQuestions[i]),
                backgroundColor: AppColors.primaryContainer,
                labelStyle: const TextStyle(color: AppColors.primary),
                side: BorderSide.none,
                padding: EdgeInsets.zero,
              ),
            ),
          ),

        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: 'Ask anything about the app...',
                    hintStyle: const TextStyle(fontSize: 13),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: IconButton.filled(
                  onPressed: _isLoading ? null : () => _send(_controller.text),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.surface))
                      : const Icon(Icons.send_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── Welcome view ──────────────────────────────────────────────────────────────

class _WelcomeView extends StatelessWidget {
  final void Function(String) onQuickTap;
  const _WelcomeView({required this.onQuickTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 16),
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppShadows.md,
          ),
          child: const Icon(Icons.support_agent_rounded,
              color: AppColors.surface, size: 40),
        ),
        const SizedBox(height: 16),
        const Text('Hi! I\'m OB',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        const Text(
          'Your 24/7 AI assistant for DocAssist.\nAsk me anything about the app!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Quick questions',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500, letterSpacing: 0.5)),
        ),
        const SizedBox(height: 10),
        _QuickChipList(
          questions: const [
            'How do I upload a document?',
            'How does OCR work?',
            'How do I compare two documents?',
            'How do I create a matter?',
            'How do I draft a legal document?',
            'What AI features are available?',
            'How do I favourite a document?',
            'How do I change my password?',
          ],
          onTap: onQuickTap,
        ),
      ]),
    );
  }
}

class _QuickChipList extends StatelessWidget {
  final List<String> questions;
  final void Function(String) onTap;
  const _QuickChipList({required this.questions, required this.onTap});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: questions
        .map((q) => _QuickChip(label: q, onTap: () => onTap(q)))
        .toList(),
  );
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryContainer.withValues(alpha: 2)),
        boxShadow: AppShadows.sm,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.chat_bubble_outline_rounded,
            size: 13, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary,
                fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _Message message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.support_agent_rounded,
                  size: 16, color: AppColors.surface),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: AppShadows.sm,
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isUser ? Colors.white : AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.support_agent_rounded,
            size: 16, color: AppColors.surface),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: AppShadows.sm,
        ),
        child: const _DotsAnimation(),
      ),
    ]),
  );
}

class _DotsAnimation extends StatefulWidget {
  const _DotsAnimation();
  @override
  State<_DotsAnimation> createState() => _DotsAnimationState();
}

class _DotsAnimationState extends State<_DotsAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) {
      final t = _ctrl.value;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _dot(t, 0.0),
        const SizedBox(width: 4),
        _dot(t, 0.33),
        const SizedBox(width: 4),
        _dot(t, 0.66),
      ]);
    },
  );

  Widget _dot(double t, double offset) {
    final phase = ((t - offset) % 1.0 + 1.0) % 1.0;
    final scale = phase < 0.5
        ? 0.6 + 0.8 * (phase / 0.5)
        : 1.4 - 0.8 * ((phase - 0.5) / 0.5);
    return Transform.scale(
      scale: scale.clamp(0.6, 1.4),
      child: Container(
        width: 7, height: 7,
        decoration: const BoxDecoration(
          color: AppColors.primary, shape: BoxShape.circle),
      ),
    );
  }
}

