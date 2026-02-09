import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio para procesar imágenes de vinilos con Gemini AI
/// Usa Edge Functions de Supabase para el procesamiento
class GeminiService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Flag para usar datos mock en desarrollo/pruebas
  /// Cambiar a false para usar la Edge Function real
  static const bool useMock = false;

  /// Cache en memoria: imageUrl → respuesta de Gemini
  static final Map<String, GeminiResponse> _cache = {};

  /// Procesa una imagen de zona para identificar vinilos
  /// Retorna una lista de álbumes detectados (usa caché si existe)
  Future<GeminiResponse> processZoneImage(String imageUrl) async {
    if (useMock) {
      return _getMockResponse();
    }

    // Devolver resultado cacheado si existe para esta URL
    if (_cache.containsKey(imageUrl)) {
      debugPrint('⚡ Cache HIT para: ${imageUrl.substring(imageUrl.length - 30)}');
      return _cache[imageUrl]!;
    }

    final response = await _callEdgeFunction(imageUrl);
    
    // Cachear solo si hay resultados (no errores)
    if (response.hasAlbums) {
      _cache[imageUrl] = response;
      debugPrint('💾 Cacheado: ${response.albums.length} albums para esta URL');
    }
    
    return response;
  }
  
  /// Limpia la caché (útil si se quiere forzar un re-escaneo)
  static void clearCache() {
    _cache.clear();
    debugPrint('🗑️ Cache de Gemini limpiada');
  }

  /// Re-analiza discos específicos con baja confianza
  Future<GeminiResponse> reanalyzeAlbums({
    required String imageUrl,
    required List<int> positions,
    required Map<int, Map<String, double>> spineCoords,
  }) async {
    try {
      // Refrescar sesión para evitar JWT expirado (401)
      try {
        await _supabase.auth.refreshSession();
      } catch (_) {}
      
      debugPrint('Re-analizando ${positions.length} discos dudosos...');
      
      final response = await _supabase.functions.invoke(
        'process-vinyls',
        body: {
          'imageUrl': imageUrl,
          'reanalyzePositions': positions,
          'spineCoords': spineCoords.map((k, v) => MapEntry(k.toString(), v)),
        },
      );

      if (response.status != 200) {
        throw Exception('Error en re-análisis: ${response.status}');
      }

      Map<String, dynamic> data;
      if (response.data is Map<String, dynamic>) {
        data = response.data as Map<String, dynamic>;
      } else if (response.data is String) {
        data = jsonDecode(response.data as String) as Map<String, dynamic>;
      } else {
        data = jsonDecode(jsonEncode(response.data)) as Map<String, dynamic>;
      }

      debugPrint('Re-análisis: ${data['albums']?.length ?? 0} discos mejorados');
      return GeminiResponse.fromJson(data);
    } catch (e) {
      debugPrint('Error en re-análisis: $e');
      rethrow;
    }
  }

  /// Timeout para la llamada a Edge Function (70s — margen sobre los 60s de Supabase)
  static const Duration _edgeFunctionTimeout = Duration(seconds: 70);

  /// Llamada real a la Edge Function de Supabase con timeout y reintento
  Future<GeminiResponse> _callEdgeFunction(String imageUrl, {int attempt = 1}) async {
    try {
      // Refrescar sesión para evitar JWT expirado (401)
      try {
        await _supabase.auth.refreshSession();
      } catch (_) {
        // Ignorar si falla — puede que ya esté vigente
      }
      
      debugPrint('Llamando Edge Function (intento $attempt) con URL: $imageUrl');
      
      final response = await _supabase.functions.invoke(
        'process-vinyls',
        body: {'imageUrl': imageUrl},
      ).timeout(
        _edgeFunctionTimeout,
        onTimeout: () => throw TimeoutException(
          'La petición tardó más de ${_edgeFunctionTimeout.inSeconds}s. '
          'Prueba recortando la foto para que contenga menos discos.',
        ),
      );

      debugPrint('Edge Function status: ${response.status}');
      
      // Convertir data a String de forma segura para debug
      String dataPreview;
      try {
        dataPreview = response.data.toString();
        if (dataPreview.length > 500) {
          dataPreview = '${dataPreview.substring(0, 500)}...';
        }
      } catch (_) {
        dataPreview = 'No se pudo convertir a string';
      }
      debugPrint('Edge Function data preview: $dataPreview');

      if (response.status != 200) {
        // Si es un 504/502 y es primer intento, reintentar una vez
        if (attempt == 1 && (response.status == 504 || response.status == 502)) {
          debugPrint('⚠️ Status ${response.status} — reintentando...');
          return _callEdgeFunction(imageUrl, attempt: 2);
        }
        throw Exception('Error en Edge Function: ${response.status}');
      }

      // Handle different response types
      Map<String, dynamic> data;
      
      if (response.data == null) {
        throw Exception('Respuesta vacía de Edge Function');
      }
      
      if (response.data is Map<String, dynamic>) {
        data = response.data as Map<String, dynamic>;
      } else if (response.data is String) {
        final stringData = response.data as String;
        if (stringData.isEmpty) {
          throw Exception('Respuesta vacía (string)');
        }
        data = jsonDecode(stringData) as Map<String, dynamic>;
      } else {
        // Intentar serializar y deserializar para limpiar
        final jsonString = jsonEncode(response.data);
        data = jsonDecode(jsonString) as Map<String, dynamic>;
      }

      debugPrint('Albums encontrados: ${data['albums']?.length ?? 0}');
      
      // Mostrar info de debug si viene (cuando hay 0 resultados)
      if (data['_debug'] != null) {
        debugPrint('⚠️ DEBUG INFO de Gemini:');
        final debug = data['_debug'];
        debugPrint('  finishReason: ${debug['finishReason']}');
        debugPrint('  parseError: ${debug['parseError']}');
        debugPrint('  responsePreview: ${debug['responsePreview']?.toString().substring(0, 300)}');
      }
      
      return GeminiResponse.fromJson(data);
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Timeout: $e');
      // Si es primer intento, reintentar una vez
      if (attempt == 1) {
        debugPrint('⚠️ Timeout — reintentando (intento 2)...');
        return _callEdgeFunction(imageUrl, attempt: 2);
      }
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('Error llamando a Edge Function: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // Si fue un "Failed to fetch" (timeout en web) y primer intento, reintentar
      if (attempt == 1 && e.toString().contains('Failed to fetch')) {
        debugPrint('⚠️ Failed to fetch (probable timeout) — reintentando...');
        return _callEdgeFunction(imageUrl, attempt: 2);
      }
      rethrow;
    }
  }

  /// Respuesta mock para desarrollo y pruebas
  Future<GeminiResponse> _getMockResponse() async {
    // Simular tiempo de procesamiento de la IA
    await Future.delayed(const Duration(seconds: 2));

    const mockJson = '''
    {
      "albums": [
        {
          "position": 1,
          "artist": "Pink Floyd",
          "title": "The Wall",
          "year": 1979,
          "confidence": 0.95
        },
        {
          "position": 2,
          "artist": "Daft Punk",
          "title": "Discovery",
          "year": 2001,
          "confidence": 0.92
        },
        {
          "position": 3,
          "artist": "Fleetwood Mac",
          "title": "Rumours",
          "year": 1977,
          "confidence": 0.88
        },
        {
          "position": 4,
          "artist": "The Beatles",
          "title": "Abbey Road",
          "year": 1969,
          "confidence": 0.91
        },
        {
          "position": 5,
          "artist": "Michael Jackson",
          "title": "Thriller",
          "year": 1982,
          "confidence": 0.89
        }
      ],
      "processingTime": 1.5,
      "model": "gemini-1.5-pro (mock)"
    }
    ''';

    return GeminiResponse.fromJson(jsonDecode(mockJson));
  }
}

