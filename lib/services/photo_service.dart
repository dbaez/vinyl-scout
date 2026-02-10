import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/album_photo_model.dart';
import 'storage_service.dart';

/// Servicio para gestionar fotos de vinilos subidas por el usuario
class PhotoService {
  final _supabase = Supabase.instance.client;
  final _storageService = StorageService();

  static const String _bucket = 'vinyl-photos';

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  // ─── OBTENER FOTOS ─────────────────────────

  /// Fotos de un álbum del usuario actual
  Future<List<AlbumPhotoModel>> getAlbumPhotos(String albumId) async {
    try {
      final result = await _supabase
          .from('album_photos')
          .select()
          .eq('album_id', albumId)
          .order('created_at', ascending: false);

      return (result as List)
          .map((json) => AlbumPhotoModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting album photos: $e');
      return [];
    }
  }

  /// Fotos públicas de un álbum (para perfil público)
  Future<List<AlbumPhotoModel>> getPublicAlbumPhotos(String albumId) async {
    try {
      final result = await _supabase
          .from('album_photos')
          .select()
          .eq('album_id', albumId)
          .order('created_at', ascending: false);

      return (result as List)
          .map((json) => AlbumPhotoModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting public album photos: $e');
      return [];
    }
  }

  // ─── AÑADIR FOTO ──────────────────────────

  /// Sube una foto desde XFile (cámara o galería) y la registra en la BD
  Future<AlbumPhotoModel?> addPhoto({
    required String albumId,
    required XFile file,
    String? caption,
  }) async {
    if (_currentUserId == null) return null;
    try {
      // Subir a Storage
      final photoUrl = await _storageService.uploadImage(
        file: file,
        bucket: _bucket,
        userId: _currentUserId!,
        folder: albumId,
      );

      if (photoUrl == null) return null;

      // Insertar en BD
      final result = await _supabase
          .from('album_photos')
          .insert({
            'album_id': albumId,
            'user_id': _currentUserId!,
            'photo_url': photoUrl,
            if (caption != null && caption.isNotEmpty) 'caption': caption,
          })
          .select()
          .single();

      return AlbumPhotoModel.fromJson(result);
    } catch (e) {
      debugPrint('Error adding photo: $e');
      return null;
    }
  }

  // ─── ELIMINAR FOTO ─────────────────────────

  /// Elimina una foto de storage y de la BD
  Future<bool> deletePhoto(AlbumPhotoModel photo) async {
    if (_currentUserId == null) return false;
    try {
      // Extraer path del storage
      final filePath = _storageService.extractFilePathFromUrl(
        photo.photoUrl,
        _bucket,
      );
      if (filePath != null) {
        await _storageService.deleteImage(
          bucket: _bucket,
          filePath: filePath,
        );
      }

      // Eliminar de BD
      await _supabase
          .from('album_photos')
          .delete()
          .eq('id', photo.id)
          .eq('user_id', _currentUserId!);

      return true;
    } catch (e) {
      debugPrint('Error deleting photo: $e');
      return false;
    }
  }

  // ─── FEED DE FOTOS ─────────────────────────

  /// Fotos recientes de usuarios seguidos que comparten fotos (para el feed)
  Future<List<PhotoFeedItem>> getPhotoFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    if (_currentUserId == null) return [];
    try {
      // Obtener IDs de usuarios que sigo
      final followsResult = await _supabase
          .from('follows')
          .select('following_id')
          .eq('follower_id', _currentUserId!);

      final followingIds = (followsResult as List)
          .map((f) => f['following_id'] as String)
          .toList();

      if (followingIds.isEmpty) return [];

      // Filtrar solo los que tienen share_photos = true
      final shareResult = await _supabase
          .from('users')
          .select('id')
          .inFilter('id', followingIds)
          .eq('share_photos', true);

      final shareIds = (shareResult as List)
          .map((u) => u['id'] as String)
          .toList();

      if (shareIds.isEmpty) return [];

      // Obtener fotos recientes con join a albums y users
      final result = await _supabase
          .from('album_photos')
          .select('*, albums!album_id(title, artist, cover_url), users!user_id(display_name, photo_url, username)')
          .inFilter('user_id', shareIds)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (result as List)
          .map((json) => PhotoFeedItem.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting photo feed: $e');
      return [];
    }
  }

  /// Fotos recientes de todos los usuarios públicos que comparten fotos (para descubrir)
  Future<List<PhotoFeedItem>> getDiscoverPhotoFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      // Solo fotos de usuarios con share_photos = true
      final shareResult = await _supabase
          .from('users')
          .select('id')
          .eq('share_photos', true);

      final shareIds = (shareResult as List)
          .map((u) => u['id'] as String)
          .toList();

      if (shareIds.isEmpty) return [];

      final result = await _supabase
          .from('album_photos')
          .select('*, albums!album_id(title, artist, cover_url), users!user_id(display_name, photo_url, username)')
          .inFilter('user_id', shareIds)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (result as List)
          .map((json) => PhotoFeedItem.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting discover photo feed: $e');
      return [];
    }
  }

  // ─── HELPERS ───────────────────────────────

  /// Seleccionar foto de galería
  Future<XFile?> pickFromGallery() => _storageService.pickImageFromGallery();

  /// Tomar foto con cámara
  Future<XFile?> takePhoto() => _storageService.takePhoto();

  /// Contar fotos de un álbum
  Future<int> getPhotoCount(String albumId) async {
    try {
      final result = await _supabase
          .from('album_photos')
          .select('id')
          .eq('album_id', albumId);
      return (result as List).length;
    } catch (e) {
      return 0;
    }
  }
}
