import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';
import '../models/shelf_model.dart';
import '../models/album_model.dart';

/// Servicio para funcionalidades sociales: follows, feed, perfiles públicos
class SocialService {
  final _supabase = Supabase.instance.client;

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  // ─── FOLLOWS ─────────────────────────────────

  /// Seguir a un usuario
  Future<bool> followUser(String targetUserId) async {
    if (_currentUserId == null) return false;
    if (_currentUserId == targetUserId) return false; // No puedes seguirte a ti mismo
    try {
      await _supabase.from('follows').insert({
        'follower_id': _currentUserId,
        'following_id': targetUserId,
      });
      return true;
    } catch (e) {
      debugPrint('Error following user: $e');
      return false;
    }
  }

  /// Dejar de seguir a un usuario
  Future<bool> unfollowUser(String targetUserId) async {
    if (_currentUserId == null) return false;
    try {
      await _supabase
          .from('follows')
          .delete()
          .eq('follower_id', _currentUserId!)
          .eq('following_id', targetUserId);
      return true;
    } catch (e) {
      debugPrint('Error unfollowing user: $e');
      return false;
    }
  }

  /// Verifica si sigo a un usuario
  Future<bool> isFollowing(String targetUserId) async {
    if (_currentUserId == null) return false;
    try {
      final result = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', _currentUserId!)
          .eq('following_id', targetUserId)
          .maybeSingle();
      return result != null;
    } catch (e) {
      debugPrint('Error checking follow: $e');
      return false;
    }
  }

  /// Obtener contadores de seguidores y seguidos
  Future<Map<String, int>> getFollowCounts(String userId) async {
    try {
      final followers = await _supabase
          .from('follows')
          .select('id')
          .eq('following_id', userId);
      final following = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', userId);
      return {
        'followers': (followers as List).length,
        'following': (following as List).length,
      };
    } catch (e) {
      debugPrint('Error getting follow counts: $e');
      return {'followers': 0, 'following': 0};
    }
  }

  // ─── FEED ────────────────────────────────────

