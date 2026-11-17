import 'package:flutter/material.dart';

enum AppTheme { white, black, grey }

ThemeData getThemeData(AppTheme theme) {
  switch (theme) {
    case AppTheme.white:
      return ThemeData(brightness: Brightness.light, useMaterial3: true, colorSchemeSeed: Colors.blue);
    case AppTheme.black:
      return ThemeData(brightness: Brightness.dark, useMaterial3: true, colorSchemeSeed: Colors.blue);
    case AppTheme.grey:
      return ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF303030),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF212121)),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark).copyWith(
          surface: const Color(0xFF424242),
        ),
      );
  }
}