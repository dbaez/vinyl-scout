import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/wishlist_item_model.dart';

/// Servicio para gestionar la wishlist de discos deseados
class WishlistService {
  final _supabase = Supabase.instance.client;

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  // ─── CRUD ──────────────────────────────────

  /// Obtener la wishlist del usuario actual
  Future<List<WishlistItemModel>> getMyWishlist() async {
    if (_currentUserId == null) return [];
    try {
      final result = await _supabase
          .from('wishlist_items')
          .select()
          .eq('user_id', _currentUserId!)
          .order('created_at', ascending: false);

      return (result as List)
          .map((json) => WishlistItemModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting wishlist: $e');
      return [];
    }
  }

  /// Obtener la wishlist pública de otro usuario
  Future<List<WishlistItemModel>> getPublicWishlist(String userId) async {
    try {
      final result = await _supabase
          .from('wishlist_items')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (result as List)
          .map((json) => WishlistItemModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting public wishlist: $e');
      return [];
    }
  }

  /// Añadir un disco a la wishlist
  Future<WishlistItemModel?> addToWishlist({
    required String title,
    required String artist,
    String? coverUrl,
    int? year,
    int? discogsId,
    String? note,
  }) async {
    if (_currentUserId == null) return null;
    try {
      final data = {
        'user_id': _currentUserId!,
        'title': title,
        'artist': artist,
        if (coverUrl != null) 'cover_url': coverUrl,
        if (year != null) 'year': year,
        if (discogsId != null) 'discogs_id': discogsId,
        if (note != null && note.isNotEmpty) 'note': note,
      };

      final result = await _supabase
          .from('wishlist_items')
          .insert(data)
          .select()
          .single();

      return WishlistItemModel.fromJson(result);
    } catch (e) {
      debugPrint('Error adding to wishlist: $e');
      return null;
    }
  }

  /// Eliminar un item de la wishlist
  Future<bool> removeFromWishlist(String itemId) async {
    if (_currentUserId == null) return false;
    try {
      await _supabase
          .from('wishlist_items')
          .delete()
          .eq('id', itemId)
          .eq('user_id', _currentUserId!);
      return true;
    } catch (e) {
      debugPrint('Error removing from wishlist: $e');
      return false;
    }
  }

  /// Actualizar la nota de un item
  Future<bool> updateNote(String itemId, String note) async {
    if (_currentUserId == null) return false;
    try {
      await _supabase
          .from('wishlist_items')
          .update({'note': note.isEmpty ? null : note})
          .eq('id', itemId)
          .eq('user_id', _currentUserId!);
      return true;
    } catch (e) {
      debugPrint('Error updating wishlist note: $e');
      return false;
    }
  }

  /// Verificar si un disco ya está en la wishlist (por discogs_id o por artist+title)
  Future<bool> isInWishlist({int? discogsId, String? artist, String? title}) async {
    if (_currentUserId == null) return false;
    try {
      if (discogsId != null) {
        final result = await _supabase
            .from('wishlist_items')
            .select('id')
            .eq('user_id', _currentUserId!)
            .eq('discogs_id', discogsId)
            .maybeSingle();
        if (result != null) return true;
      }
      if (artist != null && title != null) {
        final result = await _supabase
            .from('wishlist_items')
            .select('id')
            .eq('user_id', _currentUserId!)
            .ilike('artist', artist)
            .ilike('title', title)
            .maybeSingle();
        return result != null;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking wishlist: $e');
      return false;
    }
  }

  /// Contar items en la wishlist del usuario actual
  Future<int> getWishlistCount() async {
    if (_currentUserId == null) return 0;
    try {
      final result = await _supabase
          .from('wishlist_items')
          .select('id')
          .eq('user_id', _currentUserId!);
      return (result as List).length;
    } catch (e) {
      return 0;
    }
  }
}
