import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Vibrant & Soft Color Palette
  static const Color primaryCoral = Color(0xFFFF6B6B); // Soft Vibrant Coral
  static const Color accentLavender = Color(0xFF845EF7); // Gentle Lavender
  static const Color softOrange = Color(0xFFFFA94D); // Warm Sunset
  
  static const Color highRisk = Color(0xFFFF4D4D);
  static const Color mediumRisk = Color(0xFFFAB005);
  static const Color lowRisk = Color(0xFF40C057);
  
  static const Color lightBg = Color(0xFFF8F9FA);      // Very light grey/white
  static const Color surfaceWhite = Color(0xFFFFFFFF); // Pure white
  static const Color surfaceMuted = Color(0xFFE9ECEF); // Muted grey

  static ThemeData lightTheme = ThemeData.light().copyWith(
    scaffoldBackgroundColor: lightBg,
    primaryColor: primaryCoral,
    colorScheme: const ColorScheme.light(
      primary: primaryCoral,
      secondary: accentLavender,
      surface: surfaceWhite,
      onSurface: Color(0xFF212529),
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme).copyWith(
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: const Color(0xFF212529),
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w700,
        fontSize: 20,
        color: const Color(0xFF212529),
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: lightBg,
      elevation: 0,
      centerTitle: true,
      iconTheme: const IconThemeData(color: Color(0xFF212529)),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF212529),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryCoral,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );

  // Keep darkTheme for system compatibility but update it to be less "neon"
  static ThemeData darkTheme = lightTheme; // For now, let's default to light for that vibrant feel
}
