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
    int? callId, // <- опционально передаём идентификатор звонка
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
            debugPrint(
              '[Agora] ✅ onJoinChannelSuccess uid=${connection.localUid} ch=${connection.channelId}',
            );
            // Раньше тут насильно включали громкую связь.
            // Теперь начальный маршрут — как у обычного звонка (в ухо).
          },

          onFirstRemoteAudioDecoded: (RtcConnection _, int remoteUid, int __) async {
            debugPrint('[Agora] 🎧 onFirstRemoteAudioDecoded uid=$remoteUid');
            // Раньше здесь тоже включали громкую связь,
            // теперь управляем только по нажатию на кнопку в UI.
          },

          onRemoteAudioStateChanged: (
              RtcConnection _,
              int remoteUid,
              RemoteAudioState state,
              RemoteAudioStateReason reason,
              int elapsed,
              ) {
            debugPrint(
              '[Agora] 🎚 onRemoteAudioStateChanged uid=$remoteUid state=$state reason=$reason',
            );
          },

          // В 6.5.3 сигнатура без RtcConnection:
          onAudioRoutingChanged: (int routing) async {
            debugPrint('[Agora] 🔁 onAudioRoutingChanged routing=$routing');
            // Ничего не трогаем: авто-переключения на speakerphone убраны.
          },

          // 🔔 Главное: если удалённый участник ушёл — завершаем звонок наверху
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            debugPrint(
              '[Agora] ❌ onUserOffline uid=$remoteUid reason=$reason callId=$_callId ch=${connection.channelId}',
            );
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

      // Только маршрут по умолчанию — ДО joinChannel.
      // Для голосового звонка по умолчанию — в ухо, а не громкая связь.
      await _engine!.setDefaultAudioRouteToSpeakerphone(false);
      // НЕ вызываем setEnableSpeakerphone здесь — даёт ERR_NOT_READY (-3) и ломает начальный маршрут.
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

  /// Включить/выключить громкую связь.
  /// true  → звук идёт через спикер (громкий динамик)
  /// false → обычный разговорный динамик / наушник
  Future<void> setSpeakerEnabled(bool enabled) async {
    if (_engine == null) return;
    try {
      await _engine!.setEnableSpeakerphone(enabled);
      debugPrint(
        '[Agora] 🔊 speaker=${enabled ? 'ON' : 'OFF'} callId=$_callId ch=$_channelId',
      );
    } catch (e, st) {
      debugPrint('[Agora][Error] setSpeakerEnabled($enabled): $e\n$st');
    }
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
