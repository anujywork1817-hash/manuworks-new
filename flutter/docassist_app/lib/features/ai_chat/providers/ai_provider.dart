import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

// ─── AI feature notifier (Summarize, KeyPoints, Timeline, Actions, Analyze) ───

class AIState {
  final bool isLoading;
  final String? error;
  const AIState({this.isLoading = false, this.error});
  AIState copyWith({bool? isLoading, String? error}) =>
      AIState(isLoading: isLoading ?? this.isLoading, error: error);
}

class AINotifier extends StateNotifier<AIState> {
  AINotifier() : super(const AIState());

  Future<String> processDocument(String docId) async {
    final response = await DioClient.post('/documents/$docId/process');
    return response['message'] ?? 'Document processed successfully';
  }

  Future<String> summarize(String docId) async {
    final response = await DioClient.post('/documents/$docId/summarize');
    final data = response['data'];
    return data['summary'] ?? data.toString();
  }

  Future<String> extractKeyPoints(String docId) async {
    final response = await DioClient.post('/documents/$docId/keypoints');
    final data = response['data'];
    if (data is List) return data.map((e) => '• $e').join('\n');
    if (data is Map && data['key_points'] is List) {
      return (data['key_points'] as List).map((e) => '• $e').join('\n');
    }
    return data.toString();
  }

  Future<String> extractTimeline(String docId) async {
    final response = await DioClient.post('/documents/$docId/timeline');
    final data = response['data'];
    if (data is Map && data['events'] is List) {
      return (data['events'] as List)
          .map((e) => '${e['date']}: ${e['event']}')
          .join('\n');
    }
    return data.toString();
  }

  Future<String> extractActionItems(String docId) async {
    final response = await DioClient.post('/documents/$docId/actions');
    final data = response['data'];
    if (data is List) return data.map((e) => '☑ $e').join('\n');
    if (data is Map && data['action_items'] is List) {
      return (data['action_items'] as List)
          .map((e) => '☑ ${e['action']} (${e['priority'] ?? ''})')
          .join('\n');
    }
    return data.toString();
  }

  Future<String> analyzeDocument(String docId) async {
    final response = await DioClient.post('/documents/$docId/analyze');
    final data = response['data'];
    if (data is Map) {
      final buffer = StringBuffer();
      if (data['document_type'] != null) {
        buffer.writeln('Type: ${data['document_type']}');
      }
      if (data['sentiment'] != null) buffer.writeln('Sentiment: ${data['sentiment']}');
      if (data['risk_level'] != null) buffer.writeln('Risk: ${data['risk_level']}');
      if (data['insights'] is List) {
        buffer.writeln('\nInsights:');
        for (final i in (data['insights'] as List)) {
          buffer.writeln('• $i');
        }
      }
      return buffer.toString();
    }
    return data.toString();
  }

  Future<String> translateDocument(String docId, String targetLanguage) async {
    final response = await DioClient.post('/documents/$docId/translate',
        data: {'target_language': targetLanguage});
    final data = response['data'];
    if (data is Map) return data['translated_text'] ?? data.toString();
    return data.toString();
  }

  Future<String> checkGrammar(String docId) async {
    final response = await DioClient.post('/documents/$docId/grammar');
    final data = response['data'];
    if (data is! Map) return data.toString();

    final score = data['score'] ?? 0;
    final issueCount = data['issue_count'] ?? 0;
    final summary = data['summary'] ?? '';
    final issues = data['issues'];

    final scoreIcon = score >= 90 ? '✅' : score >= 70 ? '🟡' : '🔴';
    final buf = StringBuffer();
    buf.writeln('$scoreIcon GRAMMAR CHECK — Score: $score/100');
    buf.writeln();

    if (issueCount == 0) {
      buf.writeln('✅ No grammatical errors found.');
      buf.writeln();
      buf.writeln(summary);
      return buf.toString().trim();
    }

    buf.writeln('Found $issueCount issue${issueCount == 1 ? '' : 's'}\n');

    if (issues is List) {
      for (final issue in issues) {
        if (issue is! Map) continue;
        final type = (issue['type'] ?? '').toString();
        final typeIcon = _grammarTypeIcon(type);
        buf.writeln('$typeIcon ${_grammarTypeLabel(type)}');
        buf.writeln('  ✗ "${issue['original'] ?? ''}"');
        buf.writeln('  ✓ "${issue['correction'] ?? ''}"');
        if ((issue['explanation'] ?? '').toString().isNotEmpty) {
          buf.writeln('  → ${issue['explanation']}');
        }
        buf.writeln();
      }
    }

    buf.writeln('─────────────────────');
    buf.writeln(summary);
    return buf.toString().trim();
  }

