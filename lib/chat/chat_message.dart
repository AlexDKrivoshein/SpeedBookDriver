// lib/chat/chat_message.dart
class ChatMessage {
  final int id;
  final DateTime ts;
  final int driveId;

  /// Идентификаторы сторон, если пришли числа
  final int? from; // прежнее поле, оставляем (может быть null, если пришло имя)
  final int? to;   // прежнее поле, оставляем (может быть null, если пришло имя)

  /// Имена сторон, если сервер вернул строки ("Me" или displayName)
  final String? fromName;
  final String? toName;

  final String text;
  final bool isRead;

  /// Новый флаг — серверный признак «моё сообщение»
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

  /// Безопасный парсер: поддерживает как числовые, так и строковые поля.
  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    // ts
    final tsRaw = j['ts'];
    final ts = (tsRaw is String)
        ? (DateTime.tryParse(tsRaw) ?? DateTime.now())
        : (tsRaw is DateTime ? tsRaw : DateTime.now());

    // drive_id
    final driveIdRaw = j['drive_id'];
    final driveId = (driveIdRaw is num)
        ? driveIdRaw.toInt()
        : int.tryParse('${driveIdRaw ?? ''}') ?? 0;

    // from / to: могут прийти как int, как строка "Me"/имя, или как числовая строка
    final fromRaw = j['from'];
    final toRaw   = j['to'];

    int? _asInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    String? _asStringName(dynamic v) {
      if (v == null) return null;
      if (v is String) return v;
      // если сервер прислал число — имени нет
      return null;
    }

    final int? fromId   = _asInt(fromRaw);
    final int? toId     = _asInt(toRaw);
    final String? fromNm = _asStringName(fromRaw);
    final String? toNm   = _asStringName(toRaw);

    // is_read
    final isRead = j['is_read'] == true;

    // is_mine
    final isMine = j['is_mine'] == true;

    // id
    final idRaw = j['id'];
    final id = (idRaw is num) ? idRaw.toInt() : int.tryParse('${idRaw ?? 0}') ?? 0;

    return ChatMessage(
      id: id,
      ts: ts,
      driveId: driveId,
      from: fromId,
      to: toId,
      fromName: fromNm,
      toName: toNm,
      text: (j['text'] ?? '').toString(),
      isRead: isRead,
      isMine: isMine,
    );
  }
}
