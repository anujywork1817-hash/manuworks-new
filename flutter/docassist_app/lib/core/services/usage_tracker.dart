import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks how many times each AI feature has been used, locally on-device,
/// so the Usage Dashboard (Profile → Dashboard) can show "who used what,
/// how many times" without needing a backend analytics endpoint.
///
/// Data shape stored under a single shared_preferences key:
/// {
///   "totalRuns": 12,
///   "byFeature": { "summarize": 5, "keypoints": 2, ... },
///   "byDay": { "2026-08-13": { "summarize": 3, "grammar": 1 }, ... }
/// }
class UsageTracker {
  UsageTracker._();
  static const _storageKey = 'ai_usage_stats_v1';

  /// Total credits available on the account. There's no credits endpoint
  /// on the backend yet, so this is a local placeholder plan allowance
  /// (mirrors the manuworks.ai web dashboard's default "Pro" plan).
  static const int totalCredits = 7500;

  /// Credits charged per AI feature run — a flat placeholder cost used
  /// until the backend exposes real per-feature pricing.
  static const int creditsPerRun = 20;

  /// Per-feature credit cost, shown on the Dashboard's AI Tools cards
  /// (mirrors the manuworks.ai web dashboard's pricing per tool).
  /// Falls back to [creditsPerRun] for any feature not listed here.
  static const Map<String, int> creditsPerFeature = {
    'summarize': 5,
    'draft': 40,
    'translate': 15,
    'ocr': 12,
    'timeline': 6,
    'ai_chat': 4,
    'compare': 8,
    'citations': 10,
  };

  /// Credit cost for a given feature id, falling back to [creditsPerRun].
  static int creditsFor(String featureId) =>
      creditsPerFeature[featureId] ?? creditsPerRun;

  /// Used / balance derived from local run counts, against a real account
  /// total. [totalOverride] should come from the backend (user_settings.credits,
  /// exposed via GET /auth/me) — pass it whenever available so purchases made
  /// through Recharge Credits are reflected instead of the placeholder plan.
  static Future<Map<String, int>> getCreditsSummary({int? totalOverride}) async {
    final stats = await getStats();
    final total = totalOverride ?? totalCredits;
    final totalRuns = stats['totalRuns'] as int? ?? 0;
    final used = (totalRuns * creditsPerRun).clamp(0, total);
    return {
      'total': total,
      'used': used,
      'balance': total - used,
    };
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Call this every time an AI feature successfully runs.
  static Future<void> logUsage(String featureId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    Map<String, dynamic> data = raw != null
        ? jsonDecode(raw) as Map<String, dynamic>
        : {'totalRuns': 0, 'byFeature': {}, 'byDay': {}};

    data['totalRuns'] = (data['totalRuns'] as int? ?? 0) + 1;

    final byFeature = Map<String, dynamic>.from(data['byFeature'] ?? {});
    byFeature[featureId] = (byFeature[featureId] as int? ?? 0) + 1;
    data['byFeature'] = byFeature;

    final byDay = Map<String, dynamic>.from(data['byDay'] ?? {});
    final today = _todayKey();
    final todayMap = Map<String, dynamic>.from(byDay[today] ?? {});
    todayMap[featureId] = (todayMap[featureId] as int? ?? 0) + 1;
    byDay[today] = todayMap;
    data['byDay'] = byDay;

    await prefs.setString(_storageKey, jsonEncode(data));
  }

  /// Returns the raw stats map (never null — empty defaults if nothing yet).
  static Future<Map<String, dynamic>> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return {'totalRuns': 0, 'byFeature': {}, 'byDay': {}};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Feature usage counts for the last [days] days (default: 7), per day,
  /// in chronological order (oldest first). Handy for a bar chart.
  static Future<List<MapEntry<String, int>>> lastNDaysTotals({int days = 7}) async {
    final stats = await getStats();
    final byDay = Map<String, dynamic>.from(stats['byDay'] ?? {});
    final now = DateTime.now();
    final result = <MapEntry<String, int>>[];
    for (int i = days - 1; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      final dayData = Map<String, dynamic>.from(byDay[key] ?? {});
      final total = dayData.values.fold<int>(0, (sum, v) => sum + (v as int));
      result.add(MapEntry(key, total));
    }
    return result;
  }
}