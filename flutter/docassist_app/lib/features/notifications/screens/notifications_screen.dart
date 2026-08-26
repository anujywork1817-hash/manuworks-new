import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../providers/notifications_provider.dart';
import '../../../core/services/notification_service.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh list and mark all as read when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).load();
      ref.read(notificationsProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);

    return Scaffold(
      
      appBar: AppBar(
        
        elevation: 0,
        leading: const BackButton(),
        title: const Text('Notifications',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        actions: [
          if (state.notifications.isNotEmpty)
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear All'),
                    content: const Text(
                        'Remove all notifications? This cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.error),
                          child: const Text('Clear All')),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref
                      .read(notificationsProvider.notifier)
                      .clearAll();
                }
              },
              child: const Text('Clear All',
                  style: TextStyle(color: AppColors.error, fontSize: 13)),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.notifications.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(notificationsProvider.notifier).load(),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.notifications.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, i) =>
                        _NotificationTile(notif: state.notifications[i]),
                  ),
                ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notif;
  const _NotificationTile({required this.notif});

  IconData get _icon {
    switch (notif.type) {
      case 'upload':
        return Icons.upload_file_rounded;
      case 'process':
        return Icons.auto_awesome_rounded;
      case 'matter':
        return Icons.folder_rounded;
      case 'compare':
        return Icons.compare_arrows_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color get _iconColor {
    switch (notif.type) {
      case 'upload':
        return AppColors.info;
      case 'process':
        return AppColors.accent;
      case 'matter':
        return AppColors.primary;
      case 'compare':
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }

  Color get _iconBg {
    switch (notif.type) {
      case 'upload':
        return AppColors.infoContainer;
      case 'process':
        return AppColors.accentContainer;
      case 'matter':
        return AppColors.primaryContainer;
      case 'compare':
        return AppColors.secondaryContainer;
      default:
        return const Color(0xFFEEEDF8);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: notif.isRead ? Colors.transparent : AppColors.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: _iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon, color: _iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(notif.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: notif.isRead
                            ? FontWeight.w500
                            : FontWeight.w700,
                        color: AppColors.textPrimary,
                      )),
                ),
                if (!notif.isRead)
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(notif.body,
                  style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: 4),
              Text(timeago.format(notif.createdAt),
                  style: const TextStyle(
                    fontSize: 11, color: AppColors.textTertiary)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFEEEDF8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.notifications_none_rounded,
                color: AppColors.primary, size: 40),
          ),
          const SizedBox(height: 20),
          const Text('No notifications yet',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
            'You\'ll be notified when documents are\nuploaded, processed, or ready.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          ),
        ]),
      );
}
