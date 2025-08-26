import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import 'api_service.dart';
import 'home_page.dart';
import 'phone_input_page.dart';
import 'location_service.dart';
import 'permission_helper.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.loadPreloginTranslations();

  await Firebase.initializeApp();

  // Глобальная реакция на невалидный токен — сразу уводим на /login
  ApiService.setOnAuthFailed(() {
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/login',
          (route) => false,
    );
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'SpeedBook taxi driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      routes: {
        '/': (_) => const _Root(),
        '/login': (_) => const PhoneInputPage(), // убедись, что конструктор const
      },
      initialRoute: '/',
    );
  }
}

class _Root extends StatefulWidget {
  const _Root({super.key});

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _checkingInit = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      _isLoggedIn = user != null;

      if (_isLoggedIn) {
        try {
          // 1) Проверяем токен онлайн и получаем профиль (в т.ч. язык)
          final profile = await ApiService.checkTokenOnline(validateOnline: true);

          // 2) Язык пользователя из профиля, иначе — язык системы
          final userLang = (profile['lang'] as String?)?.toLowerCase() ??
              ui.window.locale.languageCode.toLowerCase();

          // 3) Грузим переводы под язык пользователя
          await ApiService.loadTranslations(lang: userLang);
        } catch (_) {
          // onAuthFailed уже сделал редирект на /login
          return;
        }
      } else {
        // Гость — грузим переводы по системному языку
        final sysLang = ui.window.locale.languageCode.toLowerCase();
        await ApiService.loadTranslations(lang: sysLang);
      }

      if (mounted) {
        setState(() => _checkingInit = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingInit) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isLoggedIn) {
      return const PhoneInputPage();
    }

    // Пользователь залогинен и переводы загружены
    return ChangeNotifierProvider<LocationService>(
      create: (ctx) => LocationService(
        onDeniedForever: () => showLocationPermissionDialog(ctx),
      ),
      child: HomePage(),
    );
  }
}