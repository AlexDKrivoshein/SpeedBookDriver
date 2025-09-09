// lib/home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'driver_api.dart';
import 'brand.dart';
import 'brand_header.dart';
import 'route_observer.dart';
import 'verification_page.dart';

String t(BuildContext context, String key) =>
    ApiService.getTranslationForWidget(context, key);

enum DriverVerificationStatus {
  needVerification,
  awaitingVerification,
  verified,
  rejected,
}

DriverVerificationStatus _statusFromClass(String? driverClass) {
  switch ((driverClass ?? '').toUpperCase()) {
    case 'NEW_DRIVER':
      return DriverVerificationStatus.needVerification;
    case 'VERIFIED':
      return DriverVerificationStatus.verified;
    case 'REJECTED':
      return DriverVerificationStatus.rejected;
    default:
      return DriverVerificationStatus.awaitingVerification;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}


class _HomePageState extends State<HomePage> with RouteAware {
  DriverDetails? _details;
  bool _loading = true;
  String? _error;
  int _currentPage = 0;

  static const _assetPattern = 'assets/brand/background_alpha.png';

  // --- Referral state ---
  String? _referalName; // к кому привязан
  bool _canAddReferal = false; // можно ли сейчас привязать
  final TextEditingController _referalCtrl = TextEditingController();
  bool _refBusy = false;

  // --- Transactions state ---
  List<DriverTransaction> _transactions = [];
  bool _txLoading = true;
  String? _txError;

  late final PageController _pageController;
  late final ImageProvider _bg;
  static const double _bgScale = 1.15;
  static const double _bgOpacityLight = 0.18;
  static const double _bgOpacityDark = 0.10;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.62);
    _bg = const AssetImage(_assetPattern);
    _load();
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(_bg, context);

    // подписываемся на события роутера
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _pageController.dispose();
    _referalCtrl.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _txLoading = true;
      _txError = null;
    });

    try {
      final d = await DriverApi.getDriverDetails()
          .timeout(const Duration(seconds: 15));

      // грузим транзакции (тихо, даже если упадёт)
      List<DriverTransaction> tx = [];
      String? txErr;
      try {
        tx = await DriverApi.getDriverTransactions(limit: 20);
      } catch (e) {
        txErr = e.toString();
      }

      if (!mounted) return;
      setState(() {
        _details = d;
        _referalName = d.referal;
        _canAddReferal = d.canAddReferal;

        _transactions = tx;
        _txError = txErr;
        _txLoading = false;

        _loading = false;

        //debugPrint('[HomePage] DriverDetails: $_details');
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = t(context, 'common.timeout');
        _loading = false;
        _txLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _txLoading = false;
      });
    }
  }

  Future<void> _setReferal() async {
    final id = _referalCtrl.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'home.referral.enter_id'))),
      );
      return;
    }

    setState(() => _refBusy = true);
    try {
      final res = await DriverApi.setReferal(id);
      if (res['status'] != 'OK') {
        final code = res['message']?.toString() ?? 'unknown_error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${t(context, 'home.referral.error')}: $code')),
        );
        return;
      }

      await _load();
      _referalCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'home.referral.success'))),
      );
    } catch (e) {
      debugPrint('[Referral] set_referal error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t(context, 'home.referral.error')}: $e')),
      );
    } finally {
      if (mounted) setState(() => _refBusy = false);
    }
  }

  Widget _buildBackground(BuildContext context) {
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    final opacity = isDark ? _bgOpacityDark : _bgOpacityLight;

    return Positioned.fill(
      child: Transform.scale(
        scale: _bgScale,
        alignment: Alignment.topLeft,
        child: Image(
          image: _bg,
          fit: BoxFit.none,
          repeat: ImageRepeat.repeat,
          alignment: Alignment.topLeft,
          filterQuality: FilterQuality.none,
          excludeFromSemantics: true,
          opacity: AlwaysStoppedAnimation(opacity),
        ),
      ),
    );
  }

  Widget _buildSoftGradient() =>
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.65),
                  Colors.white.withOpacity(0.0),
                  Colors.white.withOpacity(0.70),
                ],
                stops: const [0.0, 0.22, 1.0],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Brand.theme(Theme.of(context));

    // Loading
    if (_loading) {
      return Theme(
        data: theme,
        child: Scaffold(
          appBar: BrandHeader(),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Error
    if (_error != null) {
      return Theme(
        data: theme,
        child: Scaffold(
          appBar: BrandHeader(),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t(context, 'home.load_failed'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _load,
                    child: Text(t(context, 'common.retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Data
    final d = _details!;
    final accounts = d.accounts;
    final status = _statusFromClass(d.driverClass);

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: BrandHeader(),
        body: Stack(
          children: [
            // 1) Фон
            _buildBackground(context),
            // _buildSoftGradient(),

            // 2) Контент
            RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Driver info (name + rating + your referral id)
                  _InfoCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          child: Text(
                            _initials(d.name),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Имя + зелёный бейдж при верификации
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      d.name.isEmpty ? '—' : d.name,
                                      style:
                                      theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (status ==
                                      DriverVerificationStatus.verified) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.verified,
                                        size: 18, color: Colors.green),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Рейтинг слева + Referral ID справа
                              Row(
                                children: [
                                  const Icon(Icons.star, size: 16),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      d.rating.isEmpty ? '—' : d.rating,
                                      style: theme.textTheme.bodyMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(Icons.tag, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${t(context, "home.referral.your_id")}: ${d
                                        .id}',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  IconButton(
                                    tooltip: t(context, 'common.copy'),
                                    icon: const Icon(Icons.copy, size: 18),
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: d.id.toString()),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                t(context, 'common.copied')),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Referral (к кому привязан) — ПЕРЕД аккаунтами
                  _buildReferralCard(),
                  const SizedBox(height: 12),

                  // Accounts carousel
                  Text(
                    t(context, 'home.accounts.title'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),

                  if (accounts.isNotEmpty)
                    SizedBox(
                      height: 140, // компактнее
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: accounts.length,
                        onPageChanged: (i) => setState(() => _currentPage = i),
                        itemBuilder: (context, index) {
                          final acc = accounts[index];
                          final isActive = index == _currentPage;
                          return AnimatedPadding(
                            duration: const Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(
                              horizontal: isActive ? 6 : 10,
                              vertical: isActive ? 0 : 8,
                            ),
                            child: _AccountSquareCard(
                              account: acc,
                              highlighted: isActive,
                            ),
                          );
                        },
                      ),
                    )
                  else
                    _InfoCard(
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              t(context, 'home.accounts.empty'),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (accounts.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _Dots(count: accounts.length, index: _currentPage),
                  ],
                  const SizedBox(height: 12),

                  // Verification status
                  if (status != DriverVerificationStatus.verified) ...[
                    _InfoCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(context, 'home.verification.title'),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          _VerificationBadge(status: status),

                          // Причина отказа
                          if (status == DriverVerificationStatus.rejected &&
                              (_details?.rejectionReason?.isNotEmpty ??
                                  false)) ...[
                            const SizedBox(height: 8),
                            Text(
                              t(context, 'home.verification.rejected_reason'),
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _details!.rejectionReason!,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],

                          if (status ==
                              DriverVerificationStatus.needVerification ||
                              status == DriverVerificationStatus.rejected) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () async {
                                  final res = await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                        const VerificationPage()),
                                  );
                                },
                                icon: const Icon(Icons.verified_user),
                                label: Text(t(context, 'verification.open')),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Transactions
                  Text(
                    t(context, 'home.transactions.title'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),

                  if (_txLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    if (_txError != null)
                      _InfoCard(
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_txError!)),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _load,
                              child: Text(t(context, 'common.retry')),
                            ),
                          ],
                        ),
                      )
                    else
                      if (_transactions.isEmpty)
                        _InfoCard(
                          child: Row(
                            children: [
                              const Icon(Icons.receipt_long_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                  child:
                                  Text(t(context, 'home.transactions.empty'))),
                            ],
                          ),
                        )
                      else
                        _InfoCard(
                          child: Column(
                            children: [
                              for (int i = 0;
                              i <
                                  (_transactions.length > 10
                                      ? 10
                                      : _transactions.length);
                              i++) ...[
                                _TxItem(tx: _transactions[i]),
                                if (i !=
                                    (_transactions.length > 10
                                        ? 10
                                        : _transactions.length) -
                                        1)
                                  const Divider(height: 16),
                              ],
                            ],
                          ),
                        ),

                  const SizedBox(height: 12),
                  // … другие секции
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- helpers ----

  static String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '🙂';
    final one = parts.first[0].toUpperCase();
    final two = parts.length > 1 ? parts[1][0].toUpperCase() : '';
    return '$one$two';
  }

  Widget _buildReferralCard() {
    // уже подключён — просто показываем
    if ((_referalName ?? '').isNotEmpty) {
      return _InfoCard(
        child: Row(
          children: [
            const Icon(Icons.handshake, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${t(context,
                    "home.referral.current_prefix")}: ${_referalName!}',
                style: Theme
                    .of(context)
                    .textTheme
                    .titleMedium,
              ),
            ),
          ],
        ),
      );
    }

    // можно добавить — поле ввода + кнопка
    if (_canAddReferal) {
      return _InfoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(context, 'home.referral.title'),
                style: Theme
                    .of(context)
                    .textTheme
                    .titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _referalCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t(context, 'home.referral.id_label'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.tag),
              ),
              maxLength: 12,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _refBusy ? null : _setReferal,
                icon: _refBusy
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.link),
                label: Text(t(context, 'home.referral.attach')),
              ),
            ),
          ],
        ),
      );
    }

    // ничего не требуется — ничего не рисуем
    return const SizedBox.shrink();
  }
}

