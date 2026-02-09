import '../services/discogs_service.dart';

/// Modelo de Álbum (El inventario real de vinilos)
/// Representa un disco de vinilo en la colección del usuario
class AlbumModel {
  final String id;
  final String userId;
  final String? zoneId;
  final int? discogsId;
  final String title;
  final String artist;
  final String? coverUrl;
  final int? year;
  final List<String> genres;
  final List<String> styles;
  final int? positionIndex;  // Posición dentro del hueco (1, 2, 3...)
  final List<double>? embedding;  // Vector para recomendaciones de IA
  final DateTime createdAt;
  final DateTime? lastPlayedAt;  // Para playlists inteligentes

  AlbumModel({
    required this.id,
    required this.userId,
    this.zoneId,
    this.discogsId,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.year,
    this.genres = const [],
    this.styles = const [],
    this.positionIndex,
    this.embedding,
    required this.createdAt,
    this.lastPlayedAt,
  });

  /// Crea un AlbumModel desde un Map JSON (respuesta de Supabase)
  factory AlbumModel.fromJson(Map<String, dynamic> json) {
    return AlbumModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      zoneId: json['zone_id'] as String?,
      discogsId: json['discogs_id'] as int?,
      title: json['title'] as String,
      artist: json['artist'] as String,
      coverUrl: json['cover_url'] != null 
          ? DiscogsAlbum.proxyUrlForWeb(
              DiscogsAlbum.unwrapProxyUrl(json['cover_url'] as String))
          : null,
      year: json['year'] as int?,
      genres: json['genres'] != null
          ? List<String>.from(json['genres'] as List)
          : [],
      styles: json['styles'] != null
          ? List<String>.from(json['styles'] as List)
          : [],
      positionIndex: json['position_index'] as int?,
      embedding: json['embedding'] != null
          ? List<double>.from((json['embedding'] as List).map((e) => (e as num).toDouble()))
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastPlayedAt: json['last_played_at'] != null
          ? DateTime.parse(json['last_played_at'] as String)
          : null,
    );
  }

  /// Convierte el modelo a un Map para insertar/actualizar en Supabase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'zone_id': zoneId,
      'discogs_id': discogsId,
      'title': title,
      'artist': artist,
      'cover_url': coverUrl,
      'year': year,
      'genres': genres,
      'styles': styles,
      'position_index': positionIndex,
      'embedding': embedding,
      'created_at': createdAt.toIso8601String(),
      'last_played_at': lastPlayedAt?.toIso8601String(),
    };
  }

  /// Map para crear un nuevo álbum (sin id, Supabase lo genera)
  Map<String, dynamic> toInsertMap() {
    return {
      'user_id': userId,
      'zone_id': zoneId,
      'discogs_id': discogsId,
      'title': title,
      'artist': artist,
      'cover_url': coverUrl,
      'year': year,
      'genres': genres,
      'styles': styles,
      'position_index': positionIndex,
      'embedding': embedding,
    };
  }

  /// Crea una copia del modelo con campos actualizados
  AlbumModel copyWith({
    String? id,
    String? userId,
    String? zoneId,
    int? discogsId,
    String? title,
    String? artist,
    String? coverUrl,
    int? year,
    List<String>? genres,
    List<String>? styles,
    int? positionIndex,
    List<double>? embedding,
    DateTime? createdAt,
    DateTime? lastPlayedAt,
  }) {
    return AlbumModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      zoneId: zoneId ?? this.zoneId,
      discogsId: discogsId ?? this.discogsId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      coverUrl: coverUrl ?? this.coverUrl,
      year: year ?? this.year,
      genres: genres ?? this.genres,
      styles: styles ?? this.styles,
      positionIndex: positionIndex ?? this.positionIndex,
      embedding: embedding ?? this.embedding,
      createdAt: createdAt ?? this.createdAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  /// Verifica si el álbum está sincronizado con Discogs
  bool get hasDiscogsId => discogsId != null;

  /// Verifica si el álbum tiene embedding para recomendaciones
  bool get hasEmbedding => embedding != null && embedding!.isNotEmpty;

  /// Verifica si el álbum está asignado a una zona
  bool get isInZone => zoneId != null;

  /// Texto formateado "Artista - Título"
  String get displayName => '$artist - $title';

  /// Géneros como string separado por comas
  String get genresText => genres.join(', ');

  /// Estilos como string separado por comas  
  String get stylesText => styles.join(', ');

  @override
  String toString() {
    return 'AlbumModel(id: $id, artist: $artist, title: $title, year: $year)';
  }
}
