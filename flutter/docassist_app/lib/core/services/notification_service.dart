import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String? type; // 'upload' | 'process' | 'matter' | 'info'

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.type,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        type: type,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'created_at': createdAt.toIso8601String(),
        'is_read': isRead,
        'type': type,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        isRead: j['is_read'] as bool? ?? false,
        type: j['type'] as String?,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  int _notifId = 0;

  static const _kPrefsKey = 'app_notifications_v1';
  static const _kChannelId = 'docassist_main';
  static const _kChannelName = 'DocAssist';

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  // Show a system notification and persist it to the in-app list.
  Future<void> show({
    required String title,
    required String body,
    String? type,
  }) async {
    await _persist(title: title, body: body, type: type);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(_notifId++, title, body, details);
  }

  Future<void> _persist({
    required String title,
    required String body,
    String? type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kPrefsKey) ?? [];
    final n = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      createdAt: DateTime.now(),
      type: type,
    );
    raw.insert(0, jsonEncode(n.toJson()));
    if (raw.length > 50) raw.removeLast();
    await prefs.setStringList(_kPrefsKey, raw);
  }

  Future<List<AppNotification>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kPrefsKey) ?? [];
    return raw
        .map((s) => AppNotification.fromJson(
            jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> markAllRead() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kPrefsKey) ?? [];
    final updated = raw.map((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      m['is_read'] = true;
      return jsonEncode(m);
    }).toList();
    await prefs.setStringList(_kPrefsKey, updated);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsKey);
  }
}
