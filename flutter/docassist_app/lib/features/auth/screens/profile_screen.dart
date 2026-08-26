import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/router.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../../notifications/providers/notifications_provider.dart';

final profileDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final results = await Future.wait([
      DioClient.get('/auth/me'),
      DioClient.get('/documents', queryParams: {'limit': 1}),
    ]);
    // Normalise to Map<String, dynamic>. Dio can hand back a plain
    // _Map<dynamic, dynamic> for nested objects, which otherwise blows up the
    // downstream `as Map<String, dynamic>` casts with a red-screen type error.
    final rawUser = results[0]['data'];
    final user = rawUser is Map ? Map<String, dynamic>.from(rawUser) : <String, dynamic>{};
    final docTotal = (results[1]['data']?['total'] as num?)?.toInt() ?? 0;
    return {'user': user, 'doc_count': docTotal};
  } catch (_) {
    return {'user': <String, dynamic>{}, 'doc_count': 0};
  }
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileDataProvider);
    final userAsync    = ref.watch(currentUserProvider);
    final isDark       = ref.watch(themeModeProvider) == ThemeMode.dark;
    final cs           = Theme.of(context).colorScheme;
    final tt           = Theme.of(context).textTheme;

    // The editable name lives on the server (/auth/me, via profileDataProvider);
    // local token storage only caches email/role and has no first/last name. Read
    // the name from the server copy so the header updates the moment an edit
    // invalidates profileDataProvider. Fall back to the cached email while the
    // profile request is still loading.
    final profileUser = profileAsync.valueOrNull?['user'] as Map<String, dynamic>?;
    final cachedEmail = userAsync.maybeWhen(
      data: (u) => (u['email'] ?? '').toString(),
      orElse: () => '',
    );

    final email = (profileUser?['email'] as String?)?.isNotEmpty == true
        ? profileUser!['email'] as String
        : cachedEmail;
    final firstName = (profileUser?['first_name'] ?? '').toString();
    final lastName = (profileUser?['last_name'] ?? '').toString();
    final displayName = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
    final initials = _initials(firstName, lastName, email);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          // Dark mode quick toggle in AppBar
          IconButton(
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [

          // ── Avatar + Name ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: cs.surface,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              child: Column(children: [
                // Avatar circle
                Container(
                  width: 86, height: 86,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.outline, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: Text(initials,
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    )),
                ),
                const SizedBox(height: 14),
                Text(
                  displayName.isNotEmpty ? displayName : _fallbackName(email),
                  style: tt.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(email, style: tt.bodyMedium),
                const SizedBox(height: 8),
                userAsync.maybeWhen(
                  data: (u) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: AppRadius.full,
                    ),
                    child: Text(
                      (u['role'] ?? 'user').toString().toUpperCase(),
                      style: tt.labelSmall?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.w700, letterSpacing: 1),
                    ),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ]),
            ),
          ),

          // ── Stats ─────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: profileAsync.maybeWhen(
              data: (data) => Container(
                color: cs.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Stat(value: '${data['doc_count']}', label: 'Documents', cs: cs, tt: tt),
                    _Divider(cs: cs),
                    _Stat(value: 'OB', label: 'AI Engine', cs: cs, tt: tt),
                    _Divider(cs: cs),
                    _Stat(value: 'Free', label: 'Plan', cs: cs, tt: tt),
                  ],
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ),

          // ── Account section ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _Section(
              title: 'ACCOUNT',
              cs: cs, tt: tt,
              tiles: [
                _Tile(
                  icon: Icons.person_outline_rounded,
                  label: 'Edit Profile',
                  cs: cs, tt: tt,
                  onTap: () {
                    final data = profileAsync.valueOrNull;
                    final user = data?['user'] as Map<String, dynamic>? ?? {};
                    _showEditProfileSheet(context, user);
                  },
                ),
                _Tile(
                  icon: Icons.bar_chart_rounded,
                  label: 'Dashboard',
                  cs: cs, tt: tt,
                  onTap: () => context.push(AppRoutes.usageDashboard),
                ),
                _Tile(
                  icon: Icons.bolt_rounded,
                  label: 'Recharge Credits',
                  cs: cs, tt: tt,
                  onTap: () => context.push(AppRoutes.rechargeCredits),
                ),
                _Tile(
                  icon: Icons.lock_outline_rounded,
                  label: 'Change Password',
                  cs: cs, tt: tt,
                  onTap: () => _showChangePasswordSheet(context),
                ),
                Builder(builder: (ctx) {
                  final unread = ref.watch(notificationsProvider.select((s) => s.unreadCount));
                  return _Tile(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    cs: cs, tt: tt,
                    trailing: unread > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('$unread',
                              style: const TextStyle(
                                color: Colors.white, fontSize: 11,
                                fontWeight: FontWeight.bold)),
                          )
                        : null,
                    onTap: () => context.push(AppRoutes.notifications),
                  );
                }),
              ],
            ),
          ),

          // ── Preferences (dark mode toggle) ────────────────────────────────
          SliverToBoxAdapter(
            child: _Section(
              title: 'PREFERENCES',
              cs: cs, tt: tt,
              tiles: [
                // Dark mode with Switch
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                        color: cs.primary, size: 18),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Dark Mode', style: tt.labelLarge),
                      Text(isDark ? 'Currently dark' : 'Currently light',
                          style: tt.bodySmall),
                    ])),
                    Switch(
                      value: isDark,
                      onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
                    ),
                  ]),
                ),
              ],
            ),
          ),

          // ── Support section ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _Section(
              title: 'SUPPORT',
              cs: cs, tt: tt,
              tiles: [
                _Tile(icon: Icons.help_outline_rounded, label: 'Help Center',
                    cs: cs, tt: tt, onTap: () => context.push(AppRoutes.helpCenter)),
                _Tile(
                  icon: Icons.info_outline_rounded, label: 'About LexDocs',
                  cs: cs, tt: tt,
                  trailing: Text('v1.0.0', style: tt.bodySmall),
                  onTap: () {},
                ),
              ],
            ),
          ),

          // ── Sign out ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String first, String last, String email) {
    if (first.isNotEmpty && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    }
    if (first.isNotEmpty) return first.substring(0, first.length >= 2 ? 2 : 1).toUpperCase();
    final name = email.split('@').first;
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _fallbackName(String email) {
    final n = email.split('@').first;
    return n.isNotEmpty ? n[0].toUpperCase() + n.substring(1) : email;
  }

  void _showEditProfileSheet(BuildContext context, Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        initialFirstName: user['first_name'] as String? ?? '',
        initialLastName: user['last_name'] as String? ?? '',
        onSaved: () => ref.invalidate(profileDataProvider),
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              final router = GoRouter.of(context);
              await ref.read(authNotifierProvider.notifier).logout();
              if (mounted) router.go(AppRoutes.login);
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final String value, label;
  final ColorScheme cs;
  final TextTheme tt;
  const _Stat({required this.value, required this.label,
      required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 2),
    Text(label, style: tt.bodySmall),
  ]);
}

