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
import 'package:provider/provider.dart';

import 'api_service.dart';
import 'brand_header.dart';
import 'brand.dart';
import 'messaging_service.dart';
import 'translations.dart';

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

  static const _assetPattern    = 'assets/brand/background.png';
  static const _assetLogoBanner = 'assets/brand/speedbooknew.png';

  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late String _verificationId;
  String? _apiUrl;

  // лёгкий таймер
  final ValueNotifier<int> _secondsVN = ValueNotifier<int>(60);
  final ValueNotifier<bool> _canResendVN = ValueNotifier<bool>(false);
  DateTime? _resendUntil;
  Timer? _ticker;

  bool _submitting = false;
  String _code = ''; // <-- вместо TextEditingController

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
      if (mounted) {
        setState(() {
          _apiUrl = url;
        });
      } else {
        _apiUrl = url;
      }
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
      final lang = context.read<Translations>().lang;
      try {
        await _auth.setLanguageCode(lang);
      } catch (_) {}

      await _auth.verifyPhoneNumber(
        phoneNumber: widget.phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (!mounted) return;
          final ok = await _handleAuth(credential);
          if (!mounted) return;
          if (ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t(context, 'common.success'))),
            );
            Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
          } else {
            setState(() => _submitting = false);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${t(context, 'common.error')}: ${e.message ?? e.code}',
              ),
            ),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          _verificationId = verificationId;
          _startCountdown();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t(context, 'sms.resend_error')}: $e')),
      );
    }
  }

  Future<String?> _getFcmTokenWithPermissions() async {
    try {
      if (Platform.isIOS) {
        // НИЧЕГО не спрашиваем у пользователя при логине
        final settings = await FirebaseMessaging.instance.getNotificationSettings();
        final auth = settings.authorizationStatus;
        if (auth == AuthorizationStatus.authorized ||
            auth == AuthorizationStatus.provisional) {
          return await FirebaseMessaging.instance.getToken();
        }
        return null; // разрешения нет — ок, работаем без токена
      }

      // Android: можно попробовать получить токен сразу
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
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

  String _msgForFirebaseError(
      FirebaseAuthException e, BuildContext context) {
    debugPrint(
        '[SMSInput] FirebaseAuthException code=${e.code} message=${e.message}');

    switch (e.code) {
      case 'invalid-verification-code':
        return t(context, 'sms.code_invalid');
      case 'invalid-verification-id':
      case 'missing-verification-id':
        return t(context, 'sms.code_expired');
      case 'session-expired':
        return t(context, 'sms.session_expired');
      case 'too-many-requests':
        return t(context, 'sms.too_many_requests');
      case 'network-request-failed':
        return t(context, 'common.network_error');
      case 'quota-exceeded':
        return t(context, 'sms.quota_exceeded');
      case 'app-not-authorized':
      case 'invalid-app-credential':
      case 'captcha-check-failed':
        return t(context, 'sms.app_check_failed');
      default:
        return e.message ?? t(context, 'common.error');
    }
  }

  Future<bool> _handleAuth(PhoneAuthCredential credential) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userCountry = prefs.getString('user_country') ?? '';
      debugPrint('[SMSInput] user_country: $userCountry');

      // 1) Firebase sign-in
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, 'sms.signin_failed'))),
          );
        }
        return false;
      }

      // 2) Firebase ID token
      final idToken = await user.getIdToken(true);

      // 3) Push init / device info
      if (!Platform.isIOS) {
        await MessagingService.I.init();
      }
      final deviceInfo = await _getDeviceInfo();
      final fcmToken = await _getFcmTokenWithPermissions();

      // 4) API url
      if (_apiUrl == null) {
        await _loadApiUrl();
        if (_apiUrl == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t(context, 'common.api_url_missing'))),
            );
          }
          return false;
        }
      }

      // 5) Backend auth
      final currentLocale =
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      final info = await PackageInfo.fromPlatform();
      final platform =
      Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');

      final pendingInviter =
      prefs.getString('referral.pending_inviter_id');
      final branchLinkId =
      prefs.getString('referral.branch_link_id');
      final referralSource =
          prefs.getString('referral.source') ?? 'branch';

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
          if (fcmToken?.isNotEmpty == true) 'fcm_token': fcmToken,
          'is_driver': true,
          'region': userCountry,
          'inviter_id': pendingInviter,
          if (branchLinkId != null) 'link_id': branchLinkId,
          'source': referralSource,
        }),
      )
          .timeout(const Duration(seconds: 15));

      debugPrint('[SMSInput] response code: ${response.statusCode}');

      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${t(context, 'common.backend_error')}: ${response.statusCode}',
              ),
            ),
          );
        }
        return false;
      }

      final Map<String, dynamic> json = jsonDecode(response.body);
      debugPrint('[SMSInput] response body: ${response.body}');

      if (json['status'] != 'OK') {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(json['status']?.toString() ??
                  t(context, 'common.unknown_error')),
            ),
          );
        }
        return false;
      }

      // 6) токены
      final token = json['data']?['token'];
      final secret = json['data']?['secret'];
      debugPrint('[SMSInput] token: $token, secret: ${secret is String ? "***" : secret}');

      // очищаем pending реферал
      final hadReferral = prefs.getString('referral.pending_inviter_id');
      if (hadReferral != null && hadReferral.isNotEmpty) {
        await prefs.remove('referral.pending_inviter_id');
      }

      if (token is String &&
          token.isNotEmpty &&
          secret is String &&
          secret.isNotEmpty) {
        await prefs.setString('secret', secret);
        await prefs.setString('token', token);
        return true;
      } else {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, 'common.unknown_error'))),
          );
        }
        return false;
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final msg = _msgForFirebaseError(e, context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      return false;
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'common.timeout'))),
        );
      }
      return false;
    } catch (e) {
      debugPrint('[SMSInput] handle error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, 'common.error')}: $e')),
        );
      }
      return false;
    }
  }

  Future<void> verifySmsCode() async {
    if (_submitting) return;
    if (!mounted) return;

    if (_code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'sms.enter_digits'))),
      );
      return;
    }

    if (_verificationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'sms.code_expired'))),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _code,
      );

      final ok = await _handleAuth(credential);

      if (!mounted) return;

      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'common.success'))),
        );
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/', (route) => false);
      } else {
        setState(() => _submitting = false);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg = _msgForFirebaseError(e, context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t(context, 'common.error')}: $e')),
      );
    }
  }

  void _goBackToPhone() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/login', (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // размеры для баннера — как на phone_input
    final w = MediaQuery.of(context).size.width;
    final bannerHeight = (w * 0.26).clamp(96.0, 120.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFB),
      appBar: BrandHeader(showBack: true, onBackTap: _goBackToPhone), // единая шапка
      body: Stack(
        children: [
          // ↓ Фон как в phone_input (без масштабирования)
          Positioned.fill(
            child: IgnorePointer(
              child: Image.asset(
                _assetPattern,
                repeat: ImageRepeat.repeat,
                fit: BoxFit.none,
                alignment: Alignment.topLeft,
                filterQuality: FilterQuality.low,
                color: Colors.white.withOpacity(0.05),
                colorBlendMode: BlendMode.srcATop,
              ),
            ),
          ),

          // Баннер SpeedBook — как на phone_input
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Image.asset(
                    _assetLogoBanner,
                    height: bannerHeight,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),

          // Контент страницы
          Padding(
            padding: EdgeInsets.fromLTRB(24, bannerHeight + 16, 24, 24),
            child: Form(
              key: _formKey,
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  const SizedBox(height: 8),

                  Text(
                    t(context, 'sms.title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),

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
                      children: [
                        const Icon(Icons.notifications_none_rounded, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            t(context, 'sms.check_push'),
                            style: const TextStyle(
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

                  PinCodeTextField(
                    appContext: context,
                    length: 6,
                    autoFocus: true,
                    keyboardType: TextInputType.number,
                    cursorColor: Colors.black,
                    animationType: AnimationType.none,
                    onChanged: (val) => _code = val,
                    onCompleted: (val) => _code = val,
                    validator: (value) => (value == null || value.length != 6)
                        ? t(context, 'sms.enter_digits')
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

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : verifySmsCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Brand.yellow,
                        foregroundColor: Colors.black87,
                        shadowColor: Colors.transparent,
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : Text(t(context, 'sms.next')),
                    ),
                  ),

                  const SizedBox(height: 12),

                  ValueListenableBuilder<bool>(
                    valueListenable: _canResendVN,
                    builder: (context, canResend, _) {
                      return ValueListenableBuilder<int>(
                        valueListenable: _secondsVN,
                        builder: (context, secondsLeft, __) {
                          final text = canResend
                              ? t(context, 'sms.get_new_code')
                              : '${t(context, 'sms.get_new_code')}   ${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}';

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
                                  fontWeight: FontWeight.w600,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
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
        ],
      ),
    );
  }
}
