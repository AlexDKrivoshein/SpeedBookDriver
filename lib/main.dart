// lib/main.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import 'api_service.dart';
import 'home_page.dart';
import 'phone_input_page.dart';
import 'location_service.dart';
import 'permission_helper.dart';
import 'onboarding_page.dart';
import 'translations.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.loadPreloginTranslations();

  await Firebase.initializeApp();

  final opts = Firebase.app().options;
  debugPrint('FB project: ${opts.projectId} appId: ${opts.appId} apiKey: ${opts.apiKey}');

  if (kDebugMode) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );
    final token = await FirebaseAppCheck.instance.getToken();
    debugPrint('AppCheck debug token: $token');
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    );
  }

  // Глобальная реакция на невалидную backend-сессию
  ApiService.setOnAuthFailed(() {
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Провайдер переводов + реактивная обёртка всего приложения
    return ChangeNotifierProvider<Translations>(
      create: (_) => Translations()..init(),
      child: Consumer<Translations>(
        builder: (context, i18n, _) {
          return TranslationsScope(
            tick: i18n.tick, // любое изменение языка триггерит перестройку
            child: MaterialApp(
              navigatorKey: navigatorKey,
              title: 'SpeedBook taxi driver',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: Colors.blue,
              ),

              // Локализация приложения
              locale: Locale(i18n.lang),
              supportedLocales: const [
                Locale('en'),
                Locale('ru'),
                Locale('km'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],

              routes: {
                '/': (_) => const _Root(),
                '/login': (_) => const PhoneInputPage(),
              },
              initialRoute: '/',
            ),
          );
        },
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root({super.key});

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool? _needOnboarding;   // null = загрузка
  bool _checkingInit = true;
  bool _isLoggedIn = false;
  bool _hasSession = false; // <-- добавлено: есть ли backend-сессия (token+secret)

  @override
  void initState() {
    super.initState();
    _decideOnboarding();
  }

  Future<bool> _hasBackendSession() async {
    final prefs = await SharedPreferences.getInstance();
    final hasToken  = (prefs.getString('token')  ?? '').isNotEmpty;
    final hasSecret = (prefs.getString('secret') ?? '').isNotEmpty;
    return hasToken && hasSecret;
  }

  /// Ждём, пока sms_input_page сохранит token/secret (макс. ~3 секунды)
  Future<bool> _waitForBackendSession({Duration timeout = const Duration(seconds: 3)}) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      if (await _hasBackendSession()) return true;
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return await _hasBackendSession();
  }

  Future<void> _decideOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') == true;
    setState(() => _needOnboarding = !done);

    if (!mounted) return;
    if (_needOnboarding == true) {
      setState(() => _checkingInit = false); // покажем онбординг
    } else {
      _attachAuthListener(); // обычный флоу
    }
  }

  Future<void> _markOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
  }

  void _onOnboardingDone() async {
    await _markOnboardingDone();
    if (!mounted) return;
    setState(() {
      _needOnboarding = false;
      _checkingInit = true;
    });
    _attachAuthListener();
  }

  void _attachAuthListener() {
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      _isLoggedIn = user != null;

      if (_isLoggedIn) {
        // 1) ждём, пока sms_input_page запишет token/secret
        final sessionReady = await _waitForBackendSession();
        if (!sessionReady) {
          if (mounted) {
            setState(() {
              _hasSession = false;
              _checkingInit = false;
            });
          }
          return; // не идём на Home
        }

        try {
          // 2) теперь безопасно: токены точно есть
          final profile = await ApiService.checkTokenOnline(validateOnline: true);

          // 3) язык: сохранённый/с профиля → загрузка переводов
          final prefs = await SharedPreferences.getInstance();
          final savedLang = (prefs.getString('user_lang') ?? '').toLowerCase();
          final userLang = savedLang.isNotEmpty
              ? savedLang
              : (profile['lang'] as String?)?.toLowerCase()
              ?? ui.window.locale.languageCode.toLowerCase();

          await ApiService.loadTranslations(lang: userLang);
          if (mounted) {
            await context.read<Translations>().setLang(userLang);
            setState(() {
              _hasSession = true;      // есть backend-сессия
              _checkingInit = false;
            });
          }
        } catch (_) {
          // onAuthFailed сам отправит на /login
          return;
        }
      } else {
        // Гость: берём выбранный язык (с онбординга) или системный
        final prefs = await SharedPreferences.getInstance();
        final savedLang = (prefs.getString('user_lang') ?? '').toLowerCase();
        final guestLang = savedLang.isNotEmpty
            ? savedLang
            : ui.window.locale.languageCode.toLowerCase();

        await ApiService.loadTranslations(lang: guestLang);
        if (mounted) {
          await context.read<Translations>().setLang(guestLang);
          setState(() {
            _hasSession = false;
            _checkingInit = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_needOnboarding == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_needOnboarding == true) {
      return OnboardingPage(onDone: _onOnboardingDone);
    }
    if (_checkingInit) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // На HomePage только при наличии backend-сессии
    if (!_isLoggedIn || !_hasSession) {
      return const PhoneInputPage();
    }

    return ChangeNotifierProvider<LocationService>(
      create: (ctx) => LocationService(
        onDeniedForever: () => showLocationPermissionDialog(ctx),
      ),
      child: HomePage(),
    );
  }
}
