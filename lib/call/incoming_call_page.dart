import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import 'call_payload.dart';
import '../fcm/incoming_call_service.dart'; // call_accepted / call_ended
import 'agora_controller.dart';            // для leave() при внешнем завершении

enum CallUIMode { incoming, outgoing, inProgress }

class IncomingCallPage extends StatefulWidget {
  final CallPayload payload;
  final CallUIMode mode;

  // Входящий
  final Future<void> Function(CallPayload)? onAccept;
  final Future<void> Function(CallPayload)? onDecline;

  // Исходящий / Идущий
  final Future<void> Function(CallPayload)? onCancel;
  final Future<void> Function(CallPayload)? onHangup;

  const IncomingCallPage({
    super.key,
    required this.payload,
    this.mode = CallUIMode.incoming,
    this.onAccept,
    this.onDecline,
    this.onCancel,
    this.onHangup,
  });

  static Route route({
    required CallPayload payload,
    CallUIMode mode = CallUIMode.incoming,
    Future<void> Function(CallPayload)? onAccept,
    Future<void> Function(CallPayload)? onDecline,
    Future<void> Function(CallPayload)? onCancel,
    Future<void> Function(CallPayload)? onHangup,
  }) {
    return MaterialPageRoute(
      settings: const RouteSettings(name: 'IncomingCallPage'),
      fullscreenDialog: true,
      builder: (_) => IncomingCallPage(
        payload: payload,
        mode: mode,
        onAccept: onAccept,
        onDecline: onDecline,
        onCancel: onCancel,
        onHangup: onHangup,
      ),
    );
  }

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  static const _brandYellow = Color(0xFFFFC107);

  late final DateTime _startedAt;
  Timer? _ticker;
  String _elapsed = '00:00';
  Timer? _autoTimeout;
  bool _busy = false;
  late final FlutterRingtonePlayer _ringer = FlutterRingtonePlayer();

  late CallUIMode _mode;

