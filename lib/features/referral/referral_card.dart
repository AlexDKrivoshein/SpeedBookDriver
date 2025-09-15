import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../brand.dart'; // Brand.yellow, Brand.black и т.п.
import '../../api_service.dart'; // для t(context, key), если используешь
// Если у тебя helper t() уже определён отдельно — используй его.
// Ниже для совместимости:
String t(BuildContext context, String key) =>
    ApiService.getTranslationForWidget(context, key);

/// Карточка рефералов:
/// - Генерит “умную” короткую ссылку через Branch (deferred deep link)
/// - Кэширует ссылку для текущего inviterId
/// - Кнопки: Поделиться, Скопировать, Показать QR
/// - Лёгкая тема оформления под SpeedBook
class ReferralCard extends StatefulWidget {
  /// Уникальный идентификатор пригласившего (uid водителя / код)
  final String inviterId;

  /// Необязательный статичный title и subtitle (иначе возьмём из t())
  final String? title;
  final String? subtitle;

  /// Опционально: кастомизация кампании / канала
  final String campaign; // например: driver_invite / passenger_invite
  final String channel;  // например: referral

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
  Uri? _refLink;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrCreateLink();
  }

  Future<void> _loadOrCreateLink() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final link = await _getCachedOrCreateBranchLink(
        inviterId: widget.inviterId,
        campaign: widget.campaign,
        channel: widget.channel,
      );
      if (mounted) setState(() => _refLink = link);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uri> _getCachedOrCreateBranchLink({
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

    // 1) Описываем контент для Branch (передаём inviter_id/ref)
    final buo = BranchUniversalObject(
      canonicalIdentifier: 'ref/$inviterId',
      title: 'SpeedBook Invite',
      contentDescription: 'Join SpeedBook with my invite code',
      contentMetadata: BranchContentMetaData()
        ..addCustomMetadata('inviter_id', inviterId)
        ..addCustomMetadata('ref', inviterId),
    );

    // 2) Свойства ссылки (канал/фича/кампания + фолыбэки)
    final lp = BranchLinkProperties(
      channel: channel,
      feature: 'invite',
      campaign: campaign,
    )
    // Фолыбэк-URLы (если нет приложения/магазин недоступен):
      ..addControlParam('\$desktop_url', 'https://speed-booking.com/invite/$inviterId')
      ..addControlParam('\$android_url', 'https://speed-booking.com/invite/$inviterId')
      ..addControlParam('\$ios_url',     'https://speed-booking.com/invite/$inviterId');

    final result = await FlutterBranchSdk.getShortUrl(
      buo: buo,
      linkProperties: lp,
    );

    if (!result.success) {
      // Фоллбэк: отдадим наш веб-URL, но сообщим об ошибке — чтобы ты увидел в логах
      debugPrint('[Referral] Branch error: ${result.errorMessage}');
      final fallback = Uri.parse('https://speed-booking.com/invite/$inviterId');
      await prefs.setString(cacheKey, fallback.toString());
      return fallback;
    }

    final url = Uri.parse(result.result);
    await prefs.setString(cacheKey, url.toString());
    return url;
  }

  Future<void> _copyLink() async {
    if (_refLink == null) return;
    await Clipboard.setData(ClipboardData(text: _refLink.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t(context, 'referral.copied'))),
    );
  }

  Future<void> _share() async {
    if (_refLink == null) return;
    final text = t(context, 'referral.share_text')
        .replaceAll('{link}', _refLink.toString());
    await Share.share(text);
  }

  void _showQr() {
    if (_refLink == null) return;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
              Center(
                child: DecoratedBox(
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
                    padding: const EdgeInsets.all(16.0),
                    child: QrImageView(
                      data: _refLink.toString(),
                      version: QrVersions.auto,
                      size: 240,
                      gapless: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _refLink.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _refLink.toString()));
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
    final title = widget.title ?? t(context, 'referral.title'); // «Пригласить друга» и т.п.
    final subtitle = widget.subtitle ??
        t(context, 'referral.subtitle'); // «Дай ссылку — получите бонусы»

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.yellow.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.yellow.withOpacity(0.5), width: 1),
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.black.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),

          // Состояния: загрузка / ошибка / ссылка
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
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t(context, 'referral.error') + ': ${_error!}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _loadOrCreateLink,
                  child: Text(t(context, 'common.retry')),
                ),
              ],
            )
          else if (_refLink != null)
              _LinkRow(
                link: _refLink!,
                onCopy: _copyLink,
                onShare: _share,
                onQr: _showQr,
              ),

          const SizedBox(height: 8),
          // Код пригласившего (для человека)
          Row(
            children: [
              Text(
                t(context, 'referral.your_code'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black.withOpacity(0.6),
                ),
              ),
              const SizedBox(width: 6),
              SelectableText(
                widget.inviterId,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.inviterId));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t(context, 'referral.code_copied'))),
                  );
                },
                child: Text(t(context, 'referral.copy_code')),
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
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onQr;

  const _LinkRow({
    required this.link,
    required this.onCopy,
    required this.onShare,
    required this.onQr,
  });

  @override
  Widget build(BuildContext context) {
    final linkTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      color: Colors.black87,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Сама ссылка (одна строка с обрезкой)
        Row(
          children: [
            const Icon(Icons.link_rounded, size: 18, color: Colors.black54),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                link.toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: linkTextStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Кнопки действий
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
