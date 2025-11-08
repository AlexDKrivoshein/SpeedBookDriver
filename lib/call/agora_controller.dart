import 'package:agora_rtc_engine/agora_rtc_engine.dart';

class AgoraController {
  AgoraController._();
  static final instance = AgoraController._();

  RtcEngine? _engine;

  Future<void> join({
    required String appId,
    required String token,
    required String channel,
    required int uid,
  }) async {
    if (_engine == null) {
      _engine = createAgoraRtcEngine();
      // Если ваша версия SDK требует appId в контексте — подставьте.
      await _engine!.initialize(RtcEngineContext(appId: appId.isNotEmpty ? appId : null));
      await _engine!.enableAudio();
    }
    await _engine!.joinChannel(
      token: token,
      channelId: channel,
      uid: uid,
      options: const ChannelMediaOptions(),
    );
  }

  Future<void> leave() async {
    try { await _engine?.leaveChannel(); } catch (_) {}
  }
}
