import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Claude-style rotating status word, shown instead of a plain spinner
/// while something slow (upload, OCR, AI processing) is happening.
const _kLoadingWords = [
  'Uploading', 'Thinking', 'Cooking', 'Combobulating', 'Percolating',
  'Marinating', 'Noodling', 'Conjuring', 'Wrangling', 'Churning',
  'Simmering', 'Pondering', 'Deciphering', 'Untangling', 'Brewing',
  'Flabbergasting', 'Sorcering',
];

class FunLoadingWord extends StatefulWidget {
  final TextStyle? style;
  const FunLoadingWord({super.key, this.style});
  @override
  State<FunLoadingWord> createState() => _FunLoadingWordState();
}

class _FunLoadingWordState extends State<FunLoadingWord> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _kLoadingWords.length);
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: Text(
        '${_kLoadingWords[_index]}...',
        key: ValueKey(_index),
        style: widget.style ?? const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
