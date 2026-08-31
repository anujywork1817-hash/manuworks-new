import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/razorpay_payment_service.dart';
import '../../auth/providers/auth_provider.dart';

/// "Recharge Credits" — a 3-step wizard (Billing Details → Choose Option →
/// Select Plan) mirroring the web app's recharge modal.
class RechargeCreditsScreen extends ConsumerStatefulWidget {
  const RechargeCreditsScreen({super.key});

  @override
  ConsumerState<RechargeCreditsScreen> createState() => _RechargeCreditsScreenState();
}

class _RechargeCreditsScreenState extends ConsumerState<RechargeCreditsScreen> {
  int _step = 1; // 1 = Billing Details, 2 = Choose Option, 3 = Select Plan

  // Step 1 — billing details
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  String? _state;

  static const _states = [
    'Maharashtra', 'Delhi', 'Karnataka', 'Tamil Nadu', 'Gujarat',
    'Uttar Pradesh', 'West Bengal', 'Rajasthan', 'Telangana', 'Other',
  ];

  // Step 2 — choose option
  String _rechargeOption = 'one_time';

  // Step 3 — select plan
  String? _selectedPlan;
  bool _payingViaUpi = false;
  static const _plans = [
    {'id': 'basic', 'name': 'Basic', 'credits': '2,500', 'price': '₹499', 'amount': 499.0},
    {'id': 'pro', 'name': 'Pro', 'credits': '7,500', 'price': '₹1,299', 'amount': 1299.0},
    {'id': 'business', 'name': 'Business', 'credits': '20,000', 'price': '₹2,999', 'amount': 2999.0},
  ];

