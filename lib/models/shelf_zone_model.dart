import 'album_model.dart';

/// Modelo de Zona de Estantería (Los "Huecos" del mueble)
/// Representa un hueco específico donde se almacenan vinilos
class ShelfZoneModel {
  final String id;
  final String shelfId;
  final int zoneIndex;
  final String? detailPhotoUrl;
  final double centerX;  // Coordenada X relativa (0-1)
  final double centerY;  // Coordenada Y relativa (0-1)
  final DateTime? lastScannedAt;
  final DateTime createdAt;
  
  /// Lista de álbumes en esta zona
  /// Se carga opcionalmente con las relaciones
  final List<AlbumModel>? albums;

  /// Conteo rápido de álbumes (cuando solo se cargan ids)
  final int? _rawAlbumCount;

  ShelfZoneModel({
    required this.id,
    required this.shelfId,
    required this.zoneIndex,
    this.detailPhotoUrl,
    required this.centerX,
    required this.centerY,
    this.lastScannedAt,
    required this.createdAt,
    this.albums,
    int? rawAlbumCount,
  }) : _rawAlbumCount = rawAlbumCount;

  /// Crea un ShelfZoneModel desde un Map JSON (respuesta de Supabase)
  factory ShelfZoneModel.fromJson(Map<String, dynamic> json) {
    return ShelfZoneModel(
      id: json['id'] as String,
      shelfId: json['shelf_id'] as String,
      zoneIndex: json['zone_index'] as int,
      detailPhotoUrl: json['detail_photo_url'] as String?,
      centerX: (json['center_x'] as num).toDouble(),
      centerY: (json['center_y'] as num).toDouble(),
      lastScannedAt: json['last_scanned_at'] != null
          ? DateTime.parse(json['last_scanned_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      albums: json['albums'] != null && (json['albums'] as List).isNotEmpty && (json['albums'] as List).first is Map && (json['albums'] as List).first.containsKey('title')
          ? (json['albums'] as List)
              .map((a) => AlbumModel.fromJson(a as Map<String, dynamic>))
              .toList()
          : null,
      rawAlbumCount: json['albums'] != null ? (json['albums'] as List).length : null,
    );
  }

  /// Convierte el modelo a un Map para insertar/actualizar en Supabase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shelf_id': shelfId,
      'zone_index': zoneIndex,
      'detail_photo_url': detailPhotoUrl,
      'center_x': centerX,
      'center_y': centerY,
      'last_scanned_at': lastScannedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Map para crear una nueva zona (sin id, Supabase lo genera)
  Map<String, dynamic> toInsertMap() {
    return {
      'shelf_id': shelfId,
      'zone_index': zoneIndex,
      'detail_photo_url': detailPhotoUrl,
      'center_x': centerX,
      'center_y': centerY,
    };
  }

  /// Crea una copia del modelo con campos actualizados
  ShelfZoneModel copyWith({
    String? id,
    String? shelfId,
    int? zoneIndex,
    String? detailPhotoUrl,
    double? centerX,
    double? centerY,
    DateTime? lastScannedAt,
    DateTime? createdAt,
    List<AlbumModel>? albums,
  }) {
    return ShelfZoneModel(
      id: id ?? this.id,
      shelfId: shelfId ?? this.shelfId,
      zoneIndex: zoneIndex ?? this.zoneIndex,
      detailPhotoUrl: detailPhotoUrl ?? this.detailPhotoUrl,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      createdAt: createdAt ?? this.createdAt,
      albums: albums ?? this.albums,
      rawAlbumCount: albums?.length ?? this._rawAlbumCount,
    );
  }

  /// Número de álbumes en esta zona
  int get albumCount => albums?.length ?? _rawAlbumCount ?? 0;

  /// Verifica si la zona ha sido escaneada
  bool get hasBeenScanned => lastScannedAt != null;

  @override
  String toString() {
    return 'ShelfZoneModel(id: $id, index: $zoneIndex, center: ($centerX, $centerY), albums: $albumCount)';
  }
}
