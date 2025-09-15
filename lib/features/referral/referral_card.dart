// lib/features/referral/referral_card.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../brand.dart';
import '../../api_service.dart';

// короткий алиас для переводов
String t(BuildContext context, String key) =>
    ApiService.getTranslationForWidget(context, key);

/// ReferralCard — карточка «Пригласить друга»
/// генерирует умную ссылку Branch (deferred deep link),
/// показывает её, даёт «Поделиться», «Скопировать», «QR».
class ReferralCard extends StatefulWidget {
  /// Уникальный код/UID пригласившего (текущий водитель)
  final String inviterId;

  /// Кастомный заголовок/подзаголовок (если не указать — берутся из переводов)
  final String? title;
  final String? subtitle;

  /// Маркировка ссылки для аналитики
  final String campaign; // driver_invite / passenger_invite / ...
  final String channel;  // referral / promo / ...

  const ReferralCard({
    super.key,
    required this.inviterId,
    this.title,
    this.subtitle,
    this.campaign = 'driver_invite',
    this.channel = 'referral',
  });

  @override
  State<ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends State<ReferralCard> {
  Uri? _link;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final link = await _getCachedOrCreateLink(
        inviterId: widget.inviterId,
        campaign: widget.campaign,
        channel: widget.channel,
      );
      if (!mounted) return;
      setState(() => _link = link);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uri> _getCachedOrCreateLink({
    required String inviterId,
    required String campaign,
    required String channel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'branch_ref_link::$inviterId::$campaign::$channel';
    final cached = prefs.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      return Uri.parse(cached);
    }

    // Описание контента для Branch
    final buo = BranchUniversalObject(
      canonicalIdentifier: 'ref/$inviterId',
      title: 'SpeedBook Invite',
      contentDescription: 'Join SpeedBook with my invite code',
      contentMetadata: BranchContentMetaData()
        ..addCustomMetadata('inviter_id', inviterId)
        ..addCustomMetadata('ref', inviterId),
    );

    // Свойства ссылки
    final lp = BranchLinkProperties(
      channel: channel,
      feature: 'invite',
      campaign: campaign,
    )
    // Фолбэки (страница с объяснением, если магазины недоступны)
      ..addControlParam(r'$desktop_url', 'https://speed-booking.com/invite/$inviterId')
      ..addControlParam(r'$android_url', 'https://speed-booking.com/invite/$inviterId')
      ..addControlParam(r'$ios_url', 'https://speed-booking.com/invite/$inviterId');

    final res = await FlutterBranchSdk.getShortUrl(
      buo: buo,
      linkProperties: lp,
    );

    if (!res.success) {
      // Фолбэк: вернём наш веб-адрес, чтобы пользователь всё равно мог делиться
      debugPrint('[Referral] Branch error: ${res.errorMessage}');
      final fallback = Uri.parse('https://speed-booking.com/invite/$inviterId');
      await prefs.setString(cacheKey, fallback.toString());
      return fallback;
    }

    final url = Uri.parse(res.result);
    await prefs.setString(cacheKey, url.toString());
    return url;
  }

  Future<void> _copyLink() async {
    if (_link == null) return;
    await Clipboard.setData(ClipboardData(text: _link.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t(context, 'referral.copied'))),
    );
  }

  Future<void> _shareLink() async {
    if (_link == null) return;
    final text =
    t(context, 'referral.share_text').replaceAll('{link}', _link.toString());
    await Share.share(text);
  }

  void _showQr() {
    if (_link == null) return;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t(context, 'referral.qr_title'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 16,
                      offset: Offset(0, 6),
                      color: Color(0x22000000),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: _link.toString(),
                    version: QrVersions.auto,
                    size: 240,
                    gapless: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _link.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _link.toString()));
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t(context, 'referral.copied'))),
                  );
                },
                child: Text(t(context, 'referral.copy_link')),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.title ?? t(context, 'referral.title');
    final subtitle = widget.subtitle ?? t(context, 'referral.subtitle');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.yellow.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.yellow.withOpacity(0.45), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Brand.yellow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link, color: Colors.black),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.black.withOpacity(0.72),
            ),
          ),
          const SizedBox(height: 12),

          // Состояния
          if (_loading)
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(t(context, 'referral.generating')),
              ],
            )
          else if (_error != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${t(context, 'referral.error')}: $_error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _prepare,
                  child: Text(t(context, 'common.retry')),
                ),
              ],
            )
          else if (_link != null)
              _LinkRow(
                link: _link!,
                onShare: _shareLink,
                onCopy: _copyLink,
                onQr: _showQr,
              ),

          const SizedBox(height: 10),

          // Ваш код (для человека)
          Row(
            children: [
              Text(
                t(context, 'referral.your_code'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.black.withOpacity(0.6),
                ),
              ),
              const SizedBox(width: 6),
              SelectableText(
                widget.inviterId,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: widget.inviterId));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t(context, 'referral.code_copied'))),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(t(context, 'referral.copy_code')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final Uri link;
  final VoidCallback onShare;
  final VoidCallback onCopy;
  final VoidCallback onQr;

  const _LinkRow({
    required this.link,
    required this.onShare,
    required this.onCopy,
    required this.onQr,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      color: Colors.black87,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.link_rounded, size: 18, color: Colors.black54),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                link.toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.ios_share),
              label: Text(t(context, 'referral.share')),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_all),
              label: Text(t(context, 'referral.copy_link')),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onQr,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('QR'),
            ),
          ],
        ),
      ],
    );
  }
}
