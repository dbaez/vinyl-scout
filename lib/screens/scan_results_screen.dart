import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/shelf_zone_model.dart';
import '../services/gemini_service.dart';
import '../services/album_service.dart';
import '../theme/app_theme.dart';
import 'review_results_screen.dart';

/// Pantalla de resultados del escaneo con Gemini
/// Procesa las imágenes secuencialmente y luego navega a ReviewResultsScreen
class ScanResultsScreen extends StatefulWidget {
  final ShelfZoneModel zone;
  final List<String> imageUrls;

  const ScanResultsScreen({
    super.key,
    required this.zone,
    required this.imageUrls,
  });

  /// Muestra la pantalla como modal
  static Future<bool?> show(
    BuildContext context, {
    required ShelfZoneModel zone,
    required List<String> imageUrls,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => ScanResultsScreen(
        zone: zone,
        imageUrls: imageUrls,
      ),
    );
  }

  @override
  State<ScanResultsScreen> createState() => _ScanResultsScreenState();
}

class _ScanResultsScreenState extends State<ScanResultsScreen>
    with SingleTickerProviderStateMixin {
  final GeminiService _geminiService = GeminiService();
  final AlbumService _albumService = AlbumService();

  // State
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  GeminiResponse? _response;
  
  // Multi-foto progress
  int _currentPhotoIndex = 0;
  int get _totalPhotos => widget.imageUrls.length;

  // Animation
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _processAllImages();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  /// Procesa todas las imágenes secuencialmente y combina resultados
  Future<void> _processAllImages() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPhotoIndex = 0;
    });

    try {
      final List<DetectedAlbum> allAlbums = [];
      int positionOffset = 0;

      for (int i = 0; i < widget.imageUrls.length; i++) {
        if (!mounted) return;
        
        setState(() => _currentPhotoIndex = i);

        final response = await _geminiService.processZoneImage(widget.imageUrls[i]);

        if (response.hasError) {
          // Si una foto falla, continuamos con las demás pero anotamos el error
          debugPrint('Error procesando foto ${i + 1}: ${response.error}');
          continue;
        }

        if (response.hasAlbums) {
          // Re-numerar posiciones consecutivamente y asignar sourceImageIndex
          for (final album in response.albums) {
            allAlbums.add(DetectedAlbum(
              position: positionOffset + album.position,
              artist: album.artist,
              title: album.title,
              year: album.year,
              confidence: album.confidence,
              spineXStart: album.spineXStart,
              spineXEnd: album.spineXEnd,
              sourceImageIndex: i,
            ));
          }
          positionOffset = allAlbums.length;
        }
      }

      if (!mounted) return;

      if (allAlbums.isNotEmpty) {
        // Re-numerar posiciones secuenciales (1-based) dentro del scan
        for (int i = 0; i < allAlbums.length; i++) {
          allAlbums[i] = DetectedAlbum(
            position: i + 1,
            artist: allAlbums[i].artist,
            title: allAlbums[i].title,
            year: allAlbums[i].year,
            confidence: allAlbums[i].confidence,
            spineXStart: allAlbums[i].spineXStart,
            spineXEnd: allAlbums[i].spineXEnd,
            sourceImageIndex: allAlbums[i].sourceImageIndex,
          );
        }

        // Cargar albums existentes de la zona para deduplicación
        final existingAlbums = await _albumService.getZoneAlbums(widget.zone.id);
        debugPrint('Albums existentes en zona: ${existingAlbums.length}');

        // === Alinear posiciones con la estantería real ===
        // Cuando se escanea una segunda foto de la misma zona, Gemini numera
        // desde 1, pero los discos reales pueden empezar más adelante.
        // Buscamos "anclas" (discos en el scan que ya existen en la BD)
        // para calcular el offset de posición correcto.
        if (existingAlbums.isNotEmpty) {
          final anchorOffsets = <int>[]; // diferencias: existingPos - detectedPos
          
          for (final detected in allAlbums) {
            final normDA = _normalize(detected.artist);
            final normDT = _normalize(detected.title);
            // Ignorar unknowns como anclas
            if (normDA.contains('unknown') || normDT.contains('unknown')) continue;
            
            for (final existing in existingAlbums) {
              if (existing.positionIndex == null) continue;
              final normEA = _normalize(existing.artist);
              final normET = _normalize(existing.title);
              if (normDA == normEA && normDT == normET) {
                anchorOffsets.add(existing.positionIndex! - detected.position);
                debugPrint('Ancla: "${detected.artist}" detectado=#${detected.position} → existente=#${existing.positionIndex}');
                break;
              }
            }
          }
          
          if (anchorOffsets.isNotEmpty) {
            // Usar la mediana de las diferencias como offset (robusto ante outliers)
            anchorOffsets.sort();
            final shelfOffset = anchorOffsets[anchorOffsets.length ~/ 2];
            
            if (shelfOffset != 0) {
              debugPrint('Offset de posición: $shelfOffset (${anchorOffsets.length} anclas)');
              for (int i = 0; i < allAlbums.length; i++) {
                allAlbums[i] = DetectedAlbum(
                  position: allAlbums[i].position + shelfOffset,
                  artist: allAlbums[i].artist,
                  title: allAlbums[i].title,
                  year: allAlbums[i].year,
                  confidence: allAlbums[i].confidence,
                  spineXStart: allAlbums[i].spineXStart,
                  spineXEnd: allAlbums[i].spineXEnd,
                  sourceImageIndex: allAlbums[i].sourceImageIndex,
                );
              }
              debugPrint('Posiciones ajustadas: ${allAlbums.first.position}..${allAlbums.last.position}');
            }
          } else {
            debugPrint('Sin anclas para calcular offset — posiciones relativas al scan');
          }
        }

        // Construir datos de deduplicación enriquecidos
        final existingArtistTitlePairs = existingAlbums
            .map((a) => '${_normalize(a.artist)}|||${_normalize(a.title)}')
            .toSet();
        
        // Mapa posición → artista normalizado (para matching por posición)
        final existingPositionArtists = <int, String>{};
        // Set de artistas normalizados (para matching cuando título es "Unknown")
        final existingArtists = <String>{};
        for (final a in existingAlbums) {
          if (a.positionIndex != null) {
            existingPositionArtists[a.positionIndex!] = _normalize(a.artist);
          }
          existingArtists.add(_normalize(a.artist));
        }

        // Navegar a ReviewResultsScreen con los resultados combinados + existentes
        final saved = await ReviewResultsScreen.show(
          context,
          zone: widget.zone,
          imageUrls: widget.imageUrls,
          detectedAlbums: allAlbums,
          existingAlbumCount: existingAlbums.length,
          existingArtistTitlePairs: existingArtistTitlePairs,
          existingPositionArtists: existingPositionArtists,
          existingArtists: existingArtists,
        );
        
        // Propagar el resultado a ShelfDetailScreen
        if (mounted) {
          Navigator.of(context).pop(saved);
        }
      } else {
        setState(() {
          _response = GeminiResponse(albums: []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _saveAlbums() async {
    if (_response == null || !_response!.hasAlbums) return;

    final confirmedAlbums = _response!.albums.where((a) => a.isConfirmed).toList();
    if (confirmedAlbums.isEmpty) {
      _showSnackBar('Selecciona al menos un álbum para guardar', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Usuario no autenticado');

      final created = await _albumService.createAlbumsFromGemini(
        userId: userId,
        zoneId: widget.zone.id,
        albums: confirmedAlbums,
      );

      if (mounted) {
        _showSnackBar('¡$created álbumes guardados!');
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.of(context).pop(true); // Retorna true para indicar éxito
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnackBar('Error: $e', isError: true);
      }
    }
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

  void _toggleAlbum(int index) {
    setState(() {
      _response!.albums[index].isConfirmed = !_response!.albums[index].isConfirmed;
    });
  }

  void _selectAll() {
    setState(() {
      for (var album in _response!.albums) {
        album.isConfirmed = true;
      }
    });
  }

  void _deselectAll() {
    setState(() {
      for (var album in _response!.albums) {
        album.isConfirmed = false;
      }
    });
  }

  int get _selectedCount => _response?.albums.where((a) => a.isConfirmed).length ?? 0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      height: size.height - statusBarHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
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
          _buildHeader(),

          // Content
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _error != null
                    ? _buildErrorState()
                    : _buildResultsList(),
          ),

          // Footer with save button
          if (!_isLoading && _error == null && _response?.hasAlbums == true)
            _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Resultados del Escaneo',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${l10n?.zone ?? 'Zona'} ${widget.zone.zoneIndex + 1}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // Mock indicator
          if (GeminiService.useMock)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'MOCK',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    final isMulti = _totalPhotos > 1;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated Gemini icon
            AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor.withOpacity(0.2),
                        AppTheme.accentColor.withOpacity(0.3 + _shimmerController.value * 0.3),
                        AppTheme.secondaryColor.withOpacity(0.2),
                      ],
                      transform: GradientRotation(_shimmerController.value * 6.28),
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 48,
                    color: AppTheme.accentColor,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              isMulti
                  ? 'Analizando foto ${_currentPhotoIndex + 1} de $_totalPhotos...'
                  : 'Analizando con Gemini...',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isMulti
                  ? 'Procesando cada sección de tu estantería'
                  : 'Identificando los vinilos en tu estantería',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: isMulti
                  ? Column(
                      children: [
                        LinearProgressIndicator(
                          value: (_currentPhotoIndex + 1) / _totalPhotos,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation(AppTheme.accentColor),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_currentPhotoIndex + 1} / $_totalPhotos fotos',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    )
                  : LinearProgressIndicator(
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation(AppTheme.accentColor),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Error al procesar',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Error desconocido',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _processAllImages,
              icon: const Icon(Icons.refresh),
              label: Text('Reintentar', style: GoogleFonts.poppins()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    if (_response == null || !_response!.hasAlbums) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // Stats and actions
        _buildStatsBar(),

        // Albums list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _response!.albums.length,
            itemBuilder: (context, index) {
              final album = _response!.albums[index];
              return _buildAlbumTile(album, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsBar() {
    final total = _response!.albums.length;
    final selected = _selectedCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey[50],
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$selected / $total seleccionados',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _selectAll,
            child: Text(
              'Todos',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppTheme.secondaryColor,
              ),
            ),
          ),
          TextButton(
            onPressed: _deselectAll,
            child: Text(
              'Ninguno',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumTile(DetectedAlbum album, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: album.isConfirmed ? Colors.white : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: album.isConfirmed
              ? AppTheme.primaryColor.withOpacity(0.3)
              : Colors.grey[200]!,
          width: album.isConfirmed ? 2 : 1,
        ),
        boxShadow: album.isConfirmed
            ? [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: InkWell(
        onTap: () => _toggleAlbum(index),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Position number
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: album.isConfirmed
                      ? AppTheme.primaryColor
                      : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '${album.position}',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Album info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: album.isConfirmed ? Colors.black : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      album.artist,
                      style: GoogleFonts.poppins(
                        color: album.isConfirmed ? Colors.grey[600] : Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                    if (album.year != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 12,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${album.year}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                          ),
                          if (album.confidence != null) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getConfidenceColor(album.confidence!).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                album.confidencePercent,
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _getConfidenceColor(album.confidence!),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Checkbox
              Transform.scale(
                scale: 1.2,
                child: Checkbox(
                  value: album.isConfirmed,
                  onChanged: (_) => _toggleAlbum(index),
                  activeColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.9) return Colors.green;
    if (confidence >= 0.7) return Colors.orange;
    return Colors.red;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.album_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No se detectaron álbumes',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Intenta con una foto más clara o con mejor iluminación',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
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
                    '$_selectedCount álbumes seleccionados',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Se guardarán en la Zona ${widget.zone.zoneIndex + 1}',
                    style: GoogleFonts.poppins(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Save button
            ElevatedButton(
              onPressed: _isSaving || _selectedCount == 0 ? null : _saveAlbums,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.save_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Guardar en Estantería',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Normaliza un string para comparación: lowercase, trim, colapsar espacios
  static String _normalize(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}
