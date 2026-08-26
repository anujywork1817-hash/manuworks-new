import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/services/notification_service.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class Document {
  final String id;
  final String title;
  final String fileType;
  final int fileSize;
  final String fileSizeHuman;
  final String status;
  final bool isProcessed;
  final String? ocrText;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Document({
    required this.id,
    required this.title,
    required this.fileType,
    required this.fileSize,
    required this.fileSizeHuman,
    required this.status,
    required this.isProcessed,
    this.ocrText,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Document.fromJson(Map<String, dynamic> json) => Document(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        fileType: json['file_type'] ?? '',
        fileSize: json['file_size'] ?? 0,
        fileSizeHuman: json['file_size_hr'] ?? json['file_size_human'] ?? '',
        status: json['status'] ?? 'pending',
        isProcessed: json['status'] == 'ready',
        ocrText: json['ocr_text'],
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      );

  String get iconForType {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return '📄';
      case 'docx':
      case 'doc':
        return '📝';
      default:
        return '📁';
    }
  }
}

class DocumentsState {
  final List<Document> documents;
  final bool isLoading;
  final bool isUploading;
  final double uploadProgress;
  final String? error;
  final int total;

  const DocumentsState({
    this.documents = const [],
    this.isLoading = false,
    this.isUploading = false,
    this.uploadProgress = 0,
    this.error,
    this.total = 0,
  });

  DocumentsState copyWith({
    List<Document>? documents,
    bool? isLoading,
    bool? isUploading,
    double? uploadProgress,
    String? error,
    int? total,
  }) =>
      DocumentsState(
        documents: documents ?? this.documents,
        isLoading: isLoading ?? this.isLoading,
        isUploading: isUploading ?? this.isUploading,
        uploadProgress: uploadProgress ?? this.uploadProgress,
        error: error,
        total: total ?? this.total,
      );
}

// ─── Document Notifier ────────────────────────────────────────────────────────

class DocumentNotifier extends StateNotifier<DocumentsState> {
  DocumentNotifier() : super(const DocumentsState());

  Future<void> loadDocuments({int page = 1, String? search}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final queryParams = <String, dynamic>{'page': page, 'limit': 20};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final response =
          await DioClient.get('/documents', queryParams: queryParams);
      final data = response['data'];
      final docs =
          (data['documents'] as List).map((d) => Document.fromJson(d)).toList();

      state = state.copyWith(
        documents: docs,
        isLoading: false,
        total: data['total'] ?? docs.length,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Upload from a PlatformFile — works on both web and mobile
  Future<bool> uploadPlatformFile(PlatformFile file) async {
    state = state.copyWith(isUploading: true, uploadProgress: 0, error: null);
    try {
      MultipartFile multipartFile;

      if (kIsWeb) {
        // Web: use bytes
        final bytes = file.bytes;
        if (bytes == null) {
          state = state.copyWith(
              isUploading: false, error: 'Could not read file bytes');
          return false;
        }
        multipartFile = MultipartFile.fromBytes(bytes, filename: file.name);
      } else {
        // Mobile/Desktop: use path
        final path = file.path;
        if (path == null) {
          state = state.copyWith(
              isUploading: false, error: 'Could not read file path');
          return false;
        }
        multipartFile = await MultipartFile.fromFile(path, filename: file.name);
      }

      final formData = FormData.fromMap({'file': multipartFile});

      final uploadResponse = await DioClient.uploadFile(
        '/documents',
        formData,
        onSendProgress: (sent, total) {
          state = state.copyWith(uploadProgress: sent / total);
        },
      );

      await loadDocuments();
      state = state.copyWith(isUploading: false, uploadProgress: 0);
      NotificationService.instance.show(
        title: 'Document Uploaded',
        body: '${file.name} has been uploaded successfully.',
        type: 'upload',
      );
      // Auto-start background processing immediately after upload.
      try {
        final docId =
            (uploadResponse.data as Map?)?['data']?['id']?.toString() ?? '';
        if (docId.isNotEmpty) {
          await DioClient.post('/documents/$docId/process');
        }
      } catch (_) {}
      return true;
    } catch (e) {
      state = state.copyWith(isUploading: false, error: e.toString());
      return false;
    }
  }

  /// Legacy method kept for compatibility
  Future<bool> uploadDocument(String filePath, String fileName) async {
    state = state.copyWith(isUploading: true, uploadProgress: 0, error: null);
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final uploadResponse = await DioClient.uploadFile(
        '/documents',
        formData,
        onSendProgress: (sent, total) {
          state = state.copyWith(uploadProgress: sent / total);
        },
      );

      await loadDocuments();
      state = state.copyWith(isUploading: false, uploadProgress: 0);
      NotificationService.instance.show(
        title: 'Document Uploaded',
        body: '$fileName has been uploaded successfully.',
        type: 'upload',
      );
      // Auto-start background processing immediately after upload.
      try {
        final docId =
            (uploadResponse.data as Map?)?['data']?['id']?.toString() ?? '';
        if (docId.isNotEmpty) {
          await DioClient.post('/documents/$docId/process');
        }
      } catch (_) {}
      return true;
    } catch (e) {
      state = state.copyWith(isUploading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> deleteDocument(String id) async {
    try {
      await DioClient.delete('/documents/$id');
      state = state.copyWith(
        documents: state.documents.where((d) => d.id != id).toList(),
        total: state.total - 1,
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> processDocument(String id) async {
    try {
      await DioClient.post('/documents/$id/process');
      await loadDocuments();
      NotificationService.instance.show(
        title: 'Document Ready',
        body: 'Your document has been processed and is ready for AI analysis.',
        type: 'process',
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final documentProvider =
    StateNotifierProvider<DocumentNotifier, DocumentsState>(
  (ref) => DocumentNotifier(),
);

// ─── Single document provider ─────────────────────────────────────────────────

final singleDocumentProvider =
    FutureProvider.family<Document, String>((ref, id) async {
  final response = await DioClient.get('/documents/$id');
  return Document.fromJson(response['data']);
}); 