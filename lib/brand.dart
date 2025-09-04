import 'package:flutter/material.dart';

class Brand {
  // Яркий «таксичный» жёлтый + тёмный текст
//  static const Color yellow = Color.fromRGBO(254, 244, 63, 1.0); // основной
  static const Color yellow = Color(0xFFFEF305); // основной
  static const Color yellowDark = Color(0xFFFFD600); // акцент/hover
  static const Color textDark = Color(0xFF1B1B1B);
  static const Color textMuted = Color(0xFF6B6B6B);
  static const Color border = Color(0x14000000);

  static ThemeData theme(ThemeData base) {
    final scheme = base.colorScheme.copyWith(
      primary: yellow,
      onPrimary: textDark,
      surface: Colors.white,
      onSurface: textDark,
    );

    return base.copyWith(
      colorScheme: scheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: yellow,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: textDark,
          fontWeight: FontWeight.w800,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: yellow,
          foregroundColor: textDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textDark,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: border),
        ),
      ),
    );
  }
}
