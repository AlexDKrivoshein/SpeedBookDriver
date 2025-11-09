// lib/call/agora_controller.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../fcm/incoming_call_service.dart'; // markCallEnded

class AgoraController {
  AgoraController._();
  static final instance = AgoraController._();

  RtcEngine? _engine;
  int? _callId;           // <- текущий callId (если передали при join)
  String? _channelId;     // для логов/диагностики
  int? _localUid;

  Future<void> join({
    required String appId,
    required String token,
    required String channel,
    required int uid,
    int? callId, // <- НОВОЕ: опционально передаём идентификатор звонка
  }) async {
    _callId = callId;
    _channelId = channel;
    _localUid = uid;

    if (_engine == null) {
      _engine = createAgoraRtcEngine();

      // === Инициализация движка ===
      await _engine!.initialize(
        RtcEngineContext(
          appId: appId.isNotEmpty ? appId : null,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // === Регистрация колбэков (совместимо с 6.5.3) ===
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) async {
            debugPrint('[Agora] ✅ onJoinChannelSuccess uid=${connection.localUid} ch=${connection.channelId}');
            // Небольшая задержка и попытка включить спикер
            Future.delayed(const Duration(milliseconds: 250), () async {
              try {
                await _engine?.setEnableSpeakerphone(true);
                debugPrint('[Agora] 🔊 speakerphone ON (after join)');
              } catch (e) {
                debugPrint('[Agora] setEnableSpeakerphone after join failed: $e');
              }
            });
          },

          onFirstRemoteAudioDecoded: (RtcConnection _, int remoteUid, int __) async {
            debugPrint('[Agora] 🎧 onFirstRemoteAudioDecoded uid=$remoteUid');
            try {
              await _engine?.setEnableSpeakerphone(true);
              debugPrint('[Agora] 🔊 speakerphone ON (after remote audio)');
            } catch (e) {
              debugPrint('[Agora] setEnableSpeakerphone after remote failed: $e');
            }
          },

          onRemoteAudioStateChanged: (
              RtcConnection _,
              int remoteUid,
              RemoteAudioState state,
              RemoteAudioStateReason reason,
              int elapsed,
              ) {
            debugPrint('[Agora] 🎚 onRemoteAudioStateChanged uid=$remoteUid state=$state reason=$reason');
          },

          // В 6.5.3 сигнатура без RtcConnection:
          onAudioRoutingChanged: (int routing) async {
            debugPrint('[Agora] 🔁 onAudioRoutingChanged routing=$routing');
            try { await _engine?.setEnableSpeakerphone(true); } catch (_) {}
          },

          // 🔔 Главное: если удалённый участник ушёл — завершаем звонок наверху
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            debugPrint('[Agora] ❌ onUserOffline uid=$remoteUid reason=$reason callId=$_callId ch=${connection.channelId}');
            final cid = _callId;
            if (cid != null) {
              // Уведомляем UI/сервис о завершении вызова по причине remote_offline
              IncomingCallService.markCallEnded(cid, reason: 'remote_offline');
            }
          },

          onError: (ErrorCodeType err, String msg) {
            debugPrint('[Agora][Error] $err $msg');
          },
        ),
      );

      // === Базовые аудио-настройки ===
      await _engine!.enableAudio();
      await _engine!.setChannelProfile(ChannelProfileType.channelProfileCommunication);
      await _engine!.setAudioScenario(AudioScenarioType.audioScenarioDefault);

      // Только маршрут по умолчанию — ДО joinChannel
      await _engine!.setDefaultAudioRouteToSpeakerphone(true);
      // НЕ вызываем setEnableSpeakerphone здесь — даёт ERR_NOT_READY (-3)
    }

    // === Вход в канал ===
    await _engine!.joinChannel(
      token: token,
      channelId: channel,
      uid: uid,
      options: const ChannelMediaOptions(
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
      ),
    );

    debugPrint('[Agora] 🚀 joinChannel requested: channel=$channel uid=$uid callId=$_callId');
  }

  Future<void> leave() async {
    try {
      debugPrint('[Agora] 👋 leaveChannel() ch=$_channelId uid=$_localUid callId=$_callId');
      await _engine?.leaveChannel();
    } catch (e) {
      debugPrint('[Agora][Error] leaveChannel: $e');
    } finally {
      _callId = null;
      _channelId = null;
      _localUid = null;
    }
  }
}
