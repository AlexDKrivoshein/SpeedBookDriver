import 'package:flutter/material.dart';
import '../api_service.dart';
import 'call_page.dart';

/// Кнопка "Позвонить" рядом с чатом
class CallButton extends StatefulWidget {
  final int driveId;          // обязательный идентификатор поездки
  final EdgeInsets padding;   // для визуального отступа
  final double elevation;

  const CallButton({
    super.key,
    required this.driveId,
    this.padding = const EdgeInsets.all(12),
    this.elevation = 2,
  });

  @override
  State<CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<CallButton> {
  bool _loading = false;

  Future<void> _startCall() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      // Вызываем создание звонка
      final resp = await ApiService.callAndDecode(
        'create_call',
        {
          'drive_id': widget.driveId,
          'force_new': false,
        },
      );

      final status = '${resp['status'] ?? 'OK'}'.toUpperCase();
      if (status != 'OK') {
        final msg = (resp['message'] ?? resp['error'] ?? 'Call failed').toString();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      // Достаём полезные поля из ответа
      final data = (resp['data'] ?? {}) as Map? ?? {};
      debugPrint('[Call] Create call response: $data');

      final callId  = data['call_id'] as int?;
      final token   = (data['token'] ?? '') as String;
      final channel = (data['channel'] ?? '') as String;

      // uid может называться по-разному, подстрахуемся
      final uid = (data['uid'] ?? data['agora_uid']) is int
          ? data['uid'] ?? data['agora_uid']
          : int.tryParse('${data['uid'] ?? data['agora_uid'] ?? ''}');
      final appId = (data['agora_app_id'] ?? data['appId'] ?? '') as String;

      if (callId == null || token.isEmpty || appId.isEmpty || uid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bad server response: missing call_id/token/appId/uid')),
        );
        return;
      }

      // Навигация на страницу звонка
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallPage(
            appId: appId,
            token: token,
            channel: channel,
            uid: uid,
            callId: callId, // ✅ передаём правильный идентификатор
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Call error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: widget.elevation,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _loading ? null : _startCall,
        child: Padding(
          padding: widget.padding,
          child: _loading
              ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.phone, color: Colors.green, size: 24),
        ),
      ),
    );
  }
}
