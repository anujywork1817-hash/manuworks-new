import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class Matter {
  final String id;
  final String title;
  final String matterNo;
  final String client;
  final String court;
  final String status;
  final String description;
  final int docCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Matter({
    required this.id,
    required this.title,
    required this.matterNo,
    required this.client,
    required this.court,
    required this.status,
    required this.description,
    required this.docCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Matter.fromJson(Map<String, dynamic> j) => Matter(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        matterNo: j['matter_no'] ?? '',
        client: j['client'] ?? '',
        court: j['court'] ?? '',
        status: j['status'] ?? 'active',
        description: j['description'] ?? '',
        docCount: (j['doc_count'] ?? 0) as int,
        createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at'] ?? '') ?? DateTime.now(),
      );

  bool get isActive => status == 'active';
}

class MatterDoc {
  final String id;
  final String title;
  final String fileType;
  final String status;

  const MatterDoc({
    required this.id,
    required this.title,
    required this.fileType,
    required this.status,
  });

  factory MatterDoc.fromJson(Map<String, dynamic> j) => MatterDoc(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        fileType: j['file_type'] ?? '',
        status: j['status'] ?? '',
      );
}

// ─── State ────────────────────────────────────────────────────────────────────

class MattersState {
  final List<Matter> matters;
  final bool isLoading;
  final String? error;

  const MattersState({
    this.matters = const [],
    this.isLoading = false,
    this.error,
  });

  MattersState copyWith({
    List<Matter>? matters,
    bool? isLoading,
    String? error,
  }) =>
      MattersState(
        matters: matters ?? this.matters,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class MatterNotifier extends StateNotifier<MattersState> {
  MatterNotifier() : super(const MattersState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await DioClient.get('/matters');
      final list = (res['data']['matters'] as List? ?? [])
          .map((e) => Matter.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(matters: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<Matter?> create({
    required String title,
    String matterNo = '',
    String client = '',
    String court = '',
    String description = '',
  }) async {
    try {
      final res = await DioClient.post('/matters', data: {
        'title': title,
        'matter_no': matterNo,
        'client': client,
        'court': court,
        'description': description,
      });
      final m = Matter.fromJson(res['data'] as Map<String, dynamic>);
      state = state.copyWith(matters: [m, ...state.matters]);
      return m;
    } catch (e) {
      return null;
    }
  }

  Future<bool> update(
    String matterId, {
    String? title,
    String? matterNo,
    String? client,
    String? court,
    String? status,
    String? description,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (matterNo != null) body['matter_no'] = matterNo;
      if (client != null) body['client'] = client;
      if (court != null) body['court'] = court;
      if (status != null) body['status'] = status;
      if (description != null) body['description'] = description;
      await DioClient.patch<dynamic>('/matters/$matterId', data: body);
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(String matterId) async {
    try {
      await DioClient.delete('/matters/$matterId');
      state = state.copyWith(
          matters: state.matters.where((m) => m.id != matterId).toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> addDocument(String matterId, String documentId) async {
    try {
      await DioClient.post('/matters/$matterId/documents',
          data: {'document_id': documentId});
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeDocument(String matterId, String documentId) async {
    try {
      await DioClient.delete('/matters/$matterId/documents/$documentId');
      return true;
    } catch (_) {
      return false;
    }
  }
}

final matterProvider =
    StateNotifierProvider<MatterNotifier, MattersState>((ref) => MatterNotifier());

// Detail provider — fetches single matter with its documents
final matterDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, matterId) async {
  final res = await DioClient.get('/matters/$matterId');
  return res['data'] as Map<String, dynamic>;
});