  @override
  void dispose() {
    for (final c in [_fullNameCtrl, _emailCtrl, _mobileCtrl, _countryCtrl,
        _addressCtrl, _cityCtrl, _zipCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _step1Valid =>
      _fullNameCtrl.text.trim().isNotEmpty &&
      _emailCtrl.text.trim().isNotEmpty &&
      _mobileCtrl.text.trim().isNotEmpty &&
      _countryCtrl.text.trim().isNotEmpty &&
      _addressCtrl.text.trim().isNotEmpty &&
      _cityCtrl.text.trim().isNotEmpty &&
      _state != null &&
      _zipCtrl.text.trim().isNotEmpty;

  Future<void> _continue() async {
    if (_step == 1) {
      if (!_step1Valid) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please fill in all required fields'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      setState(() => _step = 2);
    } else if (_step == 2) {
      setState(() => _step = 3);
    } else {
      if (_selectedPlan == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select a plan'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      await _payWithUpi();
    }
  }

  Future<void> _payWithUpi() async {
    final plan = _plans.firstWhere((p) => p['id'] == _selectedPlan);
    setState(() => _payingViaUpi = true);

    await RazorpayPaymentService.pay(
      amount: plan['amount'] as double,
      planId: plan['id'] as String,
      planName: plan['name'] as String,
      onResult: (result) {
        if (!mounted) return;
        setState(() => _payingViaUpi = false);
        if (result.success) {
          ref.invalidate(creditsProvider);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${plan['credits']} credits added to your account 🎉'),
            behavior: SnackBarBehavior.floating,
          ));
          Navigator.of(context).maybePop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.errorMessage ?? 'Payment failed'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.surface,
        leading: BackButton(
          color: AppColors.textPrimary,
          onPressed: () {
            if (_step > 1) {
              setState(() => _step -= 1);
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
        title: const Text('Recharge Credits',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: Column(children: [
          _buildStepper(),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: switch (_step) {
                1 => _buildBillingDetails(),
                2 => _buildChooseOption(),
                _ => _buildSelectPlan(),
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.outline)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _payingViaUpi ? null : _continue,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _payingViaUpi
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_step < 3 ? 'Continue' : 'Proceed to Pay',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Stepper header ───────────────────────────────────────────────────────

  Widget _buildStepper() => Container(
    color: AppColors.surface,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      _stepCircle(1, 'Billing Details'),
      _stepLine(_step > 1),
      _stepCircle(2, 'Choose Option'),
      _stepLine(_step > 2),
      _stepCircle(3, 'Select Plan'),
    ]),
  );

  Widget _stepCircle(int n, String label) {
    final active = _step == n;
    final done = _step > n;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (active || done) ? AppColors.primary : AppColors.outline.withValues(alpha: 0.3),
        ),
        alignment: Alignment.center,
        child: done
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : Text('$n', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold,
                color: active ? Colors.white : AppColors.textSecondary)),
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(
          fontSize: 9.5,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? AppColors.textPrimary : AppColors.textSecondary)),
    ]);
  }

  Widget _stepLine(bool active) => Expanded(
    child: Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 16),
      color: active ? AppColors.primary : AppColors.outline.withValues(alpha: 0.3),
    ),
  );

  // ── Step 1: Billing Details ─────────────────────────────────────────────

  Widget _buildBillingDetails() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: _field(_fullNameCtrl, 'Full Name *', 'Your full name')),
      const SizedBox(width: 12),
      Expanded(child: _field(_emailCtrl, 'Email *', 'you@example.com')),
    ]),
    Row(children: [
      Expanded(child: _field(_mobileCtrl, 'Mobile *', '10-digit mobile number')),
      const SizedBox(width: 12),
      Expanded(child: _field(_countryCtrl, 'Country *', 'e.g. India')),
    ]),
    _field(_addressCtrl, 'Billing Address *', 'Street address', lines: 2),
    Row(children: [
      Expanded(child: _field(_cityCtrl, 'City *', 'City')),
      const SizedBox(width: 12),
      Expanded(child: _stateDropdown()),
      const SizedBox(width: 12),
      Expanded(child: _field(_zipCtrl, 'ZIP / Pin Code *', 'Pin code')),
    ]),
  ]);

  Widget _field(TextEditingController ctrl, String label, String hint, {int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: Color(0xFF374151))),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: lines,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: lines > 1 ? 12 : 14),
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
            ),
          ),
        ]),
      );

  Widget _stateDropdown() => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('State *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: Color(0xFF374151))),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: _state,
        isExpanded: true,
        hint: const Text('Select', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        ),
        items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (v) => setState(() => _state = v),
      ),
    ]),
  );

  // ── Step 2: Choose Option ───────────────────────────────────────────────

  Widget _buildChooseOption() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('How would you like to recharge?',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    const SizedBox(height: 12),
    _optionTile('one_time', Icons.bolt_rounded, 'One-time Top-up',
        'Buy a fixed number of credits, no commitment'),
    _optionTile('subscription', Icons.autorenew_rounded, 'Monthly Subscription',
        'Auto-renewing credits every month, cancel anytime'),
  ]);

  Widget _optionTile(String id, IconData icon, String title, String subtitle) {
    final selected = _rechargeOption == id;
    return GestureDetector(
      onTap: () => setState(() => _rechargeOption = id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.outline,
              width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? AppColors.primary : AppColors.textSecondary, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ])),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppColors.primary : AppColors.textSecondary,
            size: 22,
          ),
        ]),
      ),
    );
  }

  // ── Step 3: Select Plan ─────────────────────────────────────────────────

  Widget _buildSelectPlan() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Choose a plan',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    const SizedBox(height: 12),
    ..._plans.map((p) {
      final selected = _selectedPlan == p['id'];
      return GestureDetector(
        onTap: () => setState(() => _selectedPlan = p['id'] as String),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.primary : AppColors.outline,
                width: selected ? 1.5 : 1),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['name']! as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text('${p['credits']} credits', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ])),
            Text(p['price']! as String, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                color: AppColors.primary)),
            const SizedBox(width: 10),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
          ]),
        ),
      );
    }),
  ]);
}