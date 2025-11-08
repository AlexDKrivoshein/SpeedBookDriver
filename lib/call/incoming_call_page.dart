// lib/call/incoming_call_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'call_payload.dart';

/// Экран входящего звонка (full-screen).
/// Используется из MessagingService и IncomingCallService.
class IncomingCallPage extends StatefulWidget {
  final CallPayload payload;
  final Future<void> Function(CallPayload)? onAccept;
  final Future<void> Function(CallPayload)? onDecline;

  const IncomingCallPage({
    super.key,
    required this.payload,
    this.onAccept,
    this.onDecline,
  });

  static Route route({
    required CallPayload payload,
    Future<void> Function(CallPayload)? onAccept,
    Future<void> Function(CallPayload)? onDecline,
  }) {
    return MaterialPageRoute(
      settings: const RouteSettings(name: 'IncomingCallPage'),
      fullscreenDialog: true,
      builder: (_) => IncomingCallPage(
        payload: payload,
        onAccept: onAccept,
        onDecline: onDecline,
      ),
    );
  }

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  static const _brandYellow = Color(0xFFFFC107);
  static const _brandYellowDark = Color(0xFFFFA000);

  late final DateTime _startedAt;
  Timer? _ticker;
  String _elapsed = '00:00';
  Timer? _autoTimeout;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();

    // таймер секундомера
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final sec = DateTime.now().difference(_startedAt).inSeconds;
      final m = (sec ~/ 60).toString().padLeft(2, '0');
      final s = (sec % 60).toString().padLeft(2, '0');
      if (mounted) setState(() => _elapsed = '$m:$s');
    });

    // авто-завершение по ringMs (если пришёл в payload)
    final ringMs = widget.payload.ringMs;
    if (ringMs > 0) {
      _autoTimeout = Timer(Duration(milliseconds: ringMs), _timeoutDecline);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _autoTimeout?.cancel();
    super.dispose();
  }

  Future<void> _timeoutDecline() async {
    if (!mounted) return;
    await _handleDecline();
  }

  Future<void> _handleAccept() async {
    if (_busy) return;
    _busy = true;
    try {
      if (widget.onAccept != null) {
        await widget.onAccept!(widget.payload);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _handleDecline() async {
    if (_busy) return;
    _busy = true;
    try {
      if (widget.onDecline != null) {
        await widget.onDecline!(widget.payload);
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    final name = (p.initiatorName ?? '').trim();
    final avatar = (p.initiatorAvatar ?? '').trim();

    return WillPopScope(
      onWillPop: () async => false, // блокируем "назад"
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // фон
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Color(0xFF111111)],
                  ),
                ),
              ),

              // Верхняя плашка
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                          const Text(
                            'Incoming call',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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

              // Центр
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // аватар
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
                        name.isNotEmpty ? name : 'Incoming caller',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 36),

                      // кнопки
                      Row(
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
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Tap to answer or decline',
                        style: TextStyle(color: Colors.white30, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Универсальная кнопка
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
            : () async {
          final f = onTap!;
          await f();
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

/// Безопасная загрузка аватарки
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
