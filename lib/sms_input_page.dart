// lib/sms_input_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'features/home/brand.dart'; // kBrandYellow, kBrandYellowDark
import 'messaging_service.dart';

class SmsInputPage extends StatefulWidget {
  final String phone;
  final String verificationId;

  const SmsInputPage({
    super.key,
    required this.phone,
    required this.verificationId,
  });

  @override
  State<SmsInputPage> createState() => _SmsInputPageState();
}

class _SmsInputPageState extends State<SmsInputPage>
    with WidgetsBindingObserver {
  static const MethodChannel _configChannel =
  MethodChannel('com.speedbook.taxidriver/config');

  final _formKey = GlobalKey<FormState>();
  final TextEditingController smsController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late String _verificationId;
  String? _apiUrl;

  // лёгкий таймер
  final ValueNotifier<int> _secondsVN = ValueNotifier<int>(60);
  final ValueNotifier<bool> _canResendVN = ValueNotifier<bool>(false);
  DateTime? _resendUntil;
  Timer? _ticker;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _verificationId = widget.verificationId;
    _loadApiUrl();
    _startCountdown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    smsController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _ticker?.cancel();
      _ticker = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_resendUntil != null && DateTime.now().isBefore(_resendUntil!)) {
        _startTicker();
      }
    }
  }

  Future<void> _loadApiUrl() async {
    try {
      final url = await _configChannel.invokeMethod<String>('getApiUrl');
      if (mounted) _apiUrl = url;
    } catch (e) {
      debugPrint('Error loading API_URL: $e');
    }
  }

  void _startCountdown() {
    _resendUntil = DateTime.now().add(const Duration(seconds: 60));
    _canResendVN.value = false;
    _secondsVN.value = 60;
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final left =
      _resendUntil != null ? _resendUntil!.difference(now).inSeconds : 0;
      if (left <= 0) {
        _secondsVN.value = 0;
        _canResendVN.value = true;
        _ticker?.cancel();
        _ticker = null;
      } else {
        _secondsVN.value = left;
      }
    });
  }

  Future<void> _resendCode() async {
    if (_submitting) return;
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: widget.phone,
        verificationCompleted: (PhoneAuthCredential credential) {
          _handleAuth(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.message ?? e.code}')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _startCountdown();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resending code: $e')),
      );
    }
  }

  Future<String?> _getFcmTokenWithPermissions() async {
    if (Platform.isIOS) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return null;
      }
    }
    return FirebaseMessaging.instance.getToken();
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String device = 'unknown';
    String osVersion = 'unknown';
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        device = info.model ?? 'unknown';
        osVersion = 'Android ${info.version.release}';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        device = info.utsname.machine ?? 'unknown';
        osVersion = 'iOS ${info.systemVersion}';
      }
    } catch (_) {}
    return {'device': device, 'osVersion': osVersion};
  }

  Future<void> _handleAuth(PhoneAuthCredential credential) async {
    final currentLocale =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final info = await PackageInfo.fromPlatform();

    if (_apiUrl == null) {
      await _loadApiUrl();
      if (_apiUrl == null) return;
    }

    try {
      setState(() => _submitting = true);

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        if (mounted) setState(() => _submitting = false);
        return;
      }

      final idToken = await user.getIdToken();
      await MessagingService.I.init();

      final deviceInfo = await _getDeviceInfo();
      final fcmToken = await _getFcmTokenWithPermissions();

      final platform = Platform.isAndroid
          ? 'android'
          : Platform.isIOS
          ? 'ios'
          : 'unknown';

      final urlStr = '${_apiUrl!}/api/auth_driver';
      final response = await http
          .post(
        Uri.parse(urlStr),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'uid': user.uid,
          'phone': user.phoneNumber,
          'device': deviceInfo['device'],
          'os_version': deviceInfo['osVersion'],
          'platform': platform,
          'locale': currentLocale,
          'app_version': info.version,
          'fcm_token': fcmToken,
          'is_driver': true,
        }),
      )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        try {
          final Map<String, dynamic> json = jsonDecode(response.body);
          if (json['status'] == 'OK') {
            final token = json['data']?['token'];
            final secret = json['data']?['secret'];
            if (token is String) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('secret', secret);
              await prefs.setString('token', token);
//              await ApiService.loadTranslations();
            }
            if (!mounted) return;
            final messenger = ScaffoldMessenger.of(context);
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            messenger.showSnackBar(const SnackBar(content: Text('Success!')));
          } else {
            final errorMsg = json['status'] ?? 'Unknown error';
            await FirebaseAuth.instance.signOut();
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(errorMsg.toString())));
            }
          }
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid server response')),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backend error: ${response.statusCode}')),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server timeout')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> verifySmsCode() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final code = smsController.text.trim();
    if (code.length != 6) return;

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: code,
    );
    await _handleAuth(credential);
  }

  void _goBackToPhone() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