class _InfoCard extends StatelessWidget {
  final Widget child;

  const _InfoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14000000)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          )
        ],
      ),
      child: child,
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  final DriverVerificationStatus status;

  const _VerificationBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;

    switch (status) {
      case DriverVerificationStatus.needVerification:
        label = ApiService.getTranslationForWidget(
            context, 'home.verification.need');
        color = Colors.red;
        break;
      case DriverVerificationStatus.awaitingVerification:
        label = ApiService.getTranslationForWidget(
            context, 'home.verification.pending');
        color = Colors.amber;
        break;
      case DriverVerificationStatus.verified:
        label = ApiService.getTranslationForWidget(
            context, 'home.verification.verified');
        color = Colors.green;
        break;
      case DriverVerificationStatus.rejected:
        label = ApiService.getTranslationForWidget(
            context, 'home.verification.rejected');
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _AccountSquareCard extends StatelessWidget {
  final DriverAccount account;
  final bool highlighted;

  const _AccountSquareCard({required this.account, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow:
          highlighted ? kElevationToShadow[3] : kElevationToShadow[1],
          border: Border.all(
            color: highlighted
                ? theme.colorScheme.primary.withOpacity(0.6)
                : const Color(0x14000000),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.name.isEmpty
                  ? ApiService.getTranslationForWidget(
                  context, 'home.account.default_name')
                  : account.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              _formatMoney(account.balance, account.currency),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.account_balance_wallet,
                    size: 16, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${account.currency}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatMoney(double v, String currencyCode) {
    final whole = v.truncate();
    final frac = ((v - whole) * 100).round().toString().padLeft(2, '0');
    final wholeStr = _thousandsSep(whole);
    // return '$wholeStr.$frac $currencyCode';
    return '$wholeStr $currencyCode';
  }

  static String _thousandsSep(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    var count = 0;
    for (var i = s.length - 1; i >= 0; i--) {
      buf.write(s[i]);
      count++;
      if (count == 3 && i != 0) {
        buf.write(' ');
        count = 0;
      }
    }
    return buf
        .toString()
        .split('')
        .reversed
        .join();
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;

  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final primary = Theme
        .of(context)
        .colorScheme
        .primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 10 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: active ? primary : const Color(0x33000000),
          ),
        );
      }),
    );
  }
}

