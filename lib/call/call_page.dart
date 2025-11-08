import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

// подкорректируй путь под свой проект при необходимости
import '../api_service.dart';

class CallPage extends StatefulWidget {
  final String appId;     // Agora App ID
  final String token;     // Agora RTC token
  final String channel;   // Имя канала (например, drive_415)
  final int uid;          // Твой uid (driver/customer)
  final int? callId;      // корректный идентификатор звонка для бекенда

  const CallPage({
    super.key,
    required this.appId,
    required this.token,
    required this.channel,
    required this.uid,
    this.callId,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late final RtcEngine _engine;
  bool _joined = false;
  bool _muted = false;
  bool _speakerOn = true;
  int? _remoteUid;

  // для end_call
  late final DateTime _callStart;
  bool _endReported = false;

  @override
  void initState() {
    super.initState();
    _callStart = DateTime.now();
    _init();
  }

  Future<void> _init() async {
    // Разрешение на микрофон
    final st = await Permission.microphone.request();
    if (!st.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      Navigator.pop(context);
      return;
    }

    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(appId: widget.appId));

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        setState(() => _joined = true);
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        setState(() => _remoteUid = remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) {
        // собеседник ушёл/отвалился — считаем завершением
        _reportEnd('remote_offline_${reason.name}');
        setState(() => _remoteUid = null);
      },
      onLeaveChannel: (connection, stats) {
        // локально покинули канал — считаем завершением
        _reportEnd('leave_channel');
        setState(() => _joined = false);
      },
      onTokenPrivilegeWillExpire: (connection, token) async {
        // сюда можно добавить запрос нового токена и _engine.renewToken(newToken)
      },
      onConnectionStateChanged: (connection, state, changeReason) {
        // на всякий случай фиксируем фатальные дисконнекты
        if (state == ConnectionStateType.connectionStateFailed ||
            state == ConnectionStateType.connectionStateDisconnected) {
          _reportEnd('conn_${changeReason.name}');
        }
      },
    ));

    await _engine.enableAudio();
    await _engine.setDefaultAudioRouteToSpeakerphone(true);

    // Используем userAccount, чтобы не путать типы токенов
    final account = widget.uid.toString();
    await _engine.registerLocalUserAccount(
      appId: widget.appId,
      userAccount: account,
    );

    await _engine.joinChannelWithUserAccount(
      token: widget.token,               // токен от сервера
      channelId: widget.channel,         // канал
      userAccount: account,              // строковый аккаунт = uid.toString()
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  // единая точка отправки end_call (идемпотентно в рамках страницы)
  Future<void> _reportEnd(String reason) async {
    if (_endReported) return;
    _endReported = true;

    final durationMs = DateTime.now().difference(_callStart).inMilliseconds;
    try {
      await ApiService.callAndDecode('end_call', {
        if (widget.callId != null) 'call_id': widget.callId, // ✅ правильное поле
        'reason': reason,
        'duration_ms': durationMs,
      });
    } catch (e) {
      // не ломаем UX, просто лог
      // ignore: avoid_print
      print('[CallPage] end_call error: $e');
    }
  }

  @override
  void dispose() {
    // если каким-либо путём сюда пришли — считаем завершением
    _reportEnd('dispose');
    () async {
      try {
        await _engine.leaveChannel();
        await _engine.release();
      } catch (_) {}
    }();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _engine.muteLocalAudioStream(_muted);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    await _engine.setEnableSpeakerphone(_speakerOn);
  }

  Future<void> _hangup() async {
    _reportEnd('local_hangup');
    try {
      await _engine.leaveChannel();
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _handleWillPop() async {
    // «назад» жестом/кнопкой — тоже завершаем
    _reportEnd('back_pressed');
    try {
      await _engine.leaveChannel();
    } catch (_) {}
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _joined
        ? (_remoteUid != null ? 'Connected' : 'Waiting for peer…')
        : 'Connecting…';

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        appBar: AppBar(title: const Text('Voice call')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(statusText),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: _muted ? 'Unmute' : 'Mute',
                    onPressed: _toggleMute,
                    icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                  ),
                  const SizedBox(width: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _hangup,
                    icon: const Icon(Icons.call_end),
                    label: const Text('Hang up'),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    tooltip: _speakerOn ? 'Speaker off' : 'Speaker on',
                    onPressed: _toggleSpeaker,
                    icon: Icon(_speakerOn ? Icons.volume_up : Icons.hearing),
                  ),
                ],
              ),
              if (widget.callId != null) ...[
                const SizedBox(height: 8),
                Text('call_id: ${widget.callId}'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
