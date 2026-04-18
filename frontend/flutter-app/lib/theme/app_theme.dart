import 'package:flutter/material.dart';

// ── Colour palette ─────────────────────────────────────────────────────────────
// Inspired by Obenseuer: dark concrete, amber warmth, desaturated greens/reds
class AppColors {
  AppColors._();

  static const bg       = Color(0xFF0C0E11);   // near-black background
  static const bg2      = Color(0xFF111418);   // panel background
  static const bg3      = Color(0xFF181C22);   // inner card / input
  static const panel    = Color(0xFF1B2028);   // elevated panel
  static const border   = Color(0xFF252C37);   // subtle border
  static const border2  = Color(0xFF333D4C);   // active border

  static const text     = Color(0xFFCAD0DC);   // primary text
  static const text2    = Color(0xFF7E8899);   // secondary / dim text
  static const text3    = Color(0xFF4A5568);   // placeholder / muted

  static const accent   = Color(0xFFE8A020);   // amber — primary action
  static const accent2  = Color(0xFFC07818);   // amber darker hover

  static const pos      = Color(0xFF4ABA6E);   // muted green — gain
  static const neg      = Color(0xFFD95555);   // muted red — loss

  static const gold     = Color(0xFFE8C060);   // gold for game coins
  static const sea      = Color(0xFF2A4A6A);   // Hanseatic sea blue

  // Gradient for headers
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end:   Alignment.bottomRight,
    colors: [Color(0xFF1A2030), Color(0xFF0C0E11)],
  );
}

// ── Typography ─────────────────────────────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  static const String _mono = 'JetBrainsMono';

  static const headline = TextStyle(
    fontSize: 22, fontWeight: FontWeight.w800,
    color: AppColors.text, letterSpacing: -0.5,
  );

  static const title = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w700,
    color: AppColors.text,
  );

  static const label = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w600,
    color: AppColors.text3, letterSpacing: 0.8,
  );

  static const mono = TextStyle(
    fontFamily: _mono, fontSize: 14,
    color: AppColors.text, fontWeight: FontWeight.w400,
  );

  static const monoSm = TextStyle(
    fontFamily: _mono, fontSize: 12,
    color: AppColors.text2,
  );

  static const price = TextStyle(
    fontFamily: _mono, fontSize: 20,
    color: AppColors.text, fontWeight: FontWeight.w700,
  );

  static const priceLg = TextStyle(
    fontFamily: _mono, fontSize: 28,
    color: AppColors.text, fontWeight: FontWeight.w800,
  );
}

// ── Theme ──────────────────────────────────────────────────────────────────────
ThemeData buildAppTheme() {
  return ThemeData(
    brightness:       Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    primaryColor:     AppColors.accent,
    colorScheme: const ColorScheme.dark(
      primary:   AppColors.accent,
      secondary: AppColors.accent2,
      surface:   AppColors.bg2,
      error:     AppColors.neg,
    ),

    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor:  AppColors.bg2,
      foregroundColor:  AppColors.text,
      elevation:        0,
      centerTitle:      false,
      titleTextStyle: TextStyle(
        fontSize: 17, fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),

    // Bottom nav
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor:      AppColors.bg2,
      selectedItemColor:    AppColors.accent,
      unselectedItemColor:  AppColors.text3,
      type:                 BottomNavigationBarType.fixed,
      elevation:            0,
    ),

    // Cards
    cardTheme: CardThemeData(
      color:        AppColors.panel,
      elevation:    0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),

    // Input fields
    inputDecorationTheme: InputDecorationTheme(
      filled:      true,
      fillColor:   AppColors.bg3,
      hintStyle:   const TextStyle(color: AppColors.text3, fontSize: 14),
      labelStyle:  const TextStyle(color: AppColors.text2, fontSize: 13),
      border:      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:   const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:   const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:   const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),

    // Elevated buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        elevation: 0,
      ),
    ),

    // Text buttons
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: AppColors.border, thickness: 1, space: 0,
    ),

    // Chip
    chipTheme: ChipThemeData(
      backgroundColor:   AppColors.bg3,
      labelStyle:        const TextStyle(color: AppColors.text2, fontSize: 12),
      side:              const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),

    useMaterial3: true,
  );
}
