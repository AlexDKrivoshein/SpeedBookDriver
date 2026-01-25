import 'package:flutter/material.dart';

import '../api_service.dart';
import '../call/agora_controller.dart';
import '../call/call_payload.dart';
import '../call/incoming_call_page.dart';
import '../call/permissions.dart';  // <-- добавили общий хелпер
import '../brand.dart';

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
      // 1) Проверка всех нужных пермишенов (микрофон, нотификации, BT и т.п.)
      final ok = await CallPermissions.ensure();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
        return;
      }

      // 2) Создаём звонок на бэке
      final resp = await ApiService.callAndDecode('create_call', {
        'drive_id': widget.driveId,
        'force_new': false,
      });

      final status = '${resp['status'] ?? 'OK'}'.toUpperCase();
      if (status != 'OK') {
        final msg = (resp['message'] ?? resp['error'] ?? 'Call failed').toString();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      final data = (resp['data'] ?? {}) as Map? ?? {};
      debugPrint('[Call] Create call response: $data');

      final callId  = data['call_id'] as int?;
      final token   = (data['token'] ?? '') as String;
      final channel = (data['channel'] ?? '') as String;

      // uid может называться по-разному
      final uid = (data['uid'] ?? data['agora_uid']) is int
          ? (data['uid'] ?? data['agora_uid']) as int
          : int.tryParse('${data['uid'] ?? data['agora_uid'] ?? ''}');
      final appId = (data['agora_app_id'] ?? data['appId'] ?? '') as String;

      // Доп. инфо для UI (если бэк отдаёт)
      final peerName   = (data['peer_name'] ?? data['name'] ?? '') as String;
      final peerAvatar = (data['peer_avatar'] ?? data['avatar'] ?? '') as String;

      if (callId == null || token.isEmpty || appId.isEmpty || uid == null || channel.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bad server response: missing call_id/token/appId/uid/channel')),
        );
        return;
      }

      // 3) Сразу подключаемся к каналу (исходящий звонок)
      await AgoraController.instance.join(
        appId: appId,
        token: token,
        channel: channel,
        uid: uid,
      );

      // 4) Готовим payload для UI
      final payload = CallPayload(
        callId: callId,
        channel: channel,
        token: token,
        uid: uid,
        appId: appId,
        initiatorName: peerName.toString().trim().isNotEmpty ? peerName : 'Calling...',
        initiatorAvatar: peerAvatar,
        ringMs: 0, // для исходящего авто-таймаут не нужен
      );

      // 5) Открываем универсальный экран в режиме исходящего звонка
      if (!mounted) return;
      await Navigator.of(context).push(
        IncomingCallPage.route(
          payload: payload,
          mode: CallUIMode.outgoing,
          // Отмена исходящего: завершаем звонок и выходим из канала
          onCancel: (p) async {
            try {
              await ApiService.callAndDecode('end_call', {
                'call_id': callId,
                'reason': 'caller_cancelled',
              });
            } catch (_) {} finally {
              await AgoraController.instance.leave();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            }
          },
          // На случай, если ты решишь переводить этот же экран в режим inProgress и вешать Hangup
          onHangup: (p) async {
            try {
              await ApiService.callAndDecode('end_call', {
                'call_id': callId,
                'reason': 'hangup',
              });
            } catch (_) {} finally {
              await AgoraController.instance.leave();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            }
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call error: $e')),
      );
      // При ошибке — на всякий случай выйти из канала
      try { await AgoraController.instance.leave(); } catch (_) {}
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final splash = Brand.yellow.withOpacity(0.2);
    return Material(
      color: Brand.yellowDark,
      shape: const CircleBorder(),
      elevation: widget.elevation,
      child: InkWell(
        customBorder: const CircleBorder(),
        splashColor: splash,
        highlightColor: splash,
        hoverColor: splash,
        onTap: _loading ? null : _startCall,
        child: Padding(
          padding: widget.padding,
          child: _loading
              ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Brand.textDark),
            ),
          )
              : const Icon(Icons.phone, color: Brand.textDark, size: 24),
        ),
      ),
    );
  }
}
