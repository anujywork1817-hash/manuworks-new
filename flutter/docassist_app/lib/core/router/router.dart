import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/shell/main_shell.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/documents/screens/documents_screen.dart';
import '../../features/documents/screens/document_detail_screen.dart';
import '../../features/ai_chat/screens/chat_screen.dart';
import '../../features/ai_chat/screens/general_chat_screen.dart';
import '../../features/matters/screens/matters_screen.dart';
import '../../features/matters/screens/matter_detail_screen.dart';
import '../../features/draft/screens/draft_document_screen.dart';
import '../../features/compare/screens/compare_screen.dart';
import '../../features/ocr/screens/ocr_scan_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/auth/screens/profile_screen.dart';
import '../../features/documents/screens/favourites_screen.dart';
import '../../features/help/screens/help_center_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/complaint_reply/screens/complaint_reply_screen.dart';
import '../../features/ai_features/screens/ai_features_screen.dart';
import '../../features/ai_features/screens/ai_feature_detail_screen.dart';
import '../../features/dashboard/screens/usage_dashboard_screen.dart';
import '../../features/billing/screens/recharge_credits_screen.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const dashboard = '/dashboard';
  static const documents = '/documents';
  static const documentDetail = '/documents/:id';
  static const chat = '/documents/:id/chat';
  static const aiChat = '/ai-chat';
  static const generalChat = '/ai-chat/general';
  static const matters = '/matters';
  static const matterDetail = '/matters/:id';
  static const draft = '/draft';
  static const ocrScan = '/ocr-scan';
  static const compare = '/compare';
  static const templates = '/templates';
  static const search = '/search';
  static const profile = '/profile';
  static const favourites = '/favourites';
  static const helpCenter = '/help';
  static const notifications = '/notifications';
  static const complaintReply = '/complaint-reply';
  static const aiFeatures = '/ai-features';
  static const usageDashboard = '/usage-dashboard';
  static const rechargeCredits = '/recharge-credits';
}

class AuthNotifierListenable extends ChangeNotifier {
  AuthNotifierListenable(this._ref) {
    _ref.listen(authNotifierProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = AuthNotifierListenable(ref);
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    refreshListenable: listenable,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final loc = state.matchedLocation;

      // While auth is still resolving, stay on splash (shows loading spinner)
      if (authState.isLoading) {
        return loc == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final isLoggedIn = authState.value ?? false;

      // From splash, always redirect based on resolved auth state
      if (loc == AppRoutes.splash) {
        return isLoggedIn ? AppRoutes.dashboard : AppRoutes.login;
      }

      final isAuthRoute = loc == AppRoutes.login ||
          loc == AppRoutes.register ||
          loc == AppRoutes.forgotPassword;
      if (!isLoggedIn && !isAuthRoute) return AppRoutes.login;
      if (isLoggedIn && isAuthRoute) return AppRoutes.dashboard;
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (c, s) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (c, s) => const LoginScreen()),
      GoRoute(path: AppRoutes.register, builder: (c, s) => const RegisterScreen()),
      GoRoute(path: AppRoutes.forgotPassword, builder: (c, s) => const ForgotPasswordScreen()),

      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: AppRoutes.dashboard, builder: (c, s) => const DashboardScreen()),
          GoRoute(
            path: AppRoutes.documents,
            builder: (c, s) => const DocumentsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (c, s) => DocumentDetailScreen(documentId: s.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'chat',
                    builder: (c, s) => ChatScreen(documentId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.aiFeatures,
            builder: (c, s) => const AiFeaturesScreen(),
            routes: [
              GoRoute(
                path: ':featureId',
                builder: (c, s) => AiFeatureDetailScreen(
                    featureId: s.pathParameters['featureId']!),
              ),
            ],
          ),
          GoRoute(path: AppRoutes.usageDashboard, builder: (c, s) => const UsageDashboardScreen()),
          GoRoute(path: AppRoutes.rechargeCredits, builder: (c, s) => const RechargeCreditsScreen()),
          GoRoute(path: AppRoutes.aiChat, builder: (c, s) => const GeneralChatScreen()),
          GoRoute(path: AppRoutes.generalChat, builder: (c, s) => const GeneralChatScreen()),
          GoRoute(
            path: AppRoutes.matters,
            builder: (c, s) => MattersScreen(autoOpenAdd: s.extra == true),
            routes: [
              GoRoute(
                path: ':id',
                builder: (c, s) => MatterDetailScreen(matterId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: AppRoutes.draft, builder: (c, s) => DraftDocumentScreen(initialTypeId: s.extra as String?)),
          GoRoute(path: AppRoutes.ocrScan, builder: (c, s) => const OcrScanScreen()),
          GoRoute(path: AppRoutes.compare, builder: (c, s) => const CompareScreen()),
          GoRoute(path: AppRoutes.templates, builder: (c, s) => const _TemplatesScreen()),
          GoRoute(path: AppRoutes.search, builder: (c, s) => const SearchScreen()),
          GoRoute(path: AppRoutes.profile, builder: (c, s) => const ProfileScreen()),
          GoRoute(path: AppRoutes.favourites, builder: (c, s) => const FavouritesScreen()),
          GoRoute(path: AppRoutes.helpCenter, builder: (c, s) => const HelpCenterScreen()),
          GoRoute(path: AppRoutes.notifications, builder: (c, s) => const NotificationsScreen()),
          GoRoute(path: AppRoutes.complaintReply, builder: (c, s) => const ComplaintReplyScreen()),
        ],
      ),
    ],
  );
});

// ── Templates placeholder ─────────────────────────────────────────────────────
class _TemplatesScreen extends StatelessWidget {
  const _TemplatesScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFEEEDF8),
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: const Text('Templates',
        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
    ),
    body: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.grid_view_rounded,
            color: Color(0xFF10B981), size: 40),
        ),
        const SizedBox(height: 20),
        const Text('Templates', style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        const SizedBox(height: 8),
        const Text('Legal document templates coming soon.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
        const SizedBox(height: 4),
        const Text('Contract, NDA, Agreement and more.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
      ],
    )),
  );
}

// ── Splash ────────────────────────────────────────────────────────────────────
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}