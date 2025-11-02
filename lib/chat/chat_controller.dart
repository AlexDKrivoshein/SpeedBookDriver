// lib/chat/chat_controller.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../api_service.dart';
import 'chat_message.dart';

/// Контроллер чата:
/// - грузит историю (loadInitial)
/// - каждые 3 сек подтягивает новые (_pullNew)
/// - считает непрочитанные (только входящие и !isRead)
/// - отправляет сообщения (send) и игнорирует дубликаты (пустой ответ)
/// - помечает прочитанными по серверной процедуре mark_chat_read (upto/upto_id)
class ChatController extends ChangeNotifier {
  final int driveId;

  final List<ChatMessage> _items = <ChatMessage>[];
  final Set<int> _seenIds = <int>{}; // дедуп по id

  String? _nextAfterIso; // курсоры сервера для пагинации (вперёд)
  int? _nextAfterId;

  int _unreadCount = 0;
  bool _loading = false;
  Timer? _pollTimer;

  List<ChatMessage> get items => List.unmodifiable(_items);
  int get unreadCount => _unreadCount;
  bool get loading => _loading;

  ChatController({required this.driveId});

  // ==== lifecycle ============================================================

  Future<void> init() async {
    await loadInitial();
    _startPolling();
  }

  Future<void> disposeAsync() async {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ==== data flow ============================================================

  Future<void> loadInitial() async {
    _loading = true;
    notifyListeners();
    try {
      final fetched = await _fetchPage(limit: 50);
      _applyFetched(fetched, initial: true);
    } catch (e, st) {
      debugPrint('[Chat] loadInitial error: $e\n$st');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pullNew());
  }

  Future<void> _pullNew() async {
    try {
      final fetched = await _fetchPage(
        limit: 50,
        afterIso: _nextAfterIso,
        afterId: _nextAfterId,
      );
      if (fetched.items.isEmpty &&
          fetched.nextAfterIso == null &&
          fetched.nextAfterId == null) {
        return;
      }
      _applyFetched(fetched, initial: false);
    } catch (e, st) {
      debugPrint('[Chat] _pullNew error: $e\n$st');
    }
  }

  // ==== read tracking: mark as read ==========================================

  /// Пометить все входящие непрочитанные как прочитанные.
  /// Локально обновляем ленту и (важно) шлём на сервер:
  ///   { drive_id, upto: timestamptz, upto_id: int8 } — оба параметра включительно.
  Future<void> markAllRead() async {
    // 1) Соберём все входящие непрочитанные
    final unreadIncoming = _items.where((m) => !m.isMine && !m.isRead).toList();
    if (unreadIncoming.isEmpty) {
      if (_unreadCount != 0) {
        _unreadCount = 0;
        notifyListeners();
      }
      return;
    }

    // 2) Вычислим «границу» upto/upto_id:
    //    берём максимальную ts среди непрочитанных входящих;
    //    на этой временной границе берём максимум id.
    final boundary = _computeBoundary(unreadIncoming);
    final uptoIso = boundary.uptoTs.toUtc().toIso8601String();
    final uptoId = boundary.uptoId;

    // 3) Оптимистично локально пометим как прочитанные (<= границы)
    bool changed = false;
    for (var i = 0; i < _items.length; i++) {
      final m = _items[i];
      if (!m.isMine && !m.isRead) {
        final before = m.ts.isBefore(boundary.uptoTs);
        final atSameTsAndId = m.ts.isAtSameMomentAs(boundary.uptoTs) && m.id <= uptoId;
        if (before || atSameTsAndId) {
          _items[i] = m.copyWith(isRead: true);
          changed = true;
        }
      }
    }
    _unreadCount = 0;
    if (changed) notifyListeners();

    // 4) Шлём на сервер mark_chat_read (без for_user: на бэке возьмут из _sys)
    try {
      final reply = await ApiService.callAndDecode('mark_chat_read', {
        'drive_id': driveId,
        'upto': uptoIso,
        'upto_id': uptoId,
        // 'for_user': <int?>  // можно не слать — сервер подставит текущего
      });

      // ожидаем: {status:OK, data:{affected, remaining_unread, next_unread_ts, next_unread_id}}
      if (reply is Map && reply['status']?.toString() == 'OK') {
        final data = reply['data'];
        if (data is Map) {
          final remaining = (data['remaining_unread'] is num)
              ? (data['remaining_unread'] as num).toInt()
              : null;
          if (remaining != null) {
            _unreadCount = remaining; // синхронизируем бейдж с сервером
          }
          // next_unread_ts/next_unread_id можно сохранить при желании
        }
      }
      notifyListeners();
    } catch (e) {
      // не критично: локально уже пометили
      debugPrint('[Chat] markAllRead server call failed: $e');
    }
  }

  /// Подбор включающей границы для mark-read.
  _Boundary _computeBoundary(List<ChatMessage> unreadIncoming) {
    // max ts
    DateTime maxTs = unreadIncoming.first.ts;
    for (final m in unreadIncoming) {
      if (m.ts.isAfter(maxTs)) maxTs = m.ts;
    }
    // на границе maxTs берём максимальный id
    int maxIdOnTs = 0;
    for (final m in unreadIncoming) {
      if (m.ts.isAtSameMomentAs(maxTs)) {
        if (m.id > maxIdOnTs) maxIdOnTs = m.id;
      }
    }
    return _Boundary(uptoTs: maxTs, uptoId: maxIdOnTs);
  }

  // ==== sending ==============================================================

  Future<void> send(String text) async {
    final msgText = text.trim();
    if (msgText.isEmpty) return;

    final raw = await ApiService.callAndDecode('send_chat_message', {
      'drive_id': driveId,
      'text': msgText,
    });

    final data = _unwrapData(raw);

    Map<String, dynamic>? m =
        _asMap(data['message']) ??
            _asMap(data['item']) ??
            (data['items'] is List && (data['items'] as List).isNotEmpty
                ? _asMap((data['items'] as List).first)
                : null) ??
            _asMap(data);

    // Сервер может вернуть пусто при дубликате — ничего не добавляем
    if (m == null || m.isEmpty) {
      debugPrint('[Chat] duplicate or empty response, skip adding');
      return;
    }

    // Гарантируем «моё и прочитано» для только что отправленного
    m['is_mine'] = m['is_mine'] ?? true;
    m['is_read'] = true;

    final msg = ChatMessage.fromJson(m);

    // Дедуп по id, на случай гонок
    if (_seenIds.contains(msg.id)) return;

    _items.add(msg);
    _seenIds.add(msg.id);

    _items.sort((a, b) => a.ts.compareTo(b.ts));

    // Обновим курсоры «вперёд», если сервер их не пришлёт позже
    _nextAfterIso = msg.ts.toUtc().toIso8601String();
    _nextAfterId = msg.id;

    notifyListeners();
  }

  // ==== fetch & apply ========================================================

  Future<_Fetched> _fetchPage({
    required int limit,
    String? afterIso,
    int? afterId,
  }) async {
    final params = <String, dynamic>{
      'drive_id': driveId,
      'limit': limit,
      if (afterIso != null) 'after_iso': afterIso,
      if (afterId != null) 'after_id': afterId,
    };

    final raw = await ApiService.callAndDecode('get_chat_by_drive', params);

    final data = (raw is Map) ? raw['data'] : null;

    final itemsJson = (data is Map && data['items'] is List)
        ? (data['items'] as List)
        : const <dynamic>[];

    final nextAfterIso = (data is Map) ? data['next_after']?.toString() : null;
    final nextAfterId = (data is Map && data['next_after_id'] is num)
        ? (data['next_after_id'] as num).toInt()
        : null;
    final unreadFromServer = (data is Map && data['unread_count'] is num)
        ? (data['unread_count'] as num).toInt()
        : null;

    final items = itemsJson
        .map((j) => ChatMessage.fromJson(_asMap(j) ?? const {}))
        .toList();

    return _Fetched(
      items: items,
      nextAfterIso: nextAfterIso,
      nextAfterId: nextAfterId,
      unreadFromServer: unreadFromServer,
    );
  }

  void _applyFetched(_Fetched f, {required bool initial}) {
    // Курсоры из сервера — первичны
    if (f.nextAfterIso != null) _nextAfterIso = f.nextAfterIso;
    if (f.nextAfterId != null) _nextAfterId = f.nextAfterId;

    // Добавляем только реально новые сообщения
    final List<ChatMessage> newOnes = [];
    for (final m in f.items) {
      if (_seenIds.add(m.id)) {
        newOnes.add(m);
        _items.add(m);
      }
    }

    if (newOnes.isEmpty && !initial) {
      return; // ничего нового — выходим без пересчётов
    }

    _items.sort((a, b) => a.ts.compareTo(b.ts));

    if (initial) {
      // unread_count от сервера — в приоритете
      if (f.unreadFromServer != null) {
        _unreadCount = f.unreadFromServer!;
      } else {
        _unreadCount = _items.where((m) => !m.isMine && !m.isRead).length;
      }
    } else {
      // Инкремент только по реально новым входящим непрочитанным
      final inc = newOnes.where((m) => !m.isMine && !m.isRead).length;
      if (inc > 0) _unreadCount += inc;
    }

    notifyListeners();
  }

  // ==== utils ================================================================

  Map<String, dynamic> _unwrapData(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      if (raw.containsKey('data') && raw['data'] is Map<String, dynamic>) {
        return raw['data'] as Map<String, dynamic>;
      }
      return raw;
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic>? _asMap(dynamic v) =>
      v is Map<String, dynamic> ? v : null;
}

class _Fetched {
  final List<ChatMessage> items;
  final String? nextAfterIso;
  final int? nextAfterId;
  final int? unreadFromServer;
  _Fetched({
    required this.items,
    required this.nextAfterIso,
    required this.nextAfterId,
    required this.unreadFromServer,
  });
}

class _Boundary {
  final DateTime uptoTs;
  final int uptoId;
  _Boundary({required this.uptoTs, required this.uptoId});
}
