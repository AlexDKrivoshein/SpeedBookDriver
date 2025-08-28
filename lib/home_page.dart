import 'dart:async';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'verification_page.dart';

/// Статус верификации водителя (пока захардкожен, можно связать с бэком позже)
enum DriverVerificationStatus {
  needVerification,
  awaitingVerification,
  verified,
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DriverDetails? _details;
  bool _loading = true;
  String? _error;
  int _currentPage = 0;

  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.62);
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Страховочный таймаут: даже если внутри зависнет — оборвёмся
      final d = await ApiService.getDriverDetails()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _details = d;
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Время ожидания ответа истекло';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Спиннер
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Главная')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Экран ошибки
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Главная')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Не удалось загрузить данные',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _load,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Данные получены
    final d = _details!;
    final accounts = d.accounts;
    final status = _statusFromClass(d.driverClass);

    return Scaffold(
      appBar: AppBar(title: const Text('Главная')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Информация о водителе (имя + класс)
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
                        Text(
                          d.name.isEmpty ? '—' : d.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              d.rating.isEmpty ? 'rating: —' : 'rating: ${d.rating}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Карусель аккаунтов
            Text(
              'Ваши аккаунты',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (accounts.isNotEmpty)
              SizedBox(
                height: 180,
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
                        'Аккаунты не найдены',
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

            // Статус верификации
            _InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Статус верификации',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _VerificationBadge(status: status),
                  if (status == DriverVerificationStatus.needVerification) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final res = await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const VerificationPage()),
                          );
                          // если нужно — после возврата обновим данные
                          if (res == true && mounted) {
                            _load(); // перезагрузить статус
                          }
                        },
                        icon: const Icon(Icons.verified_user),
                        label: const Text('Пройти верификацию'),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Здесь можно добавить твои остальные блоки/кнопки
          ],
        ),
      ),
    );
  }

  // ==== helpers ====

  static String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '🙂';
    final one = parts.first[0].toUpperCase();
    final two = parts.length > 1 ? parts[1][0].toUpperCase() : '';
    return '$one$two';
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: kElevationToShadow[1],
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
    final color = _statusColor(status);
    final label = switch (status) {
      DriverVerificationStatus.needVerification => 'Нужна верификация',
      DriverVerificationStatus.awaitingVerification => 'Проверка документов',
      DriverVerificationStatus.verified => 'Верифицирован',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static Color _statusColor(DriverVerificationStatus s) {
    switch (s) {
      case DriverVerificationStatus.needVerification:
        return Colors.red;
      case DriverVerificationStatus.awaitingVerification:
        return Colors.amber;
      case DriverVerificationStatus.verified:
        return Colors.green;
    }
  }
}

/// Квадратная карточка аккаунта для карусели
class _AccountSquareCard extends StatelessWidget {
  final DriverAccount account;
  final bool highlighted;
  const _AccountSquareCard({required this.account, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AspectRatio(
      aspectRatio: 1, // квадрат
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow:
          highlighted ? kElevationToShadow[3] : kElevationToShadow[1],
          border: Border.all(
            color: highlighted
                ? theme.colorScheme.primary.withOpacity(0.35)
                : theme.dividerColor.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок аккаунта
            Text(
              account.name.isEmpty ? 'Аккаунт' : account.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            // Баланс
            Text(
              _formatMoney(account.balance, account.currency),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            // Валюта + id
            Row(
              children: [
                Icon(Icons.account_balance_wallet,
                    size: 16, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${account.currency} · id: ${account.id}',
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
    return '$wholeStr.$frac $currencyCode';
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
    return buf.toString().split('').reversed.join();
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
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
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor.withOpacity(0.4),
          ),
        );
      }),
    );
  }
}
DriverVerificationStatus _statusFromClass(String? driverClass) {
  switch ((driverClass ?? '').toUpperCase()) {
    case 'NEW_DRIVER':
      return DriverVerificationStatus.needVerification;
    case 'VERIFIED':
      return DriverVerificationStatus.verified;
    default:
      return DriverVerificationStatus.awaitingVerification;
  }
}