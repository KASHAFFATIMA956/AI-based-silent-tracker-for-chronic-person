import 'package:flutter/material.dart';

/// Colors lifted directly from the design prototype's "Sage" (Paper/light)
/// palette (`UI Inspo/.../RozNoor.dc.html`, `#rn` custom properties) — see
/// context/conventions.md. `RnDarkColors` below is the same file's
/// "Nocturne" (dark) palette, added 2026-08-27 for real theme switching.
class RnColors {
  RnColors._();

  // Light ("Sage" / "Paper")
  static const bg = Color(0xFFEAF1EE);
  static const surface = Color(0xFFF7F8F5);
  static const text = Color(0xFF18302F);
  static const accent = Color(0xFF0F6B68); // brand teal
  static const accentDark = Color(0xFF0C5B54);
  static const accent2 = Color(0xFF4A7FA7); // AI / secondary blue
  static const divider = Color(0xFFD3E0DA);
  static const accent100 = Color(0xFFEEF5F2);
  static const accent200 = Color(0xFFDDEBE6);
  static const accent300 = Color(0xFFC2DDD5);
  static const accent400 = Color(0xFF8FC0B8);
  static const neutral500 = Color(0xFF8FA39E);

  // Risk levels — matches Green/Yellow/Orange/Red badges everywhere in the
  // prototype (light "Sage" values).
  static const riskGreen = Color(0xFF237A57);
  static const riskAmber = Color(0xFFA97112);
  static const riskCoral = Color(0xFFBD5A25);
  static const riskRed = Color(0xFFB83A46);

  static Color forRiskLevel(String? level) {
    switch (level) {
      case 'Green':
        return riskGreen;
      case 'Yellow':
        return riskAmber;
      case 'Orange':
        return riskCoral;
      case 'Red':
        return riskRed;
      default:
        return neutral500;
    }
  }
}

/// "Nocturne" (dark) palette — same source values as the `#rn[data-theme="dark"]`
/// block in `RozNoor.dc.html` (void ground, teal primary, coral secondary).
/// `RnColors.forRiskLevel` is deliberately NOT duplicated here: risk badges
/// keep their light-mode ink even in Nocturne, matching how every other
/// non-theme-reactive brand color (e.g. `RnColors.riskRed` on the Emergency
/// button) is used directly across the app today — see decisions-log.md.
class RnDarkColors {
  RnDarkColors._();

  static const bg = Color(0xFF070F0F);
  static const surface = Color(0xFF0D1A19);
  static const text = Color(0xFFEAF6F4);
  static const accent = Color(0xFF2DD4C4);
  static const accentDark = Color(0xFF14B8A6);
  static const accent2 = Color(0xFFFF6F5E); // coral secondary
  static const divider = Color(0xFF1C3532);
  static const accent100 = Color(0xFF0B2B2A);
  static const accent200 = Color(0xFF0F4C4C);
  static const accent300 = Color(0xFF12635E);
  static const accent400 = Color(0xFF0F9C8D);
  static const neutral500 = Color(0xFF5B7975);
}

/// Theme-aware secondary/muted text color. Added 2026-08-27 alongside real
/// Nocturne support — screens across this app used `Colors.black.withValues
/// (alpha: ...)` for secondary text, which stays literally black regardless
/// of theme and goes near-unreadable against Nocturne's dark backgrounds.
/// Use `context.rnMuted()` instead of that pattern anywhere a screen needs a
/// dimmed version of the theme's own text color.
extension RnTextColors on BuildContext {
  Color rnMuted([double alpha = 0.6]) {
    final isDark = Theme.of(this).brightness == Brightness.dark;
    return (isDark ? RnDarkColors.text : RnColors.text).withValues(alpha: alpha);
  }
}

/// A slightly more clinical accent used only on the doctor/admin login
/// styling and the placeholder screen — per the task's "optionally with
/// slightly more clinical styling" note. Reuses accent2 (the prototype's
/// own "AI/clinical" blue note) rather than inventing a new color.
const clinicalAccent = RnColors.accent2;

ThemeData buildRnLightTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: RnColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: RnColors.accent,
      secondary: RnColors.accent2,
      surface: RnColors.surface,
      error: RnColors.riskRed,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: RnColors.text,
      displayColor: RnColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: RnColors.bg,
      foregroundColor: RnColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: RnColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: RnColors.divider),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(color: RnColors.divider, thickness: 1),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: RnColors.accent,
        foregroundColor: RnColors.surface,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: RnColors.accent,
        side: const BorderSide(color: RnColors.accent400),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: RnColors.accent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RnColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: RnColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: RnColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: RnColors.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: RnColors.surface,
      indicatorColor: RnColors.accent200,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          color: selected ? RnColors.accentDark : RnColors.neutral500,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        );
      }),
    ),
  );
}

/// "Nocturne" dark theme — same structure as [buildRnLightTheme], mapped to
/// [RnDarkColors]. Added 2026-08-27 alongside `ThemeProvider` so the app
/// actually has a dark `ThemeData` to switch to (previously `MaterialApp`
/// only ever built the light theme — see context/decisions-log.md).
ThemeData buildRnDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: RnDarkColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: RnDarkColors.accent,
      secondary: RnDarkColors.accent2,
      surface: RnDarkColors.surface,
      error: RnColors.riskRed,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: RnDarkColors.text,
      displayColor: RnDarkColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: RnDarkColors.bg,
      foregroundColor: RnDarkColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: RnDarkColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: RnDarkColors.divider),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(color: RnDarkColors.divider, thickness: 1),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: RnDarkColors.accent,
        foregroundColor: RnDarkColors.bg,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: RnDarkColors.accent,
        side: const BorderSide(color: RnDarkColors.accent400),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: RnDarkColors.accent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RnDarkColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: RnDarkColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: RnDarkColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: RnDarkColors.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: RnDarkColors.surface,
      indicatorColor: RnDarkColors.accent200,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          color: selected ? RnDarkColors.accent : RnDarkColors.neutral500,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        );
      }),
    ),
  );
}
