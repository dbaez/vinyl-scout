import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/shelf_zone_model.dart';
import '../services/gemini_service.dart';
import '../services/discogs_service.dart';
import '../services/album_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// Modelo editable para un disco detectado
class EditableAlbum {
  int position;
  String artist;
  String title;
  int? year;
  double? confidence;
  String? coverUrl;
  bool isLoadingCover;
  bool isSelected;
  List<String> genres;
  List<String> styles;
  
  /// Coordenadas X normalizadas del lomo en la imagen
  double? spineXStart;
  double? spineXEnd;
  
  /// Índice de la foto de origen (para multi-foto por zona)
  int sourceImageIndex;
  
  /// true si este album ya existe en la zona (deduplicación)
  bool isExisting;
  
  /// true si el usuario editó manualmente con resultado de Discogs
  bool isUserEdited;
  
  final TextEditingController artistController;
  final TextEditingController titleController;
  final GlobalKey key;

  EditableAlbum({
    required this.position,
    required this.artist,
    required this.title,
    this.year,
    this.confidence,
    this.coverUrl,
    this.isLoadingCover = true,
    this.isSelected = true,
    this.genres = const [],
    this.styles = const [],
    this.spineXStart,
    this.spineXEnd,
    this.sourceImageIndex = 0,
    this.isExisting = false,
    this.isUserEdited = false,
  }) : artistController = TextEditingController(text: artist),
       titleController = TextEditingController(text: title),
       key = GlobalKey();

  factory EditableAlbum.fromDetected(DetectedAlbum album) {
    return EditableAlbum(
      position: album.position,
      artist: album.artist,
      title: album.title,
      year: album.year,
      confidence: album.confidence,
      spineXStart: album.spineXStart,
      spineXEnd: album.spineXEnd,
      sourceImageIndex: album.sourceImageIndex,
    );
  }

  void dispose() {
    artistController.dispose();
    titleController.dispose();
  }

  void syncFromControllers() {
    artist = artistController.text.trim();
    title = titleController.text.trim();
  }

  bool get isValid => artist.isNotEmpty && title.isNotEmpty && isSelected;
}

/// Pantalla de revisión de resultados - Diseño Bento Box 2026
class ReviewResultsScreen extends StatefulWidget {
  final ShelfZoneModel zone;
  final List<String> imageUrls;
  final List<DetectedAlbum> detectedAlbums;
  
  /// Número de albums ya existentes en la zona (para calcular position_index)
  final int existingAlbumCount;
  
  /// Set de "artist|||title" normalizados para deduplicación
  final Set<String> existingArtistTitlePairs;
  
  /// Mapa posición → artista normalizado (matching por posición)
  final Map<int, String> existingPositionArtists;
  
  /// Set de artistas normalizados (matching cuando título es "Unknown")
  final Set<String> existingArtists;

  const ReviewResultsScreen({
    super.key,
    required this.zone,
    required this.imageUrls,
    required this.detectedAlbums,
    this.existingAlbumCount = 0,
    this.existingArtistTitlePairs = const {},
    this.existingPositionArtists = const {},
    this.existingArtists = const {},
  });

  /// URL de la primera imagen (compatibilidad y fallback)
  String get imageUrl => imageUrls.isNotEmpty ? imageUrls.first : '';
  
  /// Verdadero si hay varias fotos
  bool get isMultiPhoto => imageUrls.length > 1;

  static Future<bool?> show(
    BuildContext context, {
    required ShelfZoneModel zone,
    required List<String> imageUrls,
    required List<DetectedAlbum> detectedAlbums,
    int existingAlbumCount = 0,
    Set<String> existingArtistTitlePairs = const {},
    Map<int, String> existingPositionArtists = const {},
    Set<String> existingArtists = const {},
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => ReviewResultsScreen(
        zone: zone,
        imageUrls: imageUrls,
        detectedAlbums: detectedAlbums,
        existingAlbumCount: existingAlbumCount,
        existingArtistTitlePairs: existingArtistTitlePairs,
        existingPositionArtists: existingPositionArtists,
        existingArtists: existingArtists,
      ),
    );
  }

  @override
  State<ReviewResultsScreen> createState() => _ReviewResultsScreenState();
}

