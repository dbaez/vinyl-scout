import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env_config.dart';
import 'services/user_service.dart';
import 'theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'screens/main_navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Debug: mostrar estado de configuración
  if (kDebugMode) {
    EnvConfig.printStatus();
  }

  // Inicialización de Supabase
  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VinylScout',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
        Locale('fr'),
        Locale('it'),
        Locale('de'),
      ],
      locale: _getLocale(),
      home: const AuthWrapper(),
    );
  }

  Locale _getLocale() {
    final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final languageCode = systemLocale.languageCode;
    
    if (['es', 'en', 'fr', 'it', 'de'].contains(languageCode)) {
      return Locale(languageCode);
    }
    return const Locale('en');
  }
}

/// Wrapper que escucha cambios de autenticación
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    // Dar tiempo a Supabase para recuperar la sesión de localStorage
    _checkInitialSession();
  }

  Future<void> _checkInitialSession() async {
    // Esperar a que el primer evento de auth llegue
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Mientras inicializa, mostrar splash (evita flash de login)
        if (_isInitializing && !snapshot.hasData) {
          return Scaffold(
            backgroundColor: const Color(0xFF0D0D0D),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SpinningVinylLoader(size: 80),
                ],
              ),
            ),
          );
        }

        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;
        
        if (session != null) {
          return const AuthenticatedWrapper();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

/// Wrapper para usuarios autenticados - sincroniza datos
class AuthenticatedWrapper extends StatefulWidget {
  const AuthenticatedWrapper({super.key});

  @override
  State<AuthenticatedWrapper> createState() => _AuthenticatedWrapperState();
}

class _AuthenticatedWrapperState extends State<AuthenticatedWrapper> {
  final UserService _userService = UserService();
  bool _isSyncing = true;

  @override
  void initState() {
    super.initState();
    _syncUser();
  }

  Future<void> _syncUser() async {
    await _userService.syncUserFromAuth();
    if (mounted) {
      setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSyncing) {
      return Scaffold(
        backgroundColor: AppTheme.primaryColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SpinningVinylLoader(size: 80),
              const SizedBox(height: 20),
              Text(
                AppLocalizations.of(context)?.loading ?? 'Loading...',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    return const MainNavigation();
  }
}

/// Placeholder temporal para la pantalla principal
class HomeScreenPlaceholder extends StatelessWidget {
  const HomeScreenPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.appTitle ?? 'VinylScout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.album, size: 100, color: AppTheme.primaryColor),
            const SizedBox(height: 24),
            Text(
              '¡Bienvenido a ${l10n?.appTitle ?? "VinylScout"}!',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              l10n?.discoverYourCollection ?? 'Discover your collection',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            const Text('🚧 App en construcción 🚧'),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.album),
            label: l10n?.collection ?? 'Collection',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.shelves),
            label: l10n?.shelves ?? 'Shelves',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.qr_code_scanner),
            label: l10n?.scan ?? 'Scan',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.playlist_play),
            label: l10n?.playlists ?? 'Playlists',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: l10n?.profile ?? 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Pantalla de Login con Google
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    try {
      setState(() => _isLoading = true);
      
      // Determinar redirect URL
      String redirectUrl;
      if (kIsWeb) {
        final currentHost = Uri.base.host;
        if (currentHost.contains('github.io')) {
          // TODO: Cambiar a tu URL de producción
          redirectUrl = 'https://tuusuario.github.io/vinyl-scout/';
        } else {
          redirectUrl = Uri.base.origin;
        }
      } else {
        redirectUrl = 'com.vinylscout.app://auth/callback';
      }
      
      debugPrint('OAuth redirect URL: $redirectUrl');
      
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
    } catch (e) {
      debugPrint("Error en OAuth: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: AppTheme.backgroundColor,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Disco de vinilo animado (girando) con borde Pop Art
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primaryColor, width: 4),
                      boxShadow: AppTheme.popShadow(AppTheme.secondaryColor, offset: 6),
                    ),
                    child: AnimatedBuilder(
                      animation: _spinController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _spinController.value * 2 * pi,
                          child: child,
                        );
                      },
                      child: _buildVinylDisc(),
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // Título — Pop Art bold
                  Text(
                    "LET'S SPIN",
                    style: GoogleFonts.archivoBlack(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryColor,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Slogan — texto simple, sin aspecto de botón
                  Text(
                    "— dust off the needle —",
                    style: GoogleFonts.robotoCondensed(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor.withOpacity(0.4),
                      letterSpacing: 2,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 64),
                  
                  // Botón de login — Pop Art style
                  if (_isLoading)
                    const SpinningVinylLoader(size: 56)
                  else
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 320),
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor,
                        border: Border.all(color: AppTheme.primaryColor, width: 3),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: AppTheme.popShadow(AppTheme.primaryColor, offset: 5),
                      ),
                      child: ElevatedButton(
                        onPressed: _handleSignIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppTheme.primaryColor, width: 2),
                              ),
                              child: const Icon(Icons.g_mobiledata, size: 20, color: Colors.red),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                AppLocalizations.of(context)?.continueWithGoogle ?? 'CONTINUE WITH GOOGLE',
                                style: GoogleFonts.archivoBlack(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 48),
                  
                  // Features — Pop Art chips
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildFeatureChip(Icons.photo_camera, 'SCAN'),
                      const SizedBox(width: 12),
                      _buildFeatureChip(Icons.library_music, 'ORGANIZE'),
                      const SizedBox(width: 12),
                      _buildFeatureChip(Icons.play_arrow_rounded, 'PLAY'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVinylDisc() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Disco exterior
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.grey[900]!,
                Colors.black,
                Colors.grey[850]!,
                Colors.black,
              ],
              stops: const [0.0, 0.3, 0.6, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: AppTheme.secondaryColor.withOpacity(0.2),
                blurRadius: 40,
                spreadRadius: -5,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Surcos del vinilo
              ...List.generate(8, (index) {
                return Container(
                  width: 160 - (index * 16),
                  height: 160 - (index * 16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey[800]!.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        // Etiqueta central
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.secondaryColor,
                AppTheme.secondaryColor.withOpacity(0.7),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.secondaryColor.withOpacity(0.3),
                blurRadius: 10,
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.music_note,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.primaryColor, width: 2.5),
        boxShadow: AppTheme.popShadow(AppTheme.canaryYellow, offset: 3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.archivoBlack(
              color: AppTheme.primaryColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget reutilizable de vinilo girando como indicador de carga
class SpinningVinylLoader extends StatefulWidget {
  final double size;
  const SpinningVinylLoader({super.key, this.size = 64});

  @override
  State<SpinningVinylLoader> createState() => _SpinningVinylLoaderState();
}

class _SpinningVinylLoaderState extends State<SpinningVinylLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final labelSize = s * 0.33;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.rotate(
        angle: _controller.value * 2 * pi,
        child: child,
      ),
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.grey[900]!,
                    Colors.black,
                    Colors.grey[850]!,
                    Colors.black,
                  ],
                  stops: const [0.0, 0.3, 0.6, 1.0],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: List.generate(5, (i) {
                  final d = s * 0.88 - (i * s * 0.14);
                  return Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.grey[800]!.withOpacity(0.5),
                        width: 0.8,
                      ),
                    ),
                  );
                }),
              ),
            ),
            Container(
              width: labelSize,
              height: labelSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.secondaryColor,
                    AppTheme.secondaryColor.withOpacity(0.7),
                  ],
                ),
              ),
              child: Center(
                child: Icon(Icons.music_note, color: Colors.white, size: labelSize * 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
