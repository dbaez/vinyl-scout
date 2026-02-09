import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env_config.dart';

/// Servicio para gestionar el almacenamiento de archivos en Supabase Storage
class StorageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  /// Selecciona una imagen de la galería
  Future<XFile?> pickImageFromGallery() async {
    try {
      return await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('Error seleccionando imagen: $e');
      return null;
    }
  }

  /// Toma una foto con la cámara
  Future<XFile?> takePhoto() async {
    try {
      return await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('Error tomando foto: $e');
      return null;
    }
  }

  /// Sube una imagen al bucket especificado
  /// Retorna la URL pública de la imagen
  Future<String?> uploadImage({
    required XFile file,
    required String bucket,
    required String userId,
    String? folder,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final fileExt = file.name.split('.').last.toLowerCase();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = folder != null 
          ? '$userId/$folder/$fileName'
          : '$userId/$fileName';

      await _supabase.storage.from(bucket).uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          contentType: 'image/$fileExt',
          upsert: true,
        ),
      );

      // Obtener URL pública
      final publicUrl = _supabase.storage.from(bucket).getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      debugPrint('Error subiendo imagen: $e');
      return null;
    }
  }

  /// Sube bytes de imagen directamente (útil para Web)
  /// Retorna la URL pública de la imagen
  Future<String?> uploadImageBytes({
    required Uint8List bytes,
    required String bucket,
    required String userId,
    String? folder,
    String fileExtension = 'jpg',
  }) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final filePath = folder != null 
          ? '$userId/$folder/$fileName'
          : '$userId/$fileName';

      await _supabase.storage.from(bucket).uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          contentType: 'image/$fileExtension',
          upsert: true,
        ),
      );

      // Obtener URL pública
      final publicUrl = _supabase.storage.from(bucket).getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      debugPrint('Error subiendo imagen (bytes): $e');
      return null;
    }
  }

  /// Elimina una imagen del bucket
  Future<bool> deleteImage({
    required String bucket,
    required String filePath,
  }) async {
    try {
      await _supabase.storage.from(bucket).remove([filePath]);
      return true;
    } catch (e) {
      debugPrint('Error eliminando imagen: $e');
      return false;
    }
  }

  /// Descarga una imagen desde una URL (ej. Discogs) y la sube a Supabase Storage.
  /// Retorna la URL pública de Supabase Storage, o null si falla.
  /// En web, usa la Edge Function como proxy para evitar CORS al descargar.
  Future<String?> persistCoverImage({
    required String imageUrl,
    required String userId,
    required String albumId,
  }) async {
    try {
      // En web: descargar via Edge Function proxy (evita CORS)
      // En móvil: descargar directamente
      final downloadUrl = kIsWeb
          ? '${EnvConfig.supabaseUrl}/functions/v1/discogs-proxy?image_url=${Uri.encodeComponent(imageUrl)}'
          : imageUrl;
      
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) {
        debugPrint('Error descargando carátula: ${response.statusCode}');
        return null;
      }

      final bytes = response.bodyBytes;
      if (bytes.isEmpty || bytes.length < 100) return null; // Evitar imágenes rotas

      // Determinar extensión desde content-type
      final contentType = response.headers['content-type'] ?? 'image/jpeg';
      String ext = 'jpg';
      if (contentType.contains('png')) ext = 'png';
      if (contentType.contains('webp')) ext = 'webp';

      // Subir a Supabase Storage: album-covers/{userId}/{albumId}.jpg
      final filePath = '$userId/$albumId.$ext';

      await _supabase.storage.from('album-covers').uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          contentType: contentType,
          upsert: true,
        ),
      );

      final publicUrl = _supabase.storage.from('album-covers').getPublicUrl(filePath);
      debugPrint('Carátula persistida: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('Error persistiendo carátula: $e');
      return null;
    }
  }

  /// Extrae el path del archivo desde una URL pública de Supabase
  String? extractFilePathFromUrl(String url, String bucket) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf(bucket);
      if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
        return pathSegments.sublist(bucketIndex + 1).join('/');
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
