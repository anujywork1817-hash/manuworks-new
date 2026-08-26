import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/services/ai_history_service.dart';
import '../../../core/services/document_export_service.dart';
import '../../../shared/widgets/feature_history_sheet.dart';

// ─── Document types ───────────────────────────────────────────────────────────

class _DocType {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final String hint;

  const _DocType(this.id, this.label, this.icon, this.color, this.hint);
}

const _docTypes = [
  _DocType('Writ Petition', 'Writ Petition', Icons.account_balance_outlined,
      AppColors.secondary, 'Under Art. 226/32 of Constitution'),
  _DocType('Civil Suit / Plaint', 'Civil Plaint', Icons.gavel_outlined,
      AppColors.info, 'CPC Order VII Rule 1'),
  _DocType('Written Statement / Reply', 'Written Statement', Icons.edit_document,
      AppColors.success, 'Reply to Plaint/Petition'),
  _DocType('Legal Notice', 'Legal Notice', Icons.mail_outline_rounded,
      AppColors.warning, 'Under Sec. 80 CPC / 138 NI Act'),
  _DocType('Bail Application', 'Bail Application', Icons.lock_open_outlined,
      AppColors.error, 'Regular / Anticipatory Bail'),
  _DocType('Affidavit', 'Affidavit', Icons.verified_outlined,
      AppColors.secondary, 'Sworn statement'),
  _DocType('Application', 'Application', Icons.assignment_outlined,
      AppColors.info, 'Interlocutory / Misc. Application'),
  _DocType('Appeal', 'Appeal', Icons.upload_outlined,
      AppColors.warning, 'First / Second Appeal'),
  _DocType('Counter Affidavit', 'Counter Affidavit', Icons.swap_horiz_rounded,
      AppColors.textSecondary, 'Reply to Affidavit'),
  _DocType('Vakalatnama', 'Vakalatnama', Icons.handshake_outlined,
      AppColors.textPrimary, 'Authority to Advocate'),
];

// ─── AI Draft Prompts (ready-made prompt templates) ────────────────────────────

class _PromptTemplate {
  final String title;
  final String prompt;
  const _PromptTemplate(this.title, this.prompt);
}