  String _grammarTypeIcon(String type) {
    switch (type) {
      case 'spelling': return '🔤';
      case 'punctuation': return '⚡';
      case 'tense': return '⏰';
      case 'subject-verb': return '🔗';
      case 'article': return '📌';
      case 'preposition': return '📍';
      case 'sentence-structure': return '🏗️';
      default: return '❌';
    }
  }

  String _grammarTypeLabel(String type) {
    switch (type) {
      case 'subject-verb': return 'Subject-Verb Agreement';
      case 'sentence-structure': return 'Sentence Structure';
      default: return type[0].toUpperCase() + type.substring(1);
    }
  }

  Future<String> autoTag(String docId) async {
    final response = await DioClient.post('/documents/$docId/autotag');
    final data = response['data'];
    if (data is! Map) return data.toString();

    final buf = StringBuffer();
    buf.writeln('🏷️ AUTO-TAGS\n');

    final type = data['document_type'] ?? '';
    final area = data['practice_area'] ?? '';
    final complexity = (data['complexity'] ?? '').toString();

    if (type.isNotEmpty) buf.writeln('📄 Type: $type');
    if (area.isNotEmpty) buf.writeln('⚖️ Practice Area: $area');
    if (complexity.isNotEmpty) {
      final icon = complexity == 'complex' ? '🔴' : complexity == 'moderate' ? '🟡' : '🟢';
      buf.writeln('$icon Complexity: ${complexity[0].toUpperCase()}${complexity.substring(1)}');
    }

    final tags = data['tags'];
    if (tags is List && tags.isNotEmpty) {
      buf.writeln('\n🔖 Tags:');
      buf.writeln(tags.map((t) => '#$t').join('  '));
    }

    return buf.toString().trim();
  }

  Future<String> extractDeadlines(String docId) async {
    final response = await DioClient.post('/documents/$docId/deadlines');
    final data = response['data'];
    if (data is! Map) return data.toString();

    final deadlines = data['deadlines'];
    if (deadlines is! List || deadlines.isEmpty) {
      return '📅 No time-bound obligations or deadlines found in this document.';
    }

    final high = <dynamic>[];
    final medium = <dynamic>[];
    final low = <dynamic>[];
    for (final d in deadlines) {
      if (d is! Map) continue;
      final p = (d['priority'] ?? '').toString().toLowerCase();
      if (p == 'high') { high.add(d); }
      else if (p == 'medium') { medium.add(d); }
      else { low.add(d); }
    }

    final buf = StringBuffer();
    buf.writeln('📅 DEADLINES & TIME LIMITS (${deadlines.length} found)\n');

    void writeGroup(String header, String icon, List<dynamic> items) {
      if (items.isEmpty) return;
      buf.writeln('$icon $header');
      for (final d in items) {
        buf.writeln('  ⏰ ${d['title'] ?? 'Deadline'}');
        buf.writeln('     Date: ${d['date'] ?? 'See document'}');
        if (d['party'] != null && (d['party'] as String).isNotEmpty) {
          buf.writeln('     Party: ${d['party']}');
        }
        buf.writeln('     Action: ${d['obligation'] ?? ''}');
        buf.writeln();
      }
    }

    writeGroup('HIGH PRIORITY', '🔴', high);
    writeGroup('MEDIUM PRIORITY', '🟡', medium);
    writeGroup('LOW PRIORITY', '🟢', low);

    return buf.toString().trim();
  }

