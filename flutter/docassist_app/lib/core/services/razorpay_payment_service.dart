import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../network/dio_client.dart';

/// Result handed back to the caller once the Razorpay checkout sheet closes.
class RazorpayResult {
  final bool success;
  final String? paymentId;
  final String? orderId;
  final String? errorMessage;

  const RazorpayResult({
    required this.success,
    this.paymentId,
    this.orderId,
    this.errorMessage,
  });
}

/// Wraps the Razorpay checkout flow:
///
///  1. Ask the backend to create an order (amount is decided server-side —
///     never trust a client-supplied amount for a real charge).
///  2. Open the Razorpay checkout sheet with that order_id.
///  3. On success, verify the payment signature with the backend before
///     treating the recharge as complete.
///
/// The Razorpay **Key ID** below is safe to ship in the app (it's public,
/// the same way a Stripe publishable key is). The **Key Secret** must only
/// ever live in the backend's environment — it is never referenced here.
class RazorpayPaymentService {
  RazorpayPaymentService._();

  /// Public Razorpay Key ID — safe for client-side use.
  static const String keyId = 'rzp_test_TPdksTOsRQXexE';

  static Razorpay? _razorpay;
  static void Function(RazorpayResult)? _onDone;
  static String? _pendingOrderId;

  /// Starts checkout for [amount] (INR, e.g. 499.0 = ₹499) tied to [planId].
  /// Calls [onResult] exactly once when the flow finishes (success, failure,
  /// or the user dismissing the sheet).
  static Future<void> pay({
    required double amount,
    required String planId,
    required String planName,
    required void Function(RazorpayResult) onResult,
  }) async {
    _onDone = onResult;

    // Step 1 — create the order server-side. The backend owns the amount
    // for the given planId, so a tampered client amount can't be charged.
    final Map<String, dynamic> order;
    try {
      order = await DioClient.post<Map<String, dynamic>>(
        '/payments/razorpay/create-order',
        data: {
          'plan_id': planId,
          'amount': amount,
          'currency': 'INR',
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );
    } catch (e) {
      onResult(RazorpayResult(success: false, errorMessage: 'Could not start payment: $e'));
      return;
    }

    final orderId = order['order_id'] ?? order['id'];
    if (orderId == null) {
      onResult(const RazorpayResult(success: false, errorMessage: 'Backend did not return an order_id'));
      return;
    }
    _pendingOrderId = orderId.toString();

    // Step 2 — open the checkout sheet.
    _razorpay?.clear();
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handleError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    _razorpay!.open({
      'key': keyId,
      'amount': (amount * 100).round(), // paise
      'currency': 'INR',
      'order_id': _pendingOrderId,
      'name': 'ManuWorks AI',
      'description': '$planName plan recharge',
      'theme': {'color': '#1F2A44'},
    });
  }

  static Future<void> _handleSuccess(PaymentSuccessResponse response) async {
    // Step 3 — verify the signature server-side before crediting anything.
    try {
      await DioClient.post(
        '/payments/razorpay/verify',
        data: {
          'razorpay_order_id': response.orderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
        },
      );
      _onDone?.call(RazorpayResult(
        success: true,
        paymentId: response.paymentId,
        orderId: response.orderId,
      ));
    } catch (e) {
      _onDone?.call(RazorpayResult(
        success: false,
        errorMessage: 'Payment captured but verification failed: $e',
      ));
    } finally {
      _cleanup();
    }
  }

  static void _handleError(PaymentFailureResponse response) {
    _onDone?.call(RazorpayResult(
      success: false,
      orderId: _pendingOrderId,
      errorMessage: response.message ?? 'Payment failed or cancelled',
    ));
    _cleanup();
  }

  static void _handleExternalWallet(ExternalWalletResponse response) {
    // User picked a wallet outside Razorpay's own flow (rare) — treat as
    // not-yet-resolved rather than success/failure.
    _onDone?.call(RazorpayResult(
      success: false,
      orderId: _pendingOrderId,
      errorMessage: 'Selected external wallet: ${response.walletName}',
    ));
    _cleanup();
  }

  static void _cleanup() {
    _razorpay?.clear();
    _razorpay = null;
    _pendingOrderId = null;
    _onDone = null;
  }
}