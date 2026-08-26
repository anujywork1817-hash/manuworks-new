import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/document_provider.dart';

class EditDocumentScreen extends ConsumerStatefulWidget {
  final String documentId;
  const EditDocumentScreen({super.key, required this.documentId});

  @override
  ConsumerState<EditDocumentScreen> createState() => _EditDocumentScreenState();
}

class _EditDocumentScreenState extends ConsumerState<EditDocumentScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _ocrCtrl = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _ocrCtrl.dispose();
    super.dispose();
  }

  void _populate(Document doc) {
    if (_loaded) return;
    _titleCtrl.text = doc.title;
    _descCtrl.text = '';
    _ocrCtrl.text = doc.ocrText ?? '';
    _loaded = true;
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Title cannot be empty');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await DioClient.patch<dynamic>('/documents/${widget.documentId}', data: {
        'title': _titleCtrl.text.trim(),
        if (_descCtrl.text.isNotEmpty) 'description': _descCtrl.text.trim(),
        if (_ocrCtrl.text.isNotEmpty) 'ocr_text': _ocrCtrl.text,
      });
      ref.invalidate(singleDocumentProvider(widget.documentId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved. Re-process the document to refresh AI features.'),
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(singleDocumentProvider(widget.documentId));
    final theme = Theme.of(context);

    return Scaffold(
      
      appBar: AppBar(
        title: const Text('Edit Document'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'Content'),
          ],
        ),
      ),
      body: docAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (doc) {
          _populate(doc);
          return Column(
            children: [
              if (_error != null)
                Container(
                  width: double.infinity,
                  color: AppColors.errorContainer,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.error)),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    // ── Tab 1: Metadata ──────────────────────────────────
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Document Info',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(color: AppColors.textSecondary)),
                          const SizedBox(height: AppSpacing.sm),
                          TextFormField(
                            controller: _titleCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Title',
                              prefixIcon: Icon(Icons.title),
                            ),
                            textCapitalization: TextCapitalization.words,
                            maxLength: 500,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _descCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              prefixIcon: Icon(Icons.description_outlined),
                              alignLabelWithHint: true,
                            ),
                            maxLines: 4,
                            maxLength: 2000,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('File info',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(color: AppColors.textSecondary)),
                                  const SizedBox(height: AppSpacing.sm),
                                  _InfoRow('Type', doc.fileType.toUpperCase()),
                                  _InfoRow('Size', doc.fileSizeHuman),
                                  _InfoRow('Status', doc.status),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Tab 2: OCR Text ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.edit_note,
                                color: AppColors.primary, size: 18),
                            const SizedBox(width: 6),
                            Text('Extracted Text',
                                style: theme.textTheme.titleSmall),
                            const Spacer(),
                            Text('${_ocrCtrl.text.length} chars',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary)),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            'Edit the text extracted from your document. After saving, re-process to refresh AI features.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: AppRadius.md,
                                border: Border.all(color: AppColors.outline),
                              ),
                              child: TextField(
                                controller: _ocrCtrl,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                style: const TextStyle(fontSize: 13, height: 1.5),
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.all(AppSpacing.md),
                                  border: InputBorder.none,
                                  hintText: 'No text extracted yet. Process the document first.',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ),
      ]),
    );
  }
}
