import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/album_model.dart';
import 'gemini_service.dart';
import 'discogs_service.dart';
import 'storage_service.dart';

/// Servicio para gestionar álbumes/vinilos
class AlbumService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final StorageService _storageService = StorageService();

  /// Set de albumIds que ya se están migrando (evitar duplicados)
  static final Set<String> _migrating = {};

  /// Obtiene todos los álbumes del usuario
  Future<List<AlbumModel>> getUserAlbums(String userId) async {
    try {
      final response = await _supabase
          .from('albums')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final albums = (response as List)
          .map((json) => AlbumModel.fromJson(json))
          .toList();
      
      // Migrar carátulas de Discogs a Storage en background
      _migrateCoversToStorage(albums);
      
      return albums;
    } catch (e) {
      debugPrint('Error obteniendo álbumes: $e');
      return [];
    }
  }

  /// Obtiene todos los álbumes del usuario con información de ubicación
  /// (estantería y zona donde está guardado)
  Future<List<AlbumWithLocation>> getUserAlbumsWithLocation(String userId) async {
    try {
      final response = await _supabase
          .from('albums')
          .select('''
            *,
            shelf_zones!zone_id (
              id,
              zone_index,
              shelves!shelf_id (
                id,
                name
              )
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List).map((json) {
        final album = AlbumModel.fromJson(json);
        
        String? shelfName;
        String? shelfId;
        int? zoneIndex;
        
        if (json['shelf_zones'] != null) {
          final zoneData = json['shelf_zones'];
          zoneIndex = zoneData['zone_index'] as int?;
          
          if (zoneData['shelves'] != null) {
            shelfName = zoneData['shelves']['name'] as String?;
            shelfId = zoneData['shelves']['id'] as String?;
          }
        }
        
        return AlbumWithLocation(
          album: album,
          shelfName: shelfName,
          shelfId: shelfId,
          zoneIndex: zoneIndex != null ? zoneIndex + 1 : null, // +1 para mostrar 1-based
        );
      }).toList();
    } catch (e) {
      debugPrint('Error obteniendo álbumes con ubicación: $e');
      return [];
    }
  }

  /// Obtiene álbumes de una zona específica (ordenados por posición 1→N)
  Future<List<AlbumModel>> getZoneAlbums(String zoneId) async {
    try {
      final response = await _supabase
          .from('albums')
          .select()
          .eq('zone_id', zoneId)
          .order('position_index', ascending: true);

      final albums = (response as List)
          .map((json) => AlbumModel.fromJson(json))
          .toList();
      
      // Migrar carátulas de Discogs a Storage en background
      _migrateCoversToStorage(albums);
      
      return albums;
    } catch (e) {
      debugPrint('Error obteniendo álbumes de zona: $e');
      return [];
    }
  }

  /// Obtiene la posición máxima de los álbumes en una zona
  Future<int> getMaxPositionInZone(String zoneId) async {
    try {
      final result = await _supabase
          .from('albums')
          .select('position_index')
          .eq('zone_id', zoneId)
          .order('position_index', ascending: false)
          .limit(1);

      if ((result as List).isNotEmpty && result[0]['position_index'] != null) {
        return result[0]['position_index'] as int;
      }
      return 0;
    } catch (e) {
      debugPrint('Error obteniendo max position: $e');
      return 0;
    }
  }

  /// Migración lazy: persiste carátulas de Discogs a Supabase Storage.
  /// Se ejecuta en background (fire-and-forget) al cargar albums.
  /// Solo migra las que aún apuntan a Discogs, una sola vez por sesión.
  void _migrateCoversToStorage(List<AlbumModel> albums) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    for (final album in albums) {
      final url = album.coverUrl;
      if (url == null || url.isEmpty) continue;
      // Ya está en Storage — no necesita migración
      if (url.contains('supabase.co/storage')) continue;
      // Ya se está migrando en esta sesión
      if (_migrating.contains(album.id)) continue;

      _migrating.add(album.id);

      // Extraer URL original (sin proxy wrapper)
      final originalUrl = DiscogsAlbum.unwrapProxyUrl(url);

      _storageService.persistCoverImage(
        imageUrl: originalUrl,
        userId: userId,
        albumId: album.id,
      ).then((storageUrl) {
        if (storageUrl != null) {
          updateAlbumCover(album.id, storageUrl);
          debugPrint('✓ Migrada carátula: ${album.artist} - ${album.title}');
        }
      }).catchError((e) {
        _migrating.remove(album.id); // Permitir reintento en próxima carga
        debugPrint('⚠ Error migrando carátula ${album.id}: $e');
      });
    }
  }

  /// Actualiza la URL de la carátula de un álbum
  Future<bool> updateAlbumCover(String albumId, String coverUrl) async {
    try {
      await _supabase
          .from('albums')
          .update({'cover_url': coverUrl})
          .eq('id', albumId);
      return true;
    } catch (e) {
      debugPrint('Error actualizando carátula: $e');
      return false;
    }
  }

  /// Crea un nuevo álbum
  Future<AlbumModel?> createAlbum({
    required String userId,
    required String title,
    required String artist,
    String? zoneId,
    int? year,
    int? positionIndex,
    String? coverUrl,
    List<String>? genres,
    List<String>? styles,
  }) async {
    try {
      final response = await _supabase
          .from('albums')
          .insert({
            'user_id': userId,
            'zone_id': zoneId,
            'title': title,
            'artist': artist,
            'year': year,
            'position_index': positionIndex,
            'cover_url': coverUrl,
            'genres': genres ?? [],
            'styles': styles ?? [],
          })
          .select()
          .single();

      return AlbumModel.fromJson(response);
    } catch (e) {
      debugPrint('Error creando álbum: $e');
      return null;
    }
  }

  /// Crea múltiples álbumes a partir de resultados de Gemini
  /// Retorna la cantidad de álbumes creados exitosamente
  Future<int> createAlbumsFromGemini({
    required String userId,
    required String zoneId,
    required List<DetectedAlbum> albums,
  }) async {
    int created = 0;

    for (final album in albums) {
      if (!album.isConfirmed) continue; // Solo guardar los confirmados

      try {
        await _supabase.from('albums').insert({
          'user_id': userId,
          'zone_id': zoneId,
          'title': album.title,
          'artist': album.artist,
          'year': album.year,
          'position_index': album.position,
          'genres': [],
          'styles': [],
        });
        created++;
      } catch (e) {
        debugPrint('Error creando álbum ${album.title}: $e');
      }
    }

    return created;
  }

  /// Actualiza un álbum existente
  Future<bool> updateAlbum(String albumId, Map<String, dynamic> updates) async {
    try {
      await _supabase
          .from('albums')
          .update(updates)
          .eq('id', albumId);
      return true;
    } catch (e) {
      debugPrint('Error actualizando álbum: $e');
      return false;
    }
  }

  /// Elimina un álbum y reindeza la zona si pertenecía a una
  Future<bool> deleteAlbum(String albumId) async {
    try {
      // Obtener zone_id antes de borrar
      final albumData = await _supabase
          .from('albums')
          .select('zone_id')
          .eq('id', albumId)
          .maybeSingle();

      final zoneId = albumData?['zone_id'] as String?;

      // Borrar el álbum
      await _supabase
          .from('albums')
          .delete()
          .eq('id', albumId);

      // Reindexar la zona si tenía una asignada
      if (zoneId != null) {
        await reindexZoneAlbums(zoneId);
      }

      return true;
    } catch (e) {
      debugPrint('Error eliminando álbum: $e');
      return false;
    }
  }

  /// Reindexa las posiciones de los álbumes en una zona (1, 2, 3...)
  Future<void> reindexZoneAlbums(String zoneId) async {
    try {
      final albums = await _supabase
          .from('albums')
          .select('id, position_index')
          .eq('zone_id', zoneId)
          .order('position_index', ascending: true);

      for (int i = 0; i < (albums as List).length; i++) {
        final album = albums[i];
        final newIndex = i + 1;
        if (album['position_index'] != newIndex) {
          await _supabase
              .from('albums')
              .update({'position_index': newIndex})
              .eq('id', album['id']);
        }
      }
      debugPrint('Zona $zoneId reindexada: ${albums.length} álbumes');
    } catch (e) {
      debugPrint('Error reindexando zona: $e');
    }
  }

  /// Desplaza los álbumes de una zona a partir de una posición (incrementa position_index en 1)
  /// para hacer hueco a un nuevo álbum en esa posición
  Future<void> shiftAlbumsFromPosition(String zoneId, int fromPosition) async {
    try {
      // Obtener álbumes con position_index >= fromPosition
      final albums = await _supabase
          .from('albums')
          .select('id, position_index')
          .eq('zone_id', zoneId)
          .gte('position_index', fromPosition)
          .order('position_index', ascending: false); // De mayor a menor para evitar conflictos

      for (final album in (albums as List)) {
        final currentPos = album['position_index'] as int;
        await _supabase
            .from('albums')
            .update({'position_index': currentPos + 1})
            .eq('id', album['id']);
      }
      debugPrint('Zona $zoneId: desplazados álbumes desde posición $fromPosition');
    } catch (e) {
      debugPrint('Error desplazando álbumes: $e');
    }
  }

  /// Busca álbumes por texto
  Future<List<AlbumModel>> searchAlbums(String userId, String query) async {
    try {
      final response = await _supabase
          .from('albums')
          .select()
          .eq('user_id', userId)
          .or('title.ilike.%$query%,artist.ilike.%$query%')
          .order('artist')
          .limit(50);

      return (response as List)
          .map((json) => AlbumModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error buscando álbumes: $e');
      return [];
    }
  }

  /// Obtiene estadísticas de la colección
  Future<Map<String, dynamic>> getCollectionStats(String userId) async {
    try {
      final albums = await getUserAlbums(userId);
      
      final uniqueArtists = albums.map((a) => a.artist).toSet();
      final albumsWithYear = albums.where((a) => a.year != null);
      final oldestYear = albumsWithYear.isNotEmpty 
          ? albumsWithYear.map((a) => a.year!).reduce((a, b) => a < b ? a : b)
          : null;
      final newestYear = albumsWithYear.isNotEmpty
          ? albumsWithYear.map((a) => a.year!).reduce((a, b) => a > b ? a : b)
          : null;

      return {
        'totalAlbums': albums.length,
        'uniqueArtists': uniqueArtists.length,
        'oldestYear': oldestYear,
        'newestYear': newestYear,
        'inZones': albums.where((a) => a.isInZone).length,
        'unassigned': albums.where((a) => !a.isInZone).length,
      };
    } catch (e) {
      debugPrint('Error obteniendo estadísticas: $e');
      return {};
    }
  }

  /// Enriquece álbumes sin géneros/estilos buscando en Discogs
  /// Retorna cuántos álbumes fueron actualizados
  Future<int> enrichAlbumsWithGenres(String userId, {Function(int current, int total)? onProgress}) async {
    final DiscogsService discogsService = DiscogsService();
    int updated = 0;
    
    try {
      // Obtener álbumes sin géneros
      final response = await _supabase
          .from('albums')
          .select('id, artist, title, genres, styles')
          .eq('user_id', userId);

      final albums = (response as List).where((json) {
        final genres = json['genres'] as List?;
        final styles = json['styles'] as List?;
        return (genres == null || genres.isEmpty) && (styles == null || styles.isEmpty);
      }).toList();

      debugPrint('Enriqueciendo ${albums.length} álbumes sin géneros...');

      for (int i = 0; i < albums.length; i++) {
        final album = albums[i];
        onProgress?.call(i + 1, albums.length);

        try {
          final result = await discogsService.searchAlbum(
            artist: album['artist'] as String,
            title: album['title'] as String,
          );

          if (result != null && (result.genres.isNotEmpty || result.styles.isNotEmpty)) {
            await _supabase
                .from('albums')
                .update({
                  'genres': result.genres,
                  'styles': result.styles,
                  'discogs_id': result.id,
                })
                .eq('id', album['id']);
            updated++;
            debugPrint('  ✓ ${album['artist']} - ${album['title']}: ${result.genres} / ${result.styles}');
          }
        } catch (e) {
          debugPrint('  ✗ Error en ${album['title']}: $e');
        }

        // Rate limiting para Discogs
        if (i < albums.length - 1) {
          await Future.delayed(const Duration(milliseconds: 1100));
        }
      }
    } catch (e) {
      debugPrint('Error enriqueciendo álbumes: $e');
    }

    return updated;
  }
}

/// Modelo extendido de álbum con información de ubicación
class AlbumWithLocation {
  final AlbumModel album;
  final String? shelfName;
  final String? shelfId;
  final int? zoneIndex;

  AlbumWithLocation({
    required this.album,
    this.shelfName,
    this.shelfId,
    this.zoneIndex,
  });

  /// Texto de ubicación formateado
  String get locationText {
    if (shelfName == null) return 'Sin ubicación';
    if (zoneIndex == null) return shelfName!;
    return '$shelfName - Zona $zoneIndex';
  }

  /// Verifica si tiene ubicación
  bool get hasLocation => shelfName != null;
}