  /// Feed "Siguiendo": estanterías públicas de usuarios que sigo
  Future<List<FeedItem>> getFollowingFeed({int limit = 20, int offset = 0}) async {
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

      // Obtener estanterías públicas de esos usuarios
      final shelvesResult = await _supabase
          .from('shelves')
          .select('*, users!user_id(id, display_name, photo_url, username)')
          .eq('is_public', true)
          .inFilter('user_id', followingIds)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return _parseFeedItems(shelvesResult as List);
    } catch (e) {
      debugPrint('Error getting following feed: $e');
      return [];
    }
  }

  /// Feed "Descubrir": todas las estanterías públicas
  Future<List<FeedItem>> getDiscoverFeed({int limit = 20, int offset = 0}) async {
    try {
      final result = await _supabase
          .from('shelves')
          .select('*, users!user_id(id, display_name, photo_url, username)')
          .eq('is_public', true)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return _parseFeedItems(result as List);
    } catch (e) {
      debugPrint('Error getting discover feed: $e');
      return [];
    }
  }

  List<FeedItem> _parseFeedItems(List items) {
    return items.map((json) {
      final user = json['users'] as Map<String, dynamic>?;
      return FeedItem(
        shelfId: json['id'] as String,
        shelfName: json['name'] as String,
        masterPhotoUrl: json['master_photo_url'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        userId: json['user_id'] as String,
        userDisplayName: user?['display_name'] as String? ?? 'Usuario',
        userPhotoUrl: user?['photo_url'] as String?,
        userUsername: user?['username'] as String?,
      );
    }).toList();
  }

  // ─── BÚSQUEDA DE USUARIOS ────────────────────

  /// Buscar usuarios públicos por nombre o username
  Future<List<PublicUserProfile>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final result = await _supabase
          .from('users')
          .select('id, display_name, photo_url, username, bio')
          .eq('is_public', true)
          .or('display_name.ilike.%$query%,username.ilike.%$query%')
          .limit(20);

      final users = <PublicUserProfile>[];
      for (final json in (result as List)) {
        final userId = json['id'] as String;
        final isFollowed = await isFollowing(userId);
        users.add(PublicUserProfile.fromJson(
          json,
          isFollowedByMe: isFollowed,
        ));
      }
      return users;
    } catch (e) {
      debugPrint('Error searching users: $e');
      return [];
    }
  }

  // ─── PERFIL PÚBLICO ──────────────────────────

  /// Obtener perfil público completo de un usuario
  Future<PublicUserProfile?> getPublicProfile(String userId) async {
    try {
      final result = await _supabase
          .from('users')
          .select('id, display_name, photo_url, username, bio')
          .eq('id', userId)
          .eq('is_public', true)
          .maybeSingle();

      if (result == null) return null;

      // Contadores
      final counts = await getFollowCounts(userId);
      final isFollowed = await isFollowing(userId);

      // Contar álbumes
      final albumsResult = await _supabase
          .from('albums')
          .select('id')
          .eq('user_id', userId);

      return PublicUserProfile.fromJson(
        result,
        albumCount: (albumsResult as List).length,
        followerCount: counts['followers'] ?? 0,
        followingCount: counts['following'] ?? 0,
        isFollowedByMe: isFollowed,
      );
    } catch (e) {
      debugPrint('Error getting public profile: $e');
      return null;
    }
  }

  /// Obtener estanterías públicas de un usuario
  Future<List<ShelfModel>> getPublicShelves(String userId) async {
    try {
      final result = await _supabase
          .from('shelves')
          .select('*')
          .eq('user_id', userId)
          .eq('is_public', true)
          .order('created_at', ascending: false);

      return (result as List)
          .map((json) => ShelfModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting public shelves: $e');
      return [];
    }
  }

  /// Obtener álbumes públicos de un usuario (sin posición/zona)
  Future<List<AlbumModel>> getPublicAlbums(String userId) async {
    try {
      final result = await _supabase
          .from('albums')
          .select()
          .eq('user_id', userId)
          .order('artist', ascending: true);

      return (result as List)
          .map((json) => AlbumModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting public albums: $e');
      return [];
    }
  }

  // ─── PRIVACIDAD ──────────────────────────────

  /// Actualizar perfil público del usuario actual
  Future<bool> updatePublicProfile({
    bool? isPublic,
    bool? sharePhotos,
    String? username,
    String? bio,
  }) async {
    if (_currentUserId == null) return false;
    try {
      final updates = <String, dynamic>{};
      if (isPublic != null) updates['is_public'] = isPublic;
      if (sharePhotos != null) updates['share_photos'] = sharePhotos;
      if (username != null) updates['username'] = username.isEmpty ? null : username;
      if (bio != null) updates['bio'] = bio.isEmpty ? null : bio;

      if (updates.isEmpty) return true;

      await _supabase
          .from('users')
          .update(updates)
          .eq('id', _currentUserId!);
      return true;
    } catch (e) {
      debugPrint('Error updating public profile: $e');
      return false;
    }
  }

  /// Verificar si un username está disponible
  Future<bool> isUsernameAvailable(String username) async {
    if (username.trim().isEmpty) return false;
    try {
      final result = await _supabase
          .from('users')
          .select('id')
          .eq('username', username.trim().toLowerCase())
          .maybeSingle();
      // Disponible si no existe, o si es del usuario actual
      return result == null || result['id'] == _currentUserId;
    } catch (e) {
      return false;
    }
  }

  /// Actualizar visibilidad de una estantería
  Future<bool> updateShelfVisibility(String shelfId, bool isPublic) async {
    try {
      await _supabase
          .from('shelves')
          .update({'is_public': isPublic})
          .eq('id', shelfId);
      return true;
    } catch (e) {
      debugPrint('Error updating shelf visibility: $e');
      return false;
    }
  }
}

// ─────────────────────────────────────────────
// Modelo de item del feed
// ─────────────────────────────────────────────
class FeedItem {
  final String shelfId;
  final String shelfName;
  final String masterPhotoUrl;
  final DateTime createdAt;
  final String userId;
  final String userDisplayName;
  final String? userPhotoUrl;
  final String? userUsername;

  FeedItem({
    required this.shelfId,
    required this.shelfName,
    required this.masterPhotoUrl,
    required this.createdAt,
    required this.userId,
    required this.userDisplayName,
    this.userPhotoUrl,
    this.userUsername,
  });
}
