import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/dio_client.dart';

class _Msg {
  final String text;
  final bool isUser;
  _Msg(this.text, this.isUser);
}

/// A general-purpose AI chat that does NOT require an uploaded document.
/// Reachable directly from the "AI Chat" bottom nav tab.
class GeneralChatScreen extends StatefulWidget {
  const GeneralChatScreen({super.key});

  @override
  State<GeneralChatScreen> createState() => _GeneralChatScreenState();
}

class _GeneralChatScreenState extends State<GeneralChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Msg> _messages = [];
  bool _isLoading = false;
  String? _error;

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

  String _friendlyError(String raw) {
    if (raw.contains('Daily AI token limit') ||
        raw.contains('tokens per day') ||
        raw.contains('TPD')) {
      final match = RegExp(r'try again in ([^.]+)').firstMatch(raw);
      final wait = match?.group(1);
      return 'Daily AI limit reached.${wait != null ? ' Try again in $wait.' : ' Please try again later.'}';
    }
    if (raw.contains('Rate limit') || raw.contains('rate limit') || raw.contains('TPM')) {
      return 'AI is busy right now. Please wait a moment and try again.';
    }
    return raw;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;
    _controller.clear();

    setState(() {
      _messages.add(_Msg(text, true));
      _isLoading = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      final response = await DioClient.post('/ai/help', data: {'message': text});
      final data = response is Map ? response['data'] : response;

      String answer;
      if (data is Map) {
        answer = (data['reply'] ?? data['message'] ?? data.toString()).toString();
      } else {
        answer = data.toString();
      }

      setState(() {
        _messages.add(_Msg(answer, false));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = _friendlyError(e.toString());
      });
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              color: cs.surface,
              padding: const EdgeInsets.fromLTRB(4, 10, 20, 10),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
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
                  Text('Ask me anything legal',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
                ]),
              ]),
            ),
            const Divider(height: 1),

            // ── Body ────────────────────────────────────────────────────────
            Expanded(
              child: _messages.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return _ChatBubble(msg: msg);
                      },
                    ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask a legal question...',
                        filled: true,
                        fillColor: AppColors.accentContainer,
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.full,
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isLoading ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _Msg msg;
  const _ChatBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: msg.isUser ? AppColors.accentContainer : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(msg.text),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.auto_awesome_rounded,
                  color: cs.onPrimaryContainer, size: 40),
            ),
            const SizedBox(height: 20),
            Text('Ask me anything legal',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}