// ===== Transactions row =====
class _TxItem extends StatelessWidget {
  final DriverTransaction tx;

  const _TxItem({required this.tx});

  String _two(int n) => n.toString().padLeft(2, '0');

  String _fmtDate(DateTime d) =>
      '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(
          d.minute)}';

  String _formatMoney(double v, String currency) {
    final sign = v >= 0 ? '' : '-';
    final n = v.abs();
    final whole = n.truncate();
    final frac = ((n - whole) * 100).round().toString().padLeft(2, '0');
    final s = _thousands(whole);
    // так же как в аккаунтах — без копеек:
    return '$sign$s $currency';
    // с копейками: return '$sign$s.$frac $currency';
  }

  String _thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    var cnt = 0;
    for (var i = s.length - 1; i >= 0; i--) {
      b.write(s[i]);
      cnt++;
      if (cnt == 3 && i != 0) {
        b.write(' ');
        cnt = 0;
      }
    }
    return b
        .toString()
        .split('')
        .reversed
        .join();
  }

  IconData _icon(String t) {
    final x = t.toLowerCase();
    if (x.contains('ride') || x.contains('trip')) return Icons.local_taxi;
    if (x.contains('payout') || x.contains('withdraw'))
      return Icons.payments_outlined;
    if (x.contains('topup') || x.contains('deposit'))
      return Icons.add_card_outlined;
    if (x.contains('commission')) return Icons.receipt_long_outlined;
    return Icons.swap_vert;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlus = tx.total >= 0;
    final sumColor = isPlus ? Colors.green : Colors.red;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child:
          Icon(_icon(tx.type), size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок
              Text(
                (tx.service.isNotEmpty ? tx.service : tx.type),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              // Описание (если есть)
              if (tx.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  tx.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 2),
              Text(
                _fmtDate(tx.date),
                style:
                theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Суммы
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatMoney(tx.total, tx.currency),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: sumColor),
            ),
            if (tx.commission != 0)
              Text(
                '- ${_formatMoney(tx.commission, tx.currency)}',
                style:
                theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
          ],
        ),
      ],
    );
  }
}
