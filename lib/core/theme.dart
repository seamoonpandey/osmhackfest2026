import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color highRisk = Color(0xFFEF4444);
  static const Color mediumRisk = Color(0xFFF59E0B);
  static const Color lowRisk = Color(0xFF10B981);
  static const Color darkBg = Color(0xFF0F172A);
  static const Color surfaceBg = Color(0xFF1E293B);

  static ThemeData darkTheme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: darkBg,
    primaryColor: primaryBlue,
    colorScheme: const ColorScheme.dark(
      primary: accentCyan,
      secondary: primaryBlue,
      surface: surfaceBg,
    ),
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
    cardTheme: CardThemeData(
      color: surfaceBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: darkBg,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accentCyan,
      foregroundColor: Colors.white,
    ),
  );
}
