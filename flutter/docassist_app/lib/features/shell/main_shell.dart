import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/router.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _locationToIndex(String loc) {
    if (loc.startsWith('/ai-chat'))   return 1;
    if (loc.startsWith('/profile'))   return 2;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0: context.go(AppRoutes.dashboard); break;
      case 1: context.go(AppRoutes.aiChat);     break;
      case 2: context.go(AppRoutes.profile);    break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final index    = _locationToIndex(location);
    final cs       = Theme.of(context).colorScheme;
    final isDark   = Theme.of(context).brightness == Brightness.dark;

    // Handle the Android system back button / back-swipe. Tabs are switched with
    // context.go() (which replaces the stack), so without this a back press on any
    // non-Home tab has nothing to pop and would exit the app to the phone home
    // screen. Intercept every back and route it sensibly:
    //   • a pushed sub-screen is on top  → pop it
    //   • a non-Home tab root            → go to the Home tab
    //   • the Home tab root              → leave the app
    final isOnDashboard = location == AppRoutes.dashboard;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.canPop()) {
          // A sub-screen (document detail, chat, ai-feature detail, etc.) is
          // pushed on top → just pop it.
          context.pop();
        } else if (!isOnDashboard) {
          // Any tab/feature root with nothing left to pop (docs, ai-chat,
          // draft, profile, ai-features, ocr-scan, compare, search, matters,
          // notifications, help, favourites, complaint-reply, usage-dashboard,
          // templates, etc.) → go to Home instead of exiting the app.
          // NOTE: this must check the actual location, not the bottom-nav
          // `index`, because `index` defaults to 0 for every route that isn't
          // one of the 5 bottom-nav tabs — using `index != 0` here was the
          // bug that caused the whole app to close from those feature screens.
          context.go(AppRoutes.dashboard);
        } else {
          // Already on Home with nothing to pop → actually exit the app.
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outline, width: 0.8)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => _onTap(context, i),
            backgroundColor: cs.surface,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            indicatorColor: isDark
                ? cs.primaryContainer
                : cs.primaryContainer,
            height: 60,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome_rounded),
                label: 'AI Chat',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}