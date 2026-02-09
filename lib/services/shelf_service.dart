import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shelf_model.dart';
import '../models/shelf_zone_model.dart';

/// Servicio para gestionar estanterías y zonas
/// Proporciona operaciones CRUD para shelves y shelf_zones
class ShelfService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ==================== ESTANTERÍAS ====================

  /// Crea una nueva estantería
  /// Retorna el ShelfModel creado con su id generado
  Future<ShelfModel?> createShelf({
    required String userId,
    required String name,
    required String masterPhotoUrl,
  }) async {
    try {
      final response = await _supabase
          .from('shelves')
          .insert({
            'user_id': userId,
            'name': name,
            'master_photo_url': masterPhotoUrl,
          })
          .select()
          .single();

      return ShelfModel.fromJson(response);
    } catch (e) {
      print('Error creando estantería: $e');
      return null;
    }
  }

  /// Obtiene todas las estanterías de un usuario
  Future<List<ShelfModel>> getUserShelves(String userId) async {
    try {
      final response = await _supabase
          .from('shelves')
          .select('*, shelf_zones(*, albums(id))')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => ShelfModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error obteniendo estanterías: $e');
      return [];
    }
  }

  /// Obtiene una estantería por su id con todas sus zonas
  Future<ShelfModel?> getShelfById(String shelfId) async {
    try {
      final response = await _supabase
          .from('shelves')
          .select('*, shelf_zones(*, albums(*))')
          .eq('id', shelfId)
          .single();

      return ShelfModel.fromJson(response);
    } catch (e) {
      print('Error obteniendo estantería: $e');
      return null;
    }
  }

  /// Obtiene una zona por su id con sus álbumes
  Future<ShelfZoneModel?> getZoneById(String zoneId) async {
    try {
      final response = await _supabase
          .from('shelf_zones')
          .select('*, albums(*)')
          .eq('id', zoneId)
          .single();

      return ShelfZoneModel.fromJson(response);
    } catch (e) {
      print('Error obteniendo zona: $e');
      return null;
    }
  }

  /// Actualiza el nombre de una estantería
  Future<bool> updateShelfName(String shelfId, String newName) async {
    try {
      await _supabase
          .from('shelves')
          .update({'name': newName})
          .eq('id', shelfId);
      return true;
    } catch (e) {
      print('Error actualizando estantería: $e');
      return false;
    }
  }

  /// Elimina una estantería (cascade elimina zonas y desvincula álbumes)
  Future<bool> deleteShelf(String shelfId) async {
    try {
      await _supabase
          .from('shelves')
          .delete()
          .eq('id', shelfId);
      return true;
    } catch (e) {
      print('Error eliminando estantería: $e');
      return false;
    }
  }

  // ==================== ZONAS ====================

  /// Añade una nueva zona a una estantería
  /// [shelfId] - ID de la estantería
  /// [zoneIndex] - Índice de la zona (0, 1, 2...)
  /// [centerX] - Coordenada X relativa (0.0 - 1.0)
  /// [centerY] - Coordenada Y relativa (0.0 - 1.0)
  Future<ShelfZoneModel?> addZone({
    required String shelfId,
    required int zoneIndex,
    required double centerX,
    required double centerY,
    String? detailPhotoUrl,
  }) async {
    try {
      final response = await _supabase
          .from('shelf_zones')
          .insert({
            'shelf_id': shelfId,
            'zone_index': zoneIndex,
            'center_x': centerX,
            'center_y': centerY,
            'detail_photo_url': detailPhotoUrl,
          })
          .select()
          .single();

      return ShelfZoneModel.fromJson(response);
    } catch (e) {
      print('Error añadiendo zona: $e');
      return null;
    }
  }

  /// Añade múltiples zonas a una estantería de una vez
  /// Útil cuando el usuario define todas las zonas en la foto maestra
  Future<List<ShelfZoneModel>> addMultipleZones({
    required String shelfId,
    required List<ZoneCoordinates> zones,
  }) async {
    try {
      final insertData = zones.asMap().entries.map((entry) => {
        'shelf_id': shelfId,
        'zone_index': entry.key,
        'center_x': entry.value.centerX,
        'center_y': entry.value.centerY,
      }).toList();

      final response = await _supabase
          .from('shelf_zones')
          .insert(insertData)
          .select();

      return (response as List)
          .map((json) => ShelfZoneModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error añadiendo múltiples zonas: $e');
      return [];
    }
  }

  /// Añade múltiples zonas con un índice inicial personalizado
  /// Útil cuando ya existen zonas y se quieren añadir más
  Future<List<ShelfZoneModel>> addMultipleZonesWithOffset({
    required String shelfId,
    required List<ZoneCoordinates> zones,
    required int startIndex,
  }) async {
    try {
      final insertData = zones.asMap().entries.map((entry) => {
        'shelf_id': shelfId,
        'zone_index': startIndex + entry.key,
        'center_x': entry.value.centerX,
        'center_y': entry.value.centerY,
      }).toList();

      final response = await _supabase
          .from('shelf_zones')
          .insert(insertData)
          .select();

      return (response as List)
          .map((json) => ShelfZoneModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error añadiendo múltiples zonas: $e');
      return [];
    }
  }

  /// Obtiene todas las zonas de una estantería
  Future<List<ShelfZoneModel>> getShelfZones(String shelfId) async {
    try {
      final response = await _supabase
          .from('shelf_zones')
          .select('*, albums(*)')
          .eq('shelf_id', shelfId)
          .order('zone_index');

      return (response as List)
          .map((json) => ShelfZoneModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error obteniendo zonas: $e');
      return [];
    }
  }

  /// Actualiza la foto de detalle de una zona
  Future<bool> updateZonePhoto(String zoneId, String detailPhotoUrl) async {
    try {
      await _supabase
          .from('shelf_zones')
          .update({
            'detail_photo_url': detailPhotoUrl,
            'last_scanned_at': DateTime.now().toIso8601String(),
          })
          .eq('id', zoneId);
      return true;
    } catch (e) {
      print('Error actualizando foto de zona: $e');
      return false;
    }
  }

  /// Actualiza las coordenadas de una zona
  Future<bool> updateZoneCoordinates(
    String zoneId, 
    double centerX, 
    double centerY,
  ) async {
    try {
      await _supabase
          .from('shelf_zones')
          .update({
            'center_x': centerX,
            'center_y': centerY,
          })
          .eq('id', zoneId);
      return true;
    } catch (e) {
      print('Error actualizando coordenadas: $e');
      return false;
    }
  }

  /// Elimina una zona (los álbumes quedan con zone_id = null)
  Future<bool> deleteZone(String zoneId) async {
    try {
      await _supabase
          .from('shelf_zones')
          .delete()
          .eq('id', zoneId);
      return true;
    } catch (e) {
      print('Error eliminando zona: $e');
      return false;
    }
  }

  /// Marca una zona como escaneada (actualiza last_scanned_at)
  Future<bool> markZoneAsScanned(String zoneId) async {
    try {
      await _supabase
          .from('shelf_zones')
          .update({
            'last_scanned_at': DateTime.now().toIso8601String(),
          })
          .eq('id', zoneId);
      return true;
    } catch (e) {
      print('Error marcando zona como escaneada: $e');
      return false;
    }
  }
}

/// Clase auxiliar para definir coordenadas de zonas
class ZoneCoordinates {
  final double centerX;
  final double centerY;

  ZoneCoordinates({
    required this.centerX,
    required this.centerY,
  });
}