class _ReviewResultsScreenState extends State<ReviewResultsScreen>
    with SingleTickerProviderStateMixin {
  final DiscogsService _discogsService = DiscogsService();
  final AlbumService _albumService = AlbumService();
  final GeminiService _geminiService = GeminiService();
  final StorageService _storageService = StorageService();
  bool _isReanalyzing = false;

  late List<EditableAlbum> _albums;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final ScrollController _scrollController = ScrollController();
  
  bool _isSaving = false;
  bool _isLoadingCovers = true;
  bool _isImageExpanded = true; // Imagen visible por defecto
  int? _highlightedIndex; // Índice del disco resaltado en la imagen

  /// Umbral de confianza: por debajo, se considera "necesita revisión"
  static const double _confidenceThreshold = 0.95;

  /// Normaliza string para comparación de deduplicación
  static String _normalize(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  void initState() {
    super.initState();
    
    _albums = widget.detectedAlbums.map((a) {
      final ea = EditableAlbum.fromDetected(a);
      final normArtist = _normalize(ea.artist);
      final normTitle = _normalize(ea.title);
      final isUnknownTitle = normTitle.contains('unknown');
      
      // Criterio 1: Coincidencia exacta artista + título
      final key = '$normArtist|||$normTitle';
      bool matched = widget.existingArtistTitlePairs.contains(key);
      
      // Criterio 2: Coincidencia por posición + artista
      // Si el disco detectado en posición X tiene el mismo artista que
      // el existente en posición X, es el mismo disco (título pudo cambiar)
      if (!matched && widget.existingPositionArtists.containsKey(ea.position)) {
        final existingArtistAtPos = widget.existingPositionArtists[ea.position]!;
        if (normArtist == existingArtistAtPos) {
          matched = true;
          debugPrint('Dedup por posición: #${ea.position} "$normArtist" coincide');
        }
      }
      
      // Criterio 3: Artista conocido + título "Unknown"
      // Si Gemini reconoce el artista pero no el título, y ya tenemos
      // un disco de ese artista en la zona, es probable que sea el mismo
      if (!matched && isUnknownTitle && normArtist.isNotEmpty) {
        if (widget.existingArtists.contains(normArtist)) {
          matched = true;
          debugPrint('Dedup por artista+unknown: "$normArtist" / "$normTitle"');
        }
      }
      
      if (matched) {
        ea.isExisting = true;
        ea.isSelected = false; // No seleccionado: ya existe
      }
      
      // No permitir seleccionar si AMBOS son "Unknown" — no tiene sentido añadirlo
      final isFullyUnknown = normArtist.contains('unknown') && isUnknownTitle;
      if (isFullyUnknown && !ea.isExisting) {
        ea.isSelected = false;
      }
      
      return ea;
    }).toList();

    // === Deduplicación intra-detección ===
    // Si el mismo disco aparece varias veces en el escaneo (p.ej. fotos solapadas),
    // marcamos las apariciones extra como duplicado (existing) para no añadirlo 2 veces.
    final seenNewKeys = <String>{};
    for (final album in _albums) {
      // Solo nos interesa deduplicar entre los "nuevos" (no marcados como existing)
      if (album.isExisting) continue;
      
      final normArtist = _normalize(album.artist);
      final normTitle = _normalize(album.title);
      
      // Ignorar albums completamente desconocidos para este chequeo
      if (normArtist.contains('unknown') && normTitle.contains('unknown')) continue;
      
      final key = '$normArtist|||$normTitle';
      if (seenNewKeys.contains(key)) {
        // Ya vimos este disco como nuevo: este es un duplicado intra-scan
        album.isExisting = true;
        album.isSelected = false;
        debugPrint('Dedup intra-scan: "$normArtist" / "$normTitle" (duplicado de otra foto)');
      } else {
        seenNewKeys.add(key);
      }
    }

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();

    _loadCovers();
  }

  /// Discos que necesitan revisión (confianza < umbral y no editados)
  List<EditableAlbum> get _lowConfidenceAlbums => _albums
      .where((a) => a.confidence != null && a.confidence! < _confidenceThreshold && !a.isUserEdited)
      .toList();

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    for (final album in _albums) {
      album.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCovers() async {
    for (int i = 0; i < _albums.length; i++) {
      if (!mounted) return;
      
      final album = _albums[i];
      
      if (album.artist.toLowerCase().contains('unknown') ||
          album.title.toLowerCase().contains('unknown')) {
        setState(() => album.isLoadingCover = false);
        continue;
      }

      try {
        final result = await _discogsService.searchAlbum(
          artist: album.artist,
          title: album.title,
        );

        if (mounted) {
          setState(() {
            album.coverUrl = result?.imageUrl;
            if (result != null) {
              album.genres = result.genres;
              album.styles = result.styles;
            }
            album.isLoadingCover = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => album.isLoadingCover = false);
        }
      }

      if (i < _albums.length - 1) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    if (mounted) {
      setState(() => _isLoadingCovers = false);
    }
  }

  Future<void> _reloadCover(EditableAlbum album) async {
    album.syncFromControllers();
    if (album.artist.isEmpty || album.title.isEmpty) return;

    setState(() => album.isLoadingCover = true);
    HapticFeedback.lightImpact();

    try {
      final result = await _discogsService.searchAlbum(
        artist: album.artist,
        title: album.title,
      );

      if (mounted) {
        setState(() {
          album.coverUrl = result?.imageUrl;
          if (result != null) {
            album.genres = result.genres;
            album.styles = result.styles;
          }
          album.isLoadingCover = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => album.isLoadingCover = false);
      }
    }
  }

  /// Comprueba si un album es completamente desconocido (no seleccionable)
  bool _isFullyUnknown(EditableAlbum album) {
    final a = _normalize(album.artist);
    final t = _normalize(album.title);
    return a.contains('unknown') && t.contains('unknown');
  }

  void _toggleSelection(EditableAlbum album) {
    // No permitir seleccionar si es completamente desconocido
    if (_isFullyUnknown(album)) return;
    HapticFeedback.selectionClick();
    setState(() => album.isSelected = !album.isSelected);
  }

  void _updatePositions() {
    // Preservar la base de posición (offset del estante) al reordenar.
    // Si las posiciones estaban alineadas al estante (ej. 15-28),
    // tras reordenar mantener esa base en lugar de reiniciar a 1.
    final basePosition = _albums.isNotEmpty
        ? _albums.map((a) => a.position).reduce((a, b) => a < b ? a : b)
        : 1;
    for (int i = 0; i < _albums.length; i++) {
      _albums[i].position = basePosition + i;
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final album = _albums.removeAt(oldIndex);
      _albums.insert(newIndex, album);
      _updatePositions();
    });
  }

  void _showSearchDialog(EditableAlbum album) {
    final searchArtistController = TextEditingController(text: album.artist);
    final searchTitleController = TextEditingController(text: album.title);
    List<DiscogsAlbum> searchResults = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> performSearch() async {
            if (searchArtistController.text.isEmpty && 
                searchTitleController.text.isEmpty) return;

            setDialogState(() => isSearching = true);

            try {
              final query = '${searchArtistController.text} ${searchTitleController.text}'.trim();
              final results = await _discogsService.searchMultipleResults(query, limit: 6);
              setDialogState(() {
                searchResults = results;
                isSearching = false;
              });
            } catch (e) {
              setDialogState(() => isSearching = false);
            }
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.close, size: 20),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Buscar en Discogs',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search fields - Bento style
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildSearchInput(
                          controller: searchTitleController,
                          hint: 'Álbum',
                          icon: Icons.album_outlined,
                        ),
                        const SizedBox(height: 12),
                        _buildSearchInput(
                          controller: searchArtistController,
                          hint: 'Artista',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isSearching ? null : performSearch,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: isSearching
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Buscar',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Results
                Expanded(
                  child: searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_rounded, size: 56, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'Busca un álbum',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[500],
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final result = searchResults[index];
                            return _buildSearchResult(result, onTap: () {
                              HapticFeedback.mediumImpact();
                              setState(() {
                                album.artistController.text = result.artist;
                                album.titleController.text = result.title ?? '';
                                album.coverUrl = result.imageUrl;
                                album.genres = result.genres;
                                album.styles = result.styles;
                                album.isUserEdited = true;
                                album.syncFromControllers();
                                // Si era un disco no identificado, ahora es seleccionable
                                if (!album.isSelected && !album.isExisting) {
                                  album.isSelected = true;
                                }
                              });
                              Navigator.pop(context);
                            });
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        style: GoogleFonts.poppins(fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.poppins(color: Colors.grey[500]),
          prefixIcon: Icon(icon, color: Colors.grey[500], size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildSearchResult(DiscogsAlbum result, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: result.hasImage
                  ? CachedNetworkImage(
                      imageUrl: result.imageUrl!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 52,
                      height: 52,
                      color: Colors.grey[200],
                      child: Icon(Icons.album, color: Colors.grey[400]),
                    ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title ?? 'Sin título',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [result.year, result.format].where((e) => e != null).join(' • '),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAlbums() async {
    for (final album in _albums) {
      album.syncFromControllers();
    }

    // Solo guardar albums NUEVOS (no existentes) que estén seleccionados
    // Filtrar también "Unknown Artist" / "Unknown Album" como valores literales
    final newSelectedAlbums = _albums
        .where((a) => !a.isExisting && a.isSelected && a.artist.isNotEmpty && a.title.isNotEmpty)
        .where((a) {
          final na = _normalize(a.artist);
          final nt = _normalize(a.title);
          return !na.contains('unknown') || !nt.contains('unknown');
        })
        .toList();
    
    if (newSelectedAlbums.isEmpty) {
      _showSnackBar('No hay discos nuevos seleccionados', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Usuario no autenticado');

      // Usar la posición real del disco (ya alineada con el estante
      // si se calculó offset desde anclas en ScanResultsScreen).
      // Si no hay offset (primer scan), las posiciones son 1-based secuenciales.
      int savedCount = 0;
      for (final album in newSelectedAlbums) {
        // Guardar el album primero (con coverUrl de Discogs temporal)
        final created = await _albumService.createAlbum(
          userId: userId,
          zoneId: widget.zone.id,
          artist: album.artist,
          title: album.title,
          year: album.year,
          coverUrl: album.coverUrl,
          positionIndex: album.position,
          genres: album.genres.isNotEmpty ? album.genres : null,
          styles: album.styles.isNotEmpty ? album.styles : null,
        );
        savedCount++;

        // Persistir carátula en Supabase Storage (en background, no bloquea)
        if (created != null && album.coverUrl != null && album.coverUrl!.isNotEmpty) {
          // Extraer URL original (sin proxy) para descargar
          final originalUrl = DiscogsAlbum.unwrapProxyUrl(album.coverUrl!);
          _persistCoverInBackground(
            albumId: created.id,
            userId: userId,
            imageUrl: originalUrl,
          );
        }
      }

      if (mounted) {
        HapticFeedback.heavyImpact();
        final existingMsg = _existingCount > 0 ? ' ($_existingCount ratificados)' : '';
        _showSnackBar('¡$savedCount disco${savedCount == 1 ? '' : 's'} nuevo${savedCount == 1 ? '' : 's'} añadido${savedCount == 1 ? '' : 's'}!$existingMsg');
        await Future.delayed(const Duration(milliseconds: 400));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnackBar('Error: $e', isError: true);
      }
    }
  }

  /// Persiste una carátula de Discogs en Supabase Storage en background.
  /// No bloquea al usuario — se ejecuta fire-and-forget.
  void _persistCoverInBackground({
    required String albumId,
    required String userId,
    required String imageUrl,
  }) {
    // Fire-and-forget: no esperamos el resultado
    _storageService.persistCoverImage(
      imageUrl: imageUrl,
      userId: userId,
      albumId: albumId,
    ).then((storageUrl) {
      if (storageUrl != null) {
        // Actualizar el cover_url en la BD para que apunte a Storage
        _albumService.updateAlbumCover(albumId, storageUrl);
        debugPrint('✓ Carátula persistida en Storage: $albumId');
      }
    }).catchError((e) {
      debugPrint('⚠ Error persistiendo carátula: $e');
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: isError ? Colors.red : const Color(0xFF00C853),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  int get _selectedCount => _albums.where((a) => a.isSelected && !a.isExisting).length;
  int get _existingCount => _albums.where((a) => a.isExisting).length;
  int get _newCount => _albums.where((a) => !a.isExisting).length;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      height: size.height - statusBarHeight,
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildHeader(),
          // Imagen original colapsable con overlay de disco seleccionado
          _buildImagePreview(),
          if (_lowConfidenceAlbums.isNotEmpty && !_isLoadingCovers)
            _buildReviewBanner(),
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _buildReorderableList(),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(false),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.close, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Revisar Discos',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _existingCount > 0
                      ? '${l10n?.zone ?? 'Zona'} ${widget.zone.zoneIndex + 1} • $_newCount nuevos, $_existingCount ya guardados'
                      : '${l10n?.zone ?? 'Zona'} ${widget.zone.zoneIndex + 1} • ${_albums.length} detectados',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (_isLoadingCovers)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.grey[400]),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.check, size: 20, color: Colors.green[600]),
            ),
        ],
      ),
    );
  }

  /// Obtener la URL de la foto correcta según el disco seleccionado
  String get _currentImageUrl {
    if (_highlightedIndex != null && _highlightedIndex! < _albums.length) {
      final sourceIdx = _albums[_highlightedIndex!].sourceImageIndex;
      if (sourceIdx < widget.imageUrls.length) {
        return widget.imageUrls[sourceIdx];
      }
    }
    // Si no hay disco seleccionado, mostrar la primera foto
    // o la foto del "tab" activo si hay multi-foto
    return widget.imageUrls[_activePhotoTab.clamp(0, widget.imageUrls.length - 1)];
  }

  /// Tab activo para navegar entre fotos (sin disco seleccionado)
  int _activePhotoTab = 0;

  Widget _buildImagePreview() {
    return Column(
      children: [
        // Toggle button
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _isImageExpanded = !_isImageExpanded);
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.photo_rounded, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.isMultiPhoto
                        ? 'Fotos originales (${widget.imageUrls.length})'
                        : 'Foto original',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _isImageExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
        
        // Photo tabs for multi-photo mode
        if (_isImageExpanded && widget.isMultiPhoto && _highlightedIndex == null)
          Container(
            height: 36,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.imageUrls.length,
              itemBuilder: (context, index) {
                final isActive = index == _activePhotoTab;
                final albumsInPhoto = _albums.where((a) => a.sourceImageIndex == index).length;
                return GestureDetector(
                  onTap: () => setState(() => _activePhotoTab = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.primaryColor : Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Foto ${index + 1} ($albumsInPhoto)',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.white : Colors.grey[600],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        // Imagen expandible con overlay
        AnimatedCrossFade(
          firstChild: _buildImageWithOverlay(),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _isImageExpanded 
              ? CrossFadeState.showFirst 
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 300),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }

  Widget _buildImageWithOverlay() {
    // Calcular zoom para el disco seleccionado
    final hasHighlight = _highlightedIndex != null;
    
    // Determinar la imagen actual y los discos visibles en esta foto
    final currentUrl = _currentImageUrl;
    final int currentSourceIndex;
    if (hasHighlight) {
      currentSourceIndex = _albums[_highlightedIndex!].sourceImageIndex;
    } else {
      currentSourceIndex = _activePhotoTab.clamp(0, widget.imageUrls.length - 1);
    }
    
    // Filtrar discos de esta foto para los overlays
    final albumsInCurrentPhoto = <int, EditableAlbum>{};
    for (int i = 0; i < _albums.length; i++) {
      if (_albums[i].sourceImageIndex == currentSourceIndex) {
        albumsInCurrentPhoto[i] = _albums[i];
      }
    }
    final photoAlbumCount = albumsInCurrentPhoto.length;
    
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      height: hasHighlight ? 260 : 180, // Más alto cuando hay zoom
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calcular parámetros de zoom si hay disco seleccionado
            double zoomScale = 1.0;
            Offset zoomOffset = Offset.zero;
            
            if (hasHighlight) {
              final album = _albums[_highlightedIndex!];
              // Calcular posición relativa dentro de esta foto
              final localIndex = albumsInCurrentPhoto.keys.toList().indexOf(_highlightedIndex!);
              final xStart = album.spineXStart ?? (localIndex / photoAlbumCount.clamp(1, 999));
              final xEnd = album.spineXEnd ?? ((localIndex + 1) / photoAlbumCount.clamp(1, 999));
              final xCenter = (xStart + xEnd) / 2;
              
              // Zoom 3x centrado en el disco
              zoomScale = 3.0;
              // Offset para centrar el disco seleccionado
              final scaledCenter = xCenter * constraints.maxWidth * zoomScale;
              zoomOffset = Offset(
                -(scaledCenter - constraints.maxWidth / 2).clamp(
                  0.0,
                  constraints.maxWidth * (zoomScale - 1),
                ),
                -(constraints.maxHeight * (zoomScale - 1) / 2),
              );
            }
            
            // TransformationController para InteractiveViewer en modo zoom
            final transformController = TransformationController();
            if (hasHighlight) {
              transformController.value = Matrix4.identity()
                ..translate(zoomOffset.dx, zoomOffset.dy)
                ..scale(zoomScale);
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                // Imagen: InteractiveViewer cuando hay zoom, estática cuando no
                if (hasHighlight)
                  InteractiveViewer(
                    transformationController: transformController,
                    minScale: 1.0,
                    maxScale: 6.0,
                    boundaryMargin: const EdgeInsets.all(100),
                    child: CachedNetworkImage(
                      imageUrl: currentUrl,
                      fit: BoxFit.cover,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      placeholder: (_, __) => Container(
                        color: Colors.grey[200],
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                  )
                else
                  CachedNetworkImage(
                    imageUrl: currentUrl,
                    fit: BoxFit.cover,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    placeholder: (_, __) => Container(
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
                
                // Overlay con marcadores (solo visible sin zoom, solo discos de esta foto)
                if (!hasHighlight) ...[
                  Container(color: Colors.black.withOpacity(0.1)),
                  // Marcadores interactivos para discos de esta foto
                  ...albumsInCurrentPhoto.entries.map((entry) {
                    final globalIndex = entry.key;
                    final album = entry.value;
                    final localIndex = albumsInCurrentPhoto.keys.toList().indexOf(globalIndex);
                    final xStart = album.spineXStart ?? (localIndex / photoAlbumCount.clamp(1, 999));
                    final xEnd = album.spineXEnd ?? ((localIndex + 1) / photoAlbumCount.clamp(1, 999));
                    
                    final left = xStart * constraints.maxWidth;
                    final w = ((xEnd - xStart) * constraints.maxWidth).clamp(4.0, constraints.maxWidth);
                    
                    return Positioned(
                      left: left.clamp(0.0, constraints.maxWidth - 4),
                      top: 0,
                      bottom: 0,
                      width: w,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _highlightedIndex = globalIndex);
                          _scrollController.animateTo(
                            globalIndex * 104.0,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOutCubic,
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.symmetric(
                              vertical: BorderSide(
                                color: Colors.white.withOpacity(0.25),
                                width: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
                
                // Cuando hay zoom: mostrar info del disco y botón para salir
                if (hasHighlight) ...[
                  // Info del disco seleccionado
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.8),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '#${_albums[_highlightedIndex!].position}',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (widget.isMultiPhoto) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'F${_albums[_highlightedIndex!].sourceImageIndex + 1}',
                                style: GoogleFonts.poppins(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_albums[_highlightedIndex!].artist} — ${_albums[_highlightedIndex!].title}',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Botón para salir del zoom
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _highlightedIndex = null);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                  // Flechas de navegación
                  if (_highlightedIndex! > 0)
                    Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _highlightedIndex = _highlightedIndex! - 1);
                            _scrollController.animateTo(
                              _highlightedIndex! * 104.0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.chevron_left, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                  if (_highlightedIndex! < _albums.length - 1)
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _highlightedIndex = _highlightedIndex! + 1);
                            _scrollController.animateTo(
                              _highlightedIndex! * 104.0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.chevron_right, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildReviewBanner() {
    final count = _lowConfidenceAlbums.length;
    return GestureDetector(
      onTap: _scrollToFirstLowConfidence,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFF59E0B).withOpacity(0.15),
              const Color(0xFFF59E0B).withOpacity(0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.visibility_rounded, size: 18, color: Color(0xFFF59E0B)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count disco${count == 1 ? '' : 's'} para revisar',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF92400E),
                    ),
                  ),
                  Text(
                    'La IA no está segura de estos resultados',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: const Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
            ),
            // Botón de re-análisis
            GestureDetector(
              onTap: _isReanalyzing ? null : _reanalyzeLowConfidence,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _isReanalyzing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_fix_high, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Re-analizar',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Re-analiza discos con baja confianza usando una segunda pasada de Gemini
  /// Agrupa los discos por foto de origen para enviar la imagen correcta
  Future<void> _reanalyzeLowConfidence() async {
    final lowAlbums = _lowConfidenceAlbums;
    if (lowAlbums.isEmpty) return;
    
    HapticFeedback.mediumImpact();
    setState(() => _isReanalyzing = true);
    
    try {
      int improved = 0;
      
      // Agrupar discos dudosos por foto de origen
      final Map<int, List<EditableAlbum>> albumsByPhoto = {};
      for (final album in lowAlbums) {
        albumsByPhoto.putIfAbsent(album.sourceImageIndex, () => []).add(album);
      }
      
      // Re-analizar cada grupo con su foto correspondiente
      for (final entry in albumsByPhoto.entries) {
        final photoIndex = entry.key;
        final albumsInPhoto = entry.value;
        final imageUrl = photoIndex < widget.imageUrls.length
            ? widget.imageUrls[photoIndex]
            : widget.imageUrl;
      
        // Preparar coordenadas de los lomos dudosos
        final positions = albumsInPhoto.map((a) => a.position).toList();
        final spineCoords = <int, Map<String, double>>{};
        
        for (final album in albumsInPhoto) {
          if (album.spineXStart != null && album.spineXEnd != null) {
            spineCoords[album.position] = {
              'xStart': album.spineXStart!,
              'xEnd': album.spineXEnd!,
            };
          } else {
            // Estimar coordenadas uniformes
            final idx = _albums.indexOf(album);
            final albumsInSamePhoto = _albums.where((a) => a.sourceImageIndex == photoIndex).length;
            spineCoords[album.position] = {
              'xStart': idx / albumsInSamePhoto.clamp(1, 999),
              'xEnd': (idx + 1) / albumsInSamePhoto.clamp(1, 999),
            };
          }
        }
        
        final result = await _geminiService.reanalyzeAlbums(
          imageUrl: imageUrl,
          positions: positions,
          spineCoords: spineCoords,
        );
        
        if (!mounted) return;
        
        // Actualizar los álbumes mejorados
        for (final newAlbum in result.albums) {
          final idx = _albums.indexWhere((a) => a.position == newAlbum.position);
          if (idx >= 0) {
            final old = _albums[idx];
            // Solo actualizar si la nueva confianza es mayor o si antes era Unknown
            final wasUnknown = old.artist.contains('Unknown') || old.title.contains('Unknown');
            final isBetter = (newAlbum.confidence ?? 0) > (old.confidence ?? 0);
            
            if (wasUnknown || isBetter) {
              setState(() {
                old.artist = newAlbum.artist;
                old.title = newAlbum.title;
                old.artistController.text = newAlbum.artist;
                old.titleController.text = newAlbum.title;
                old.year = newAlbum.year;
                old.confidence = newAlbum.confidence;
                old.isLoadingCover = true;
              });
              improved++;
              
              // === Re-evaluar deduplicación tras actualización ===
              final updatedNormArtist = _normalize(newAlbum.artist);
              final updatedNormTitle = _normalize(newAlbum.title);
              final updatedKey = '$updatedNormArtist|||$updatedNormTitle';
              
              // ¿Ya existe en la colección guardada?
              bool nowDuplicate = widget.existingArtistTitlePairs.contains(updatedKey);
              
              // ¿Ya existe como otro disco nuevo en esta misma lista?
              if (!nowDuplicate) {
                for (int j = 0; j < _albums.length; j++) {
                  if (j == idx) continue; // no comparar consigo mismo
                  final other = _albums[j];
                  if (other.isExisting) continue; // ignorar los ya marcados como existing
                  final otherKey = '${_normalize(other.artist)}|||${_normalize(other.title)}';
                  if (otherKey == updatedKey) {
                    nowDuplicate = true;
                    debugPrint('Dedup post-reanalysis: "#${old.position}" ahora coincide con "#${other.position}" ($updatedKey)');
                    break;
                  }
                }
              }
              
              if (nowDuplicate) {
                setState(() {
                  old.isExisting = true;
                  old.isSelected = false;
                });
                debugPrint('Dedup post-reanalysis: "#${old.position}" marcado como existente ($updatedKey)');
              }
              
              // Buscar carátula actualizada en Discogs
              try {
                final discogsResult = await _discogsService.searchAlbum(
                  artist: newAlbum.artist,
                  title: newAlbum.title,
                );
                if (mounted) {
                  setState(() {
                    old.coverUrl = discogsResult?.imageUrl;
                    if (discogsResult != null) {
                      old.genres = discogsResult.genres;
                      old.styles = discogsResult.styles;
                    }
                    old.isLoadingCover = false;
                  });
                }
              } catch (_) {
                if (mounted) setState(() => old.isLoadingCover = false);
              }
            }
          }
        }
      }
      
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(improved > 0
                ? '$improved disco${improved == 1 ? '' : 's'} mejorado${improved == 1 ? '' : 's'}'
                : 'No se pudieron mejorar los resultados'),
            backgroundColor: improved > 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error en re-análisis: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al re-analizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isReanalyzing = false);
    }
  }

  void _scrollToFirstLowConfidence() {
    final firstLow = _lowConfidenceAlbums.first;
    final index = _albums.indexOf(firstLow);
    if (index >= 0) {
      // Cada tarjeta tiene ~90px de alto + 14px de margen
      final offset = index * 104.0;
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
      HapticFeedback.lightImpact();
    }
  }

  Widget _buildReorderableList() {
    return ReorderableListView.builder(
      scrollController: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: _albums.length,
      onReorder: _onReorder,
      buildDefaultDragHandles: false, // Desactivar handles por defecto
      proxyDecorator: _proxyDecorator,
      itemBuilder: (context, index) {
        final album = _albums[index];
        return _buildBentoCard(album, index);
      },
    );
  }

  // Decorador para el elemento arrastrado - Glassmorphism flotante
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final double elevation = Tween<double>(begin: 0, end: 20).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ).value;
        
        final double scale = Tween<double>(begin: 1.0, end: 1.02).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ).value;

        return Transform.scale(
          scale: scale,
          child: Material(
            elevation: elevation,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            shadowColor: AppTheme.primaryColor.withOpacity(0.25),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  // Detectar si estamos en web/escritorio
  bool get _isDesktop {
    return MediaQuery.of(context).size.width > 600;
  }

  // Tarjeta estilo Bento Box con Glassmorphism
  Widget _buildBentoCard(EditableAlbum album, int index) {
    final isLowConfidence = album.confidence != null && album.confidence! < _confidenceThreshold;
    final confidenceColor = album.confidence != null 
        ? _getConfidenceColor(album.confidence!) 
        : null;
    final isHighlighted = _highlightedIndex == index;
    final isExisting = album.isExisting;
    final isUnknown = _isFullyUnknown(album);
    
    final cardContent = GestureDetector(
      onTap: () {
        setState(() {
          _highlightedIndex = _highlightedIndex == index ? null : index;
          // Expandir imagen si está colapsada
          if (_highlightedIndex != null && !_isImageExpanded) {
            _isImageExpanded = true;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnknown
              ? Colors.grey.withOpacity(0.08)
              : isExisting
                  ? const Color(0xFF10B981).withOpacity(0.06)
                  : isHighlighted
                      ? AppTheme.primaryColor.withOpacity(0.08)
                      : album.isSelected 
                          ? (isLowConfidence ? confidenceColor!.withOpacity(0.04) : Colors.white.withOpacity(0.95))
                          : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isExisting
                ? const Color(0xFF10B981).withOpacity(0.4)
                : isHighlighted
                    ? AppTheme.primaryColor
                    : !album.isSelected
                        ? Colors.grey.withOpacity(0.15)
                        : isLowConfidence
                            ? confidenceColor!.withOpacity(0.5)
                            : AppTheme.primaryColor.withOpacity(0.2),
            width: isExisting ? 1.5 : (isHighlighted ? 2.5 : (isLowConfidence ? 2.0 : 1.5)),
          ),
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : album.isSelected
                  ? [
                      BoxShadow(
                        color: (isLowConfidence ? confidenceColor! : AppTheme.primaryColor).withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
            : null,
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: album.isSelected ? 1.0 : 0.5,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Número de posición prominente + indicador de foto
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor,
                        AppTheme.primaryColor.withOpacity(0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${album.position}',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                if (widget.isMultiPhoto) ...[
                  const SizedBox(height: 2),
                  Text(
                    'F${album.sourceImageIndex + 1}',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 10),
            
            // Drag handle para web/escritorio (integrado sutil)
            if (_isDesktop)
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: Colors.grey[300],
                      size: 20,
                    ),
                  ),
                ),
              ),
            
            // Cover con checkbox (sin badge de posición)
            _buildCoverSection(album, showPosition: false),
            
            const SizedBox(width: 14),
            
            // Info editable
            Expanded(child: _buildInfoSection(album)),
            
            // Solo un botón: buscar/editar
            _buildSearchButton(album),
          ],
        ),
      ),
    ),
    );

    // Swipe to delete (Dismissible) — solo para albums nuevos, no existentes
    final dismissibleCard = Dismissible(
      key: ValueKey('dismissible_${album.key}'),
      direction: album.isExisting ? DismissDirection.none : DismissDirection.endToStart,
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        setState(() {
          album.dispose();
          _albums.remove(album);
          _updatePositions();
        });
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.red[400],
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 26),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: cardContent,
          ),
        ),
      ),
    );

    // En móvil: long press para reordenar
    // En escritorio: drag handle visible
    if (_isDesktop) {
      return Container(key: album.key, child: dismissibleCard);
    } else {
      return ReorderableDelayedDragStartListener(
        key: album.key,
        index: index,
        child: dismissibleCard,
      );
    }
  }

  Widget _buildSearchButton(EditableAlbum album) {
    return GestureDetector(
      onTap: album.isLoadingCover ? null : () => _showSearchDialog(album),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: album.isLoadingCover
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.grey[400]),
                  ),
                )
              : Icon(
                  Icons.edit_rounded,
                  size: 20,
                  color: Colors.grey[600],
                ),
        ),
      ),
    );
  }

  Widget _buildCoverSection(EditableAlbum album, {bool showPosition = true}) {
    return GestureDetector(
      onTap: (album.isExisting || _isFullyUnknown(album)) ? null : () => _toggleSelection(album),
      child: Stack(
        children: [
          // Cover
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: album.isLoadingCover
                  ? _buildShimmerCover()
                  : album.coverUrl != null && album.coverUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: album.coverUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _buildShimmerCover(),
                          errorWidget: (_, __, ___) => _buildNoCover(),
                        )
                      : _buildNoCover(),
            ),
          ),
          
          // Overlay: badge de "ya existe" o checkbox normal
          Positioned(
            top: -4,
            left: -4,
            child: album.isExisting
                // Badge verde "ya en colección"
                ? Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x2010B981),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_circle, size: 14, color: Colors.white),
                  )
                // Checkbox normal para albums nuevos
                : AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: album.isSelected ? AppTheme.primaryColor : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: album.isSelected ? AppTheme.primaryColor : Colors.grey[300]!,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: album.isSelected
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(EditableAlbum album) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Badge "Ya en tu colección" para albums existentes
        if (album.isExisting)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 11, color: Color(0xFF10B981)),
                const SizedBox(width: 4),
                Text(
                  'Ya en tu colección',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
        // Badge "No identificado" para albums completamente desconocidos
        if (!album.isExisting && _isFullyUnknown(album))
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility_off, size: 11, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'No identificado — edita o descarta',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        // Confidence badge / Edited badge
        if (!album.isExisting && !_isFullyUnknown(album))
          if (album.isUserEdited)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit, size: 10, color: AppTheme.accentColor),
                  const SizedBox(width: 3),
                  Text(
                    'Editado por el usuario',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accentColor,
                    ),
                  ),
                ],
              ),
            )
          else if (album.confidence != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _getConfidenceColor(album.confidence!).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${(album.confidence! * 100).toInt()}% confianza',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _getConfidenceColor(album.confidence!),
                ),
              ),
            ),
        
        // Title field
        TextField(
          controller: album.titleController,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          maxLines: 1,
          decoration: InputDecoration(
            hintText: 'Título',
            hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
        ),
        
        // Artist field
        TextField(
          controller: album.artistController,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.grey[700],
          ),
          maxLines: 1,
          decoration: InputDecoration(
            hintText: 'Artista',
            hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
        ),
      ],
    );
  }


  Widget _buildShimmerCover() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[50]!,
      child: Container(color: Colors.grey[200]),
    );
  }

  Widget _buildNoCover() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.grey[200]!, Colors.grey[300]!],
        ),
      ),
      child: Center(
        child: Icon(Icons.album_rounded, size: 28, color: Colors.grey[400]),
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.9) return const Color(0xFF10B981);
    if (confidence >= 0.7) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedCount == 0 
                        ? 'Ningún disco nuevo seleccionado'
                        : '$_selectedCount disco${_selectedCount == 1 ? '' : 's'} nuevo${_selectedCount == 1 ? '' : 's'} listo${_selectedCount == 1 ? '' : 's'}',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    _existingCount > 0
                        ? '$_existingCount ya en tu colección'
                        : 'Mantén pulsado para reordenar',
                    style: GoogleFonts.poppins(
                      color: _existingCount > 0 ? const Color(0xFF10B981) : Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            
            // Save button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: ElevatedButton(
                onPressed: _isSaving || _selectedCount == 0 ? null : _saveAlbums,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        'Añadir $_selectedCount',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