class _Divider extends StatelessWidget {
  final ColorScheme cs;
  const _Divider({required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 32, color: cs.outline);
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> tiles;
  final ColorScheme cs;
  final TextTheme tt;
  const _Section({required this.title, required this.tiles,
      required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
        style: tt.labelSmall?.copyWith(
          color: cs.onSurface.withValues(alpha: 0.4),
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        )),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: AppRadius.md,
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          children: tiles.asMap().entries.map((e) {
            final isLast = e.key == tiles.length - 1;
            return Column(children: [
              e.value,
              if (!isLast) Divider(height: 1, indent: 16, endIndent: 0, color: cs.outline),
            ]);
          }).toList(),
        ),
      ),
    ]),
  );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;
  final ColorScheme cs;
  final TextTheme tt;

  const _Tile({
    required this.icon, required this.label, required this.onTap,
    required this.cs, required this.tt, this.trailing,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: AppRadius.md,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Icon(icon, color: cs.onSurface, size: 20),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: tt.labelLarge)),
        trailing ?? Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
      ]),
    ),
  );
}

// ── Change Password Sheet ─────────────────────────────────────────────────────

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();
  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true, _obscureNew = true, _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _currentCtrl.dispose(); _newCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    try {
      await DioClient.put('/auth/change-password', data: {
        'current_password': _currentCtrl.text.trim(),
        'new_password':     _newCtrl.text.trim(),
      });
      if (mounted) {
        nav.pop();
        msg.showSnackBar(const SnackBar(content: Text('Password changed successfully')));
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString();
        msg.showSnackBar(SnackBar(
          content: Text(err.contains('incorrect') || err.contains('wrong')
              ? 'Current password is incorrect'
              : 'Failed to change password'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Text('Change Password', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          TextFormField(
            controller: _currentCtrl, obscureText: _obscureCurrent,
            decoration: InputDecoration(
              labelText: 'Current Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
            validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _newCtrl, obscureText: _obscureNew,
            decoration: InputDecoration(
              labelText: 'New Password',
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v.length < 8) return 'Minimum 8 characters';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmCtrl, obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm New Password',
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v != _newCtrl.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  : const Text('Update Password'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Edit Profile Sheet ────────────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final String initialFirstName, initialLastName;
  final VoidCallback onSaved;
  const _EditProfileSheet({
    required this.initialFirstName, required this.initialLastName, required this.onSaved});
  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _firstCtrl = TextEditingController(text: widget.initialFirstName);
    _lastCtrl  = TextEditingController(text: widget.initialLastName);
  }

  @override
  void dispose() { _firstCtrl.dispose(); _lastCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    try {
      await DioClient.put('/auth/profile', data: {
        'first_name': _firstCtrl.text.trim(),
        'last_name':  _lastCtrl.text.trim(),
      });
      widget.onSaved();
      if (mounted) {
        nav.pop();
        msg.showSnackBar(const SnackBar(content: Text('Profile updated')));
      }
    } catch (e) {
      if (mounted) {
        msg.showSnackBar(SnackBar(
          content: Text('Failed: ${e.toString().split(':').last.trim()}'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Text('Edit Profile', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          TextFormField(
            controller: _firstCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'First Name', prefixIcon: Icon(Icons.person_outline_rounded)),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length < 2) return 'Minimum 2 characters';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _lastCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Last Name', prefixIcon: Icon(Icons.person_outline_rounded)),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length < 2) return 'Minimum 2 characters';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  : const Text('Save Changes'),
            ),
          ),
        ]),
      ),
    );
  }
}