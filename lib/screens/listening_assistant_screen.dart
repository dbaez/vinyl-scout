import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/env_config.dart';
import '../models/album_model.dart';
import '../services/album_service.dart';
import '../services/discogs_service.dart';
import '../theme/app_theme.dart';
import 'album_detail_screen.dart';
import 'collection_screen.dart';

// ─────────────────────────────────────────────
// Modelo de Mood / Sugerencia rápida
// ─────────────────────────────────────────────
class MoodSuggestion {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color textColor;

  const MoodSuggestion({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.textColor = Colors.white,
  });
}

const _moods = [
  MoodSuggestion(
    id: 'jazz',
    title: 'Noche de Jazz',
    subtitle: 'Smooth & Soulful',
    icon: Icons.nightlight_round,
    color: Color(0xFF1B1464),
  ),
  MoodSuggestion(
    id: 'rave',
    title: 'Me voy de Rave',
    subtitle: 'Electronic & Beats',
    icon: Icons.flash_on,
    color: Color(0xFF6C22BD),
  ),
  MoodSuggestion(
    id: '80s',
    title: 'Años 80',
    subtitle: 'Synth & Nostalgia',
    icon: Icons.calendar_today,
    color: Color(0xFFE94560),
  ),
  MoodSuggestion(
    id: 'forgotten',
    title: 'Joyas Olvidadas',
    subtitle: 'Redescubre tu colección',
    icon: Icons.auto_awesome,
    color: Color(0xFF0D7377),
  ),
  MoodSuggestion(
    id: 'random',
    title: 'Sorpréndeme',
    subtitle: 'Déjalo al azar',
    icon: Icons.shuffle,
    color: Color(0xFFF5A623),
  ),
];

// ─────────────────────────────────────────────
// Modelo de respuesta de Gemini
// ─────────────────────────────────────────────
class MusicIntent {
  final List<String> genres;
  final List<String> styles;
  final int? yearStart;
  final int? yearEnd;
  final String moodDescription;
  final String energy;
  final List<String> keywords;

  MusicIntent({
    required this.genres,
    required this.styles,
    this.yearStart,
    this.yearEnd,
    required this.moodDescription,
    required this.energy,
    required this.keywords,
  });

  factory MusicIntent.fromJson(Map<String, dynamic> json) {
    return MusicIntent(
      genres: (json['genres'] as List?)?.cast<String>() ?? [],
      styles: (json['styles'] as List?)?.cast<String>() ?? [],
      yearStart: json['year_start'] as int?,
      yearEnd: json['year_end'] as int?,
      moodDescription: json['mood_description'] as String? ?? '',
      energy: json['energy'] as String? ?? 'medium',
      keywords: (json['keywords'] as List?)?.cast<String>() ?? [],
    );
  }
}

// ─────────────────────────────────────────────
// Modelo de historial
// ─────────────────────────────────────────────
class PlayHistoryEntry {
  final String id;
  final DateTime playedAt;
  final String? requestContext;
  final AlbumModel album;

  PlayHistoryEntry({
    required this.id,
    required this.playedAt,
    this.requestContext,
    required this.album,
  });
}

// ─────────────────────────────────────────────
// Pantalla principal: Asistente de Escucha
// ─────────────────────────────────────────────
class ListeningAssistantScreen extends StatefulWidget {
  const ListeningAssistantScreen({super.key});

  @override
  State<ListeningAssistantScreen> createState() => _ListeningAssistantScreenState();
}

