// Script para enriquecer álbumes existentes con géneros/estilos de Discogs
// Ejecutar: dart run scripts/enrich_genres.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

// Configurar estas variables antes de ejecutar el script
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const discogsToken = String.fromEnvironment('DISCOGS_TOKEN');

Future<void> main() async {
  print('🎵 Enriqueciendo álbumes con géneros de Discogs...\n');

  // 1. Obtener todos los álbumes
  final albumsResponse = await http.get(
    Uri.parse('$supabaseUrl/rest/v1/albums?select=id,artist,title,genres,styles'),
    headers: {
      'apikey': supabaseKey,
      'Authorization': 'Bearer $supabaseKey',
    },
  );

  if (albumsResponse.statusCode != 200) {
    print('❌ Error obteniendo álbumes: ${albumsResponse.statusCode}');
    print(albumsResponse.body);
    return;
  }

  final allAlbums = jsonDecode(albumsResponse.body) as List;
  
  // Filtrar los que no tienen géneros
  final albumsToEnrich = allAlbums.where((a) {
    final genres = a['genres'] as List?;
    final styles = a['styles'] as List?;
    return (genres == null || genres.isEmpty) && (styles == null || styles.isEmpty);
  }).toList();

  print('📊 Total álbumes: ${allAlbums.length}');
  print('🔍 Sin géneros: ${albumsToEnrich.length}\n');

  if (albumsToEnrich.isEmpty) {
    print('✅ Todos los álbumes ya tienen géneros.');
    return;
  }

  int updated = 0;
  int errors = 0;

  for (int i = 0; i < albumsToEnrich.length; i++) {
    final album = albumsToEnrich[i];
    final artist = album['artist'] as String;
    final title = album['title'] as String;
    final id = album['id'] as String;

    print('[${i + 1}/${albumsToEnrich.length}] $artist - $title');

    try {
      // Buscar en Discogs
      final query = _cleanSearch('$artist $title');
      final searchResponse = await http.get(
        Uri.parse('https://api.discogs.com/database/search?q=${Uri.encodeComponent(query)}&type=release&per_page=3'),
        headers: {
          'User-Agent': 'VinylScout/1.0',
          'Authorization': 'Discogs token=$discogsToken',
        },
      );

      if (searchResponse.statusCode == 200) {
        final data = jsonDecode(searchResponse.body);
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          // Buscar el primer resultado con géneros
          List<String> genres = [];
          List<String> styles = [];

          for (final result in results) {
            final g = (result['genre'] as List?)?.cast<String>() ?? [];
            final s = (result['style'] as List?)?.cast<String>() ?? [];
            if (g.isNotEmpty || s.isNotEmpty) {
              genres = g;
              styles = s;
              break;
            }
          }

          if (genres.isNotEmpty || styles.isNotEmpty) {
            // Actualizar en Supabase
            final updateResponse = await http.patch(
              Uri.parse('$supabaseUrl/rest/v1/albums?id=eq.$id'),
              headers: {
                'apikey': supabaseKey,
                'Authorization': 'Bearer $supabaseKey',
                'Content-Type': 'application/json',
                'Prefer': 'return=minimal',
              },
              body: jsonEncode({
                'genres': genres,
                'styles': styles,
              }),
            );

            if (updateResponse.statusCode == 204) {
              updated++;
              print('   ✅ Géneros: ${genres.join(", ")}');
              if (styles.isNotEmpty) print('   🎨 Estilos: ${styles.join(", ")}');
            } else {
              errors++;
              print('   ❌ Error actualizando: ${updateResponse.statusCode}');
            }
          } else {
            print('   ⚠️  Sin géneros en Discogs');
          }
        } else {
          print('   ⚠️  No encontrado en Discogs');
        }
      } else if (searchResponse.statusCode == 429) {
        print('   ⏳ Rate limited, esperando...');
        await Future.delayed(const Duration(seconds: 3));
        i--; // Reintentar
        continue;
      } else {
        errors++;
        print('   ❌ Discogs error: ${searchResponse.statusCode}');
      }
    } catch (e) {
      errors++;
      print('   ❌ Error: $e');
    }

    // Rate limiting: esperar 1.1s entre peticiones
    if (i < albumsToEnrich.length - 1) {
      await Future.delayed(const Duration(milliseconds: 1100));
    }
  }

  print('\n════════════════════════════════');
  print('✅ Actualizados: $updated');
  print('❌ Errores: $errors');
  print('⚠️  Sin datos: ${albumsToEnrich.length - updated - errors}');
  print('════════════════════════════════');
}

String _cleanSearch(String term) {
  return term
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}