// адаптивный отступ под макет: ~30% высоты экрана, но не меньше 96 и не больше 160
    final clampedTopExtra = (h * 0.30).clamp(96.0, 160.0) as double;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFB),
      body: Stack(
        children: [
          // ── верхний бренд-бэнд с картинкой
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 64,
              color: kBrandYellow,
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Image.asset(
                  'assets/brand/speedbook.png',
                  height: 24,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // ── контент
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24 + clampedTopExtra, 24, 24),
              child: Form(
                key: _formKey,
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    const SizedBox(height: 8),

                    // заголовок
                    const Text(
                      'Enter the code from the push\nnotification',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // карточка уведомления — увеличенная
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          )
                        ],
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.notifications_none_rounded, size: 32),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Check your push notifications',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // PIN — подчёркнутые слоты
                    PinCodeTextField(
                      controller: smsController,
                      appContext: context,
                      length: 6,
                      autoFocus: true,
                      keyboardType: TextInputType.number,
                      cursorColor: Colors.black,
                      animationType: AnimationType.none,
                      onChanged: (_) {},
                      validator: (value) =>
                      (value == null || value.length != 6)
                          ? 'Enter 6 digits'
                          : null,
                      pinTheme: PinTheme(
                        shape: PinCodeFieldShape.underline,
                        borderRadius: BorderRadius.circular(8),
                        fieldHeight: 56,
                        fieldWidth: 44,
                        activeColor: Colors.black87,
                        selectedColor: Colors.black87,
                        inactiveColor: Colors.black38,
                        borderWidth: 1.4,
                      ),
                      boxShadows: const [BoxShadow(color: Colors.transparent)],
                      enableActiveFill: false,
                    ),

                    const SizedBox(height: 22),

                    // Next
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : verifySmsCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDCCFB5),
                          foregroundColor: Colors.black87,
                          shadowColor: Colors.transparent,
                          textStyle: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _submitting
                            ? const SizedBox(
                          width: 22,
                          height: 22,
                          child:
                          CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('Next'),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Get a new code (ValueNotifier)
                    ValueListenableBuilder<bool>(
                      valueListenable: _canResendVN,
                      builder: (context, canResend, _) {
                        return ValueListenableBuilder<int>(
                          valueListenable: _secondsVN,
                          builder: (context, secondsLeft, __) {
                            final text = canResend
                                ? 'Get a new code'
                                : 'Get a new code   ${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}';

                            return SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: canResend ? _resendCode : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF1EFEF),
                                  foregroundColor: Colors.black87,
                                  disabledBackgroundColor:
                                  const Color(0xFFF1EFEF),
                                  disabledForegroundColor: Colors.black38,
                                  shadowColor: Colors.transparent,
                                  textStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                child: Text(text),
                              ),
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),

          // круглая кнопка "назад" (слева под бэндом)
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _goBackToPhone,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.arrow_back, color: Colors.black87),
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
