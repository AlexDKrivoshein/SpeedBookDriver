class CallPayload {
  final int callId;
  final String channel;
  final String appId;
  final String token;
  final int uid;

  final String? initiatorName;
  final String? initiatorAvatar;
  final int ringMs;
  final String? expiresAtIso;

  const CallPayload({
    required this.callId,
    required this.channel,
    required this.appId,
    required this.token,
    required this.uid,
    this.initiatorName,
    this.initiatorAvatar,
    this.ringMs = 30000,
    this.expiresAtIso,
  });
}
