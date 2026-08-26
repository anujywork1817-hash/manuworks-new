import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/router.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../../core/services/usage_tracker.dart';

final dashboardStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final res = await DioClient.get('/documents', queryParams: {'limit': 5});
    return {
      'recent_documents': res['data']['documents'] ?? [],
      'total_documents': res['data']['total'] ?? 0,
    };
  } catch (_) {
    return {'recent_documents': [], 'total_documents': 0};
  }
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dashboardStatsProvider); // keeps stats cached/refreshed for other screens
    final userAsync   = ref.watch(currentUserProvider);
    final unreadCount = ref.watch(notificationsProvider.select((s) => s.unreadCount));
    final cs          = Theme.of(context).colorScheme;
    final tt          = Theme.of(context).textTheme;

    final userName = userAsync.maybeWhen(
      data: (u) {
        final email = (u['email'] ?? '').toString();
        final name  = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
        return name.isNotEmpty ? name : email.split('@').first;
      },
      orElse: () => '',
    );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: cs.primary,
          onRefresh: () => ref.refresh(dashboardStatsProvider.future),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [

              // ── Header ─────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(children: [
                    // Logo mark
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.balance_rounded,
                          color: cs.onPrimary, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Text('LexDocs',
                      style: tt.titleLarge?.copyWith(
                        letterSpacing: -0.5, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    _NotificationBell(unreadCount: unreadCount, cs: cs),
                  ]),
                ),
              ),

              // ── Greeting ───────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      userName.isNotEmpty ? 'Good day, $userName.' : 'Good day.',
                      style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text('Your legal workspace is ready.',
                      style: tt.bodyMedium),
                  ]),
                ),
              ),

              // ── Quick actions: Dashboard + Recharge Credits ──────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: IntrinsicHeight(child: Row(children: [
                    Expanded(child: _QuickCard(
                      icon: Icons.bar_chart_rounded,
                      title: 'Dashboard',
                      subtitle: 'View your usage & activity stats',
                      onTap: () => context.push(AppRoutes.usageDashboard),
                      cs: cs, tt: tt,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _QuickCard(
                      icon: Icons.bolt_rounded,
                      title: 'Recharge Credits',
                      subtitle: 'Top up credits to keep using AI tools',
                      onTap: () => context.push(AppRoutes.rechargeCredits),
                      cs: cs, tt: tt,
                    )),
                  ])),
                ),
              ),


              // ── AI Tools ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('AI Tools', style: tt.titleMedium),
                    const SizedBox(height: 4),
                    Text('AI-powered tools for your documents',
                        style: tt.bodySmall?.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 14),
                    IntrinsicHeight(child: Row(children: [
                      Expanded(child: _AiToolCard(
                        icon: Icons.summarize_outlined,
                        title: 'Generate Summary',
                        subtitle: 'Turn long docs into concise summaries',
                        credits: UsageTracker.creditsFor('summarize'),
                        onTap: () => context.push('${AppRoutes.aiFeatures}/summarize'),
                        cs: cs, tt: tt,
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _AiToolCard(
                        icon: Icons.edit_note_outlined,
                        title: 'Drafter',
                        subtitle: 'Draft documents tailored to your needs',
                        credits: UsageTracker.creditsFor('draft'),
                        onTap: () => context.push(AppRoutes.draft),
                        cs: cs, tt: tt,
                      )),
                    ])),
                    const SizedBox(height: 10),
                    IntrinsicHeight(child: Row(children: [
                      Expanded(child: _AiToolCard(
                        icon: Icons.translate_outlined,
                        title: 'Translator',
                        subtitle: 'Translate documents instantly',
                        credits: UsageTracker.creditsFor('translate'),
                        onTap: () => context.push('${AppRoutes.aiFeatures}/translate'),
                        cs: cs, tt: tt,
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _AiToolCard(
                        icon: Icons.document_scanner_outlined,
                        title: 'OCR',
                        subtitle: 'Convert scanned docs to editable text',
                        credits: UsageTracker.creditsFor('ocr'),
                        onTap: () => context.push(AppRoutes.ocrScan),
                        cs: cs, tt: tt,
                      )),
                    ])),
                    const SizedBox(height: 10),
                    IntrinsicHeight(child: Row(children: [
                      Expanded(child: _AiToolCard(
                        icon: Icons.timeline_outlined,
                        title: 'Timeline Generator',
                        subtitle: 'Visualize events in sequence over time',
                        credits: UsageTracker.creditsFor('timeline'),
                        onTap: () => context.push('${AppRoutes.aiFeatures}/timeline'),
                        cs: cs, tt: tt,
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _AiToolCard(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'Ask Questions',
                        subtitle: 'Ask questions & get cited answers',
                        credits: UsageTracker.creditsFor('ai_chat'),
                        onTap: () => context.push(AppRoutes.aiChat),
                        cs: cs, tt: tt,
                      )),
                    ])),
                    const SizedBox(height: 10),
                    IntrinsicHeight(child: Row(children: [
                      Expanded(child: _AiToolCard(
                        icon: Icons.compare_arrows_rounded,
                        title: 'Compare Documents',
                        subtitle: 'Compare two documents side by side',
                        credits: UsageTracker.creditsFor('compare'),
                        onTap: () => context.push(AppRoutes.compare),
                        cs: cs, tt: tt,
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _AiToolCard(
                        icon: Icons.gavel_outlined,
                        title: 'Citation Verifier',
                        subtitle: 'Verify citations instantly',
                        credits: UsageTracker.creditsFor('citations'),
                        onTap: () => context.push('${AppRoutes.aiFeatures}/citations'),
                        cs: cs, tt: tt,
                      )),
                    ])),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Notification bell ─────────────────────────────────────────────────────────

class _NotificationBell extends StatelessWidget {
  final int unreadCount;
  final ColorScheme cs;
  const _NotificationBell({required this.unreadCount, required this.cs});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push(AppRoutes.notifications),
    child: Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outline),
        ),
        child: Icon(Icons.notifications_outlined, color: cs.onSurface, size: 20),
      ),
      if (unreadCount > 0)
        Positioned(
          right: -2, top: -2,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              unreadCount > 99 ? '99+' : '$unreadCount',
              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
    ]),
  );
}

// ── Quick access card ─────────────────────────────────────────────────────────

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final ColorScheme cs;
  final TextTheme tt;

  const _QuickCard({
    required this.icon, required this.title, required this.subtitle,
    required this.onTap, required this.cs, required this.tt,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: cs.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.2)),
          const SizedBox(height: 2),
          Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall),
        ])),
      ]),
    ),
  );
}

// ── AI Tool card (title, subtitle, "Try it now" + credit cost) ────────────────

class _AiToolCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final int credits;
  final String? badge; // e.g. 'NEW' / 'PRO'
  final VoidCallback onTap;
  final ColorScheme cs;
  final TextTheme tt;

  const _AiToolCard({
    required this.icon, required this.title, required this.subtitle,
    required this.credits,
    required this.onTap, required this.cs, required this.tt,
  }) : badge = null;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Icon + optional badge
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: cs.primary, size: 16),
          ),
          if (badge != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: cs.onPrimary,
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.2)),
        const SizedBox(height: 2),
        Text(subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tt.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.25)),
        const SizedBox(height: 10),
        // Bottom: credit cost
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bolt_rounded, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 2),
          Text(
            '$credits credits',
            style: tt.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ]),
      ]),
    ),
  );
}