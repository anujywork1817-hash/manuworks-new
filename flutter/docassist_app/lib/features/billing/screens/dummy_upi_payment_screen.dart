import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// A self-contained **demo** payment screen that mimics the look of a UPI
/// app (GPay-style) opening to collect payment, then always resolves to a
/// success screen after a short simulated delay.
///
/// ⚠️ This is a dummy/demo flow only — no real money moves and no real UPI
/// app is required to be installed. Swap this out for a real payment
/// gateway / UPI intent before going live.
class DummyUpiPaymentScreen extends StatefulWidget {
  final double amount;
  final String planName;
  final String note;

  const DummyUpiPaymentScreen({
    super.key,
    required this.amount,
    required this.planName,
    required this.note,
  });

  @override
  State<DummyUpiPaymentScreen> createState() => _DummyUpiPaymentScreenState();
}

enum _PayStage { app, processing, success }

class _DummyUpiPaymentScreenState extends State<DummyUpiPaymentScreen> {
  _PayStage _stage = _PayStage.app;
  late final String _txnId;

  @override
  void initState() {
    super.initState();
    _txnId = 'DEMO${DateTime.now().millisecondsSinceEpoch}';
    // Simulate the "opening GPay" hand-off, then processing, then success.
    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _stage = _PayStage.processing);
      Timer(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        setState(() => _stage = _PayStage.success);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _PayStage.success,
      child: Scaffold(
        backgroundColor: _stage == _PayStage.success ? AppColors.background : const Color(0xFF202124),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: switch (_stage) {
              _PayStage.app => _buildGPaySplash(key: const ValueKey('app')),
              _PayStage.processing => _buildProcessing(key: const ValueKey('processing')),
              _PayStage.success => _buildSuccess(key: const ValueKey('success')),
            },
          ),
        ),
      ),
    );
  }

  // ── "GPay opening" splash ────────────────────────────────────────────
  Widget _buildGPaySplash({Key? key}) => Center(
        key: key,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const _GPayLogo(size: 34),
          ),
          const SizedBox(height: 18),
          const Text('Google Pay', style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Demo mode — connecting…',
              style: TextStyle(color: Colors.white54, fontSize: 12.5)),
          const SizedBox(height: 26),
          const SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70),
          ),
        ]),
      );

  // ── Processing payment ───────────────────────────────────────────────
  Widget _buildProcessing({Key? key}) => Center(
        key: key,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30, height: 30,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const _GPayLogo(size: 16),
          ),
          const SizedBox(height: 22),
          const SizedBox(
            width: 40, height: 40,
            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
          ),
          const SizedBox(height: 22),
          Text('₹${widget.amount.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Processing payment…',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ]),
      );

  // ── Success screen ───────────────────────────────────────────────────
  Widget _buildSuccess({Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(children: [
          const Spacer(),
          Container(
            width: 84, height: 84,
            decoration: const BoxDecoration(
              color: AppColors.successContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_rounded, color: AppColors.success, size: 48),
          ),
          const SizedBox(height: 22),
          const Text('Payment Successful',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('₹${widget.amount.toStringAsFixed(0)} paid for ${widget.planName} plan',
              style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outline),
            ),
            child: Column(children: [
              _receiptRow('Transaction ID', _txnId),
              const SizedBox(height: 10),
              _receiptRow('Paid via', 'Google Pay (Demo)'),
              const SizedBox(height: 10),
              _receiptRow('Status', 'Success'),
            ]),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      );

  Widget _receiptRow(String label, String value) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ]);
}

/// Minimal 4-colour "G"-style mark so the demo splash reads as "Google Pay"
/// without pulling in a real logo asset or trademarked image.
class _GPayLogo extends StatelessWidget {
  final double size;
  const _GPayLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GPayLogoPainter()),
    );
  }
}

class _GPayLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final stroke = size.width * 0.28;
    final rect = Rect.fromCircle(center: center, radius: r - stroke / 2);
    final colors = [
      const Color(0xFF4285F4), // blue
      const Color(0xFF34A853), // green
      const Color(0xFFFBBC05), // yellow
      const Color(0xFFEA4335), // red
    ];
    const sweep = 1.5708; // 90deg each
    for (var i = 0; i < 4; i++) {
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, -1.5708 + i * sweep, sweep - 0.12, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}