import 'shelf_zone_model.dart';

/// Modelo de Estantería (La "Foto Maestra" del mueble)
/// Representa una estantería física del usuario con sus zonas
class ShelfModel {
  final String id;
  final String userId;
  final String name;
  final String masterPhotoUrl;
  final DateTime createdAt;
  
  /// Lista de zonas (huecos) de la estantería
  /// Se carga opcionalmente con las relaciones
  final List<ShelfZoneModel>? zones;

  ShelfModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.masterPhotoUrl,
    required this.createdAt,
    this.zones,
  });

  /// Crea un ShelfModel desde un Map JSON (respuesta de Supabase)
  factory ShelfModel.fromJson(Map<String, dynamic> json) {
    // Parsear zonas y ordenarlas por zone_index
    List<ShelfZoneModel>? parsedZones;
    if (json['shelf_zones'] != null) {
      parsedZones = (json['shelf_zones'] as List)
          .map((z) => ShelfZoneModel.fromJson(z as Map<String, dynamic>))
          .toList();
      // Ordenar por zone_index para asegurar orden correcto
      parsedZones.sort((a, b) => a.zoneIndex.compareTo(b.zoneIndex));
    }

    return ShelfModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      masterPhotoUrl: json['master_photo_url'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      zones: parsedZones,
    );
  }

  /// Convierte el modelo a un Map para insertar/actualizar en Supabase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'master_photo_url': masterPhotoUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Map para crear una nueva estantería (sin id, Supabase lo genera)
  Map<String, dynamic> toInsertMap() {
    return {
      'user_id': userId,
      'name': name,
      'master_photo_url': masterPhotoUrl,
    };
  }

  /// Crea una copia del modelo con campos actualizados
  ShelfModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? masterPhotoUrl,
    DateTime? createdAt,
    List<ShelfZoneModel>? zones,
  }) {
    return ShelfModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      masterPhotoUrl: masterPhotoUrl ?? this.masterPhotoUrl,
      createdAt: createdAt ?? this.createdAt,
      zones: zones ?? this.zones,
    );
  }

  /// Número de zonas en la estantería
  int get zoneCount => zones?.length ?? 0;

  @override
  String toString() {
    return 'ShelfModel(id: $id, name: $name, zones: $zoneCount)';
  }
}
