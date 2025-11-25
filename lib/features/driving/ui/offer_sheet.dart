import 'dart:async';
import 'package:flutter/material.dart';
import '../../../brand.dart'; // поправь путь, если другой

typedef AsyncAction = Future<void> Function();

class OfferSheet {
  static Future<void> show(
      BuildContext context, {
        // тексты
        required String fromName,
        required String fromDetails,
        required String toName,
        required String toDetails,
        required String distanceLabel,
        required String durationLabel,
        required String priceLabel, // "KHR 194862"
        // колбэки
        required AsyncAction onAccept,
        required AsyncAction onDecline,
        // локализация
        required String Function(String key) t,
        // новое: длительность оффера в секундах
        int? offerValidSeconds,
      }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: bottomInset + 20,
          ),
          child: _OfferSheetBody(
            fromName: fromName,
            fromDetails: fromDetails,
            toName: toName,
            toDetails: toDetails,
            distanceLabel: distanceLabel,
            durationLabel: durationLabel,
            priceLabel: priceLabel,
            onAccept: onAccept,
            onDecline: onDecline,
            t: t,
            offerValidSeconds: offerValidSeconds,
          ),
        );
      },
    );
  }
}

class _OfferSheetBody extends StatefulWidget {
  final String fromName;
  final String fromDetails;
  final String toName;
  final String toDetails;
  final String distanceLabel;
  final String durationLabel;
  final String priceLabel;

  final AsyncAction onAccept;
  final AsyncAction onDecline;
  final String Function(String key) t;

  /// Сколько секунд оффер валиден (null/<=0 → без таймера)
  final int? offerValidSeconds;

  const _OfferSheetBody({
    super.key,
    required this.fromName,
    required this.fromDetails,
    required this.toName,
    required this.toDetails,
    required this.distanceLabel,
    required this.durationLabel,
    required this.priceLabel,
    required this.onAccept,
    required this.onDecline,
    required this.t,
    this.offerValidSeconds,
  });

  @override
  State<_OfferSheetBody> createState() => _OfferSheetBodyState();
}

class _OfferSheetBodyState extends State<_OfferSheetBody> {
  int? _secondsLeft;
  bool _actionCalled = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final v = widget.offerValidSeconds;
    if (v != null && v > 0) {
      _secondsLeft = v;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft == null) {
        t.cancel();
        return;
      }
      if (_secondsLeft! <= 0) {
        t.cancel();
        return;
      }

      setState(() {
        _secondsLeft = _secondsLeft! - 1;
      });

      if (_secondsLeft == 0) {
        t.cancel();
        _handleExpire();
      }
    });
  }

  Future<void> _handleExpire() async {
    if (_actionCalled) return;
    _actionCalled = true;

    // Автоматический отказ по истечении времени
    await widget.onDecline();
  }

  Future<void> _handleAcceptPressed() async {
    if (_actionCalled) return;
    if (!(_secondsLeft == null || _secondsLeft! > 0)) return; // уже истёк

    _actionCalled = true;
    await widget.onAccept();
  }

  Future<void> _handleDeclinePressed() async {
    if (_actionCalled) return;
    _actionCalled = true;
    await widget.onDecline();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _acceptEnabled =>
      !_actionCalled && (_secondsLeft == null || _secondsLeft! > 0);

  String _acceptLabel(BuildContext context) {
    final base = widget.t('common.ok'); // "Accept"
    if (_secondsLeft == null) return base;
    if (_secondsLeft! <= 0) return base;
    // Показываем таймер прямо на кнопке: "Accept (12s)"
    return '$base (${_secondsLeft!}s)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // маленький "хэндл" сверху
        Container(
          width: 44,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Brand.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // основная карточка оффера
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: const Border.fromBorderSide(
              BorderSide(color: Brand.border),
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: 16,
                spreadRadius: 1,
                offset: const Offset(0, 8),
                color: Colors.black.withOpacity(0.05),
              ),
            ],
          ),
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeaderRow(context),
                const SizedBox(height: 18),
                _buildRouteTimeline(context),
                const SizedBox(height: 18),
                _buildStatsRow(context),
                const SizedBox(height: 24),
                _buildActionsRow(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===== HEADER =====

  Widget _buildHeaderRow(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Чип "New order" НА БЕЛОМ ФОНЕ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: const Border.fromBorderSide(
              BorderSide(color: Brand.border),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🚕',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 6),
              Text(
                widget.t('driving.new_order'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Brand.textDark,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // крупная цена
        Text(
          widget.priceLabel,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: Brand.textDark,
          ),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  // ===== ROUTE TIMELINE =====

  Widget _buildRouteTimeline(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // левая колонка: точки и линия
        Column(
          children: [
            Icon(
              Icons.radio_button_checked,
              size: 16,
              color: Brand.textDark,
            ),
            Container(
              width: 2,
              height: 32,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: Brand.border,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            Icon(
              Icons.location_on,
              size: 16,
              color: Colors.redAccent.shade400,
            ),
          ],
        ),
        const SizedBox(width: 12),
        // правая колонка: адреса
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.fromName,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Brand.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.fromDetails.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: Text(
                    widget.fromDetails,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Brand.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Divider(
                height: 12,
                thickness: 0.6,
                color: Brand.border,
              ),
              Text(
                widget.toName,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Brand.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.toDetails.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.toDetails,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Brand.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ===== STATS (distance / time / price) =====

  Widget _buildStatsRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: const Border.fromBorderSide(
          BorderSide(color: Colors.black12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildPill(
              context: context,
              icon: Icons.route,
              label: widget.distanceLabel,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildPill(
              context: context,
              icon: Icons.timer_outlined,
              label: widget.durationLabel,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildPill(
              context: context,
              icon: Icons.account_balance_wallet_outlined,
              label: widget.priceLabel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const ShapeDecoration(
        color: Colors.white,
        shape: StadiumBorder(
          side: BorderSide(color: Colors.black12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Brand.textDark,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Brand.textDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ===== ACTIONS (Decline / Accept) =====

  Widget _buildActionsRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _handleDeclinePressed,
            icon: const Icon(Icons.close),
            label: Text(widget.t('common.decline')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.yellowDark,
              foregroundColor: Brand.textDark, // текст снова чёрный
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 1,
              shadowColor: Colors.black.withOpacity(0.06),
            ),
            onPressed: _acceptEnabled ? _handleAcceptPressed : null,
            icon: const Icon(Icons.check),
            label: Text(_acceptLabel(context)),
          ),
        ),
      ],
    );
  }
}
