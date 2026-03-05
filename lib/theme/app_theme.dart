import 'package:flutter/material.dart';

class AppTheme {
  // Primary brand colors
  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color primaryBlueDark = Color(0xFF0D47A1);
  static const Color primaryBlueLight = Color(0xFF1976D2);
  static const Color accentBlue = Color(0xFF42A5F5);
  static const Color lightBlue = Color(0xFFE3F2FD);

  // Status colors
  static const Color salesColor = Color(0xFF2E7D32);
  static const Color purchasesColor = Color(0xFF6A1B9A);
  static const Color inventoryColor = Color(0xFF0277BD);
  static const Color reportsColor = Color(0xFFE65100);
  static const Color warningColor = Color(0xFFF9A825);
  static const Color errorColor = Color(0xFFC62828);

  // Neutral
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F7FA);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          brightness: Brightness.light,
          primary: primaryBlue,
          secondary: accentBlue,
          surface: cardColor,
        ),
        scaffoldBackgroundColor: background,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryBlue,
          foregroundColor: white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        cardTheme: CardThemeData(
          color: cardColor,
          elevation: 2,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBlue,
            foregroundColor: white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE1E7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE1E7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primaryBlue, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          labelStyle: const TextStyle(color: textGrey, fontSize: 14),
          hintStyle: const TextStyle(color: Color(0xFFADB5BD), fontSize: 14),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primaryBlue,
          foregroundColor: white,
          elevation: 4,
        ),
        dividerTheme: const DividerThemeData(
          color: divider,
          thickness: 1,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
              fontSize: 32, fontWeight: FontWeight.bold, color: textDark),
          displayMedium: TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, color: textDark),
          headlineLarge: TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold, color: textDark),
          headlineMedium: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w600, color: textDark),
          headlineSmall: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: textDark),
          titleLarge: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: textDark),
          titleMedium: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500, color: textDark),
          bodyLarge: TextStyle(fontSize: 15, color: textDark),
          bodyMedium: TextStyle(fontSize: 14, color: textGrey),
          bodySmall: TextStyle(fontSize: 13, color: textGrey),
          labelLarge: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: textDark),
          labelMedium: TextStyle(fontSize: 13, color: textGrey),
          labelSmall: TextStyle(fontSize: 12, color: textGrey),
        ),
      );
}
