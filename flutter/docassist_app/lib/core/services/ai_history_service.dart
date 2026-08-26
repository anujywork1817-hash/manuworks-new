import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A single saved AI-generated result, scoped to one feature (e.g. 'draft',
/// 'summarize', 'complaint_reply', 'compare', 'ocr'...).
class AiHistoryEntry {
  final String id;
  final String featureId;
  final String title;
  final String subtitle;
  final String content;
  final DateTime createdAt;

  const AiHistoryEntry({
    required this.id,
    required this.featureId,
    required this.title,
    this.subtitle = '',
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'feature_id': featureId,
        'title': title,
        'subtitle': subtitle,
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };

  factory AiHistoryEntry.fromJson(Map<String, dynamic> json) => AiHistoryEntry(
        id: json['id'] ?? '',
        featureId: json['feature_id'] ?? '',
        title: json['title'] ?? '',
        subtitle: json['subtitle'] ?? '',
        content: json['content'] ?? '',
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      );
}

/// Persists AI-generated results locally, **per feature**, so each feature
/// (Draft, Summarize, Complaint Reply, Compare, OCR, ...) keeps its own
/// separate history that survives app restarts. No backend changes needed.
class AiHistoryService {
  AiHistoryService._();

  static const _uuid = Uuid();
  static String _key(String featureId) => 'ai_history_v1_$featureId';

  /// All saved entries for [featureId], newest first.
  static Future<List<AiHistoryEntry>> getAll(String featureId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(featureId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final entries = list
          .map((e) => AiHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } catch (_) {
      return [];
    }
  }

  static Future<AiHistoryEntry> save({
    required String featureId,
    required String title,
    String subtitle = '',
    required String content,
  }) async {
    final entry = AiHistoryEntry(
      id: _uuid.v4(),
      featureId: featureId,
      title: title,
      subtitle: subtitle,
      content: content,
      createdAt: DateTime.now(),
    );
    final all = await getAll(featureId);
    all.insert(0, entry);
    await _persist(featureId, all);
    return entry;
  }

  static Future<void> delete(String featureId, String id) async {
    final all = await getAll(featureId);
    all.removeWhere((e) => e.id == id);
    await _persist(featureId, all);
  }

  static Future<void> clearAll(String featureId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(featureId));
  }

  static Future<void> _persist(String featureId, List<AiHistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_key(featureId), raw);
  }
}