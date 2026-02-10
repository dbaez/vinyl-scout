import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/env_config.dart';

/// Servicio para buscar información de álbumes en Discogs
/// Los tokens de Discogs NO expiran
class DiscogsService {
  static const String _baseUrl = 'https://api.discogs.com';
  static const String _userAgent = 'VinylScout/1.0';
  
  // Token de Discogs - configurar via variable de entorno
  // Fallback para desarrollo si la variable no está configurada
  static String get _token {
    const envToken = String.fromEnvironment('DISCOGS_TOKEN', defaultValue: '');
    if (envToken.isNotEmpty) return envToken;
    // Fallback para desarrollo local — configurar via --dart-define=DISCOGS_TOKEN=xxx
    return '';
  }

  /// Ejecuta búsqueda: Edge Function en web, directo en móvil
  Future<http.Response> _search(String query, {int perPage = 8}) async {
    if (kIsWeb) {
      // En web: usar Supabase Edge Function como proxy (evita CORS)
      final edgeUrl = '${EnvConfig.supabaseUrl}/functions/v1/discogs-proxy?q=${Uri.encodeComponent(query)}&type=release&per_page=$perPage';
      debugPrint('Discogs search (edge function): $query');
      return http.get(
        Uri.parse(edgeUrl),
        headers: {
          'Authorization': 'Bearer ${EnvConfig.supabaseAnonKey}',
          'Content-Type': 'application/json',
        },
      );
    }
    // En móvil/desktop: llamada directa a Discogs
    final uri = Uri.parse('$_baseUrl/database/search').replace(
      queryParameters: {
        'q': query,
        'type': 'release',
        'per_page': '$perPage',
      },
    );
    return http.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        if (_token.isNotEmpty) 'Authorization': 'Discogs token=$_token',
      },
    );
  }

  /// Busca un álbum en Discogs y retorna la información incluyendo portada
  Future<DiscogsAlbum?> searchAlbum({
    required String artist,
    required String title,
  }) async {
    try {
      final cleanArtist = _cleanSearchTerm(artist);
      final cleanTitle = _cleanSearchTerm(title);
      
      if (cleanArtist.isEmpty && cleanTitle.isEmpty) {
        return null;
      }

      final query = '$cleanArtist $cleanTitle';

      debugPrint('Discogs search: $query (token: ${_token.isNotEmpty ? "✓" : "✗"})');

      final response = await _search(query, perPage: 5);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          // Buscar el mejor resultado con portada
          for (final result in results) {
            final coverImage = result['cover_image'] as String?;
            if (coverImage != null && 
                coverImage.isNotEmpty && 
                !coverImage.contains('spacer.gif')) {
              return DiscogsAlbum.fromJson(result as Map<String, dynamic>);
            }
          }
          // Si ninguno tiene portada válida, usar el primero
          return DiscogsAlbum.fromJson(results.first as Map<String, dynamic>);
        }
      } else if (response.statusCode == 429) {
        // Rate limited - esperar y reintentar
        debugPrint('Discogs rate limited, waiting...');
        await Future.delayed(const Duration(seconds: 2));
        return searchAlbum(artist: artist, title: title);
      } else {
        debugPrint('Discogs error: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error searching Discogs: $e');
    }
    return null;
  }

  /// Busca múltiples álbumes en paralelo (con rate limiting)
  Future<List<DiscogsAlbum?>> searchMultipleAlbums(
    List<AlbumSearchRequest> requests,
  ) async {
    final results = <DiscogsAlbum?>[];
    
    for (int i = 0; i < requests.length; i++) {
      final request = requests[i];
      
      // Rate limiting: máximo 1 request por segundo para tier gratuito
      if (i > 0) {
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      
      final result = await searchAlbum(
        artist: request.artist,
        title: request.title,
      );
      results.add(result);
    }
    
    return results;
  }

  /// Busca por query general y retorna múltiples resultados
  Future<List<DiscogsAlbum>> searchMultipleResults(String query, {int limit = 8}) async {
    try {
      final cleanQuery = _cleanSearchTerm(query);
      
      if (cleanQuery.isEmpty) {
        return [];
      }
      debugPrint('Discogs multi-search: $cleanQuery');

      final response = await _search(cleanQuery, perPage: limit);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          return results
              .map((r) => DiscogsAlbum.fromJson(r as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error in multi-search: $e');
    }
    return [];
  }

  /// Búsqueda avanzada con filtros (format, year, genre, style, sort).
  /// Siempre envía `q` (usando genre/style como fallback) para compatibilidad
  /// con versiones del proxy que lo requieran.
  Future<http.Response> _searchAdvanced({
    String? query,
    String? format,
    String? year,
    String? genre,
    String? style,
    String sort = 'year',
    String sortOrder = 'desc',
    int perPage = 10,
  }) async {
    // Garantizar que siempre haya un q (el proxy puede requerirlo)
    final effectiveQuery = (query != null && query.isNotEmpty)
        ? query
        : (genre ?? style ?? '');

    final params = <String, String>{
      'q': effectiveQuery,
      'type': 'release',
      'per_page': '$perPage',
      'sort': sort,
      'sort_order': sortOrder,
    };
    if (format != null) params['format'] = format;
    if (year != null) params['year'] = year;
    if (genre != null) params['genre'] = genre;
    if (style != null) params['style'] = style;

    if (kIsWeb) {
      final edgeUrl = '${EnvConfig.supabaseUrl}/functions/v1/discogs-proxy?${Uri(queryParameters: params).query}';
      debugPrint('Discogs advanced search (edge): q=$effectiveQuery genre=$genre year=$year format=$format');
      return http.get(
        Uri.parse(edgeUrl),
        headers: {
          'Authorization': 'Bearer ${EnvConfig.supabaseAnonKey}',
          'Content-Type': 'application/json',
        },
      );
    }
    // Móvil/desktop: directo a Discogs
    final uri = Uri.parse('$_baseUrl/database/search').replace(queryParameters: params);
    return http.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        if (_token.isNotEmpty) 'Authorization': 'Discogs token=$_token',
      },
    );
  }

  /// Busca lanzamientos recientes de vinilo relevantes para el usuario.
  ///
  /// Estrategia en 2 fases:
  /// 1. Buscar nuevos vinilos de los artistas favoritos del usuario
  /// 2. Completar con búsquedas por estilos específicos (no géneros amplios)
  ///
  /// [topArtists] - Artistas con más discos en la colección.
  /// [topStyles] - Estilos específicos (ej. Post-Punk, Shoegaze, no "Rock").
  /// [existingAlbums] - Set de "artist|title" para excluir discos que ya tiene.
  Future<List<DiscogsAlbum>> searchNewReleases({
    required List<String> topArtists,
    required List<String> topStyles,
    Set<String>? existingAlbums,
    int limit = 10,
  }) async {
    final results = <DiscogsAlbum>[];
    final seen = <String>{};
    final currentYear = DateTime.now().year;
    final prevYear = currentYear - 1;

    // ── Fase 1: Vinilos de artistas favoritos que NO tienes ──
    final artistsToSearch = topArtists.take(4).toList();
    for (final artist in artistsToSearch) {
      try {
        final response = await _searchAdvanced(
          query: artist,
          format: 'Vinyl',
          // Sin filtro de año: cualquier disco que no tengas
          sort: 'year',
          sortOrder: 'desc',
          perPage: 8,
        );

        _addValidResults(response, results, seen, existingAlbums, limit);
        if (results.length >= limit) return results;

        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (e) {
        debugPrint('Error searching releases for artist $artist: $e');
      }
    }

    // ── Fase 2: Por estilos específicos ──
    for (final style in topStyles) {
      if (results.length >= limit) break;
      try {
        final response = await _searchAdvanced(
          style: style,
          format: 'Vinyl',
          year: '$currentYear',
          sort: 'year',
          sortOrder: 'desc',
          perPage: 6,
        );

        _addValidResults(response, results, seen, existingAlbums, limit);
        if (results.length >= limit) return results;

        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (e) {
        debugPrint('Error searching releases for style $style: $e');
      }
    }

    return results;
  }

  /// Helper: parsea la respuesta y añade resultados válidos (no duplicados, con imagen, no en colección)
  void _addValidResults(
    http.Response response,
    List<DiscogsAlbum> results,
    Set<String> seen,
    Set<String>? existingAlbums,
    int limit,
  ) {
    if (response.statusCode != 200) return;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['results'] as List?;
    if (items == null) return;

    for (final item in items) {
      final album = DiscogsAlbum.fromJson(item as Map<String, dynamic>);
      final key = '${album.artist.toLowerCase()}|${album.title.toLowerCase()}';

      if (existingAlbums != null && existingAlbums.contains(key)) continue;
      if (seen.contains(key)) continue;
      if (!album.hasImage) continue;

      seen.add(key);
      results.add(album);
      if (results.length >= limit) return;
    }
  }

  /// Busca el release de vinilo más completo (LP) para un artista/título.
  /// Prioriza releases con formato Vinyl y más tracks.
  Future<DiscogsAlbum?> searchVinylRelease({
    required String artist,
    required String title,
  }) async {
    try {
      final cleanArtist = _cleanSearchTerm(artist);
      final cleanTitle = _cleanSearchTerm(title);
      if (cleanArtist.isEmpty && cleanTitle.isEmpty) return null;

      final query = '$cleanArtist $cleanTitle';
      debugPrint('Discogs vinyl search: $query');

      // Buscar con formato Vinyl para mejor match
      final response = await _search(query, perPage: 10);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          // Priorizar: 1) formato Vinyl/LP, 2) más páginas (= más tracks)
          DiscogsAlbum? bestVinyl;
          DiscogsAlbum? fallback;

          for (final result in results) {
            final formatList = result['format'] as List?;
            final formats = formatList?.map((f) => f.toString().toLowerCase()).toList() ?? [];
            final coverImage = result['cover_image'] as String?;
            final hasCover = coverImage != null && coverImage.isNotEmpty && !coverImage.contains('spacer.gif');

            if (!hasCover) continue;

            final album = DiscogsAlbum.fromJson(result as Map<String, dynamic>);

            // Es un vinilo LP?
            final isVinyl = formats.any((f) => f.contains('vinyl') || f.contains('lp'));

            if (isVinyl) {
              if (bestVinyl == null) {
                bestVinyl = album;
              }
            } else if (fallback == null) {
              fallback = album;
            }
          }

          return bestVinyl ?? fallback;
        }
      }
    } catch (e) {
      debugPrint('Error searching vinyl release: $e');
    }
    return null;
  }

  /// Obtiene el tracklist de un release de Discogs por su ID.
  /// Retorna una lista de maps con {position, title, duration} solo para tracks reales.
  Future<List<Map<String, dynamic>>?> fetchReleaseTracklist(int discogsId) async {
    try {
      http.Response response;

      if (kIsWeb) {
        // En web: usar proxy Edge Function
        final edgeUrl = '${EnvConfig.supabaseUrl}/functions/v1/discogs-proxy?release_id=$discogsId';
        debugPrint('Discogs release (edge): $discogsId');
        response = await http.get(
          Uri.parse(edgeUrl),
          headers: {
            'Authorization': 'Bearer ${EnvConfig.supabaseAnonKey}',
            'Content-Type': 'application/json',
          },
        );
      } else {
        // En móvil/desktop: directo a Discogs
        final uri = Uri.parse('$_baseUrl/releases/$discogsId');
        response = await http.get(
          uri,
          headers: {
            'User-Agent': _userAgent,
            if (_token.isNotEmpty) 'Authorization': 'Discogs token=$_token',
          },
        );
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tracklist = data['tracklist'] as List?;

        if (tracklist != null && tracklist.isNotEmpty) {
          // Filtrar solo tracks reales (type_ == "track" o sin type_)
          return tracklist
              .where((t) {
                final type = t['type_'] as String? ?? 'track';
                return type == 'track';
              })
              .map((t) => <String, dynamic>{
                    'position': t['position'] as String? ?? '',
                    'title': t['title'] as String? ?? '',
                    'duration': t['duration'] as String?,
                  })
              .toList();
        }
      } else {
        debugPrint('Discogs release error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching release tracklist: $e');
    }
    return null;
  }

  /// Limpia un término de búsqueda
  String _cleanSearchTerm(String term) {
    return term
        // Preservar letras Unicode (acentos, ñ, etc.), números y espacios
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }
}

/// Request para búsqueda de álbum
class AlbumSearchRequest {
  final String artist;
  final String title;
  final int index;

  AlbumSearchRequest({
    required this.artist,
    required this.title,
    required this.index,
  });
}

/// Resultado de búsqueda en Discogs
class DiscogsAlbum {
  final int id;
  final String title;
  final String artist;
  final String? coverImage;
  final String? thumb;
  final String? yearString;
  final String? country;
  final String? label;
  final String? catno;
  final String? format;
  final String? resourceUrl;
  final List<String> genres;
  final List<String> styles;

  DiscogsAlbum({
    required this.id,
    required this.title,
    required this.artist,
    this.coverImage,
    this.thumb,
    this.yearString,
    this.country,
    this.label,
    this.catno,
    this.format,
    this.resourceUrl,
    this.genres = const [],
    this.styles = const [],
  });

  /// Año como int (null si no se puede parsear)
  int? get year => yearString != null ? int.tryParse(yearString!) : null;

  factory DiscogsAlbum.fromJson(Map<String, dynamic> json) {
    // El título de Discogs viene como "Artista - Título"
    final fullTitle = json['title'] as String? ?? '';
    String artist = 'Desconocido';
    String title = fullTitle;
    
    if (fullTitle.contains(' - ')) {
      final parts = fullTitle.split(' - ');
      artist = parts[0].trim();
      title = parts.sublist(1).join(' - ').trim();
    }
    
    return DiscogsAlbum(
      id: json['id'] as int? ?? 0,
      title: title.isNotEmpty ? title : 'Sin título',
      artist: artist,
      coverImage: json['cover_image'] as String?,
      thumb: json['thumb'] as String?,
      yearString: json['year'] as String?,
      country: json['country'] as String?,
      label: (json['label'] as List?)?.firstOrNull as String?,
      catno: json['catno'] as String?,
      format: (json['format'] as List?)?.firstOrNull as String?,
      resourceUrl: json['resource_url'] as String?,
      genres: json['genre'] != null
          ? List<String>.from(json['genre'] as List)
          : [],
      styles: json['style'] != null
          ? List<String>.from(json['style'] as List)
          : [],
    );
  }

  /// URL de imagen con proxy CORS para web.
  /// En web: usa la Edge Function discogs-proxy como proxy de imágenes.
  /// En móvil/desktop: URL directa de Discogs.
  String? get imageUrl {
    final url = coverImage ?? thumb;
    if (url == null || url.isEmpty) return null;
    return proxyUrlForWeb(url);
  }

  /// URL original sin proxy (para móvil o para guardar en BD)
  String? get originalImageUrl => coverImage ?? thumb;

  /// Extrae la URL original de una URL proxy (wsrv.nl legacy o Edge Function)
  static String unwrapProxyUrl(String url) {
    // Legacy: wsrv.nl proxy
    if (url.startsWith('https://wsrv.nl/')) {
      try {
        final uri = Uri.parse(url);
        final original = uri.queryParameters['url'];
        if (original != null && original.isNotEmpty) {
          return original;
        }
      } catch (_) {}
    }
    // Edge Function proxy
    if (url.contains('/functions/v1/discogs-proxy') && url.contains('image_url=')) {
      try {
        final uri = Uri.parse(url);
        final original = uri.queryParameters['image_url'];
        if (original != null && original.isNotEmpty) {
          return original;
        }
      } catch (_) {}
    }
    return url;
  }

  /// Envuelve una URL de imagen con proxy CORS para web.
  /// Usa la Edge Function de Supabase como proxy (fiable, sin terceros).
  /// En móvil/desktop devuelve la URL sin modificar.
  static String? proxyUrlForWeb(String? url) {
    if (url == null || url.isEmpty) return url;
    if (!kIsWeb) return url;
    // Ya está proxied (Edge Function o wsrv.nl legacy)
    if (url.contains('/functions/v1/discogs-proxy')) return url;
    if (url.startsWith('https://wsrv.nl/')) return url;
    // URLs de Supabase Storage no necesitan proxy (tienen CORS)
    if (url.contains('supabase.co/storage')) return url;
    // Proxy via Edge Function propia
    return '${EnvConfig.supabaseUrl}/functions/v1/discogs-proxy?image_url=${Uri.encodeComponent(url)}';
  }

  /// Verifica si tiene imagen disponible
  bool get hasImage {
    final url = coverImage ?? thumb;
    return url != null && url.isNotEmpty && !url.contains('spacer.gif');
  }
}
