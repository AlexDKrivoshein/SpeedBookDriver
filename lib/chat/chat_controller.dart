// lib/chat/chat_controller.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'chat_message.dart';
import '../api_service.dart';

class ChatController extends ChangeNotifier {
  final int driveId;
  final List<ChatMessage> _items = [];
  String? _nextAfterIso;
  int? _nextAfterId;
  int _unreadCount = 0;
  bool _loading = false;
  Timer? _pollTimer;

  List<ChatMessage> get items => List.unmodifiable(_items);
  int get unreadCount => _unreadCount;
  bool get loading => _loading;

  ChatController({required this.driveId});

  Future<void> init() async {
    await loadInitial();
    _startPolling();
  }

  Future<void> disposeAsync() async {
    _pollTimer?.cancel();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pullNew());
  }

  // ——— helpers ———
  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  /// unwraps `{ data: {...}, status: ... }` → `{...}`
  Map<String, dynamic> _unwrapData(dynamic result) {
    final root = _asMap(result) ?? const <String, dynamic>{};
    final data = _asMap(root['data']);
    return data ?? root;
  }

  // ——— API calls ———
  Future<void> loadInitial() async {
    _loading = true;
    try {
      final raw = await ApiService.callAndDecode('get_chat_by_drive', {
        'drive_id': driveId,
        'limit': 50,
      });
      final result = _unwrapData(raw);

      final arr = (result['items'] as List?) ?? const [];
      _items
        ..clear()
        ..addAll(arr.map((e) => ChatMessage.fromJson(_asMap(e)!)));

      _nextAfterIso = result['next_after'] as String?;
      _nextAfterId  = (result['next_after_id'] as num?)?.toInt();
      _unreadCount  = (result['unread_count'] as num?)?.toInt() ?? 0;

      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  Future<void> _pullNew() async {
    if (_loading) return;
    _loading = true;
    try {
      final raw = await ApiService.callAndDecode('get_chat_by_drive', {
        'drive_id': driveId,
        'after': _nextAfterIso,
        'after_id': _nextAfterId,
        'limit': 100,
      });

      final result = _unwrapData(raw);
      debugPrint('Chat API result: $result');

      final arr = (result['items'] as List?) ?? const [];
      if (arr.isNotEmpty) {
        final msgs = arr.map((e) => ChatMessage.fromJson(_asMap(e)!)).toList();
        _items.addAll(msgs);
        _nextAfterIso = result['next_after'] as String?;
        _nextAfterId  = (result['next_after_id'] as num?)?.toInt();
        notifyListeners();
      }
      _unreadCount = (result['unread_count'] as num?)?.toInt() ?? _unreadCount;
    } finally {
      _loading = false;
    }
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty) return;

    final raw = await ApiService.callAndDecode('send_chat_message', {
      'drive_id': driveId,
      'text': text,
    });
    final data = _unwrapData(raw);

    // допускаем варианты: message / item / items[0] / сам data
    Map<String, dynamic>? m =
        _asMap(data['message']) ??
            _asMap(data['item']) ??
            (data['items'] is List && (data['items'] as List).isNotEmpty
                ? _asMap((data['items'] as List).first)
                : null) ??
            _asMap(data);

    if (m == null) {
      throw StateError('send_chat_message: unexpected response format: $raw');
    }

    // гарантируем is_mine=true для только что отправленного сообщения
    m['is_mine'] = m['is_mine'] ?? true;

    final msg = ChatMessage.fromJson(m);
    _items.add(msg);
    _nextAfterIso = msg.ts.toUtc().toIso8601String();
    _nextAfterId  = msg.id;
    notifyListeners();
  }
}