class _ListeningAssistantScreenState extends State<ListeningAssistantScreen>
    with TickerProviderStateMixin {
  final AlbumService _albumService = AlbumService();
  final _supabase = Supabase.instance.client;
  final TextEditingController _intentController = TextEditingController();

  List<AlbumWithLocation> _allAlbums = [];
  List<AlbumWithLocation> _shuffledAlbums = [];
  List<PlayHistoryEntry> _playHistory = [];
  bool _isLoading = true;
  String? _selectedMoodId;
  List<AlbumWithLocation> _filteredAlbums = [];
  AlbumWithLocation? _chosenAlbum;
  bool _isAnalyzing = false;
  bool _isMarkedAsPlayed = false;
  String? _currentContext; // Contexto de la búsqueda actual
  MusicIntent? _lastIntent;
  Map<String, String> _albumReasons = {}; // album.id → razón de la recomendación
  String? _moodSummary; // Resumen del mood generado por la IA

  // Fases: 'moods', 'selection', 'enjoy'
  String _phase = 'moods';
  bool _isEnriching = false;
  String _enrichProgress = '';
  bool _enrichBannerDismissed = false;

  // Novedades para ti
  final DiscogsService _discogsService = DiscogsService();
  List<DiscogsAlbum> _newReleases = [];
  bool _isLoadingReleases = false;
  bool _releasesDismissed = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _vinylSpinController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _vinylSpinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _loadData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _vinylSpinController.dispose();
    _intentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final albumsFuture = _albumService.getUserAlbumsWithLocation(userId);
    final historyFuture = _loadPlayHistory(userId);

    final results = await Future.wait([albumsFuture, historyFuture]);

    if (mounted) {
      final albums = results[0] as List<AlbumWithLocation>;
      final shuffled = List<AlbumWithLocation>.from(albums)..shuffle(Random());
      setState(() {
        _allAlbums = albums;
        _shuffledAlbums = shuffled;
        _playHistory = results[1] as List<PlayHistoryEntry>;
        _isLoading = false;
      });
      // Cargar novedades en segundo plano
      if (!_releasesDismissed) {
        _loadNewReleases(albums);
      }
    }
  }

  /// Busca novedades relevantes: primero por artistas favoritos, luego por estilos.
  Future<void> _loadNewReleases(List<AlbumWithLocation> albums) async {
    if (_isLoadingReleases) return;
    setState(() => _isLoadingReleases = true);

    try {
      // ── 1. Top artistas (los que más discos tienes) ──
      final artistCount = <String, int>{};
      for (final al in albums) {
        final artist = al.album.artist.trim();
        if (artist.isNotEmpty && artist != 'Desconocido') {
          artistCount[artist] = (artistCount[artist] ?? 0) + 1;
        }
      }
      final topArtists = (artistCount.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5)
          .map((e) => e.key)
          .toList();

      // ── 2. Estilos específicos (no géneros amplios) ──
      // Excluir géneros genéricos para obtener resultados más precisos
      const broadGenres = {'Rock', 'Electronic', 'Pop', 'Hip Hop', 'Jazz', 'Classical', 'Folk, World, & Country', 'Latin', 'Funk / Soul', 'Stage & Screen'};
      final styleCount = <String, int>{};
      for (final al in albums) {
        for (final s in al.album.styles) {
          styleCount[s] = (styleCount[s] ?? 0) + 1;
        }
        for (final g in al.album.genres) {
          if (!broadGenres.contains(g)) {
            styleCount[g] = (styleCount[g] ?? 0) + 1;
          }
        }
      }
      final topStyles = (styleCount.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(3)
          .map((e) => e.key)
          .toList();

      debugPrint('🆕 Top artistas: $topArtists');
      debugPrint('🆕 Top estilos: $topStyles');

      // Set de álbumes existentes para excluir
      final existingSet = albums
          .map((a) => '${a.album.artist.toLowerCase()}|${a.album.title.toLowerCase()}')
          .toSet();

      final releases = await _discogsService.searchNewReleases(
        topArtists: topArtists,
        topStyles: topStyles,
        existingAlbums: existingSet,
        limit: 10,
      );

      if (mounted) {
        setState(() {
          _newReleases = releases;
          _isLoadingReleases = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando novedades: $e');
      if (mounted) setState(() => _isLoadingReleases = false);
    }
  }

  Future<List<PlayHistoryEntry>> _loadPlayHistory(String userId) async {
    try {
      final response = await _supabase
          .from('play_history')
          .select('*, albums(*)')
          .eq('user_id', userId)
          .order('played_at', ascending: false)
          .limit(20);

      return (response as List).map((json) {
        final albumJson = json['albums'] as Map<String, dynamic>;
        return PlayHistoryEntry(
          id: json['id'] as String,
          playedAt: DateTime.parse(json['played_at'] as String),
          requestContext: json['request_context'] as String?,
          album: AlbumModel.fromJson(albumJson),
        );
      }).toList();
    } catch (e) {
      debugPrint('Error cargando historial: $e');
      return [];
    }
  }

  // ─── Selector Inteligente por Texto Libre (flujo de 2 pasos) ───
  //
  // Paso 1: gemini-2.0-flash-lite (ultra-barato) → extrae géneros/estilos
  // Paso 2: Filtro local por géneros → subset de la colección
  // Paso 3: gemini-2.0-flash (inteligente) → elige los mejores del subset
  //
  Future<void> _analyzeIntent() async {
    final query = _intentController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _currentContext = query;
      _albumReasons = {};
      _moodSummary = null;
    });
    HapticFeedback.mediumImpact();

    try {
      // ══ PASO 1: Clasificación de géneros (modelo ultra-ligero) ══
      debugPrint('🎵 Paso 1: Clasificando géneros (flash-lite)...');
      final intentUrl = '${EnvConfig.supabaseUrl}/functions/v1/analyze-music-intent';
      final intentResponse = await http.post(
        Uri.parse(intentUrl),
        headers: {
          'Authorization': 'Bearer ${EnvConfig.supabaseAnonKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'query': query}),
      );

      if (intentResponse.statusCode != 200) {
        debugPrint('Error paso 1: ${intentResponse.statusCode} - ${intentResponse.body}');
        _showSnackBar('Error analizando tu petición', isError: true);
        return;
      }

      final intentData = jsonDecode(intentResponse.body) as Map<String, dynamic>;
      final intent = MusicIntent.fromJson(intentData);
      _lastIntent = intent;

      debugPrint('🎵 Géneros: ${intent.genres}, Estilos: ${intent.styles}');

      // ══ PASO 2: Filtrado local por géneros ══
      final preFiltered = _preFilterByGenres(intent);
      debugPrint('🎵 Paso 2: ${preFiltered.length} álbumes tras pre-filtrado (de ${_allAlbums.length})');

      if (preFiltered.isEmpty) {
        // Sin coincidencias: tomar aleatorios como fallback
        var fallback = List<AlbumWithLocation>.from(_allAlbums)..shuffle(Random());
        fallback = fallback.take(min(5, fallback.length)).toList();
        setState(() {
          _filteredAlbums = fallback;
          _selectedMoodId = 'ai';
          _phase = 'selection';
          _moodSummary = intent.moodDescription;
        });
        _fadeController.forward(from: 0);
        return;
      }

      // ══ PASO 3: Recomendación inteligente (modelo estándar) ══
      debugPrint('🎵 Paso 3: Pidiendo recomendación inteligente (flash)...');
      final recommendUrl = '${EnvConfig.supabaseUrl}/functions/v1/smart-recommend';
      final albumsPayload = preFiltered.map((al) {
        final a = al.album;
        return {
          'id': a.id,
          'artist': a.artist,
          'title': a.title,
          'year': a.year,
          'genres': a.genres,
          'styles': a.styles,
        };
      }).toList();

      final recommendResponse = await http.post(
        Uri.parse(recommendUrl),
        headers: {
          'Authorization': 'Bearer ${EnvConfig.supabaseAnonKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'query': query,
          'albums': albumsPayload,
        }),
      );

      if (recommendResponse.statusCode == 200) {
        final recData = jsonDecode(recommendResponse.body) as Map<String, dynamic>;
        final recommendations = recData['recommendations'] as List? ?? [];
        final moodSummary = recData['mood_summary'] as String?;

        // Ordenar según las recomendaciones de la IA
        final orderedAlbums = <AlbumWithLocation>[];
        final reasons = <String, String>{};

        for (final rec in recommendations) {
          final albumId = rec['album_id'] as String?;
          final reason = rec['reason'] as String?;
          if (albumId == null) continue;

          final match = preFiltered.where((al) => al.album.id == albumId).firstOrNull;
          if (match != null) {
            orderedAlbums.add(match);
            if (reason != null) reasons[albumId] = reason;
          }
        }

        // Si la IA no cubrió todos, añadir los restantes
        for (final al in preFiltered) {
          if (!orderedAlbums.contains(al) && orderedAlbums.length < 5) {
            orderedAlbums.add(al);
          }
        }

        debugPrint('🎵 Recomendados: ${orderedAlbums.length} álbumes con razones');

        setState(() {
          _filteredAlbums = orderedAlbums.take(5).toList();
          _albumReasons = reasons;
          _moodSummary = moodSummary ?? intent.moodDescription;
          _selectedMoodId = 'ai';
          _phase = 'selection';
        });
      } else {
        // Fallback: usar pre-filtrado sin IA si el paso 3 falla
        debugPrint('⚠ Paso 3 falló (${recommendResponse.statusCode}), usando pre-filtrado');
        final fallback = preFiltered.take(5).toList();
        setState(() {
          _filteredAlbums = fallback;
          _moodSummary = intent.moodDescription;
          _selectedMoodId = 'ai';
          _phase = 'selection';
        });
      }

      _fadeController.forward(from: 0);
    } catch (e) {
      debugPrint('Error en analyze-intent: $e');
      _showSnackBar('Error de conexión', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  /// Pre-filtra la colección local por géneros/estilos/keywords.
  /// Devuelve hasta 20 álbumes que coinciden (para enviar al modelo inteligente).
  ///
  /// Mejoras vs. filtro básico:
  /// - Estilos específicos (Sadcore, Shoegaze) puntúan más que géneros genéricos (Rock)
  /// - Penaliza discos escuchados recientemente para fomentar variedad
  /// - Añade componente aleatorio para que no siempre salgan los mismos
  List<AlbumWithLocation> _preFilterByGenres(MusicIntent intent) {
    final targetGenres = intent.genres.map((g) => g.toLowerCase()).toList();
    final targetStyles = intent.styles.map((s) => s.toLowerCase()).toList();
    final targetKeywords = intent.keywords.map((k) => k.toLowerCase()).toList();

    // Calcular la "rareza" de cada género en la colección para ponderar mejor.
    // Un género que tiene 40 álbumes (Rock) puntúa menos que uno con 3 (Ambient).
    final genreCounts = <String, int>{};
    for (final al in _allAlbums) {
      for (final g in al.album.genres) genreCounts[g.toLowerCase()] = (genreCounts[g.toLowerCase()] ?? 0) + 1;
      for (final s in al.album.styles) genreCounts[s.toLowerCase()] = (genreCounts[s.toLowerCase()] ?? 0) + 1;
    }
    final totalAlbums = _allAlbums.length.clamp(1, 9999);

    // IDs de discos escuchados recientemente (últimas 10 escuchas)
    final recentlyPlayedIds = _playHistory.take(10).map((e) => e.album.id).toSet();

    final rng = Random();
    final scored = <MapEntry<AlbumWithLocation, double>>[];

    for (final albumLoc in _allAlbums) {
      final album = albumLoc.album;
      double score = 0;

      final albumGenres = album.genres.map((g) => g.toLowerCase()).toList();
      final albumStyles = album.styles.map((s) => s.toLowerCase()).toList();
      final allAlbumTags = [...albumGenres, ...albumStyles];

      // Géneros: puntúan según su rareza (inverso de frecuencia)
      for (final genre in targetGenres) {
        if (allAlbumTags.any((t) => t.contains(genre) || genre.contains(t))) {
          final count = genreCounts[genre] ?? 1;
          // Rango de 1 a 5: género raro (1 álbum) = 5 pts, género común (40+) = 1 pt
          final rarityBonus = (5.0 * (1.0 - (count / totalAlbums))).clamp(1.0, 5.0);
          score += rarityBonus;
        }
      }

      // Estilos: puntúan más que géneros y también según rareza
      for (final style in targetStyles) {
        if (allAlbumTags.any((t) => t.contains(style) || style.contains(t))) {
          final count = genreCounts[style] ?? 1;
          final rarityBonus = (6.0 * (1.0 - (count / totalAlbums))).clamp(1.5, 6.0);
          score += rarityBonus;
        }
      }

      // Año
      if (intent.yearStart != null && intent.yearEnd != null && album.year != null) {
        if (album.year! >= intent.yearStart! && album.year! <= intent.yearEnd!) {
          score += 2;
        }
      }

      // Keywords en título/artista
      final titleLower = album.title.toLowerCase();
      final artistLower = album.artist.toLowerCase();
      for (final kw in targetKeywords) {
        if (titleLower.contains(kw) || artistLower.contains(kw)) {
          score += 5; // Keywords directas pesan mucho
        }
      }

      if (score > 0) {
        // Penalizar discos escuchados recientemente (-40%)
        if (recentlyPlayedIds.contains(album.id)) {
          score *= 0.6;
        }

        // Componente aleatorio (±20%) para variedad entre peticiones similares
        final randomFactor = 0.8 + rng.nextDouble() * 0.4; // 0.8 a 1.2
        score *= randomFactor;

        scored.add(MapEntry(albumLoc, score));
      }
    }

    scored.sort((a, b) => b.value.compareTo(a.value));

    // Devolver hasta 20 para el modelo inteligente
    final result = scored.take(20).map((e) => e.key).toList();
    
    debugPrint('Pre-filtro: ${result.length} álbumes (top scores: ${scored.take(5).map((e) => '${e.key.album.artist.split(' ').first}=${e.value.toStringAsFixed(1)}').join(', ')})');
    
    return result;
  }

  // ─── Selector por Mood predefinido ──────────
  void _selectMood(MoodSuggestion mood) {
    HapticFeedback.mediumImpact();
    _currentContext = mood.title;

    List<AlbumWithLocation> filtered;
    switch (mood.id) {
      case 'jazz':
        filtered = _allAlbums.where((a) {
          final all = [...a.album.genres, ...a.album.styles].map((g) => g.toLowerCase());
          return all.any((g) => g.contains('jazz'));
        }).toList();
        break;
      case 'rave':
        filtered = _allAlbums.where((a) {
          final all = [...a.album.genres, ...a.album.styles].map((g) => g.toLowerCase());
          return all.any((g) =>
              g.contains('electronic') || g.contains('techno') ||
              g.contains('house') || g.contains('dance') ||
              g.contains('trance') || g.contains('edm'));
        }).toList();
        break;
      case '80s':
        filtered = _allAlbums.where((a) {
          final year = a.album.year;
          return year != null && year >= 1980 && year <= 1989;
        }).toList();
        break;
      case 'forgotten':
        filtered = List.from(_allAlbums)
          ..sort((a, b) {
            final aDate = a.album.lastPlayedAt;
            final bDate = b.album.lastPlayedAt;
            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return -1;
            if (bDate == null) return 1;
            return aDate.compareTo(bDate);
          });
        break;
      case 'random':
      default:
        filtered = List.from(_allAlbums)..shuffle(Random());
        break;
    }

    if (filtered.isEmpty && _allAlbums.isNotEmpty) {
      filtered = List.from(_allAlbums)..shuffle(Random());
    }

    final count = min(5, max(3, filtered.length));
    if (filtered.length > count) {
      if (mood.id != 'forgotten') filtered.shuffle(Random());
      filtered = filtered.take(count).toList();
    }

    setState(() {
      _selectedMoodId = mood.id;
      _filteredAlbums = filtered;
      _phase = 'selection';
    });
    _fadeController.forward(from: 0);
  }

  void _chooseAlbum(AlbumWithLocation album) {
    HapticFeedback.heavyImpact();
    _vinylSpinController.stop();
    _vinylSpinController.reset();
    setState(() {
      _chosenAlbum = album;
      _isMarkedAsPlayed = false;
      _phase = 'enjoy';
    });
    _fadeController.forward(from: 0);
  }

  // ─── Marcar como escuchado ──────────────────
  Future<void> _markAsPlayed() async {
    if (_chosenAlbum == null || _isMarkedAsPlayed) return;

    HapticFeedback.heavyImpact();
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final albumId = _chosenAlbum!.album.id;
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      // 1. Registrar en play_history
      await _supabase.from('play_history').insert({
        'user_id': userId,
        'album_id': albumId,
        'played_at': now,
        'request_context': _currentContext,
      });

      // 2. Actualizar last_played_at en albums
      await _albumService.updateAlbum(albumId, {'last_played_at': now});

      // 3. Actualizar estado local
      final index = _allAlbums.indexWhere((a) => a.album.id == albumId);
      if (index != -1) {
        _allAlbums[index] = AlbumWithLocation(
          album: _allAlbums[index].album.copyWith(lastPlayedAt: DateTime.now()),
          shelfName: _allAlbums[index].shelfName,
          shelfId: _allAlbums[index].shelfId,
          zoneIndex: _allAlbums[index].zoneIndex,
        );
      }

      // 4. Recargar historial
      final history = await _loadPlayHistory(userId);

      if (mounted) {
        setState(() {
          _playHistory = history;
          _isMarkedAsPlayed = true;
        });
        _vinylSpinController.repeat(); // Iniciar rotación continua
      }
    } catch (e) {
      debugPrint('Error marcando como escuchado: $e');
      _showSnackBar('Error al registrar', isError: true);
    }
  }

  void _goBack() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_phase == 'enjoy') {
        _phase = 'selection';
        _chosenAlbum = null;
      } else if (_phase == 'selection') {
        _phase = 'moods';
        _selectedMoodId = null;
        _filteredAlbums = [];
        _lastIntent = null;
      }
    });
    _fadeController.forward(from: 0);
  }

  void _reset() {
    HapticFeedback.lightImpact();
    _vinylSpinController.stop();
    _vinylSpinController.reset();
    setState(() {
      _phase = 'moods';
      _selectedMoodId = null;
      _filteredAlbums = [];
      _chosenAlbum = null;
      _lastIntent = null;
      _isMarkedAsPlayed = false;
    });
  }

  Future<void> _enrichGenres() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _isEnriching = true;
      _enrichProgress = 'Buscando discos sin géneros...';
    });

    final updated = await _albumService.enrichAlbumsWithGenres(
      userId,
      onProgress: (current, total) {
        if (mounted) {
          setState(() => _enrichProgress = 'Enriqueciendo $current de $total...');
        }
      },
    );

    await _loadData();

    if (mounted) {
      final stillMissing = _allAlbums.where((a) => a.album.genres.isEmpty && a.album.styles.isEmpty).length;
      setState(() {
        _isEnriching = false;
        _enrichProgress = '';
      });

      String message;
      bool isError = false;
      if (updated > 0 && stillMissing == 0) {
        message = '¡$updated discos enriquecidos! Todos completos.';
      } else if (updated > 0 && stillMissing > 0) {
        message = '$updated enriquecidos, $stillMissing sin resultados en Discogs.';
      } else if (updated == 0 && stillMissing > 0) {
        message = 'No se encontró info en Discogs. Puedes editarlos manualmente.';
        isError = true;
        _enrichBannerDismissed = true;
      } else {
        message = 'Todos tienen géneros.';
      }
      _showSnackBar(message, isError: isError);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.secondaryColor))
            : _allAlbums.isEmpty
                ? _buildEmptyState()
                : _buildContent(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            Text('Tu colección está vacía',
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Escanea tus vinilos primero.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_phase) {
      case 'selection':
        return _buildSelectionPhase();
      case 'enjoy':
        return _buildEnjoyPhase();
      default:
        return _buildMoodsPhase();
    }
  }

  // ═══════════════════════════════════════════
  // FASE 1: Moods + Input inteligente
  // ═══════════════════════════════════════════
  Widget _buildMoodsPhase() {
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text(
              '¿QUÉ TE APETECE ESCUCHAR?',
              style: GoogleFonts.archivoBlack(
                fontSize: 22, fontWeight: FontWeight.w900,
                color: AppTheme.primaryColor, height: 1.15,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        // ─── Input de texto libre con Gemini ───
        SliverToBoxAdapter(child: _buildSmartInput()),

        // Separador
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Expanded(child: Divider(color: Colors.grey[300])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('o elige un mood',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[400])),
                ),
                Expanded(child: Divider(color: Colors.grey[300])),
              ],
            ),
          ),
        ),

        // Carrusel de Moods
        SliverToBoxAdapter(
          child: SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              itemCount: _moods.length,
              itemBuilder: (context, index) => _buildMoodCard(_moods[index], index),
            ),
          ),
        ),

        // Stats
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Text('TU COLECCIÓN',
                    style: GoogleFonts.archivoBlack(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.primaryColor)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const CollectionScreen(),
                    )).then((_) => _loadData()); // Recargar al volver
                  },
                  child: Row(
                    children: [
                      Text('Ver todos',
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.secondaryColor)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.secondaryColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _buildCollectionStats()),
        ),

        // Enriquecer
        SliverToBoxAdapter(child: _buildEnrichButton()),

        // ─── Historial de escucha ───
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Text('ESCUCHADOS RECIENTEMENTE',
                    style: GoogleFonts.archivoBlack(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.primaryColor)),
                const Spacer(),
                if (_playHistory.isNotEmpty)
                  Text('${_playHistory.length}',
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[400])),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _buildPlayHistory()),

        // ─── Novedades para ti ───
        if (!_releasesDismissed && (_isLoadingReleases || _newReleases.isNotEmpty))
          SliverToBoxAdapter(child: _buildNewReleasesSection()),

        // ─── Explorar colección (orden aleatorio) ───
        if (_shuffledAlbums.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
              child: Row(
                children: [
                  Text('EXPLORAR COLECCIÓN',
                      style: GoogleFonts.archivoBlack(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.primaryColor)),
                  const SizedBox(width: 8),
                  Icon(Icons.shuffle, size: 16, color: Colors.grey[400]),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _shuffledAlbums = List.from(_allAlbums)..shuffle(Random());
                      });
                    },
                    child: Row(
                      children: [
                        Icon(Icons.refresh, size: 14, color: AppTheme.secondaryColor),
                        const SizedBox(width: 4),
                        Text('Mezclar',
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.secondaryColor)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildCollectionGridItem(_shuffledAlbums[index]),
                childCount: _shuffledAlbums.length,
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildSmartInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          // Campo de texto
          Expanded(
            child: Container(
              decoration: AppTheme.popCard(color: Colors.white, shadowColor: AppTheme.accentColor, radius: 10),
              child: TextField(
                controller: _intentController,
                style: GoogleFonts.robotoCondensed(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Algo movido para limpiar la casa...',
                  hintStyle: GoogleFonts.robotoCondensed(fontSize: 13, color: Colors.grey[400]),
                  prefixIcon: const Icon(Icons.auto_awesome, color: AppTheme.secondaryColor, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _analyzeIntent(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botón enviar separado
          _isAnalyzing
              ? Container(
                  width: 42, height: 42,
                  decoration: AppTheme.popCard(color: AppTheme.secondaryColor, shadowColor: AppTheme.primaryColor, radius: 10),
                  child: const Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: _analyzeIntent,
                  child: Container(
                    width: 42, height: 42,
                    decoration: AppTheme.popCard(color: AppTheme.secondaryColor, shadowColor: AppTheme.primaryColor, radius: 10),
                    child: const Center(
                      child: Icon(Icons.send_rounded, size: 20, color: Colors.white),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildMoodCard(MoodSuggestion mood, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + index * 100),
      curve: Curves.easeOutBack,
      builder: (context, value, child) =>
          Transform.scale(scale: value.clamp(0.0, 1.0), child: child),
      child: GestureDetector(
        onTap: () => _selectMood(mood),
        child: Container(
          width: 120,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: mood.color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primaryColor, width: 2.5),
            boxShadow: AppTheme.popShadow(mood.color.withOpacity(0.6), offset: 3),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                  ),
                  child: Icon(mood.icon, color: Colors.white, size: 20),
                ),
                const Spacer(),
                Text(mood.title.toUpperCase(), style: GoogleFonts.archivoBlack(
                    color: mood.textColor, fontSize: 11, fontWeight: FontWeight.w900, height: 1.2)),
                const SizedBox(height: 1),
                Text(mood.subtitle, style: GoogleFonts.robotoCondensed(
                    color: Colors.white.withOpacity(0.8), fontSize: 9, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollectionStats() {
    final total = _allAlbums.length;
    final artists = _allAlbums.map((a) => a.album.artist).toSet().length;
    final played = _playHistory.length;

    return Row(
      children: [
        _buildStatChip(Icons.album, '$total', 'discos'),
        const SizedBox(width: 10),
        _buildStatChip(Icons.person, '$artists', 'artistas'),
        const SizedBox(width: 10),
        _buildStatChip(Icons.headphones, '$played', 'escuchas'),
      ],
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    final colors = [AppTheme.secondaryColor, AppTheme.accentColor, AppTheme.canaryYellow];
    final idx = ['discos', 'artistas', 'escuchas'].indexOf(label).clamp(0, 2);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: AppTheme.popCard(color: Colors.white, shadowColor: colors[idx], radius: 10),
        child: Column(
          children: [
            Icon(icon, color: colors[idx], size: 20),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.archivoBlack(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.primaryColor)),
            Text(label.toUpperCase(), style: GoogleFonts.robotoCondensed(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildEnrichButton() {
    final withoutGenres = _allAlbums.where((a) => a.album.genres.isEmpty && a.album.styles.isEmpty).length;
    if ((withoutGenres == 0 && !_isEnriching) || _enrichBannerDismissed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: GestureDetector(
        onTap: _isEnriching ? null : _enrichGenres,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppTheme.accentColor.withOpacity(0.1), AppTheme.secondaryColor.withOpacity(0.08)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              _isEnriching
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor))
                  : const Icon(Icons.auto_fix_high, color: AppTheme.accentColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isEnriching ? _enrichProgress : '$withoutGenres discos sin género → Completar con Discogs',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.primaryColor),
                ),
              ),
              if (!_isEnriching) GestureDetector(
                onTap: () => setState(() => _enrichBannerDismissed = true),
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, color: Colors.grey, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Historial real desde play_history ──────
  Widget _buildPlayHistory() {
    if (_playHistory.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.cardShadow),
          child: Row(
            children: [
              Icon(Icons.history, color: Colors.grey[300], size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Text('Aún no has escuchado ningún disco.\n¡Elige un mood para empezar!',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500])),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 135,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _playHistory.length,
        itemBuilder: (context, index) {
          final entry = _playHistory[index];
          final album = entry.album;
          final timeAgo = _timeAgo(entry.playedAt);

          return Container(
            width: 105,
            margin: const EdgeInsets.only(right: 12),
            child: Column(
              children: [
                // Carátula
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: album.coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: album.coverUrl!,
                              width: 95, height: 95, fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                  width: 95, height: 95, color: Colors.grey[200],
                                  child: const Icon(Icons.album, color: Colors.grey)),
                            )
                          : Container(
                              width: 95, height: 95, color: Colors.grey[200],
                              child: const Icon(Icons.album, color: Colors.grey)),
                    ),
                    // Badge de contexto
                    if (entry.requestContext != null)
                      Positioned(
                        top: 4, right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppTheme.secondaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.headphones, color: Colors.white, size: 10),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600)),
                Text(timeAgo, style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey[400])),
              ],
            ),
          );
        },
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays}d';
    return '${date.day}/${date.month}';
  }

  // ─── Novedades para ti ───────────────────────
  Widget _buildNewReleasesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              const Icon(Icons.new_releases, size: 18, color: AppTheme.accentColor),
              const SizedBox(width: 6),
              Text('COMPLETA TU COLECCIÓN',
                  style: GoogleFonts.archivoBlack(
                      fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.primaryColor)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _releasesDismissed = true),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        if (_isLoadingReleases)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor),
              ),
            ),
          )
        else
          SizedBox(
            height: 135,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _newReleases.length,
              itemBuilder: (context, index) => _buildReleaseCard(_newReleases[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildReleaseCard(DiscogsAlbum release) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        final locale = Localizations.localeOf(context).languageCode;
        final url = EnvConfig.amazonSearchUrl(
          artist: release.artist,
          album: release.title,
          locale: locale,
        );
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        width: 105,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Carátula con badge "Nuevo"
            Stack(
              children: [
                Container(
                  height: 95, width: 95,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: release.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: release.imageUrl!,
                            fit: BoxFit.cover,
                            width: 95,
                            height: 95,
                            placeholder: (_, __) => Container(
                              width: 95, height: 95,
                              color: Colors.grey[200],
                              child: const Center(child: Icon(Icons.album, size: 28, color: Colors.grey)),
                            ),
                          )
                        : Container(
                            width: 95, height: 95,
                            color: Colors.grey[200],
                            child: const Center(child: Icon(Icons.album, size: 28, color: Colors.grey)),
                          ),
                  ),
                ),
                // Badge "Nuevo"
                Positioned(
                  top: 4, left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('NEW',
                        style: GoogleFonts.archivoBlack(fontSize: 6, color: Colors.white)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(release.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600)),
            Text(release.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionGridItem(AlbumWithLocation albumLoc) {
    final album = albumLoc.album;
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => AlbumDetailScreen(
            albumWithLocation: albumLoc,
            onAlbumUpdated: (_) => _loadData(),
            onAlbumDeleted: (_) => _loadData(),
          ),
        ));
        _loadData();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryColor, width: 2.5),
                boxShadow: AppTheme.popShadow(AppTheme.secondaryColor.withOpacity(0.4), offset: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5.5),
                child: album.coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: album.coverUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (_, __) => Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.album, size: 28, color: Colors.grey)),
                        ),
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.album, size: 28, color: Colors.grey)),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(album.title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.archivoBlack(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.primaryColor)),
          Text(album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.robotoCondensed(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey[600])),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // FASE 2: Selección de disco
  // ═══════════════════════════════════════════
  Widget _buildSelectionPhase() {
    final isAi = _selectedMoodId == 'ai';
    final mood = isAi ? null : _moods.firstWhere((m) => m.id == _selectedMoodId, orElse: () => _moods.last);
    final headerTitle = isAi ? (_moodSummary ?? _lastIntent?.moodDescription ?? 'Resultados') : mood!.title;
    final headerColor = isAi ? AppTheme.secondaryColor : mood!.color;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: _goBack,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(headerTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                      Text('Elige tu disco para esta sesión',
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                if (!isAi)
                  IconButton(
                    onPressed: () => _selectMood(mood!),
                    icon: const Icon(Icons.refresh, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: headerColor.withOpacity(0.1),
                      foregroundColor: headerColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
              ],
            ),
          ),
          // Tags de filtro para AI
          if (isAi && _lastIntent != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Wrap(
                spacing: 6, runSpacing: 6,
                children: [
                  ..._lastIntent!.genres.map((g) => _buildFilterTag(g, AppTheme.secondaryColor)),
                  ..._lastIntent!.styles.take(3).map((s) => _buildFilterTag(s, AppTheme.accentColor)),
                  if (_lastIntent!.yearStart != null)
                    _buildFilterTag('${_lastIntent!.yearStart}-${_lastIntent!.yearEnd}', Colors.teal),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (_filteredAlbums.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off, size: 56, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('No hay discos que encajen', style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                    Text('Prueba con otro mood o añade más discos.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.75,
                  ),
                  itemCount: _filteredAlbums.length,
                  itemBuilder: (context, index) => _buildAlbumCard(_filteredAlbums[index], index),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
    );
  }

  Widget _buildAlbumCard(AlbumWithLocation albumLoc, int index) {
    final album = albumLoc.album;
    final reason = _albumReasons[album.id];
    
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + index * 100),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value.clamp(0.0, 1.2),
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: GestureDetector(
        onTap: () => _chooseAlbum(albumLoc),
        child: Container(
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.cardShadow),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      child: album.coverUrl != null
                          ? CachedNetworkImage(imageUrl: album.coverUrl!, fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: Colors.grey[200],
                                  child: const Center(child: Icon(Icons.album, size: 36, color: Colors.grey))))
                          : Container(color: Colors.grey[200],
                              child: const Center(child: Icon(Icons.album, size: 36, color: Colors.grey))),
                    ),
                    // Razón de la IA sobre la carátula
                    if (reason != null)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                            ),
                          ),
                          child: Text(
                            reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                    Text(album.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Carátula estática (antes de reproducir) ───
  Widget _buildStaticCover(AlbumModel a) {
    return Container(
      key: const ValueKey('static-cover'),
      margin: const EdgeInsets.symmetric(horizontal: 48),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppTheme.secondaryColor.withOpacity(0.2), blurRadius: 36, offset: const Offset(0, 18))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 1,
          child: a.coverUrl != null
              ? CachedNetworkImage(imageUrl: a.coverUrl!, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.grey[200],
                      child: const Center(child: Icon(Icons.album, size: 80, color: Colors.grey))))
              : Container(color: Colors.grey[200], child: const Center(child: Icon(Icons.album, size: 80, color: Colors.grey))),
        ),
      ),
    );
  }

  // ─── Vinilo girando (reproduciendo) ───
  Widget _buildSpinningVinyl(AlbumModel a) {
    return Container(
      key: const ValueKey('spinning-vinyl'),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedBuilder(
          animation: _vinylSpinController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _vinylSpinController.value * 2 * pi,
              child: child,
            );
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Disco negro de fondo
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.grey[900]!,
                      Colors.black,
                      const Color(0xFF2A2A2A),
                      Colors.black,
                      Colors.grey[800]!,
                      Colors.black,
                    ],
                    stops: const [0.0, 0.25, 0.35, 0.55, 0.65, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
              ),
              // Surcos del vinilo (círculos concéntricos)
              ...List.generate(8, (i) {
                final radius = 0.30 + i * 0.07;
                return FractionallySizedBox(
                  widthFactor: radius,
                  heightFactor: radius,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.grey[700]!.withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                  ),
                );
              }),
              // Reflejo de luz en el vinilo
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.06),
                        Colors.transparent,
                        Colors.white.withOpacity(0.03),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.3, 0.6, 1.0],
                    ),
                  ),
                ),
              ),
              // Carátula circular en el centro (label del vinilo)
              FractionallySizedBox(
                widthFactor: 0.38,
                heightFactor: 0.38,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: a.coverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: a.coverUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: AppTheme.secondaryColor.withOpacity(0.3),
                              child: const Center(child: Icon(Icons.music_note, size: 32, color: Colors.white)),
                            ),
                          )
                        : Container(
                            color: AppTheme.secondaryColor.withOpacity(0.3),
                            child: const Center(child: Icon(Icons.music_note, size: 32, color: Colors.white)),
                          ),
                  ),
                ),
              ),
              // Agujero central del vinilo
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300],
                  border: Border.all(color: Colors.grey[500]!, width: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // FASE 3: ¡A disfrutar!
  // ═══════════════════════════════════════════
  Widget _buildEnjoyPhase() {
    final album = _chosenAlbum!;
    final a = album.album;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _goBack,
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(onPressed: _reset, icon: const Icon(Icons.refresh, size: 18), label: const Text('Nuevo mood')),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Estado animado
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _isMarkedAsPlayed
                  ? Column(
                      key: const ValueKey('playing'),
                      children: [
                        const Icon(Icons.music_note, color: AppTheme.secondaryColor, size: 36),
                        const SizedBox(height: 4),
                        Text('♫ Disfrutando de la música ♫',
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold,
                                color: AppTheme.secondaryColor)),
                      ],
                    )
                  : Text('¡A disfrutar!', key: const ValueKey('ready'),
                      style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            ),
            const SizedBox(height: 20),

            // Carátula / Vinilo girando
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _isMarkedAsPlayed
                  ? _buildSpinningVinyl(a)
                  : _buildStaticCover(a),
            ),
            const SizedBox(height: 24),

            // Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Text(a.title, textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                  const SizedBox(height: 2),
                  Text(a.artist, textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 15, color: Colors.grey[600])),
                  if (a.year != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                      child: Text('${a.year}', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Ubicación física
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(18),
                boxShadow: AppTheme.cardShadow,
                border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.place, color: AppTheme.accentColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('¿Dónde está?', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                        const SizedBox(height: 2),
                        Text(
                          album.hasLocation
                              ? 'Estante ${album.shelfName}, Zona ${album.zoneIndex}${a.positionIndex != null ? ', posición #${a.positionIndex}' : ''}'
                              : 'Sin ubicación asignada',
                          style: GoogleFonts.poppins(fontSize: 12, color: album.hasLocation ? Colors.grey[700] : Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ─── Botón "Reproducir ahora" ───
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isMarkedAsPlayed ? null : _markAsPlayed,
                      icon: Icon(
                        _isMarkedAsPlayed ? Icons.check_circle : Icons.play_circle_fill,
                        size: 24,
                      ),
                      label: Text(
                        _isMarkedAsPlayed ? '¡Escuchando ahora!' : 'Reproducir ahora',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isMarkedAsPlayed ? AppTheme.successColor : AppTheme.secondaryColor,
                        disabledBackgroundColor: AppTheme.successColor,
                        disabledForegroundColor: Colors.white,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _goBack,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: Text('Elegir otro disco', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}
