import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../ai_features/screens/ai_feature_detail_screen.dart';

const _kWelcomeSeenKey = 'welcome_dialog_seen_v1';

/// Shows the first-run welcome dialog once per install. Safe to call on
/// every Dashboard build — it no-ops after the first successful dismissal.
Future<void> maybeShowWelcomeDialog(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kWelcomeSeenKey) == true) return;
  if (!context.mounted) return;
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Welcome',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, __, ___) => const _WelcomeDialog(),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
  await prefs.setBool(_kWelcomeSeenKey, true);
}

class _WelcomeDialog extends StatelessWidget {
  const _WelcomeDialog();

  static const _highlightFeatures = [
    'summarize', 'translate', 'analyze', 'timeline', 'risks', 'grammar',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 40, offset: const Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Gradient hero ─────────────────────────────────────────────
            Stack(children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [cs.primary, cs.secondary.withValues(alpha: 0.85)],
                  ),
                ),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('WELCOME', style: tt.labelSmall?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                    ),
                    child: const Icon(Icons.balance_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 14),
                  Text('Welcome to LexDocs',
                    textAlign: TextAlign.center,
                    style: tt.headlineSmall?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Text('Your AI-powered legal document workspace',
                    textAlign: TextAlign.center,
                    style: tt.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
                ]),
              ),
              Positioned(
                top: 12, right: 12,
                child: _CloseButton(onTap: () => Navigator.of(context).pop()),
              ),
            ]),

            // ── Body ─────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _WayCard(
                    icon: Icons.auto_awesome_outlined,
                    iconColor: cs.primary,
                    title: '1. AI Tools',
                    body: 'Summarize, Translate, Draft, Compare, OCR and more — '
                        'pick any tool right from the Home screen.',
                    cs: cs, tt: tt,
                  ),
                  const SizedBox(height: 10),
                  _WayCard(
                    icon: Icons.chat_bubble_outline_rounded,
                    iconColor: cs.secondary,
                    title: '2. AI Chat',
                    body: 'Ask questions about your documents and get cited '
                        'answers straight from the source.',
                    cs: cs, tt: tt,
                  ),
                  const SizedBox(height: 20),

                  // Feature icon strip
                  Wrap(
                    spacing: 10, runSpacing: 10,
                    children: _highlightFeatures.map((id) {
                      final f = kAiFeatures.firstWhere((e) => e.id == id);
                      return _FeatureChip(icon: f.icon, label: f.label, cs: cs, tt: tt);
                    }).toList(),
                  ),
                  const SizedBox(height: 22),

                  Text('YOU\'LL ALSO FIND', style: tt.labelSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.5), letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _HighlightRow(icon: Icons.bar_chart_rounded,
                      title: 'Dashboard', subtitle: 'Track your usage & activity', cs: cs, tt: tt),
                  const SizedBox(height: 10),
                  _HighlightRow(icon: Icons.bolt_rounded,
                      title: 'Credits', subtitle: 'Recharge and manage your balance', cs: cs, tt: tt),
                  const SizedBox(height: 10),
                  _HighlightRow(icon: Icons.folder_outlined,
                      title: 'Documents', subtitle: 'Every file you upload, in one place', cs: cs, tt: tt),
                ]),
              ),
            ),

            // ── CTA ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Get Started', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    customBorder: const CircleBorder(),
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
    ),
  );
}

class _WayCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, body;
  final ColorScheme cs;
  final TextTheme tt;
  const _WayCard({required this.icon, required this.iconColor, required this.title,
      required this.body, required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 19),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(body, style: tt.bodySmall?.copyWith(height: 1.35)),
      ])),
    ]),
  );
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme cs;
  final TextTheme tt;
  const _FeatureChip({required this.icon, required this.label, required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: cs.outline),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: cs.primary),
      const SizedBox(width: 6),
      Text(label, style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
    ]),
  );
}

class _HighlightRow extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final ColorScheme cs;
  final TextTheme tt;
  const _HighlightRow({required this.icon, required this.title, required this.subtitle,
      required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 34, height: 34,
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, color: cs.primary, size: 17),
    ),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      Text(subtitle, style: tt.bodySmall),
    ])),
  ]);
}
