import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
import '../../../core/theme/app_theme.dart';
import '../../../core/services/usage_tracker.dart';
import '../../../core/services/document_export_service.dart';
import '../../ai_features/screens/ai_feature_detail_screen.dart';
import '../../auth/providers/auth_provider.dart';

/// "Dashboard" screen reachable from Profile → Dashboard.
/// Shows the user's credits (total / used / balance), a last-7-days usage
/// chart, a per-feature breakdown, and CSV / PPT / Word export — modelled
/// after the manuworks.ai analytics dashboard.
class UsageDashboardScreen extends ConsumerStatefulWidget {
  const UsageDashboardScreen({super.key});
  @override
  ConsumerState<UsageDashboardScreen> createState() => _UsageDashboardScreenState();
}

class _UsageDashboardScreenState extends ConsumerState<UsageDashboardScreen> {
  Map<String, dynamic>? _stats;
  List<MapEntry<String, int>>? _last7Days;
  Map<String, int>? _credits;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await UsageTracker.getStats();
    final last7 = await UsageTracker.lastNDaysTotals(days: 7);
    final credits = await UsageTracker.getCreditsSummary();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _last7Days = last7;
      _credits = credits;
      _loading = false;
    });
  }

  String _labelFor(String featureId) {
    final match = kAiFeatures.where((f) => f.id == featureId);
    if (match.isNotEmpty) return match.first.label;
    if (featureId == 'summarize') return 'Summarize';
    return featureId;
  }

  String _dayLabel(String isoDay) {
    final parts = isoDay.split('-');
    if (parts.length != 3) return isoDay;
    const months = ['', 'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[int.parse(parts[1])]} ${int.parse(parts[2])}';
  }

  List<MapEntry<String, int>> _featureEntries() {
    final byFeature = Map<String, dynamic>.from(_stats?['byFeature'] ?? {});
    return byFeature.entries.map((e) => MapEntry(e.key, e.value as int)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  Future<void> _export(String type) async {
    if (_exporting || _stats == null || _credits == null || _last7Days == null) return;
    setState(() => _exporting = true);
    try {
      final entries = _featureEntries();
      final totalRuns = _stats!['totalRuns'] as int? ?? 0;
      switch (type) {
        case 'csv':
          final rows = <List<String>>[
            ['Metric', 'Value'],
            ['Total Credits', '${_credits!['total']}'],
            ['Used Credits', '${_credits!['used']}'],
            ['Balance', '${_credits!['balance']}'],
            ['Total AI Runs', '$totalRuns'],
            [],
            ['Day', 'Runs'],
            ...(_last7Days!.map((e) => [_dayLabel(e.key), '${e.value}'])),
            [],
            ['Feature', 'Runs'],
            ...(entries.map((e) => [_labelFor(e.key), '${e.value}'])),
          ];
          await DocumentExportService.exportToCsv(title: 'Dashboard Summary', rows: rows);
          break;
        case 'word':
          final buffer = StringBuffer()
            ..writeln('Dashboard Summary')
            ..writeln()
            ..writeln('Total Credits: ${_credits!['total']}')
            ..writeln('Used Credits: ${_credits!['used']}')
            ..writeln('Balance: ${_credits!['balance']}')
            ..writeln('Total AI Runs: $totalRuns')
            ..writeln()
            ..writeln('Last 7 days')
            ..writeln(_last7Days!.map((e) => '${_dayLabel(e.key)}: ${e.value}').join('\n'))
            ..writeln()
            ..writeln('Usage by feature')
            ..writeln(entries.map((e) => '${_labelFor(e.key)}: ${e.value}').join('\n'));
          await DocumentExportService.exportToDocx(title: 'Dashboard Summary', content: buffer.toString());
          break;
        case 'ppt':
          await DocumentExportService.exportToPptx(title: 'Dashboard Summary', slides: [
            PptxSlide(title: 'Credits Overview', bullets: [
              'Total Credits: ${_credits!['total']}',
              'Used Credits: ${_credits!['used']}',
              'Balance: ${_credits!['balance']}',
              'Total AI Runs: $totalRuns',
            ]),
            PptxSlide(
              title: 'Last 7 Days',
              bullets: _last7Days!.map((e) => '${_dayLabel(e.key)}: ${e.value} runs').toList(),
            ),
            PptxSlide(
              title: 'Usage by Feature',
              bullets: entries.isEmpty
                  ? ['No AI features used yet.']
                  : entries.map((e) => '${_labelFor(e.key)}: ${e.value}').toList(),
            ),
          ]);
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userAsync = ref.watch(currentUserProvider);

    if (_loading || _stats == null || _last7Days == null || _credits == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final userName = userAsync.maybeWhen(
      data: (u) {
        final email = (u['email'] ?? '').toString();
        final name  = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
        if (name.isNotEmpty) return name;
        if (email.isNotEmpty) {
          final handle = email.split('@').first.replaceAll(RegExp(r'[._]'), ' ');
          return handle.split(' ').where((w) => w.isNotEmpty)
              .map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
        }
        return 'there';
      },
      orElse: () => 'there',
    );

    final entries = _featureEntries();
    final maxDayTotal = _last7Days!.isEmpty
        ? 1
        : _last7Days!.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);
    final maxFeatureCount = entries.isEmpty
        ? 1
        : entries.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);

    // Real balance from the backend — watched so a purchase made on the
    // Recharge Credits screen (which invalidates creditsProvider) is
    // reflected here immediately, without needing to reopen this screen.
    final backendTotal = ref.watch(creditsProvider).valueOrNull;
    final totalCredits = backendTotal ?? _credits!['total']!;
    final usedCredits = _credits!['used']!;
    final balance = (totalCredits - usedCredits).clamp(0, totalCredits);

    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bar_chart_rounded, size: 20),
          SizedBox(width: 8),
          Text('Dashboard'),
        ]),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_outlined),
            onPressed: _exporting ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              // ── Greeting ──────────────────────────────────────────────
              Text('Hi $userName!', style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.md),

              // ── Credits — donut ring + circular stat badges ─────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(children: [
                    SizedBox(
                      height: 170,
                      child: Stack(alignment: Alignment.center, children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 4,
                            centerSpaceRadius: 58,
                            startDegreeOffset: -90,
                            sections: [
                              PieChartSectionData(
                                value: math.max(balance, 0).toDouble(),
                                color: AppColors.primary,
                                radius: 20,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: usedCredits <= 0 ? 0.0001 : usedCredits.toDouble(),
                                color: AppColors.outlineVariant,
                                radius: 20,
                                showTitle: false,
                              ),
                            ],
                          ),
                        ),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('$balance',
                              style: theme.textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          Text('Balance',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary)),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CircleStat(
                          icon: Icons.autorenew_rounded,
                          color: Colors.blue,
                          label: 'Total Credits',
                          value: '$totalCredits',
                        ),
                        _CircleStat(
                          icon: Icons.local_fire_department_rounded,
                          color: AppColors.error,
                          label: 'Used Credits',
                          value: '$usedCredits',
                        ),
                      ],
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Export row ─────────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: Text('Last 7 days', style: theme.textTheme.titleSmall
                      ?.copyWith(color: AppColors.textSecondary)),
                ),
                _ExportButton(
                  icon: Icons.grid_on_rounded,
                  label: 'CSV',
                  color: AppColors.success,
                  onTap: _exporting ? null : () => _export('csv'),
                ),
                const SizedBox(width: 8),
                _ExportButton(
                  icon: Icons.slideshow_rounded,
                  label: 'PPT',
                  color: AppColors.error,
                  onTap: _exporting ? null : () => _export('ppt'),
                ),
                const SizedBox(width: 8),
                _ExportButton(
                  icon: Icons.description_rounded,
                  label: 'Word',
                  color: Colors.blue,
                  onTap: _exporting ? null : () => _export('word'),
                ),
              ]),
              const SizedBox(height: AppSpacing.sm),

              // ── Last 7 days chart ──────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
                  child: SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: ((maxDayTotal == 0 ? 5 : maxDayTotal) * 1.2).ceilToDouble(),
                        gridData: const FlGridData(show: true, drawVerticalLine: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                if (value != value.roundToDouble()) return const SizedBox();
                                return Text('${value.toInt()}',
                                    style: const TextStyle(fontSize: 11));
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final i = value.toInt();
                                if (i < 0 || i >= _last7Days!.length) return const SizedBox();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(_dayLabel(_last7Days![i].key),
                                      style: const TextStyle(fontSize: 10)),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (int i = 0; i < _last7Days!.length; i++)
                            BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: _last7Days![i].value.toDouble(),
                                color: AppColors.primary,
                                width: 18,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Per-feature usage breakdown ────────────────────────────
              Text('Credits by feature', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (entries.isEmpty)
                Card(child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: Text('No AI features used yet.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary)),
                  ),
                ))
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: entries.map((e) {
                        final fraction = maxFeatureCount == 0 ? 0.0 : e.value / maxFeatureCount;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(children: [
                            SizedBox(
                              width: 96,
                              child: Text(_labelFor(e.key),
                                  style: theme.textTheme.bodyMedium,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: fraction.clamp(0.02, 1.0),
                                  minHeight: 14,
                                  backgroundColor: AppColors.outlineVariant,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 28,
                              child: Text('${e.value}',
                                  textAlign: TextAlign.right,
                                  style: theme.textTheme.labelMedium),
                            ),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _CircleStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 76, height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ]),
      ),
      const SizedBox(height: 6),
      Text(label, style: theme.textTheme.bodySmall
          ?.copyWith(color: AppColors.textSecondary)),
    ]);
  }
}

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ExportButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}