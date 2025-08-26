import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'features/home/brand.dart'; // kBrandYellow, kBrandYellowDark
import 'sms_input_page.dart';      // подстрой путь, если файл лежит в другом месте

class PhoneInputPage extends StatefulWidget {
  const PhoneInputPage({super.key});
  @override
  State<PhoneInputPage> createState() => _PhoneInputPageState();
}

class _PhoneInputPageState extends State<PhoneInputPage> {
  // === ассеты (подстрой пути под свои файлы) ===
  static const _assetWordmark = 'assets/brand/speedbook.png';
  static const _assetArchBg   = 'assets/brand/intro_arch.png';
  static const _assetTemple   = 'assets/brand/temple.png';
  static const _assetCar      = 'assets/brand/car.png';
  static const _assetIconBg   = 'assets/brand/icon_bg.png';
  static const _assetSbLogo   = 'assets/brand/sb_logo.png';

  static const double _kFieldHeight = 56;
  static const double _kRadius = 16;

  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Firebase flow state
  bool _submitting = false;
  String? _verificationId;
  int? _resendToken;

  Country _country =
  kCountries.firstWhere((c) => c.iso2 == 'KH', orElse: () => kCountries.first);

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _CountryPickerSheet(),
    );
    if (picked != null && mounted) setState(() => _country = picked);
  }

  // Отправка номера в Firebase
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter phone number')),
      );
      return;
    }
    final e164 = '${_country.dialCode}$digits';

    setState(() => _submitting = true);
    try {
      // опционально язык смс
      try { await FirebaseAuth.instance.setLanguageCode('en'); } catch (_) {}

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: e164,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Android может автоподтвердить — попробуем залогиниться
          try { await FirebaseAuth.instance.signInWithCredential(credential); } catch (_) {}
          if (!mounted) return;
          // TODO: навигация на главный экран, если автологин удался
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification failed: ${e.message ?? e.code}')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          if (!mounted) return;
          setState(() => _submitting = false);

          // Переходим на экран ввода кода
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SmsInputPage(
                verificationId: verificationId,
                phone: e164,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          if (!mounted) return;
          setState(() => _submitting = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start verification: $e')),
      );
    }
  }

  void _openUrl(String url) {
    // TODO: подключить url_launcher
    debugPrint('Open URL: $url');
  }

  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final double cardBase = size.width > 420 ? 420 : size.width;

    final insets = MediaQuery.of(context).viewInsets;
    final keyboard = insets.bottom > 0;

    // высота нижней панели с Terms/Privacy
    const bottomPanelHeight = 96.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFB),
      body: Stack(
        children: [
          // верхний бренд-бэнд
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 64,
              color: kBrandYellow,
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Image.asset(
                  _assetWordmark,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(
                    'SpeedBook',
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700, color: Colors.black87),
                  ),
                ),
              ),
            ),
          ),

          // фоновая дуга (опущена ниже бэнда)
          Positioned(
            top: 80,
            left: -size.width * 0.10,
            right: -size.width * 0.10,
            child: IgnorePointer(
              child: Image.asset(
                _assetArchBg,
                height: size.width * 0.95,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),

          // прокручиваемый контент
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24 + 64,
                    24,
                    (keyboard ? 16 : bottomPanelHeight + 16) + insets.bottom,  // <-- ключ
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // иконка SB (в белой карточке)
                      _AppIcon(logoAsset: _assetSbLogo, cardAsset: _assetIconBg),

                      const SizedBox(height: 12),
                      Text('Get started with',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w400, color: Colors.black87,
                        ),
                      ),
                      Text('SpeedBook',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700, color: Colors.black87,
                        ),
                      ),

                      const SizedBox(height: 18),

                      // карточка-иллюстрация
                      Container(
                        decoration: BoxDecoration(
                          //color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
/*                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            )
                          ],*/
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.asset(
                              _assetTemple,
                              width: cardBase * 0.62,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                            Positioned(
                              left: 18,
                              bottom: 10,
                              child: Image.asset(
                                _assetCar,
                                width: 88,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // форма
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // пилюля с флагом (смена страны)
                                _FlagPill(
                                  country: _country,
                                  onTap: _pickCountry,
                                  height: _kFieldHeight,
                                  radius: _kRadius,
                                ),
                                const SizedBox(width: 10),
                                // поле телефона с кодом в prefix
                                Expanded(
                                  child: _PhoneFieldWithCountry(
                                    controller: _phoneCtrl,
                                    country: _country,
                                    onPickCountry: _pickCountry,
                                    height: _kFieldHeight,
                                    radius: _kRadius,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // кнопка регистрации
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDCCFB5),
                                  foregroundColor: Colors.black87,
                                  shadowColor: Colors.transparent,
                                  textStyle: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w600),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(_kRadius),
                                  ),
                                ),
                                onPressed: _submitting ? null : _submit,
                                child: _submitting
                                    ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                                    : const Text('Register'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // нижняя панель Terms/Privacy
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(
              top: false,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: keyboard ? 0.0 : 1.0,                // <-- плавно скрываем
                child: IgnorePointer(                         // <-- на всякий случай отключаем клики
                  ignoring: keyboard,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'By logging in or registering you agree to our Terms of Service and Privacy Policy',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          children: [
                            _Link(text: 'Terms and Conditions', onTap: () => _openUrl('https://example.com/terms')),
                            _Link(text: 'Privacy Policy', onTap: () => _openUrl('https://example.com/privacy')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── helpers ───

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.logoAsset, required this.cardAsset});
  final String logoAsset;
  final String cardAsset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84, height: 84,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              cardAsset, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.white),
            ),
          ),
          Center(
            child: Image.asset(
              logoAsset, height: 36, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

// генерирует флаг по ISO, если вдруг в Country.flag пусто
String flagFromIso(String iso2) {
  final cc = iso2.toUpperCase();
  return String.fromCharCodes(cc.codeUnits.map((c) => 0x1F1E6 + (c - 65)));
}

// пилюля с флагом
class _FlagPill extends StatelessWidget {
  const _FlagPill({required this.country, required this.onTap, required this.height, required this.radius});
  final Country country; final VoidCallback onTap; final double height; final double radius;

  @override
  Widget build(BuildContext context) {
    final String flagText =
    (country.flag.isNotEmpty ? country.flag : flagFromIso(country.iso2));

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          constraints: const BoxConstraints(minWidth: 48),
          decoration: BoxDecoration(
            //color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0x11000000)),
          //  boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(flagText, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down, color: Colors.black45, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// поле телефона с кодом страны в prefix
class _PhoneFieldWithCountry extends StatelessWidget {
  const _PhoneFieldWithCountry({
    required this.controller,
    required this.country,
    required this.onPickCountry,
    required this.height,
    required this.radius,
  });

  final TextEditingController controller;
  final Country country;
  final VoidCallback onPickCountry;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Mobile number',
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.fromLTRB(0, 18, 16, 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: const BorderSide(color: kBrandYellowDark, width: 2),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 78, minHeight: 0),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: InkWell(
              onTap: onPickCountry,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(country.dialCode, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  Container(width: 1, height: 22, color: const Color(0x22000000)),
                ],
              ),
            ),
          ),
        ),
        validator: (v) {
          final digits = v?.replaceAll(RegExp(r'\D'), '') ?? '';
          //if (digits.length < 7) return 'Enter valid number';
          return null;
        },
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.text, required this.onTap});
  final String text; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, behavior: HitTestBehavior.opaque,
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Color(0xFF4B79C4), decoration: TextDecoration.underline),
      ),
    );
  }
}

