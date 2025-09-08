import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'brand.dart';
import 'brand_header.dart';
import 'translations.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  // Поддерживаемые языки/страны (можно расширять)
  static const _languages = <Map<String, String>>[
    {'code': 'en', 'label': 'English'},
    {'code': 'ru', 'label': 'Русский'},
    {'code': 'km', 'label': 'ភាសាខ្មែរ'},
  ];
  static const _supportedLangs = {'en', 'ru', 'km'};

  static const _countries = <Map<String, String>>[
    {'code': 'RU', 'label': 'Russia'},
    {'code': 'KH', 'label': 'Cambodia'},
  ];
  static const _supportedCountries = {'RU', 'KH'};

  String _lang = 'en';
  String _country = 'KH';
  bool _busy = false;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  // Нормализация "ru-RU" -> "ru", "en_US" -> "en"
  String _normLang(String code) {
    final c = (code).split(RegExp(r'[-_]')).first.toLowerCase();
    return _supportedLangs.contains(c) ? c : 'en';
  }
  String _normCountry(String? code) {
    final c = (code ?? '').toUpperCase();
    return _supportedCountries.contains(c) ? c : 'KH';
  }

  Future<void> _initDefaults() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) язык: saved -> system -> 'en'
    final savedLang = prefs.getString('user_lang');
    if (savedLang != null && savedLang.isNotEmpty) {
      _lang = _normLang(savedLang);
    } else {
      final systemLangTag =
      WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(); // e.g. ru-RU
      _lang = _normLang(systemLangTag);
    }

    // 2) страна: saved -> system -> 'KH'
    final savedCountry = prefs.getString('user_country');
    if (savedCountry != null && savedCountry.isNotEmpty) {
      _country = _normCountry(savedCountry);
    } else {
      final systemCountry =
          WidgetsBinding.instance.platformDispatcher.locale.countryCode;
      _country = _normCountry(systemCountry);
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveLang(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_lang', lang);
  }

  Future<void> _saveCountry(String country) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_country', country);
  }

  Future<void> _markPushChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_permission_checked', true);
  }

  Future<void> _syncFcmTokenBestEffort(String? token) async {
/*    if (token == null || token.isEmpty) return;
    try {
      await ApiService.callPlain('update_fcm_token', {'fcm_token': token})
          .timeout(const Duration(seconds: 8));
    } catch (_)  */
  }

  Future<void> _requestPushAndContinue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _markPushChecked();

      // FCM токен -> бэк (best effort)
      String? token;
      try {
        token = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      await _syncFcmTokenBestEffort(token);

      if (mounted) {
        await context.read<Translations>().setLang(_lang); // страховка
        widget.onDone();
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = 'Timeout. Please try again.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Brand.theme(Theme.of(context));

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: const BrandHeader(),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const SizedBox(height: 8),
                // Иконка/иллюстрация
                Container(
                  height: 140,
                  width: 140,
                  decoration: BoxDecoration(
                    color: Brand.yellow.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x14000000)),
                  ),
                  child: const Icon(Icons.public_rounded,
                      size: 72, color: Brand.textDark),
                ),
                const SizedBox(height: 18),

                Text(
                  t(context, 'onboarding.title'),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  t(context, 'onboarding.subtitle'),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 20),

                if (_error != null) ...[
                  MaterialBanner(
                    content: Text(_error!),
                    leading: const Icon(Icons.error_outline),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _error = null),
                        child: Text(t(context, 'common.hide')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Язык
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t(context, 'onboarding.language'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _lang,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      border: OutlineInputBorder()),
                  items: _languages
                      .map((e) => DropdownMenuItem(
                    value: e['code']!,
                    child: Text(e['label']!),
                  ))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _lang = v);
                    await _saveLang(_lang);
                    if (!mounted) return;
                    // мгновенно переключаем язык интерфейса + MaterialApp.locale
                    await context.read<Translations>().setLang(_lang);
                  },
                ),

                const SizedBox(height: 16),

                // Страна
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t(context, 'onboarding.country'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _country,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      border: OutlineInputBorder()),
                  items: _countries
                      .map((e) => DropdownMenuItem(
                    value: e['code']!,
                    child:
                    Text('${e['label']} (${e['code']})'),
                  ))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _country = v);
                    await _saveCountry(_country);
                  },
                ),

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed:
                    _busy ? null : _requestPushAndContinue,
                    icon: _busy
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2),
                    )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(t(context, 'onboarding.continue')),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _busy ? null : widget.onDone,
                    child: Text(t(context, 'onboarding.skip')),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