  Future<String> scanRisks(String docId) async {
    final response = await DioClient.post('/documents/$docId/risks');
    final data = response['data'];
    if (data is! Map) return data.toString();

    final overall = (data['overall_risk'] ?? 'unknown').toString().toUpperCase();
    final clauses = data['clauses'];
    if (clauses is! List || clauses.isEmpty) {
      return '✅ Overall Risk: $overall\n\nNo significant risk clauses found.';
    }

    final buf = StringBuffer();
    buf.writeln('⚠️ Overall Risk: $overall\n');

    for (final c in clauses) {
      if (c is! Map) continue;
      final level = (c['risk_level'] ?? '').toString().toUpperCase();
      final icon = level == 'HIGH' ? '🔴' : level == 'MEDIUM' ? '🟡' : '🟢';
      buf.writeln('$icon ${c['title'] ?? 'Clause'} [$level]');
      if (c['clause_text'] != null && (c['clause_text'] as String).isNotEmpty) {
        buf.writeln('  "${c['clause_text']}"');
      }
      buf.writeln('  ⚡ ${c['concern'] ?? ''}');
      buf.writeln('  💡 ${c['recommendation'] ?? ''}');
      buf.writeln();
    }

    return buf.toString().trim();
  }

  Future<String> extractCitations(String docId) async {
    final response = await DioClient.post('/documents/$docId/citations');
    final data = response['data'];
    if (data is! Map) return data.toString();

    final buf = StringBuffer();

    void writeSection(String header, String icon, dynamic list) {
      if (list is List && list.isNotEmpty) {
        buf.writeln('$icon $header (${list.length})');
        for (final item in list) { buf.writeln('  • $item'); }
        buf.writeln();
      }
    }

    writeSection('CASES', '⚖️', data['cases']);
    writeSection('STATUTORY SECTIONS', '§', data['sections']);
    writeSection('ACTS & STATUTES', '📜', data['acts']);
    writeSection('CONSTITUTIONAL ARTICLES', '🏛️', data['articles']);
    writeSection('RULES & ORDERS', '📋', data['rules']);

    final result = buf.toString().trim();
    return result.isEmpty ? 'No legal citations found in this document.' : result;
  }
}

final aiProvider = StateNotifierProvider<AINotifier, AIState>(
  (ref) => AINotifier(),
);

// ─── Chat (Q&A) ─────────────────────────────────────────────────────────────
//
// Backend's /documents/:id/chat endpoint answers each question directly
// (it's a single-shot Q&A call, not a stateful session). We keep message
// history client-side and resend it isn't required by backend, but we keep
// the conversation displayed locally.

class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  bool get isUser => role == 'user';
}

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class ChatNotifier extends StateNotifier<ChatState> {
  final String documentId;
  ChatNotifier(this.documentId) : super(const ChatState());

  /// No-op kept for compatibility with screens that call startSession().
  /// Backend has no real session concept — each /chat call is single-shot.
  Future<void> startSession() async {
    // Nothing to initialize; backend doesn't require a session handshake.
  }

  Future<void> sendMessage(String message) async {
    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: message,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      error: null,
    );

    try {
      final response = await DioClient.post(
        '/documents/$documentId/chat',
        data: {'question': message},
      );
      final data = response['data'];

      String answer;
      if (data is Map) {
        answer = (data['answer'] ?? data['message'] ?? data.toString()).toString();
      } else {
        answer = data.toString();
      }

      final assistantMsg = ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_ai',
        role: 'assistant',
        content: answer,
        createdAt: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e.toString()));
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('Daily AI token limit') || raw.contains('tokens per day') || raw.contains('TPD')) {
      final match = RegExp(r'try again in ([^.]+)').firstMatch(raw);
      final wait = match?.group(1);
      return 'Daily AI limit reached.${wait != null ? ' Try again in $wait.' : ' Please try again later.'}';
    }
    if (raw.contains('Rate limit') || raw.contains('rate limit') || raw.contains('TPM')) {
      return 'AI is busy right now. Please wait a moment and try again.';
    }
    return raw;
  }
}

final chatProvider =
    StateNotifierProvider.family<ChatNotifier, ChatState, String>(
  (ref, documentId) => ChatNotifier(documentId),
);