  StreamSubscription<int>? _acceptSub;
  StreamSubscription<CallEndInfo>? _endSub;

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _startedAt = DateTime.now();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final sec = DateTime.now().difference(_startedAt).inSeconds;
      final m = (sec ~/ 60).toString().padLeft(2, '0');
      final s = (sec % 60).toString().padLeft(2, '0');
      if (mounted) setState(() => _elapsed = '$m:$s');
    });

    if (_mode == CallUIMode.incoming) {
      final ringMs = widget.payload.ringMs;
      // Ветка 5.x — экземплярный API и enum без 's'
      _ringer.play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.receivedMessage,
        looping: true,
        volume: 1.0,
        asAlarm: true,
      );
      if (ringMs > 0) {
        _autoTimeout = Timer(Duration(milliseconds: ringMs), _timeoutDecline);
      }
    }

    _acceptSub = IncomingCallService.acceptedStream.listen((callId) async {
      if (!mounted) return;
      if (callId == widget.payload.callId && _mode != CallUIMode.inProgress) {
        HapticFeedback.mediumImpact();
        _autoTimeout?.cancel();
        await _ringer.stop();
        setState(() => _mode = CallUIMode.inProgress);
      }
    });

    _endSub = IncomingCallService.endedStream.listen((ev) async {
      if (!mounted || ev.callId != widget.payload.callId) return;
      _autoTimeout?.cancel();
      _ticker?.cancel();
      await _ringer.stop();
      try { await AgoraController.instance.leave(); } catch (_) {}
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false) && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _acceptSub?.cancel();
    _endSub?.cancel();
    _ticker?.cancel();
    _autoTimeout?.cancel();
    _ringer.stop();
    super.dispose();
  }

  Future<void> _timeoutDecline() async {
    if (!mounted) return;
    await _handleDecline();
  }

  Future<void> _guarded(Future<void> Function()? fn) async {
    if (_busy || fn == null) return;
    _busy = true;
    try { await fn(); } finally { _busy = false; }
  }

  Future<void> _handleAccept() => _guarded(() async {
    debugPrint('[CallUI] Accept tapped');
    await _ringer.stop();
    if (widget.onAccept != null) {
      await widget.onAccept!(widget.payload);
    } else {
      debugPrint('[CallUI] onAccept is NULL');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No accept handler bound')),
        );
      }
    }
  });

  Future<void> _handleDecline() => _guarded(() async {
    debugPrint('[CallUI] Decline tapped');
    _autoTimeout?.cancel();
    await _ringer.stop();
    try {
      if (widget.onDecline != null) {
        await widget.onDecline!(widget.payload);
      } else {
        debugPrint('[CallUI] onDecline is NULL');
      }
    } catch (e, st) {
      debugPrint('[CallUI] onDecline error: $e\n$st');
    }
    // Закрываем страницу только если она всё ещё текущая (чтобы избежать двойного pop)
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false) && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  });

  Future<void> _handleCancel() => _guarded(() async {
    debugPrint('[CallUI] Cancel tapped');
    await _ringer.stop();
    if (widget.onCancel != null) await widget.onCancel!(widget.payload);
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false) && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  });

  Future<void> _handleHangup() => _guarded(() async {
    debugPrint('[CallUI] Hangup tapped');
    await _ringer.stop();
    if (widget.onHangup != null) await widget.onHangup!(widget.payload);
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false) && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  });

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    final name = (p.initiatorName ?? '').trim();
    final avatar = (p.initiatorAvatar ?? '').trim();
    final topInset = MediaQuery.of(context).padding.top;

    final title = () {
      switch (_mode) {
        case CallUIMode.incoming:   return 'Incoming call';
        case CallUIMode.outgoing:   return 'Calling...';
        case CallUIMode.inProgress: return 'In call';
      }
    }();

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Color(0xFF111111)],
                ),
              ),
            ),

            Positioned(
              top: topInset + 8,
              left: 20,
              right: 20,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _brandYellow.withOpacity(.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _brandYellow.withOpacity(.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_in_talk, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _elapsed,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '#${p.callId}',
                    style: const TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                ],
              ),
            ),

            Center(
              child: Transform.translate(
                offset: const Offset(0, -24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _brandYellow.withOpacity(.35),
                              blurRadius: 22,
                              spreadRadius: 1,
                            )
                          ],
                          gradient: const RadialGradient(
                            colors: [Color(0xFFFFF3CD), Color(0xFFFFE082), Color(0xFFFFC107)],
                            center: Alignment(0, 0),
                            radius: .95,
                          ),
                        ),
                        child: ClipOval(child: _SafeAvatar(url: avatar)),
                      ),
                      const SizedBox(height: 22),

                      Text(
                        name.isNotEmpty
                            ? name
                            : (_mode == CallUIMode.outgoing ? 'Calling...' : 'Incoming caller'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            height: 1.15,
                            fontWeight: FontWeight.w700),
                      ),

                      const SizedBox(height: 36),

                      _buildButtons(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtons() {
    switch (_mode) {
      case CallUIMode.incoming:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ActionButton(
              label: 'Decline',
              icon: Icons.call_end,
              bg: const Color(0xFFDA2C38),
              onTap: _handleDecline,
            ),
            _ActionButton(
              label: 'Accept',
              icon: Icons.call,
              bg: const Color(0xFF2ECC71),
              onTap: _handleAccept,
            ),
          ],
        );

      case CallUIMode.outgoing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionButton(
              label: 'Cancel',
              icon: Icons.call_end,
              bg: const Color(0xFFDA2C38),
              onTap: _handleCancel,
            ),
          ],
        );

      case CallUIMode.inProgress:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionButton(
              label: 'End',
              icon: Icons.call_end,
              bg: const Color(0xFFDA2C38),
              onTap: _handleHangup,
            ),
          ],
        );
    }
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Future<void> Function()? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.bg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onTap == null
            ? null
            : () {
          try { onTap!(); } catch (e, st) {
            debugPrint('[CallUI] onTap error: $e\n$st');
          }
        },
        icon: Icon(icon, size: 22, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}

class _SafeAvatar extends StatelessWidget {
  final String? url;
  const _SafeAvatar({this.url});

  bool get _valid => url != null && url!.startsWith('http');

  @override
  Widget build(BuildContext context) {
    if (!_valid) {
      return const Center(
        child: Icon(Icons.person, size: 56, color: Colors.black87),
      );
    }
    return Image.network(
      url!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.person, size: 56, color: Colors.black87),
      ),
    );
  }
}
