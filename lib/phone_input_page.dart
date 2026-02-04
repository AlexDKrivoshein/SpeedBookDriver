// lib/phone_input_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'brand.dart';                 // Brand.yellow / Brand.yellowDark
import 'sms_input_page.dart';
import 'translations.dart';          // t(context, key)

class PhoneInputPage extends StatefulWidget {
  const PhoneInputPage({super.key});
  @override
  State<PhoneInputPage> createState() => _PhoneInputPageState();
}

class _PhoneInputPageState extends State<PhoneInputPage> {
  // ассеты под макет
  static const _assetLogoBanner = 'assets/brand/speedbooknew.png';
  static const _assetPattern    = 'assets/brand/background.png';
  static const MethodChannel _configChannel =
  MethodChannel('com.speedbook.taxidriver/config');

  final _phoneCtrl  = TextEditingController();
  final _phoneFocus = FocusNode();                 // <-- фокус для поля номера
  final _formKey = GlobalKey<FormState>();

  bool _submitting = false;
  String? _verificationId;
  int? _resendToken;

  Country _country = kCountries.firstWhere(
        (c) => c.iso2 == 'KH',
    orElse: () => kCountries.first,
  );

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _phoneFocus.dispose();                         // <-- освобождаем фокус
    super.dispose();
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _CountryPickerSheet(),
    );
    if (picked != null && mounted) {
      setState(() => _country = picked);
      // Переводим фокус на поле телефона сразу после закрытия шита
      Future.microtask(() {
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_phoneFocus);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'phone.enter_number'))),
      );
      return;
    }
    final e164 = '${_country.dialCode}$digits';

    setState(() => _submitting = true);
    try {
      if (_country.iso2.toUpperCase() == 'KH') {
        final key = await _requestOtpCustom(e164);
        if (!mounted) return;
        if (key == null || key.isEmpty) {
          setState(() => _submitting = false);
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SmsInputPage(
              verificationId: key,
              phone: e164,
              useCustomOtp: true,
            ),
          ),
        );
        setState(() => _submitting = false);
        return;
      }

      final lang = context.read<Translations>().lang;
      try {
        await FirebaseAuth.instance.setLanguageCode(lang);
        // await FirebaseAuth.instance.setSettings(
        //   appVerificationDisabledForTesting: false,
        //   forceRecaptchaFlow: kDebugMode,
        // );
      } catch (_) {}

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: e164,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try { await FirebaseAuth.instance.signInWithCredential(credential); } catch (_) {}
          if (!mounted) return;
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${t(context, "phone.verification_failed")}: ${e.message ?? e.code}')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          if (!mounted) return;
          setState(() => _submitting = false);
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
        SnackBar(content: Text('${t(context, "phone.failed_start")}: $e')),
      );
    }
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String device = 'unknown';
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        device = info.model ?? 'unknown';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        device = info.utsname.machine ?? 'unknown';
      }
    } catch (_) {}
    return {'device': device};
  }

  String _extractMessage(Map<String, dynamic> json,
      {String fallback = 'Error'}) {
    final msg = (json['message']?.toString() ?? '').trim();
    if (msg.isNotEmpty) return msg;
    return fallback;
  }

  Future<String?> _requestOtpCustom(String phoneNumber) async {
    String? apiUrl;
    try {
      apiUrl = await _configChannel.invokeMethod<String>('getApiUrl');
    } catch (_) {}
    if (apiUrl == null || apiUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'common.api_url_missing'))),
        );
      }
      return null;
    }

    final info = await PackageInfo.fromPlatform();
    final platform =
    Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');
    final deviceInfo = await _getDeviceInfo();
    final locale =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;

    try {
      final resp = await http
          .post(
        Uri.parse('$apiUrl/api/request_otp'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phoneNumber': phoneNumber,
          'platform': platform,
          'device': deviceInfo['device'],
          'app_version': info.version,
          'locale': locale,
          'is_driver': true,
        }),
      )
          .timeout(const Duration(seconds: 15));

      final parsed = jsonDecode(resp.body);
      if (parsed is! Map<String, dynamic>) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, 'common.unknown_error'))),
          );
        }
        return null;
      }

      final status = (parsed['status'] ?? '').toString().toUpperCase();
      if (status != 'OK') {
        final msg = _extractMessage(parsed, fallback: t(context, 'common.error'));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
        return null;
      }

      final data = parsed['data'];
      final key = data is Map<String, dynamic> ? data['key']?.toString() : null;
      if (key == null || key.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, 'common.unknown_error'))),
          );
        }
        return null;
      }
      return key;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, 'common.error')}: $e')),
        );
      }
      return null;
    }
  }

  void _openUrl(String url) {
    // TODO: url_launcher
    debugPrint('Open URL: $url');
  }

  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final insets = MediaQuery.of(context).viewInsets;
    final keyboard = insets.bottom > 0;

    // ===== Адаптивные величины =====
    final headerHeight = (h * 0.44).clamp(280.0, 420.0);     // высота шапки
    final overlap      = (headerHeight * 0.26).clamp(72.0, 128.0); // насколько карточка «заходит» на шапку
    final cardTop      = (headerHeight - overlap).clamp(120.0, headerHeight);

    final cardRadius   = (w * 0.06).clamp(18.0, 26.0);
    final fieldHeight  = (h * 0.06).clamp(52.0, 60.0);
    final buttonHeight = (h * 0.065).clamp(52.0, 60.0);

    final bannerTop     = (headerHeight * 0.11).clamp(36.0, 64.0);
    final bannerHeight  = (w * 0.26).clamp(96.0, 120.0);

    final sloganSize    = (w * 0.058).clamp(22.0, 26.0); // 22–26 sp

    const bottomPanelHeight = 120.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFB),
      body: Stack(
        children: [
          // Верхний блок с паттерном (без жёлтой заливки)
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(36),
                bottomRight: Radius.circular(36),
              ),
              child: SizedBox(
                height: headerHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      _assetPattern,
                      repeat: ImageRepeat.repeat,
                      fit: BoxFit.none,          // плитка не масштабируется
                      alignment: Alignment.topLeft,
                      filterQuality: FilterQuality.low,
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: EdgeInsets.only(top: bannerTop),
                          child: Image.asset(
                            _assetLogoBanner,
                            height: bannerHeight,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Контент (белая карточка со скруглением и тенью)
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  cardTop,
                  16,
                  (keyboard ? 16 : bottomPanelHeight) + insets.bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(cardRadius),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Слоган
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: sloganSize,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                  color: Colors.black87,
                                ),
                                children: [
                                  TextSpan(text: t(context, 'phone.hero.prefix') + '\n'),
                                  TextSpan(
                                    text: t(context, 'phone.hero.brand'),
                                    style: TextStyle(
                                      fontSize: sloganSize,
                                      fontWeight: FontWeight.w900,
                                      color: Brand.yellow,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Форма
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _FlagPill(
                                      country: _country,
                                      onTap: _pickCountry,
                                      height: fieldHeight,
                                      radius: 16,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _PhoneFieldWithCountry(
                                        controller: _phoneCtrl,
                                        country: _country,
                                        onPickCountry: _pickCountry,
                                        height: fieldHeight,
                                        radius: 16,
                                        focusNode: _phoneFocus, // <-- фокус прокинут сюда
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),

                                // Кнопка
                                SizedBox(
                                  width: double.infinity,
                                  height: buttonHeight,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Brand.yellow,
                                      foregroundColor: Colors.black87,
                                      shadowColor: Colors.transparent,
                                      textStyle: const TextStyle(
                                          fontSize: 18, fontWeight: FontWeight.w700),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed: _submitting ? null : _submit,
                                    child: _submitting
                                        ? const SizedBox(
                                      width: 22, height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                        : Text(t(context, 'phone.register')),
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
            ),
          ),

          // Нижняя панель
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(
              top: false,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: keyboard ? 0.0 : 1.0,
                child: IgnorePointer(
                  ignoring: keyboard,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t(context, 'phone.terms.caption'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          children: [
                            _Link(
                              text: t(context, 'phone.terms.link'),
                              onTap: () => _openUrl('https://www,speedbook.com/driverterms.html'),
                            ),
                            _Link(
                              text: t(context, 'phone.privacy.link'),
                              onTap: () => _openUrl('https://www,speedbook.com/driverprivacy.html'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t(context, 'phone.established'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
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

class _FlagPill extends StatelessWidget {
  const _FlagPill({
    required this.country,
    required this.onTap,
    required this.height,
    required this.radius,
  });
  final Country country;
  final VoidCallback onTap;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String flagText =
    country.flag.isNotEmpty ? country.flag : flagFromIso(country.iso2);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      elevation: 0, // без тени
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          constraints: const BoxConstraints(minWidth: 56),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0x11000000)),
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

// флаг по ISO
String flagFromIso(String iso2) {
  final cc = iso2.toUpperCase();
  return String.fromCharCodes(cc.codeUnits.map((c) => 0x1F1E6 + (c - 65)));
}

class _PhoneFieldWithCountry extends StatelessWidget {
  const _PhoneFieldWithCountry({
    required this.controller,
    required this.country,
    required this.onPickCountry,
    required this.height,
    required this.radius,
    this.focusNode,                              // <-- добавлено
  });

  final TextEditingController controller;
  final Country country;
  final VoidCallback onPickCountry;
  final double height;
  final double radius;
  final FocusNode? focusNode;                    // <-- добавлено

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,                    // <-- используем
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: t(context, 'phone.hint'),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.fromLTRB(0, 18, 16, 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: const BorderSide(color: Brand.yellow, width: 2),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 86, minHeight: 0),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: InkWell(
              onTap: onPickCountry,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // только код страны, как на макете
                  Text(country.dialCode,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Container(width: 1, height: 22, color: const Color(0x22000000)),
                ],
              ),
            ),
          ),
        ),
        validator: (_) => null,
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF4B79C4),
          decoration: TextDecoration.underline,
        ),
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
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: t(context, 'phone.search_country'),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                      leading:
                      Text(c.flag, style: const TextStyle(fontSize: 22)),
                      title: Text(c.name),
                      trailing: Text(
                        c.dialCode,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
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
