import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Глобальный контроллер переводов.
/// Меняет язык через ApiService и пробуждает виджеты на перестройку.
class Translations extends ChangeNotifier {
  String _lang = 'en';
  int _tick = 0; // любой инкремент → зависимые виджеты перестраиваются

  String get lang => _lang;
  int get tick => _tick;

  /// Инициализация из сохранённых настроек/системы
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('user_lang');
    _lang = (saved ??
            WidgetsBinding.instance.platformDispatcher.locale.languageCode)
        .toLowerCase();
    // грузим prelogin/сетевые на старте (необязательно, но полезно)
    await ApiService.loadPreloginTranslations(lang: _lang);
    notifyListeners();
  }

  /// Сменить язык: вызовет загрузку переводов и инкремент тика.
  Future<void> setLang(String lang) async {
    if (lang.toLowerCase() == _lang.toLowerCase()) return;
    _lang = lang.toLowerCase();

    await ApiService.switchLanguage(_lang); // внутри сохранит и загрузит переводы

    _tick++; // сигнал для зависимых виджетов
    notifyListeners();
  }
}

/// Удобный хелпер: добавляет зависимость от Translations.tick,
/// чтобы при его изменении все места, вызывающие t(), перестроились.
String t(BuildContext context, String key) {
  // создаём зависимость на изменение .tick (ничего не делаем с числом)
  final _ =
      context.dependOnInheritedWidgetOfExactType<_TranslationsTick>()?.tick;

  return ApiService.getTranslationForWidget(context, key);
}

/// Внутренняя прослойка для “подписки” всего саб-дерева на изменения tick.
class TranslationsScope extends StatelessWidget {
  final Widget child;
  final int tick;
  const TranslationsScope({super.key, required this.child, required this.tick});

  @override
  Widget build(BuildContext context) {
    return _TranslationsTick(tick: tick, child: child);
  }
}

class _TranslationsTick extends InheritedWidget {
  final int tick;
  const _TranslationsTick(
      {required this.tick, required super.child, super.key});

  @override
  bool updateShouldNotify(_TranslationsTick oldWidget) =>
      oldWidget.tick != tick;
}
