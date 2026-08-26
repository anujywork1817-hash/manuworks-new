import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

// ─── Auth State Provider ──────────────────────────────────────────────────────
// Returns true if user has a valid access token

final authStateProvider = FutureProvider<bool>((ref) async {
  try {
    return await TokenStorage.hasTokens().timeout(const Duration(seconds: 3), onTimeout: () => false);
  } catch (_) {
    return false;
  }
});

// ─── Current User Provider ────────────────────────────────────────────────────

final currentUserProvider = FutureProvider<Map<String, String?>>((ref) async {
  return await TokenStorage.getUserInfo();
});

// ─── Credits Provider ─────────────────────────────────────────────────────────
// Real credit balance from the backend (/auth/me). Recharge Credits invalidates
// this after a successful purchase so every screen watching it — e.g. the
// Usage Dashboard's balance — refreshes immediately, without a manual reload.

final creditsProvider = FutureProvider<int>((ref) async {
  try {
    final response = await DioClient.get('/auth/me');
    final credits = response['data']?['credits'];
    return credits is int ? credits : (credits as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
});

// ─── Auth Notifier ────────────────────────────────────────────────────────────

class AuthNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    try {
    return await TokenStorage.hasTokens().timeout(const Duration(seconds: 3), onTimeout: () => false);
  } catch (_) {
    return false;
  }
  }

  Future<void> login(String email, String password) async {
    // Do NOT set AsyncLoading here — that triggers the router's splash redirect,
    // which navigates away and swallows any error message shown on the login screen.
    try {
      final response = await DioClient.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      final data = response['data'];
      await TokenStorage.saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      await TokenStorage.saveUserInfo(
        userId: data['user']['id'],
        email: data['user']['email'],
        role: data['user']['role'],
      );

      state = const AsyncData(true);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await DioClient.post('/auth/register', data: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'password': password,
      });

      final data = response['data'];
      await TokenStorage.saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      await TokenStorage.saveUserInfo(
        userId: data['user']['id'],
        email: data['user']['email'],
        role: data['user']['role'],
      );

      state = const AsyncData(true);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await DioClient.post('/auth/logout');
    } catch (_) {}
    await TokenStorage.clearAll();
    state = const AsyncData(false);
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, bool>(AuthNotifier.new);


