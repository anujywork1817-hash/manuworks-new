import 'package:url_launcher/url_launcher.dart';

/// Result of attempting to launch a UPI payment intent.
enum UpiLaunchResult { launched, noUpiAppFound, failed }

/// Builds a standard `upi://pay` deep link and hands it to the OS, which
/// shows the chooser of installed UPI apps (GPay, PhonePe, Paytm, ...).
/// The user picks an app and enters their own bank / UPI ID *inside that
/// app* — this screen never collects or stores UPI credentials itself.
///
/// ⚠️ Dummy / demo mode: [payeeVpa] below is a placeholder VPA, so the
/// chosen UPI app will show its own "invalid payee" / failure screen
/// instead of completing a real transaction. Swap in a real, verified
/// merchant VPA (and remove the demo note) before going live.
class UpiPaymentService {
  UpiPaymentService._();

  /// Placeholder merchant VPA — replace with the real one before launch.
  static const String payeeVpa = 'manuworks.demo@upi';
  static const String payeeName = 'ManuWorks AI';

  static Future<UpiLaunchResult> pay({
    required double amount,
    required String note,
    String? transactionRef,
  }) async {
    final params = {
      'pa': payeeVpa,
      'pn': payeeName,
      'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      'tn': note,
      if (transactionRef != null) 'tr': transactionRef,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final uri = Uri.parse('upi://pay?$query');

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return launched ? UpiLaunchResult.launched : UpiLaunchResult.noUpiAppFound;
    } catch (_) {
      return UpiLaunchResult.failed;
    }
  }
}