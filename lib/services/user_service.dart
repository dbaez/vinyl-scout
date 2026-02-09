import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

/// Servicio para gestionar usuarios
/// Sincroniza usuarios de Auth con la tabla Users
class UserService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Sincroniza el usuario de Auth con la tabla Users
  /// Si el usuario no existe, lo crea. Si existe, actualiza sus datos
  Future<UserModel?> syncUserFromAuth() async {
    try {
      final authUser = _client.auth.currentUser;
      if (authUser == null) return null;

      // Buscar usuario por google_id (sub del token)
      final googleId = authUser.userMetadata?['sub'] as String? ?? authUser.id;
      
      final response = await _client
          .from('users')
          .select()
          .eq('google_id', googleId)
          .maybeSingle();

      final now = DateTime.now();
      
      if (response == null) {
        // Crear nuevo usuario
        final newUser = {
          'id': authUser.id,
          'google_id': googleId,
          'email': authUser.email ?? '',
          'display_name': authUser.userMetadata?['full_name'] as String? ?? 
                         authUser.userMetadata?['name'] as String? ?? 
                         authUser.email?.split('@')[0] ?? 'Usuario',
          'photo_url': authUser.userMetadata?['avatar_url'] as String? ?? 
                      authUser.userMetadata?['picture'] as String?,
          'created_at': now.toIso8601String(),
        };

        await _client.from('users').insert(newUser);
        return UserModel.fromJson(newUser);
      } else {
        // Usuario existente - actualizar foto si cambió
        final currentPhotoUrl = response['photo_url'] as String?;
        final newPhotoUrl = authUser.userMetadata?['avatar_url'] as String? ?? 
                           authUser.userMetadata?['picture'] as String?;
        
        if (currentPhotoUrl != newPhotoUrl && newPhotoUrl != null) {
          await _client
              .from('users')
              .update({'photo_url': newPhotoUrl})
              .eq('id', response['id'] as String);
        }
        
        return UserModel.fromJson(response);
      }
    } catch (e) {
      print('Error sincronizando usuario: $e');
      return null;
    }
  }

  /// Obtiene el usuario actual
  Future<UserModel?> getCurrentUser() async {
    try {
      final authUser = _client.auth.currentUser;
      if (authUser == null) return null;

      final response = await _client
          .from('users')
          .select()
          .eq('id', authUser.id)
          .maybeSingle();

      if (response == null) return null;
      return UserModel.fromJson(response);
    } catch (e) {
      print('Error obteniendo usuario: $e');
      return null;
    }
  }

  /// Actualiza el token de Discogs del usuario
  Future<bool> updateDiscogsToken({
    required String userId,
    required String accessToken,
    required String username,
  }) async {
    try {
      await _client
          .from('users')
          .update({
            'discogs_access_token': accessToken,
            'discogs_username': username,
          })
          .eq('id', userId);
      return true;
    } catch (e) {
      print('Error actualizando token de Discogs: $e');
      return false;
    }
  }

  /// Desvincula la cuenta de Discogs
  Future<bool> unlinkDiscogs(String userId) async {
    try {
      await _client
          .from('users')
          .update({
            'discogs_access_token': null,
            'discogs_username': null,
          })
          .eq('id', userId);
      return true;
    } catch (e) {
      print('Error desvinculando Discogs: $e');
      return false;
    }
  }

  /// Cierra sesión
  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
