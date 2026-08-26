import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/notification_service.dart';

class NotificationsState {
  final List<AppNotification> notifications;
  final bool isLoading;

  const NotificationsState({
    this.notifications = const [],
    this.isLoading = false,
  });

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  NotificationsState copyWith({
    List<AppNotification>? notifications,
    bool? isLoading,
  }) =>
      NotificationsState(
        notifications: notifications ?? this.notifications,
        isLoading: isLoading ?? this.isLoading,
      );
}

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  NotificationsNotifier() : super(const NotificationsState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    final notifs = await NotificationService.instance.loadAll();
    state = NotificationsState(notifications: notifs, isLoading: false);
  }

  Future<void> markAllRead() async {
    await NotificationService.instance.markAllRead();
    state = state.copyWith(
      notifications: state.notifications.map((n) => n.copyWith(isRead: true)).toList(),
    );
  }

  Future<void> clearAll() async {
    await NotificationService.instance.clearAll();
    state = const NotificationsState();
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, NotificationsState>(
  (ref) => NotificationsNotifier(),
);
