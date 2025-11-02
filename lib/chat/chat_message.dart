// lib/chat/chat_message.dart

/// Модель одного сообщения чата.
/// Поддерживает оба формата: старый (числовые from/to)
/// и новый, где приходят строковые имена ("Me", "+7912...", и т.п.)
class ChatMessage {
  final int id;
  final DateTime ts;
  final int driveId;

  /// Идентификаторы сторон, если сервер прислал числа
  final int? from;
  final int? to;

  /// Имена сторон (строки вроде "Me" или "+7912...")
  final String? fromName;
  final String? toName;

  /// Текст сообщения
  final String text;

  /// Серверный флаг "прочитано"
  final bool isRead;

  /// Флаг "моё сообщение"
  final bool isMine;

  ChatMessage({
    required this.id,
    required this.ts,
    required this.driveId,
    required this.text,
    required this.isRead,
    required this.isMine,
    this.from,
    this.to,
    this.fromName,
    this.toName,
  });

  /// Безопасный парсер: умеет понимать разные типы (int/String/DateTime)
  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    // --- timestamp ---
    final tsRaw = j['ts'];
    DateTime ts;
    if (tsRaw is String) {
      ts = DateTime.tryParse(tsRaw) ?? DateTime.now();
    } else if (tsRaw is DateTime) {
      ts = tsRaw;
    } else {
      ts = DateTime.now();
    }

    // --- drive_id ---
    final driveRaw = j['drive_id'];
    final driveId = (driveRaw is num)
        ? driveRaw.toInt()
        : int.tryParse('${driveRaw ?? ''}') ?? 0;

    // --- from / to ---
    final fromRaw = j['from'];
    final toRaw = j['to'];

    int? asInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    String? asStringName(dynamic v) {
      if (v == null) return null;
      if (v is String) return v;
      return null;
    }

    final fromId = asInt(fromRaw);
    final toId = asInt(toRaw);
    final fromNm = asStringName(fromRaw);
    final toNm = asStringName(toRaw);

    // --- прочее ---
    final isRead = j['is_read'] == true;
    final isMine = j['is_mine'] == true;
    final text = (j['text'] ?? '').toString();

    final idRaw = j['id'];
    final id = (idRaw is num)
        ? idRaw.toInt()
        : int.tryParse('${idRaw ?? 0}') ?? 0;

    return ChatMessage(
      id: id,
      ts: ts,
      driveId: driveId,
      from: fromId,
      to: toId,
      fromName: fromNm,
      toName: toNm,
      text: text,
      isRead: isRead,
      isMine: isMine,
    );
  }

  /// Для удобства: копия с изменением одного-двух полей (если понадобится)
  ChatMessage copyWith({
    int? id,
    DateTime? ts,
    int? driveId,
    int? from,
    int? to,
    String? fromName,
    String? toName,
    String? text,
    bool? isRead,
    bool? isMine,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      ts: ts ?? this.ts,
      driveId: driveId ?? this.driveId,
      from: from ?? this.from,
      to: to ?? this.to,
      fromName: fromName ?? this.fromName,
      toName: toName ?? this.toName,
      text: text ?? this.text,
      isRead: isRead ?? this.isRead,
      isMine: isMine ?? this.isMine,
    );
  }

  @override
  String toString() =>
      'ChatMessage(id: $id, text: "$text", from: $fromName, mine: $isMine, read: $isRead)';

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
          other.id == id &&
          other.driveId == driveId &&
          other.text == text &&
          other.ts == ts;

  @override
  int get hashCode => Object.hash(id, driveId, text, ts);
}