const kDraftPromptTemplates = [
  _PromptTemplate(
    'Writ Petition — Service Termination',
    'Draft a Writ Petition under Article 226 challenging the wrongful '
    'termination of the petitioner\'s employment. Include: petitioner\'s '
    'designation and years of service, date and grounds of termination, '
    'absence of a show-cause notice or departmental inquiry, and the '
    'relief sought — reinstatement with full back wages.',
  ),
  _PromptTemplate(
    'Civil Plaint — Recovery of Money',
    'Draft a Civil Suit for recovery of money against the defendant for '
    'an outstanding loan/business debt. Include: the amount due, date of '
    'the transaction/agreement, repeated demands made for repayment, and '
    'the relief sought — recovery of the principal amount with interest.',
  ),
  _PromptTemplate(
    'Written Statement — Reply to Plaint',
    'Draft a Written Statement in reply to a Civil Plaint. Include: '
    'preliminary objections (maintainability, limitation, jurisdiction), '
    'a para-wise reply admitting/denying the plaint\'s averments, and the '
    'defendant\'s version of facts.',
  ),
  _PromptTemplate(
    'Legal Notice — Cheque Dishonour (Sec. 138 NI Act)',
    'Draft a Legal Notice under Section 138 of the Negotiable Instruments '
    'Act for dishonour of a cheque. Include: cheque number, date and '
    'amount, date of dishonour and the reason given by the bank, and a '
    'demand for payment within 15 days failing which criminal action will follow.',
  ),
  _PromptTemplate(
    'Bail Application — Regular Bail',
    'Draft a Regular Bail Application under Section 439 CrPC. Include: '
    'FIR number, police station and sections invoked, date of arrest, '
    'period of custody so far, and grounds for bail — no flight risk, no '
    'tampering with evidence, and cooperation with the investigation.',
  ),
  _PromptTemplate(
    'Affidavit — Sworn Statement of Facts',
    'Draft an Affidavit affirming a sworn statement of facts to be filed '
    'before the court. Include: the deponent\'s name, address and '
    'occupation, the facts being affirmed on personal knowledge, and a '
    'verification clause.',
  ),
  _PromptTemplate(
    'Anticipatory Bail Application',
    'Draft an Anticipatory Bail Application under Section 438 CrPC. '
    'Include: apprehension of arrest and the FIR/complaint details, '
    'grounds showing the accusation is false or motivated, and an '
    'undertaking to cooperate with the investigation.',
  ),
  _PromptTemplate(
    'First Appeal — Against Trial Court Judgment',
    'Draft a First Appeal challenging the judgment and decree of the '
    'trial court. Include: brief facts of the original suit, the '
    'findings of the trial court being challenged, the grounds of '
    'appeal, and the relief sought — setting aside/modifying the judgment.',
  ),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class DraftDocumentScreen extends ConsumerStatefulWidget {
  final String? initialTypeId;
  const DraftDocumentScreen({super.key, this.initialTypeId});
  @override
  ConsumerState<DraftDocumentScreen> createState() => _DraftDocumentScreenState();
}

class _DraftDocumentScreenState extends ConsumerState<DraftDocumentScreen> {
  _DocType? _selected;
  bool _showPicker = true;
  bool _generating = false;
  String? _result;
  String? _resultTitle;
  String? _error;
  bool _exportingPdf = false;
  bool _exportingDocx = false;
  bool _saved = false;

  // ── Landing / prompt entry flow ─────────────────────────────────────────
  // true  -> show the "Initiate a New Draft" landing card
  // false -> either the prompt-entry box or (once a prompt has been sent)
  //          the detailed form is shown
  bool _showLanding = false;
  bool _showPromptEntry = true;
  bool _promptGenerating = false;
  final _promptCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialTypeId != null) {
      for (final t in _docTypes) {
        if (t.id == widget.initialTypeId) {
          _selected = t;
          _showPicker = false;
          break;
        }
      }
      // Deep-linked straight into a document type: skip the landing/prompt flow.
      _showLanding = false;
    }
  }

  void _startNewDraft() {
    setState(() {
      _showLanding = false;
      _showPromptEntry = true;
    });
  }

  /// Best-effort guess of the document type from the free-text prompt,
  /// so sending a prompt goes straight to generation instead of asking
  /// the user to pick a type on a separate screen.
  _DocType _guessDocType(String text) {
    final lower = text.toLowerCase();
    bool has(String kw) => lower.contains(kw);
    if (has('writ') || has('article 226') || has('article 32')) return _docTypes[0];
    if (has('suit') || has('plaint') || has('recovery of money') || has('recovery')) return _docTypes[1];
    if (has('written statement') || (has('reply') && has('plaint'))) return _docTypes[2];
    if (has('legal notice') || has('notice under') || has('138')) return _docTypes[3];
    if (has('anticipatory bail')) return _docTypes[4];
    if (has('bail')) return _docTypes[4];
    if (has('counter affidavit')) return _docTypes[8];
    if (has('affidavit')) return _docTypes[5];
    if (has('vakalatnama')) return _docTypes[9];
    if (has('appeal')) return _docTypes[7];
    if (has('application')) return _docTypes[6];
    return _docTypes[0];
  }

  Future<void> _submitPrompt() async {
    final text = _promptCtrl.text.trim();
    if (text.isEmpty) return;
    final guessed = _guessDocType(text);
    setState(() {
      // Carry the free-text prompt into Facts + Additional Information so
      // the AI has it as context, and go straight to generation — no
      // intermediate "Select Document Type" screen.
      _selected = guessed;
      _factsCtrl.text = text;
      _additionalCtrl.text = text;
      _showPromptEntry = false;
      _promptGenerating = true;
    });
    await _generate(requirePetitioner: false);
    if (!mounted) return;
    if (_result == null) {
      // Generation failed (network issue, daily limit, etc.). Never fall
      // through to the raw multi-field form / document-type picker — send
      // the user straight back to the prompt box with the error surfaced,
      // same as every other AI tool's flow.
      final message = _error ?? 'Generation failed. Please try again.';
      setState(() {
        _promptGenerating = false;
        _showPromptEntry = true;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } else {
      setState(() => _promptGenerating = false);
    }
  }

  final _courtCtrl      = TextEditingController();
  final _petCtrl        = TextEditingController();
  final _respCtrl       = TextEditingController();
  final _caseNoCtrl     = TextEditingController();
  final _subjectCtrl    = TextEditingController();
  final _factsCtrl      = TextEditingController();
  final _reliefCtrl     = TextEditingController();
  final _actsCtrl       = TextEditingController();
  final _additionalCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in [_courtCtrl, _petCtrl, _respCtrl, _caseNoCtrl,
        _subjectCtrl, _factsCtrl, _reliefCtrl, _actsCtrl, _additionalCtrl]) {
      c.dispose();
    }
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate({bool requirePetitioner = true}) async {
    if (_selected == null) return;
    if (_factsCtrl.text.trim().isEmpty ||
        (requirePetitioner && _petCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please fill in Petitioner/Applicant name and Facts'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() { _generating = true; _result = null; _error = null; });

    try {
      final res = await DioClient.post('/ai/draft-legal', data: {
        'document_type':    _selected!.id,
        'court_name':       _courtCtrl.text.trim(),
        'petitioner_name':  _petCtrl.text.trim(),
        'respondent_name':  _respCtrl.text.trim(),
        'case_number':      _caseNoCtrl.text.trim(),
        'subject':          _subjectCtrl.text.trim(),
        'facts':            _factsCtrl.text.trim(),
        'relief_sought':    _reliefCtrl.text.trim(),
        'acts_and_sections':_actsCtrl.text.trim(),
        'additional_info':  _additionalCtrl.text.trim(),
      });
      final data = res['data'] as Map<String, dynamic>;
      final content = data['content'] ?? '';
      final title = data['title'] ?? _selected!.id;

      // Auto-save to this feature's own on-device history as soon as a
      // draft is generated.
      try {
        await AiHistoryService.save(
          featureId: 'draft',
          title: title,
          subtitle: _selected!.id,
          content: content,
        );
      } catch (_) {
        // Non-fatal: generation succeeded even if local save failed.
      }

      if (mounted) {
        setState(() {
          _result = content;
          _resultTitle = title;
          _generating = false;
          _saved = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().contains('Daily AI')
              ? 'Daily AI limit reached. Please try again later.'
              : 'Generation failed: ${e.toString()}';
          _generating = false;
        });
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_result == null) return;
    setState(() => _exportingPdf = true);
    try {
      await DocumentExportService.exportToPdf(
        title: _resultTitle ?? _selected?.id ?? 'Document',
        content: _result!,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF export failed: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportDocx() async {
    if (_result == null) return;
    setState(() => _exportingDocx = true);
    try {
      await DocumentExportService.exportToDocx(
        title: _resultTitle ?? _selected?.id ?? 'Document',
        content: _result!,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Word export failed: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exportingDocx = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      appBar: AppBar(
        
        elevation: 0,
        leading: BackButton(
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Legal Document Drafter',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          if (_result == null)
            IconButton(
              tooltip: 'Draft history',
              icon: const Icon(Icons.history_rounded, color: AppColors.textPrimary),
              onPressed: () => showFeatureHistorySheet(
                context, featureId: 'draft', featureLabel: 'Legal Document Drafter'),
            ),
          if (_result != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _result = null;
                _selected = null;
                _saved = false;
                _showPromptEntry = true;
                _showPicker = true;
                _promptCtrl.clear();
              }),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('New Draft'),
            ),
        ],
      ),
      body: (_promptGenerating && _result == null)
          ? _buildGenerating()
          : _result != null
              ? _buildResult()
              : _showLanding
                  ? _buildLanding()
                  // Any other state (including a stray fallback) goes to
                  // the free-text prompt box — the raw document-type
                  // picker form is never shown as part of this flow.
                  : _buildPromptEntry(),
    );
  }

  // ── Generating (prompt flow) view ──────────────────────────────────────────

  Widget _buildGenerating() => const Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: AppColors.primary),
      SizedBox(height: 16),
      Text('Drafting your document...',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
      SizedBox(height: 4),
      Text('This may take a moment.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    ]),
  );

  // ── Landing view ("Initiate a New Draft" card) ─────────────────────────────

  Widget _buildLanding() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      const SizedBox(height: 12),
      const Text('Drafter',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
              color: AppColors.textPrimary)),
      const SizedBox(height: 10),
      const Text(
        'Assists in the creation of legal documents, making the drafting '
        'process faster and more efficient. Provide comprehensive information, '
        'case facts, and relevant context to generate high-quality drafts.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
      ),
      const SizedBox(height: 28),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outline),
          boxShadow: AppShadows.sm,
        ),
        child: Column(children: [
          const Text('Initiate a New Draft',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          const Text(
            'Tell us about the legal document you would like to draft. '
            'Include information such as:',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 6),
          const Text(
            'Document type, Parties involved, Background and facts, '
            'Legal issues, Dates & Deadlines, Special instructions',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startNewDraft,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                backgroundColor: AppColors.primary,
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              child: const Text('Get Started'),
            ),
          ),
        ]),
      ),
    ]),
  );

  // ── Prompt-entry view (single free-text box, chat style) ────────────────────

  Widget _buildPromptEntry() => SafeArea(
    child: Column(children: [
      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showPromptTemplates(context),
              icon: const Icon(Icons.lightbulb_outline_rounded, size: 15, color: AppColors.info),
              label: const Text('AI Draft Prompts',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.info)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text('Initiate a New Draft',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Provide case details and relevant context to generate a high-quality draft.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ]),
      ),

      // Empty middle area — chat-style layout, keeps the composer pinned
      // to the bottom of the screen instead of right under the header.
      const Expanded(child: SizedBox.shrink()),

      // Composer — text box + send button, pinned to the bottom.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _promptCtrl,
              minLines: 1,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Describe what you want to draft and include key '
                    'facts, parties, and requirements...',
                hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textDisabled),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44, width: 44,
            child: ElevatedButton(
              onPressed: _submitPrompt,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              child: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
            ),
          ),
        ]),
      ),
    ]),
  );

  // ── AI Draft Prompts (ready-made prompt templates) ──────────────────────────

  void _showPromptTemplates(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(children: [
                const Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('AI Draft Prompts',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                'Tap a prompt to use it as a starting point — edit it with your own facts before sending.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: kDraftPromptTemplates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final p = kDraftPromptTemplates[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      _promptCtrl.text = p.prompt;
                      _promptCtrl.selection = TextSelection.collapsed(offset: p.prompt.length);
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.title,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text(p.prompt,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Result view ─────────────────────────────────────────────────────────────

  Widget _buildResult() => Column(children: [
    // Toolbar
    Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_resultTitle ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary))),
          if (_saved) ...[
            const Icon(Icons.check_circle, size: 14, color: AppColors.success),
            const SizedBox(width: 4),
            const Text('Saved', style: TextStyle(fontSize: 11, color: AppColors.success)),
          ],
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _result!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Document copied to clipboard'),
                behavior: SnackBarBehavior.floating,
              ));
            },
            icon: const Icon(Icons.copy, size: 15),
            label: const Text('Copy'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _exportingPdf ? null : _exportPdf,
            icon: _exportingPdf
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined, size: 15),
            label: const Text('PDF'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _exportingDocx ? null : _exportDocx,
            icon: _exportingDocx
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.description_outlined, size: 15),
            label: const Text('Word'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ]),
      ]),
    ),
    // Document text
    Expanded(child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppShadows.sm,
        ),
        child: SelectableText(_result!,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.7,
              color: AppColors.primaryLight,
            )),
      ),
    )),
  ]);

  // ── Form view ────────────────────────────────────────────────────────────────

  Widget _buildForm() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Document type picker — hidden when a specific type was opened directly
      if (_showPicker) ...[
        const Text('Select Document Type',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.6,
          children: _docTypes.map((t) => _TypeTile(
            type: t,
            selected: _selected?.id == t.id,
            onTap: () => setState(() { _selected = t; _result = null; _showPicker = false; }),
          )).toList(),
        ),
      ] else if (_selected != null) ...[
        TextButton.icon(
          onPressed: () => setState(() {
            _showPicker = true;
          }),
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: const Text('Change document type'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
      ],

      if (_selected != null) ...[
        const SizedBox(height: 24),

        // Section header
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _selected!.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_selected!.icon, color: _selected!.color, size: 18),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_selected!.label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            Text(_selected!.hint,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ]),
        const SizedBox(height: 16),

        // Fields
        _field(_courtCtrl, 'Court Name',
            'e.g. High Court of Judicature at Bombay', Icons.account_balance_outlined),
        _field(_petCtrl, 'Petitioner / Applicant / Plaintiff *',
            'Full name of the moving party', Icons.person_outlined),
        _field(_respCtrl, 'Respondent / Defendant / Opposite Party',
            'Full name of the other party', Icons.person_off_outlined),

        if (_needsCaseNumber()) ...[
          _field(_caseNoCtrl, 'Case / Application Number',
              'e.g. CRL.P. No. 1234/2024', Icons.tag),
        ],

        _field(_subjectCtrl, 'Subject / Matter in Brief',
            'e.g. Wrongful termination of service', Icons.subject_outlined),
        _field(_factsCtrl, 'Facts & Grounds *',
            'State the key facts chronologically. Include dates, events, and legal basis.',
            Icons.notes_outlined, lines: 6),
        _field(_reliefCtrl, 'Relief / Prayer Sought',
            'What order/direction are you seeking from the court?',
            Icons.how_to_vote_outlined, lines: 3),
        _field(_actsCtrl, 'Acts & Sections',
            'e.g. Section 302 IPC, Article 21 Constitution',
            Icons.gavel_outlined),
        _field(_additionalCtrl, 'Additional Information',
            'Any other details the AI should include',
            Icons.add_circle_outline, lines: 3),

        const SizedBox(height: 8),

        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13))),
            ]),
          ),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _generating ? null : _generate,
            icon: _generating
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_generating ? 'Drafting document...' : 'Generate Draft'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    ]),
  );

  bool _needsCaseNumber() {
    final id = _selected?.id ?? '';
    return id.contains('Reply') || id.contains('Counter') ||
        id.contains('Appeal') || id.contains('Application');
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      IconData icon, {int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: lines,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
              prefixIcon: lines == 1
                  ? Icon(icon, size: 17, color: AppColors.textTertiary)
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 12, vertical: lines > 1 ? 12 : 0),
            ),
          ),
        ]),
      );
}

// ── Type tile ─────────────────────────────────────────────────────────────────

class _TypeTile extends StatelessWidget {
  final _DocType type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeTile({required this.type, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      decoration: BoxDecoration(
        color: selected ? type.color.withValues(alpha: 0.1) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? type.color : AppColors.outline,
          width: selected ? 1.5 : 1,
        ),
        boxShadow: selected ? [] : AppShadows.sm,
      ),
      child: Row(children: [
        Icon(type.icon, color: selected ? type.color : AppColors.textTertiary, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(type.label,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? type.color : const Color(0xFF374151),
            ))),
      ]),
    ),
  );
}