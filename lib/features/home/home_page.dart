import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// + добавлено для меню/логаута/языка
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../translations.dart';

import '../../api_service.dart';
import '../../driver_api.dart';
import '../../brand.dart';
import '../../brand_header.dart';
import '../../route_observer.dart';
import '../../verification_page.dart';

// экран добавления авто
import 'add_car_page.dart';

import 'widgets/background.dart';
import 'widgets/info_card.dart';
import 'widgets/verification_badge.dart';
import 'widgets/referral_card.dart';      // панель привязки к рефералу (ввод кода)
import 'widgets/car_section.dart';
import 'widgets/accounts_carousel.dart';
import 'widgets/dots.dart';
import 'widgets/home_menu.dart';
import 'widgets/transactions_section.dart';
import '../driving/driving_map_page.dart';

// шарящий ReferralCard (Branch/QR) — отдельный виджет
import '../referral/referral_card.dart' as Share;

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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  DriverDetails? _details;
  bool _loading = true;
  String? _error;
  int _currentPage = 0;

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

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.62);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    _load(); // перезагружаем при возврате
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

  void _openDriving() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DrivingMapPage()),
    );
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
          SnackBar(content: Text('${t(context, 'home.referral.error')}: $code')),
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

  Future<void> _openVerification() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VerificationPage()),
    );
  }

  Future<void> _onAddCar() async {
    final res = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddCarPage()),
    );
    if (res == true) {
      await _load();
    }
  }

  void _onBookRental() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Not implemented yet')),
    );
  }

  // Открыть модалку с «шарящим» ReferralCard (Branch/QR)
  void _openShareReferral() {
    final d = _details;
    if (d == null) return;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Share.ReferralCard(
            inviterId: '${d.id}',
            campaign: 'driver_invite',
            channel: 'referral',
          ),
        );
      },
    );
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getString('user_lang') ?? 'en').toLowerCase();
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _LanguageSheet(current: current, t: (k) => t(ctx, k)),
    );
    if (choice != null && mounted) {
      await prefs.setString('user_lang', choice);
      // если Translations подключён — применим на лету
      try {
        await context.read<Translations>().setLang(choice);
      } catch (_) {}
      setState(() {});
    }
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('secret');
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  static String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '🙂';
    final one = parts.first[0].toUpperCase();
    final two = parts.length > 1 ? parts[1][0].toUpperCase() : '';
    return '$one$two';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Brand.theme(Theme.of(context));

    // loading
    if (_loading) {
      return Theme(
        data: theme,
        child: Scaffold(
          key: _scaffoldKey,
          appBar: BrandHeader(),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // error
    if (_error != null) {
      return Theme(
        data: theme,
        child: Scaffold(
          key: _scaffoldKey,
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

    // data
    final d = _details!;
    final accounts = d.accounts;
    final status = _statusFromClass(d.driverClass);

    return Theme(
      data: theme,
      child: Scaffold(
        key: _scaffoldKey,
        appBar: BrandHeader(),
        drawer: HomeMenu(
          details: d,
          onInvite: _openShareReferral,
          onOpenVerification: _openVerification,
          onOpenCar: _onAddCar,
          onOpenTransactions: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t(context, 'common.not_implemented'))),
            );
          },
          onOpenAccounts: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t(context, 'common.not_implemented'))),
            );
          },
          onOpenSettings: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t(context, 'common.not_implemented'))),
            );
          },
          onOpenSupport: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t(context, 'common.not_implemented'))),
            );
          },
          onPickLanguage: _pickLanguage,
          onLogout: _logout,
        ),
        body: Stack(
          children: [
            const HomeBackground(), // узор
            RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Driver info
                  InfoCard(
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
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      d.name.isEmpty ? '—' : d.name,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (status == DriverVerificationStatus.verified) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.verified, size: 18, color: Colors.green),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
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
                                    '${t(context, "home.referral.your_id")}: ${d.id}',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  IconButton(
                                    tooltip: t(context, 'common.copy'),
                                    icon: const Icon(Icons.copy, size: 18),
                                    onPressed: () async {
                                      await Clipboard.setData(ClipboardData(text: d.id.toString()));
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(t(context, 'common.copied'))),
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

                  // Referral — ПЕРЕД аккаунтами (панель привязки)
                  ReferralCard(
                    referalName: _referalName,
                    canAddReferal: _canAddReferal,
                    controller: _referalCtrl,
                    busy: _refBusy,
                    onAttach: _setReferal,
                  ),
                  const SizedBox(height: 8),

                  // Кнопка открытия «шарящего» ReferralCard (Branch/QR)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openShareReferral,
                      icon: const Icon(Icons.ios_share),
                      label: Text(t(context, 'home.referral.invite_btn')),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Car — ПЕРЕД аккаунтами
                  CarSection(
                    hasCar: d.carId != null,
                    // если в твоём CarSection нет этих параметров — удали строки ниже
                    carId: d.carId,
                    number: d.number,
                    brand: d.brand,
                    model: d.model,
                    carClass: d.carClass,            // NOCAR | AWAITING | REJECTED
                    carReason: d.carReason,          // причина (если REJECTED)
                    onAddCar: _onAddCar,
                    onBookRental: _onBookRental,
                    onStartDriving: _openDriving,    // переход на карту
                    t: (k) => t(context, k),
                  ),
                  const SizedBox(height: 12),

                  // Accounts
                  Text(
                    t(context, 'home.accounts.title'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  AccountsCarousel(
                    accounts: accounts,
                    pageController: _pageController,
                    currentIndex: _currentPage,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    emptyLabel: t(context, 'home.accounts.empty'),
                  ),
                  if (accounts.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Dots(count: accounts.length, index: _currentPage),
                  ],
                  const SizedBox(height: 12),

                  // Verification (водителя)
                  if (status != DriverVerificationStatus.verified) ...[
                    InfoCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(context, 'home.verification.title'),
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          VerificationBadge(status: status),
                          if (status == DriverVerificationStatus.rejected &&
                              (_details?.rejectionReason?.isNotEmpty ?? false)) ...[
                            const SizedBox(height: 8),
                            Text(
                              t(context, 'home.verification.rejected_reason'),
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(_details!.rejectionReason!, style: theme.textTheme.bodyMedium),
                          ],
                          if (status == DriverVerificationStatus.needVerification ||
                              status == DriverVerificationStatus.rejected) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _openVerification,
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
                  TransactionsSection(
                    loading: _txLoading,
                    error: _txError,
                    transactions: _transactions,
                    onRetry: _load,
                    emptyLabel: t(context, 'home.transactions.empty'),
                    title: t(context, 'home.transactions.title'),
                    retryLabel: t(context, 'common.retry'),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),

            // Кнопка открытия меню (как в «Приложение такси»)
            Positioned(
              top: 0,
              left: 12,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 0), // было top:12; стало почти у края
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.menu, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}

// ─── простой выбор языка ───────────────────────────────────────────────────────

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.current, required this.t});
  final String current;
  final String Function(String) t;

  @override
  Widget build(BuildContext context) {
    final items = const [
      {'code': 'en', 'label': 'English'},
      {'code': 'ru', 'label': 'Русский'},
      {'code': 'km', 'label': 'ខ្មែរ'},
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t('menu.language'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final it in items)
            ListTile(
              leading: Icon(
                it['code'] == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(it['label']!),
              onTap: () => Navigator.of(context).pop(it['code']),
            ),
        ],
      ),
    );
  }
}