// === Страны ===

class Country {
  final String name;
  final String iso2;
  final String dialCode;
  final String flag; // emoji
  const Country({required this.name, required this.iso2, required this.dialCode, required this.flag});
}

const List<Country> kCountries = [
  // SE Asia
  Country(name: 'Cambodia',    iso2: 'KH', dialCode: '+855', flag: '🇰🇭'),
  Country(name: 'Laos',        iso2: 'LA', dialCode: '+856', flag: '🇱🇦'),
  Country(name: 'Vietnam',     iso2: 'VN', dialCode: '+84',  flag: '🇻🇳'),
  Country(name: 'Thailand',    iso2: 'TH', dialCode: '+66',  flag: '🇹🇭'),
  Country(name: 'Malaysia',    iso2: 'MY', dialCode: '+60',  flag: '🇲🇾'),
  Country(name: 'Singapore',   iso2: 'SG', dialCode: '+65',  flag: '🇸🇬'),
  Country(name: 'Indonesia',   iso2: 'ID', dialCode: '+62',  flag: '🇮🇩'),
  Country(name: 'Philippines', iso2: 'PH', dialCode: '+63',  flag: '🇵🇭'),
  Country(name: 'Myanmar',     iso2: 'MM', dialCode: '+95',  flag: '🇲🇲'),
  // CIS
  Country(name: 'Russia',      iso2: 'RU', dialCode: '+7',   flag: '🇷🇺'),
  Country(name: 'Kazakhstan',  iso2: 'KZ', dialCode: '+7',   flag: '🇰🇿'),
  Country(name: 'Kyrgyzstan',  iso2: 'KG', dialCode: '+996', flag: '🇰🇬'),
  Country(name: 'Uzbekistan',  iso2: 'UZ', dialCode: '+998', flag: '🇺🇿'),
  Country(name: 'Tajikistan',  iso2: 'TJ', dialCode: '+992', flag: '🇹🇯'),
  Country(name: 'Armenia',     iso2: 'AM', dialCode: '+374', flag: '🇦🇲'),
  Country(name: 'Azerbaijan',  iso2: 'AZ', dialCode: '+994', flag: '🇦🇿'),
  Country(name: 'Georgia',     iso2: 'GE', dialCode: '+995', flag: '🇬🇪'),
  Country(name: 'Belarus',     iso2: 'BY', dialCode: '+375', flag: '🇧🇾'),
  Country(name: 'Moldova',     iso2: 'MD', dialCode: '+373', flag: '🇲🇩'),
  // Common
  Country(name: 'United States',  iso2: 'US', dialCode: '+1',  flag: '🇺🇸'),
  Country(name: 'United Kingdom', iso2: 'GB', dialCode: '+44', flag: '🇬🇧'),
  Country(name: 'Germany',        iso2: 'DE', dialCode: '+49', flag: '🇩🇪'),
  Country(name: 'France',         iso2: 'FR', dialCode: '+33', flag: '🇫🇷'),
  Country(name: 'Spain',          iso2: 'ES', dialCode: '+34', flag: '🇪🇸'),
];

// === Country picker (bottom sheet) ===

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet();

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchCtrl = TextEditingController();
  late List<Country> _filtered = List.of(kCountries);

  void _onSearch(String q) {
    final s = q.trim().toLowerCase();
    setState(() {
      _filtered = s.isEmpty
          ? List.of(kCountries)
          : kCountries.where((c) =>
      c.name.toLowerCase().contains(s) ||
          c.dialCode.contains(s) ||
          c.iso2.toLowerCase().contains(s)).toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: pad),
        child: Material(
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: 'Search country or code',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = _filtered[i];
                    return ListTile(
                      leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                      title: Text(c.name),
                      trailing: Text(c.dialCode, style: const TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
