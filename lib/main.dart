import 'dart:io' show exit;
import 'package:flutter/services.dart' show SystemNavigator;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, kDebugMode;

// ===== Branch (по умолчанию отключено флагом) =====
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';

import 'route_observer.dart';
import 'api_service.dart';
import 'features/home/home_page.dart';
import 'phone_input_page.dart';
import 'location_service.dart';
import 'permission_helper.dart';
import 'onboarding_page.dart';
import 'translations.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Флаг управления Branch из сборки:
///   по умолчанию false (отключено для тестов / разработки)
const bool kBranchEnabled =
bool.fromEnvironment('BRANCH_ENABLED', defaultValue: false);

Future<void> _initBranchDeepLinking() async {
  if (!kBranchEnabled) {
    debugPrint('[Branch] disabled (BRANCH_ENABLED=false)');
    return;
  }

  await FlutterBranchSdk.init(enableLogging: kDebugMode);
  if (kDebugMode) {
    // Не вызываем validateSDKIntegration, если это мешает прохождению тестов
    // FlutterBranchSdk.validateSDKIntegration();
  }

  // Stream с параметрами диплинков
  FlutterBranchSdk.listSession().listen((data) async {
    try {
      final map = Map<String, dynamic>.from(data);
      final inviter = (map['inviter_id'] ?? map['ref'])?.toString();
      final linkId  = map['~id']?.toString();

      if (inviter != null && inviter.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('referral.pending_inviter_id', inviter);
        if (linkId != null && linkId.isNotEmpty) {
          await prefs.setString('referral.branch_link_id', linkId);
        }
        await prefs.setString('referral.source', 'branch');
        debugPrint('[Branch] saved inviter=$inviter linkId=$linkId');
      } else {
        debugPrint('[Branch] no inviter in params: $map');
      }
    } catch (e) {
      debugPrint('[Branch] listSession parse error: $e');
    }
  }, onError: (e) {
    debugPrint('[Branch] listSession error: $e');
  });
}

Future<void> _initAppCheck() async {
  final isRelease = kReleaseMode;

  await FirebaseAppCheck.instance.activate(
    androidProvider: isRelease ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider:  isRelease ? AppleProvider.deviceCheck   : AppleProvider.debug,
  );

  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

  if (!isRelease) {
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      debugPrint('AppCheck debug token: $token\n'
          '➡ Добавьте его в Firebase Console → App Check → Debug tokens.');
    } catch (e) {
      debugPrint('AppCheck (debug) getToken ещё не принят сервером: $e');
      // ок до регистрации debug-токена или при выключенном Enforce
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ApiService.loadPreloginTranslations();
  await Firebase.initializeApp();

  final opts = Firebase.app().options;
  debugPrint('FB project: ${opts.projectId} appId: ${opts.appId} apiKey: ${opts.apiKey}');

  await _initAppCheck();

  // Branch включаем ТОЛЬКО если задан флаг BRANCH_ENABLED
  await _initBranchDeepLinking();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<Translations>(
      create: (_) => Translations()..init(),
      child: Consumer<Translations>(
        builder: (context, i18n, _) {
          return TranslationsScope(
            tick: i18n.tick,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              title: 'SpeedBook taxi driver',
              debugShowCheckedModeBanner: false,
              navigatorObservers: [appRouteObserver],
              theme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: Colors.blue,
              ),
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
  bool? _needOnboarding; // null = загрузка
  bool _checkingInit = true;
  bool _isLoggedIn = false;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    _decideOnboarding();
  }

  Future<bool> _hasBackendSession() async {
    final prefs = await SharedPreferences.getInstance();
    final hasToken = (prefs.getString('token') ?? '').isNotEmpty;
    final hasSecret = (prefs.getString('secret') ?? '').isNotEmpty;
    return hasToken && hasSecret;
  }

  Future<bool> _waitForBackendSession({Duration timeout = const Duration(seconds: 3)}) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      if (await _hasBackendSession()) return true;
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return await _hasBackendSession();
  }

  Future<void> _decideOnboarding() async {
    // Debug → всегда онбординг
    if (kDebugMode) {
      setState(() {
        _needOnboarding = true;
        _checkingInit = false;
      });
      return;
    }

    // Release → авто язык и страна
    final prefs = await SharedPreferences.getInstance();
    final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final sysLang = (systemLocale.languageCode).toLowerCase();
    const allowed = {'en', 'ru', 'km'};
    final lang = allowed.contains(sysLang) ? sysLang : 'en';

    await prefs.setString('user_lang', lang);
    await prefs.setString('user_country', 'KH');

    setState(() => _needOnboarding = false);

    if (!mounted) return;
    _attachAuthListener();
  }

  Future<void> _markOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
  }

  void _onOnboardingDone() async {
    if (!kDebugMode) {
      await _markOnboardingDone();
    }
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
        final sessionReady = await _waitForBackendSession();
        if (!sessionReady) {
          if (mounted) {
            setState(() {
              _hasSession = false;
              _checkingInit = false;
            });
          }
          return;
        }

        Map<String, dynamic>? profile;
        try {
          final p = await ApiService.checkTokenOnline(validateOnline: true);
          final status = '${p['status'] ?? ''}'.toUpperCase();
          if (status != 'OK') {
            final msg = _extractMsg(p, fallback: 'Authorization failed');
            await _fatal(msg);
            return;
          }
          profile = p;
        } on AuthException catch (e) {
          await _fatal(e.message);
          return;
        } catch (e) {
          await _fatal('Network error. Please try again later.');
          return;
        }

        debugPrint('[Main] Profile: $profile');

        try {
          final prefs = await SharedPreferences.getInstance();
          final savedLang = (prefs.getString('user_lang') ?? '').toLowerCase();
          final userLang = savedLang.isNotEmpty
              ? savedLang
              : (profile?['lang'] as String?)?.toLowerCase() ??
              WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();

          if (mounted) {
            await context.read<Translations>().setLang(userLang);
            setState(() {
              _hasSession = true;
              _checkingInit = false;
            });
          }
        } catch (_) {
          // ignore
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        final savedLang = (prefs.getString('user_lang') ?? '').toLowerCase();
        final guestLang = savedLang.isNotEmpty
            ? savedLang
            : WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();

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

  // ——— helpers ———
  String _extractMsg(Map<String, dynamic> map, {String fallback = 'Error'}) {
    String msg = (map['message']?.toString() ?? '').trim();
    if (msg.isEmpty) {
      final data = map['data'];
      if (data is Map<String, dynamic>) {
        msg = (data['message']?.toString() ?? data['error']?.toString() ?? '').trim();
      }
    }
    if (msg.isEmpty) {
      msg = (map['error']?.toString() ?? '').trim();
    }
    return msg.isEmpty ? fallback : msg;
  }

  Future<void> _fatal(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Ошибка'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              try {
                SystemNavigator.pop();
              } catch (_) {
                exit(0); // fallback (нежелателен на iOS)
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
