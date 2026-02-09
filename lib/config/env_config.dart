/// Configuración de variables de entorno para VinylScout
/// 
/// Las variables se pasan durante la compilación usando --dart-define:
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=xxx \
///   --dart-define=SUPABASE_ANON_KEY=xxx \
///   --dart-define=DISCOGS_CONSUMER_KEY=xxx \
///   --dart-define=DISCOGS_CONSUMER_SECRET=xxx
class EnvConfig {
  // Supabase
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  // Discogs API (para sincronización de colección)
  static const String discogsConsumerKey = String.fromEnvironment(
    'DISCOGS_CONSUMER_KEY',
    defaultValue: '',
  );
  
  static const String discogsConsumerSecret = String.fromEnvironment(
    'DISCOGS_CONSUMER_SECRET',
    defaultValue: '',
  );

  // Google Gemini (para recomendaciones con IA)
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  // Amazon Affiliates
  static const String amazonTagEs = String.fromEnvironment(
    'AMAZON_TAG_ES',
    defaultValue: 'vinylscout-21', // placeholder — reemplazar con tu tag real
  );
  static const String amazonTagCom = String.fromEnvironment(
    'AMAZON_TAG_COM',
    defaultValue: 'vinylscout-20', // placeholder — reemplazar con tu tag real
  );

  /// Genera un enlace de búsqueda de Amazon con tag de afiliado.
  /// Detecta la región por el locale del dispositivo.
  static String amazonSearchUrl({
    required String artist,
    required String album,
    required String locale,
  }) {
    // Limpiar y construir query: solo letras, números y espacios
    final raw = '$artist $album'.replaceAll(RegExp(r'[^\w\s]', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final encoded = Uri.encodeComponent(raw);
    if (locale.startsWith('es')) {
      return 'https://www.amazon.es/s?k=$encoded&tag=$amazonTagEs';
    }
    return 'https://www.amazon.com/s?k=$encoded&tag=$amazonTagCom';
  }

  /// Verifica si todas las variables requeridas están configuradas
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty;

  /// Lista de variables faltantes
  static List<String> getMissingVariables() {
    final missing = <String>[];
    if (supabaseUrl.isEmpty) missing.add('SUPABASE_URL');
    if (supabaseAnonKey.isEmpty) missing.add('SUPABASE_ANON_KEY');
    return missing;
  }

  /// Imprime el estado de configuración (para debug)
  static void printStatus() {
    print('=== VinylScout EnvConfig Status ===');
    print('SUPABASE_URL: ${supabaseUrl.isNotEmpty ? "✓ configurado" : "✗ falta"}');
    print('SUPABASE_ANON_KEY: ${supabaseAnonKey.isNotEmpty ? "✓ configurado" : "✗ falta"}');
    print('DISCOGS_CONSUMER_KEY: ${discogsConsumerKey.isNotEmpty ? "✓ configurado" : "✗ falta"}');
    print('DISCOGS_CONSUMER_SECRET: ${discogsConsumerSecret.isNotEmpty ? "✓ configurado" : "✗ falta"}');
    print('GEMINI_API_KEY: ${geminiApiKey.isNotEmpty ? "✓ configurado" : "✗ falta"}');
    print('===================================');
  }
}
