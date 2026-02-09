import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tema de la aplicación VinylScout
/// Colores inspirados en vinilos y estética retro premium
class AppTheme {
  // Colores principales — Paleta Pop Art / Warhol
  static const Color primaryColor = Color(0xFF222222);       // Negro carbón (textos, bordes)
  static const Color secondaryColor = Color(0xFFFF0099);     // Rosa fucsia impactante
  static const Color accentColor = Color(0xFF0066FF);        // Azul eléctrico vibrante
  static const Color backgroundColor = Color(0xFFF8F1E5);   // Crema cálido
  static const Color surfaceColor = Color(0xFFF8F1E5);      // Crema cálido
  static const Color errorColor = Color(0xFFFF3300);         // Rojo anaranjado intenso
  static const Color successColor = Color(0xFF00C853);       // Verde vibrante
  static const Color canaryYellow = Color(0xFFFFD700);       // Amarillo Pop Art

  // ─── POP ART: Sombras sólidas (sin difuminado) ───
  static List<BoxShadow> get cardShadow => [
    const BoxShadow(
      color: secondaryColor,
      offset: Offset(5, 5),
      blurRadius: 0,
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    const BoxShadow(
      color: primaryColor,
      offset: Offset(6, 6),
      blurRadius: 0,
    ),
  ];

  static List<BoxShadow> popShadow(Color color, {double offset = 5}) => [
    BoxShadow(
      color: color,
      offset: Offset(offset, offset),
      blurRadius: 0,
    ),
  ];

  // ─── POP ART: Bordes gruesos ───
  static Border get popBorder => const Border.fromBorderSide(
    BorderSide(color: primaryColor, width: 3),
  );

  static BoxDecoration popCard({Color? color, Color? shadowColor, double radius = 12}) => BoxDecoration(
    color: color ?? surfaceColor,
    border: Border.all(color: primaryColor, width: 3),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: popShadow(shadowColor ?? secondaryColor),
  );

  // Gradientes (mantenemos para compatibilidad pero más Pop Art)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryColor, Color(0xFF444444)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondaryColor, Color(0xFFFF66CC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentColor, Color(0xFF3399FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Tema claro
  static ThemeData get lightTheme {
    final textTheme = GoogleFonts.poppinsTextTheme();
    
    return ThemeData(
      useMaterial3: true,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: accentColor,
        surface: surfaceColor,
        error: errorColor,
      ),
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: primaryColor, width: 3),
          borderRadius: BorderRadius.circular(12),
        ),
        color: surfaceColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: primaryColor, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.archivoBlack(
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: secondaryColor,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 3),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 3),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accentColor, width: 3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: errorColor, width: 3),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        hintStyle: GoogleFonts.robotoCondensed(
          color: Colors.grey[500],
          fontWeight: FontWeight.w500,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: backgroundColor,
        selectedItemColor: secondaryColor,
        unselectedItemColor: primaryColor.withOpacity(0.4),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.archivoBlack(
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
        unselectedLabelStyle: GoogleFonts.robotoCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: primaryColor,
        ),
        contentTextStyle: GoogleFonts.poppins(
          fontSize: 15,
          color: Colors.grey[700],
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primaryColor,
        contentTextStyle: GoogleFonts.poppins(
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.grey[100],
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey[200],
        thickness: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 8,
        textStyle: GoogleFonts.poppins(),
      ),
    );
  }

  // Tema oscuro premium
  static ThemeData get darkTheme {
    final textTheme = GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme);
    
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
        primary: secondaryColor,
        secondary: accentColor,
        surface: const Color(0xFF1E1E2E),
        error: errorColor,
      ),
      scaffoldBackgroundColor: const Color(0xFF121218),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        color: const Color(0xFF1E1E2E),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFF1A1A2E),
        selectedItemColor: secondaryColor,
        unselectedItemColor: Colors.grey[600],
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
    );
  }
}