/// Respuesta del procesamiento de Gemini
class GeminiResponse {
  final List<DetectedAlbum> albums;
  final double? processingTime;
  final String? model;
  final String? error;

  GeminiResponse({
    required this.albums,
    this.processingTime,
    this.model,
    this.error,
  });

  factory GeminiResponse.fromJson(Map<String, dynamic> json) {
    return GeminiResponse(
      albums: (json['albums'] as List?)
              ?.map((a) => DetectedAlbum.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      processingTime: (json['processingTime'] as num?)?.toDouble(),
      model: json['model'] as String?,
      error: json['error'] as String?,
    );
  }

  bool get hasError => error != null;
  bool get hasAlbums => albums.isNotEmpty;
}

/// Álbum detectado por Gemini
class DetectedAlbum {
  final int position;
  final String artist;
  final String title;
  final int? year;
  final double? confidence;
  
  /// Coordenadas X normalizadas (0.0 a 1.0) del lomo en la imagen
  final double? spineXStart;
  final double? spineXEnd;
  
  /// Índice de la foto de origen (para multi-foto por zona)
  final int sourceImageIndex;
  
  /// Para UI: si el usuario confirma que es correcto
  bool isConfirmed;

  DetectedAlbum({
    required this.position,
    required this.artist,
    required this.title,
    this.year,
    this.confidence,
    this.spineXStart,
    this.spineXEnd,
    this.sourceImageIndex = 0,
    this.isConfirmed = true, // Por defecto seleccionado
  });

  factory DetectedAlbum.fromJson(Map<String, dynamic> json) {
    return DetectedAlbum(
      position: json['position'] as int? ?? 0,
      artist: json['artist'] as String? ?? 'Unknown Artist',
      title: json['title'] as String? ?? 'Unknown Album',
      year: json['year'] as int?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      spineXStart: (json['spine_x_start'] as num?)?.toDouble(),
      spineXEnd: (json['spine_x_end'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'position': position,
      'artist': artist,
      'title': title,
      'year': year,
      'confidence': confidence,
      'spine_x_start': spineXStart,
      'spine_x_end': spineXEnd,
    };
  }

  /// Porcentaje de confianza formateado
  String get confidencePercent {
    if (confidence == null) return '';
    return '${(confidence! * 100).toInt()}%';
  }

  @override
  String toString() => '$artist - $title${year != null ? ' ($year)' : ''}';
}
