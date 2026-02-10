import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/album_model.dart';
import '../models/album_photo_model.dart';
import '../models/shelf_zone_model.dart';
import '../services/album_service.dart';
import '../services/discogs_service.dart';
import '../services/photo_service.dart';
import '../services/shelf_service.dart';
import '../theme/app_theme.dart';
import 'zone_inventory_screen.dart';

/// Pantalla de detalle de álbum con edición y ubicación
class AlbumDetailScreen extends StatefulWidget {
  final AlbumWithLocation albumWithLocation;
  final int totalAlbumsInZone;
  final List<AlbumModel>? zoneAlbums; // Lista opcional para navegación
  final Function(AlbumModel) onAlbumUpdated;
  final Function(String) onAlbumDeleted;
  final Function(String)? onFilterByGenre; // Filtrar colección por género/estilo

  const AlbumDetailScreen({
    super.key,
    required this.albumWithLocation,
    this.totalAlbumsInZone = 1,
    this.zoneAlbums,
    required this.onAlbumUpdated,
    required this.onAlbumDeleted,
    this.onFilterByGenre,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen>
    with SingleTickerProviderStateMixin {
  final AlbumService _albumService = AlbumService();
  final DiscogsService _discogsService = DiscogsService();
  final _supabase = Supabase.instance.client;
  
  // Controladores para edición
  late TextEditingController _artistController;
  late TextEditingController _titleController;
  late TextEditingController _searchController;
  
  late AlbumModel _album;
  String? _coverUrl;
  bool _isEditing = false;
  bool _isSearching = false;
  bool _isSaving = false;
  bool _hasChanges = false;
  bool _isMarkedAsPlaying = false;
  
  // Animación vinilo girando
  late AnimationController _vinylSpinController;
  
  // Resultados de búsqueda de Discogs
  List<DiscogsAlbum> _searchResults = [];
  DiscogsAlbum? _selectedResult;

  // Tracklist
  bool _isLoadingTracklist = false;
  bool _showTracklist = false;

  // Fotos del vinilo
  final _photoService = PhotoService();
  List<AlbumPhotoModel> _photos = [];
  bool _isLoadingPhotos = false;
  bool _photosLoaded = false;

  @override
  void initState() {
    super.initState();
    _album = widget.albumWithLocation.album;
    _coverUrl = _album.coverUrl;
    _artistController = TextEditingController(text: _album.artist);
    _titleController = TextEditingController(text: _album.title);
    _searchController = TextEditingController(
      text: '${_album.artist} ${_album.title}'.trim(),
    );
    _vinylSpinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _loadPhotos();
  }

  @override
  void dispose() {
    _artistController.dispose();
    _titleController.dispose();
    _searchController.dispose();
    _vinylSpinController.dispose();
    super.dispose();
  }

  void _checkChanges() {
    setState(() {
      _hasChanges = _selectedResult != null ||
          _artistController.text.trim() != _album.artist ||
          _titleController.text.trim() != _album.title;
    });
  }

  /// Carga el tracklist desde Discogs si no lo tiene.
  /// Si no tiene discogs_id, primero busca el release por artista+título.
  Future<void> _loadTracklistIfNeeded() async {
    // Si ya tiene tracklist con suficientes tracks, no recargar
    if (_album.hasTracklist && _album.tracklist!.length >= 5) return;
    if (_isLoadingTracklist) return;

    setState(() => _isLoadingTracklist = true);

    try {
      int? discogsId = _album.discogsId;

      // Si tiene un tracklist corto (probable single), buscar un release mejor
      final hasShortTracklist = _album.hasTracklist && _album.tracklist!.length < 5;

      // Si no tiene discogs_id o tiene tracklist corto, buscar LP
      if (discogsId == null || hasShortTracklist) {
        debugPrint('Tracklist: buscando discogs_id para "${_album.artist} - ${_album.title}"');
        final result = await _discogsService.searchVinylRelease(
          artist: _album.artist,
          title: _album.title,
        );
        if (result != null) {
          discogsId = result.id;
          // Guardar el discogs_id para futuras consultas
          await _albumService.updateAlbum(_album.id, {'discogs_id': discogsId});
          _album = _album.copyWith(discogsId: discogsId);
          debugPrint('Tracklist: discogs_id encontrado → $discogsId');
        }
      }

      if (discogsId == null) {
        debugPrint('Tracklist: no se encontró discogs_id');
        if (mounted) setState(() => _isLoadingTracklist = false);
        return;
      }

      final tracklistData = await _discogsService.fetchReleaseTracklist(discogsId);

      if (tracklistData != null && tracklistData.isNotEmpty && mounted) {
        final tracks = tracklistData
            .map((t) => TrackEntry.fromJson(t))
            .toList();

        // Guardar en la BD para cacheo
        await _albumService.updateAlbum(_album.id, {
          'tracklist': tracklistData,
        });

        final updatedAlbum = _album.copyWith(tracklist: tracks);

        if (widget.zoneAlbums != null) {
          final index = widget.zoneAlbums!.indexWhere((a) => a.id == _album.id);
          if (index != -1) widget.zoneAlbums![index] = updatedAlbum;
        }

        setState(() {
          _album = updatedAlbum;
          _isLoadingTracklist = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingTracklist = false);
      }
    } catch (e) {
      debugPrint('Error loading tracklist: $e');
      if (mounted) setState(() => _isLoadingTracklist = false);
    }
  }

  /// Navega al disco en la posición indicada
  void _navigateToAlbum(int position) {
    final albums = widget.zoneAlbums;
    if (albums == null || position < 1 || position > albums.length) return;
    
    // Buscar el álbum con esa posición
    final targetAlbum = albums.firstWhere(
      (a) => a.positionIndex == position,
      orElse: () => albums[position - 1], // Fallback por índice
    );
    
    if (targetAlbum.id == _album.id) return; // Ya es este disco
    
    HapticFeedback.mediumImpact();
    
    _vinylSpinController.stop();
    _vinylSpinController.reset();
    setState(() {
      _album = targetAlbum;
      _coverUrl = targetAlbum.coverUrl;
      _hasChanges = false;
      _isEditing = false;
      _isMarkedAsPlaying = false;
      _isLoadingTracklist = false;
      _showTracklist = false;
      _searchResults = [];
      _selectedResult = null;
      _artistController.text = targetAlbum.artist;
      _titleController.text = targetAlbum.title;
      _searchController.text = '${targetAlbum.artist} ${targetAlbum.title}'.trim();
    });
  }

  /// Busca en Discogs y muestra resultados
  Future<void> _searchDiscogs() async {
    // Combinar artista + título para búsqueda; si ambos vacíos, usar el campo de búsqueda
    final artist = _artistController.text.trim();
    final title = _titleController.text.trim();
    final query = '${artist} ${title}'.trim().isNotEmpty
        ? '${artist} ${title}'.trim()
        : _searchController.text.trim();
    if (query.isEmpty) return;
    _searchController.text = query;

    setState(() {
      _isSearching = true;
      _searchResults = [];
      _selectedResult = null;
    });
    HapticFeedback.lightImpact();

    try {
      final results = await _discogsService.searchMultipleResults(query, limit: 8);

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        _showSnackBar('Error buscando en Discogs');
      }
    }
  }

  /// Guarda cambios manuales de artista/título
  Future<void> _saveManualChanges() async {
    final newArtist = _artistController.text.trim();
    final newTitle = _titleController.text.trim();
    if (newArtist == _album.artist && newTitle == _album.title) return;

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final updates = <String, dynamic>{
        'artist': newArtist,
        'title': newTitle,
      };

      final success = await _albumService.updateAlbum(_album.id, updates);

      if (mounted && success) {
        final updatedAlbum = _album.copyWith(
          artist: newArtist,
          title: newTitle,
        );

        if (widget.zoneAlbums != null) {
          final index = widget.zoneAlbums!.indexWhere((a) => a.id == _album.id);
          if (index != -1) widget.zoneAlbums![index] = updatedAlbum;
        }

        setState(() {
          _album = updatedAlbum;
          _hasChanges = false;
          _isSaving = false;
          _searchController.text = '$newArtist $newTitle'.trim();
        });

        widget.onAlbumUpdated(updatedAlbum);
        HapticFeedback.heavyImpact();
        _showSnackBar('¡Actualizado!');
      } else {
        setState(() => _isSaving = false);
        _showSnackBar('Error al guardar cambios');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnackBar('Error al guardar: $e');
      }
    }
  }

  /// Selecciona un resultado de Discogs
  void _selectResult(DiscogsAlbum result) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedResult = result;
      _hasChanges = true;
    });
  }

  Future<void> _saveChanges() async {
    if (_selectedResult == null) return;

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final result = _selectedResult!;
      final updates = <String, dynamic>{
        'title': result.title,
        'artist': result.artist,
        'cover_url': result.imageUrl,
        'year': result.year,
        'discogs_id': result.id,
        if (result.genres.isNotEmpty) 'genres': result.genres,
        if (result.styles.isNotEmpty) 'styles': result.styles,
      };

      final success = await _albumService.updateAlbum(_album.id, updates);

      if (mounted && success) {
        final updatedAlbum = _album.copyWith(
          title: result.title,
          artist: result.artist,
          year: result.year,
          coverUrl: result.imageUrl,
          discogsId: result.id,
          genres: result.genres.isNotEmpty ? result.genres : null,
          styles: result.styles.isNotEmpty ? result.styles : null,
        );
        
        // Actualizar también la lista de zona si existe (para navegación carrusel)
        if (widget.zoneAlbums != null) {
          final index = widget.zoneAlbums!.indexWhere((a) => a.id == _album.id);
          if (index != -1) {
            widget.zoneAlbums![index] = updatedAlbum;
          }
        }
        
        setState(() {
          _album = updatedAlbum;
          _coverUrl = result.imageUrl;
          _hasChanges = false;
          _isEditing = false;
          _selectedResult = null;
          _searchResults = [];
          _artistController.text = updatedAlbum.artist;
          _titleController.text = updatedAlbum.title;
          _searchController.text = '${updatedAlbum.artist} ${updatedAlbum.title}'.trim();
        });
        
        // Notificar a la pantalla padre
        widget.onAlbumUpdated(updatedAlbum);
        
        HapticFeedback.heavyImpact();
        _showSnackBar('¡Disco actualizado!', isSuccess: true);
      }
    } catch (e) {
      _showSnackBar('Error al guardar', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _markAsPlaying() async {
    if (_isMarkedAsPlaying) return;

    HapticFeedback.heavyImpact();
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final now = DateTime.now().toUtc().toIso8601String();

    try {
      // 1. Registrar en play_history
      await _supabase.from('play_history').insert({
        'user_id': userId,
        'album_id': _album.id,
        'played_at': now,
      });

      // 2. Actualizar last_played_at en albums
      await _albumService.updateAlbum(_album.id, {'last_played_at': now});

      if (mounted) {
        setState(() {
          _isMarkedAsPlaying = true;
        });
        _vinylSpinController.repeat();
        _showSnackBar('¡A disfrutar de ${_album.title}!', isSuccess: true);
      }
    } catch (e) {
      debugPrint('Error marcando como escuchando: $e');
      _showSnackBar('Error al registrar escucha', isError: true);
    }
  }

  Future<void> _deleteAlbum() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Eliminar disco', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          '¿Seguro que quieres eliminar "${_album.title}" de tu colección?\n\nEsta acción no se puede deshacer.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              backgroundColor: Colors.red[50],
            ),
            child: Text('Eliminar', style: GoogleFonts.poppins(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      HapticFeedback.heavyImpact();
      
      final success = await _albumService.deleteAlbum(_album.id);
      
      if (mounted && success) {
        widget.onAlbumDeleted(_album.id);
        Navigator.pop(context);
        _showSnackBar('Disco eliminado');
      } else {
        _showSnackBar('Error al eliminar', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isSuccess = false, bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (isSuccess) const Icon(Icons.check_circle, color: Colors.white, size: 20),
            if (isError) const Icon(Icons.error, color: Colors.white, size: 20),
            if (isSuccess || isError) const SizedBox(width: 12),
            Text(message, style: GoogleFonts.poppins()),
          ],
        ),
        backgroundColor: isError ? Colors.red : isSuccess ? const Color(0xFF00C853) : Colors.grey[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _navigateToZone() async {
    final zoneId = _album.zoneId;
    final shelfId = widget.albumWithLocation.shelfId;
    final shelfName = widget.albumWithLocation.shelfName ?? 'Estantería';
    
    if (zoneId == null || shelfId == null) return;
    
    HapticFeedback.lightImpact();
    
    // Cargar la zona
    final shelfService = ShelfService();
    final zone = await shelfService.getZoneById(zoneId);
    
    if (zone != null && mounted) {
      ZoneInventoryScreen.show(
        context,
        zone: zone,
        shelfName: shelfName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final location = widget.albumWithLocation;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fondo con carátula difuminada
          if (_coverUrl != null && _coverUrl!.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: _coverUrl!,
                fit: BoxFit.cover,
                color: Colors.black.withOpacity(0.7),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          
          // Contenido principal
          SafeArea(
            child: Column(
              children: [
                // Header con botones
                _buildHeader(),
                
                // Contenido scrolleable
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        
                        // Carátula grande y centrada / Vinilo girando
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 600),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _isMarkedAsPlaying
                              ? _buildSpinningVinyl(size)
                              : _buildFullCover(size),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Info del álbum o modo edición
                        _isEditing 
                            ? _buildEditMode()
                            : _buildAlbumInfo(),
                        
                        // Solo mostrar ubicación y fecha cuando NO estamos editando
                        if (!_isEditing) ...[
                          const SizedBox(height: 20),
                          
                          // Botón "Escuchando ahora"
                          _buildPlayButton(),
                          
                          // Tracklist por cara (en demanda)
                          _buildTracklistToggle(),

                          // Fotos del vinilo
                          _buildPhotoGallery(),
                          
                          const SizedBox(height: 20),
                          
                          // Find My Vinyl - Ubicación clara
                          if (location.hasLocation)
                            _buildFindMyVinyl(),
                          
                          const SizedBox(height: 24),
                          
                          // Fecha añadido
                          _buildActionButtons(),
                        ],
                        
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Botón volver
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            ),
          ),
          
          const Spacer(),
          
          // Botón editar / cancelar
          GestureDetector(
            onTap: () {
              setState(() {
                if (_isEditing) {
                  // Cancelar edición
                  _isEditing = false;
                  _searchResults = [];
                  _selectedResult = null;
                  _hasChanges = false;
                  _searchController.text = '${_album.artist} ${_album.title}'.trim();
                } else {
                  // Iniciar edición
                  _isEditing = true;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isEditing 
                    ? Colors.red.withOpacity(0.3)
                    : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _isEditing ? Icons.close : Icons.edit_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          
          const SizedBox(width: 10),
          
          // Menú (solo si no está editando)
          if (!_isEditing)
            PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.more_horiz, color: Colors.white, size: 22),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: Colors.grey[900],
            onSelected: (value) {
              if (value == 'delete') _deleteAlbum();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red[400]),
                    const SizedBox(width: 12),
                    Text('Eliminar disco', style: GoogleFonts.poppins(color: Colors.red[400])),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFullCover(Size size) {
    final coverSize = size.width * 0.7;
    
    return Hero(
      tag: 'album_cover_${_album.id}',
      child: Container(
        width: coverSize,
        height: coverSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _isSearching
              ? Shimmer.fromColors(
                  baseColor: Colors.grey[800]!,
                  highlightColor: Colors.grey[600]!,
                  child: Container(color: Colors.grey[900]),
                )
              : _coverUrl != null && _coverUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.grey[900],
                        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                      ),
                      errorWidget: (_, __, ___) => _buildNoCover(),
                    )
                  : _buildNoCover(),
        ),
      ),
    );
  }

  Widget _buildNoCover() {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Icon(Icons.album_rounded, size: 80, color: Colors.grey[700]),
      ),
    );
  }

  Widget _buildAlbumInfo() {
    // Sombras para mejorar legibilidad con cualquier fondo
    final textShadows = [
      Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 8, offset: const Offset(0, 2)),
      Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 4)),
    ];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // Título con sombra
          Text(
            _album.title,
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: textShadows,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          
          // Artista con sombra
          Text(
            _album.artist,
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: Colors.white,
              shadows: textShadows,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          // Tags (año, géneros, estilos) - clicables para filtrar
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_album.year != null)
                _buildTag('${_album.year}', Icons.calendar_today, AppTheme.primaryColor),
              ..._album.genres.take(3).map((g) => 
                _buildTag(g, Icons.music_note, Colors.purple, filterable: true)),
              ..._album.styles.take(3).map((s) => 
                _buildTag(s, Icons.style, Colors.teal, filterable: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, IconData icon, Color color, {bool filterable = false}) {
    final canFilter = filterable && widget.onFilterByGenre != null;
    
    return GestureDetector(
      onTap: canFilter ? () {
        HapticFeedback.lightImpact();
        Navigator.pop(context);
        widget.onFilterByGenre!(text);
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canFilter) ...[
              const SizedBox(width: 6),
              Icon(Icons.filter_list, size: 12, color: Colors.white.withOpacity(0.6)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditMode() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Campos de edición (Artista + Título) ───
          Text(
            'Editar información',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 12),

          // Campo Artista
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: TextField(
              controller: _artistController,
              style: GoogleFonts.poppins(color: Colors.black87, fontSize: 15),
              onChanged: (_) => _checkChanges(),
              decoration: InputDecoration(
                labelText: 'Artista',
                labelStyle: GoogleFonts.poppins(color: Colors.grey[500], fontSize: 13),
                prefixIcon: Icon(Icons.person_outline, color: Colors.grey[500], size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Campo Título
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: TextField(
              controller: _titleController,
              style: GoogleFonts.poppins(color: Colors.black87, fontSize: 15),
              onChanged: (_) => _checkChanges(),
              decoration: InputDecoration(
                labelText: 'Título del disco',
                labelStyle: GoogleFonts.poppins(color: Colors.grey[500], fontSize: 13),
                prefixIcon: Icon(Icons.album_outlined, color: Colors.grey[500], size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          // ─── Botón guardar edición manual ───
          if (_hasChanges && _selectedResult == null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveManualChanges,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded, size: 20),
                label: Text('Guardar cambios',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ─── Búsqueda en Discogs ───
          Row(
            children: [
              Text(
                'Buscar en Discogs',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.language, size: 16, color: Colors.white.withOpacity(0.4)),
            ],
          ),
          const SizedBox(height: 10),

          // Botón de búsqueda rápida (usa artista + título)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSearching ? null : _searchDiscogs,
              icon: _isSearching
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 20),
              label: Text(
                _isSearching ? 'Buscando...' : 'Buscar con artista y título',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Resultados de búsqueda
          if (_searchResults.isNotEmpty) ...[
            Text(
              'Selecciona el disco correcto:',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 10),
            
            // Grid de resultados
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final result = _searchResults[index];
                  final isSelected = _selectedResult == result;
                  
                  return GestureDetector(
                    onTap: () => _selectResult(result),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 130,
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? AppTheme.primaryColor.withOpacity(0.3)
                            : Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected 
                              ? AppTheme.primaryColor 
                              : Colors.white.withOpacity(0.1),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Carátula
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: result.imageUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: result.imageUrl!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      placeholder: (_, __) => Container(
                                        color: Colors.grey[800],
                                        child: const Center(
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => _buildNoImage(),
                                    )
                                  : _buildNoImage(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Info
                          Text(
                            result.title,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            result.artist,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: Colors.white.withOpacity(0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (result.year != null)
                            Text(
                              '${result.year}',
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          
          // Indicador de selección
          if (_selectedResult != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Disco seleccionado',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${_selectedResult!.artist} - ${_selectedResult!.title}',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Botón guardar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveChanges,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  'Aplicar cambios',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
          
          // Estado vacío
          if (_searchResults.isEmpty && !_isSearching) ...[
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.album_rounded,
                    size: 48,
                    color: Colors.white.withOpacity(0.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Escribe el nombre del disco y pulsa buscar',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.4),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoImage() {
    return Container(
      color: Colors.grey[800],
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: 32,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildTracklistToggle() {
    // Si ya está expandido, mostrar la sección completa
    if (_showTracklist) {
      if (_album.hasTracklist) return _buildTracklistSection();
      if (_isLoadingTracklist) return _buildTracklistSection();
      // Ya se intentó cargar pero no hay tracklist
      return const SizedBox.shrink();
    }

    // Botón para mostrar tracklist
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() => _showTracklist = true);
            if (!_album.hasTracklist) {
              _loadTracklistIfNeeded();
            }
          },
          icon: const Icon(Icons.queue_music_rounded, size: 20),
          label: Text(
            'Ver tracklist',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.25)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }

  Widget _buildTracklistSection() {
    final textShadows = [
      Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 8, offset: const Offset(0, 2)),
    ];
    final tracksBySide = _album.tracksBySide;
    // Determinar si hay más de 2 caras → formato "Disco X - Cara Y"
    final totalSides = tracksBySide.keys.length;
    final useDiscFormat = totalSides > 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con botón colapsar
            GestureDetector(
              onTap: () => setState(() => _showTracklist = false),
              child: Row(
                children: [
                  Icon(Icons.queue_music_rounded, color: AppTheme.primaryColor, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'TRACKLIST',
                      style: GoogleFonts.archivoBlack(
                        fontSize: 15,
                        color: Colors.white,
                        letterSpacing: 1.2,
                        shadows: textShadows,
                      ),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white.withOpacity(0.5), size: 24),
                ],
              ),
            ),

            if (_isLoadingTracklist) ...[
              const SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Cargando tracklist…',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Tracks agrupados por cara
              ...tracksBySide.entries.map((entry) {
                final side = entry.key;
                final tracks = entry.value;
                // Para formato multi-disco: A/B = Disco 1, C/D = Disco 2, etc.
                String sideLabel;
                if (useDiscFormat) {
                  final sideIndex = tracksBySide.keys.toList().indexOf(side);
                  final discNumber = (sideIndex ~/ 2) + 1;
                  final discSide = sideIndex % 2 == 0 ? 'A' : 'B';
                  sideLabel = 'DISCO $discNumber — CARA $discSide';
                } else {
                  sideLabel = 'CARA $side';
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    // Etiqueta de cara
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.25)),
                      ),
                      child: Text(
                        sideLabel,
                        style: GoogleFonts.archivoBlack(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.85),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Tracks de esta cara
                    ...tracks.map((track) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          // Posición
                          SizedBox(
                            width: 32,
                            child: Text(
                              track.position,
                              style: GoogleFonts.robotoCondensed(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withOpacity(0.5),
                              ),
                            ),
                          ),
                          // Título
                          Expanded(
                            child: Text(
                              track.title,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Duración
                          if (track.duration != null && track.duration!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              track.duration!,
                              style: GoogleFonts.robotoCondensed(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isMarkedAsPlaying ? null : _markAsPlaying,
          icon: Icon(
            _isMarkedAsPlaying ? Icons.check_circle : Icons.play_circle_fill,
            size: 22,
          ),
          label: Text(
            _isMarkedAsPlaying ? '¡Escuchando ahora!' : 'Escuchando este disco',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isMarkedAsPlaying 
                ? const Color(0xFF00C853) 
                : AppTheme.secondaryColor,
            disabledBackgroundColor: const Color(0xFF00C853),
            disabledForegroundColor: Colors.white,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            shadowColor: _isMarkedAsPlaying 
                ? const Color(0xFF00C853).withOpacity(0.4)
                : AppTheme.secondaryColor.withOpacity(0.4),
          ),
        ),
      ),
    );
  }

  Widget _buildSpinningVinyl(Size size) {
    final vinylSize = size.width * 0.7;
    return SizedBox(
      key: const ValueKey('spinning-vinyl'),
      width: vinylSize,
      height: vinylSize,
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
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
            ),
            // Surcos del vinilo
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
            // Reflejo de luz
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
            // Carátula circular en el centro (label)
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
                  child: _coverUrl != null && _coverUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: _coverUrl!,
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
            // Agujero central
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
    );
  }

  // ─── GALERÍA DE FOTOS ───────────────────────

  Future<void> _loadPhotos() async {
    if (_isLoadingPhotos || _photosLoaded) return;
    setState(() => _isLoadingPhotos = true);
    try {
      final photos = await _photoService.getAlbumPhotos(_album.id);
      if (mounted) {
        setState(() {
          _photos = photos;
          _isLoadingPhotos = false;
          _photosLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPhotos = false;
          _photosLoaded = true;
        });
      }
    }
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('AÑADIR FOTO',
                  style: GoogleFonts.archivoBlack(
                      fontSize: 16, color: AppTheme.primaryColor)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryColor, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 22),
                ),
                title: Text('CÁMARA',
                    style: GoogleFonts.archivoBlack(
                        fontSize: 13, color: AppTheme.primaryColor)),
                subtitle: Text('Haz una foto ahora',
                    style: GoogleFonts.robotoCondensed(color: Colors.grey[600])),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryColor, width: 2),
                  ),
                  child: const Icon(Icons.photo_library, color: Colors.white, size: 22),
                ),
                title: Text('GALERÍA',
                    style: GoogleFonts.archivoBlack(
                        fontSize: 13, color: AppTheme.primaryColor)),
                subtitle: Text('Elige de tu galería',
                    style: GoogleFonts.robotoCondensed(color: Colors.grey[600])),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final file = source == 'camera'
        ? await _photoService.takePhoto()
        : await _photoService.pickFromGallery();

    if (file == null) return;

    // Caption opcional
    final captionController = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.primaryColor, width: 3),
        ),
        title: Text('DESCRIPCIÓN (OPCIONAL)',
            style: GoogleFonts.archivoBlack(
                fontSize: 14, color: AppTheme.primaryColor)),
        content: TextField(
          controller: captionController,
          maxLength: 100,
          style: GoogleFonts.robotoCondensed(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Ej: Primera edición UK 1977',
            hintStyle: GoogleFonts.robotoCondensed(color: Colors.grey[400]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text('SALTAR',
                style: GoogleFonts.archivoBlack(fontSize: 12, color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, captionController.text.trim()),
            child: Text('SUBIR',
                style: GoogleFonts.archivoBlack(
                    fontSize: 12, color: AppTheme.accentColor)),
          ),
        ],
      ),
    );

    if (caption == null) return; // Canceló

    HapticFeedback.mediumImpact();
    setState(() => _isLoadingPhotos = true);

    final result = await _photoService.addPhoto(
      albumId: _album.id,
      file: file,
      caption: caption.isNotEmpty ? caption : null,
    );

    if (result != null && mounted) {
      setState(() {
        _photos.insert(0, result);
        _isLoadingPhotos = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Text('Foto añadida', style: GoogleFonts.poppins(fontSize: 13)),
            ],
          ),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      if (mounted) setState(() => _isLoadingPhotos = false);
    }
  }

  Future<void> _deletePhoto(AlbumPhotoModel photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.primaryColor, width: 3),
        ),
        title: Text('ELIMINAR FOTO',
            style: GoogleFonts.archivoBlack(
                fontSize: 16, color: AppTheme.primaryColor)),
        content: Text('¿Eliminar esta foto?',
            style: GoogleFonts.robotoCondensed(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCELAR',
                style: GoogleFonts.archivoBlack(fontSize: 12, color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ELIMINAR',
                style: GoogleFonts.archivoBlack(
                    fontSize: 12, color: AppTheme.errorColor)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      HapticFeedback.mediumImpact();
      final success = await _photoService.deletePhoto(photo);
      if (success && mounted) {
        setState(() => _photos.removeWhere((p) => p.id == photo.id));
      }
    }
  }

  void _showFullPhoto(AlbumPhotoModel photo) {
    final index = _photos.indexOf(photo);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoPageViewer(
          photos: _photos,
          initialIndex: index >= 0 ? index : 0,
        ),
      ),
    );
  }

  Widget _buildPhotoGallery() {
    // Mientras carga, spinner sutil
    if (_isLoadingPhotos && !_photosLoaded) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
          ),
        ),
      );
    }

    // Sin fotos → sólo botón para añadir (compacto)
    if (_photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addPhoto,
            icon: const Icon(Icons.add_a_photo, size: 18),
            label: Text('Añadir fotos de mi vinilo',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.25)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      );
    }

    // Con fotos → mostrar directamente
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.photo_camera_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('MIS FOTOS',
                      style: GoogleFonts.archivoBlack(
                        fontSize: 14,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      )),
                ),
                // Botón añadir
                GestureDetector(
                  onTap: _addPhoto,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_a_photo,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Grid de fotos
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length + 1,
                itemBuilder: (_, i) {
                  if (i == _photos.length) {
                    return GestureDetector(
                      onTap: _addPhoto,
                      child: Container(
                        width: 100,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo,
                                color: Colors.white.withOpacity(0.4),
                                size: 24),
                            const SizedBox(height: 4),
                            Text('Añadir',
                                style: GoogleFonts.robotoCondensed(
                                    fontSize: 10,
                                    color: Colors.white.withOpacity(0.4))),
                          ],
                        ),
                      ),
                    );
                  }

                  final photo = _photos[i];
                  return GestureDetector(
                    onTap: () => _showFullPhoto(photo),
                    onLongPress: () => _deletePhoto(photo),
                    child: Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.2), width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: photo.photoUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: Colors.grey[900],
                              child: const Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.white),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey[900],
                              child: const Icon(Icons.broken_image,
                                  color: Colors.grey, size: 20),
                            ),
                          ),
                          if (photo.caption != null &&
                              photo.caption!.isNotEmpty)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                color: Colors.black.withOpacity(0.6),
                                child: Text(photo.caption!,
                                    style: GoogleFonts.robotoCondensed(
                                        fontSize: 8, color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text('Mantén pulsado para eliminar',
                style: GoogleFonts.robotoCondensed(
                    fontSize: 10, color: Colors.white.withOpacity(0.3))),
          ],
        ),
      ),
    );
  }

  Widget _buildFindMyVinyl() {
    final location = widget.albumWithLocation;
    final position = _album.positionIndex;
    
    return GestureDetector(
      onTap: _album.zoneId != null ? _navigateToZone : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icono de ubicación
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            // Info: ubicación + posición
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location.locationText,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (position != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Posición #$position desde la izquierda',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (location.shelfId != null)
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withOpacity(0.4),
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumCarousel(int currentPosition) {
    final totalAlbums = widget.zoneAlbums?.length ?? widget.totalAlbumsInZone;
    final canNavigate = widget.zoneAlbums != null && widget.zoneAlbums!.length > 1;
    
    // Determinar qué posiciones mostrar
    final List<int> visiblePositions = [];
    if (totalAlbums <= 7) {
      for (int i = 1; i <= totalAlbums; i++) {
        visiblePositions.add(i);
      }
    } else {
      // Mostrar un rango centrado en la posición actual
      int start = currentPosition - 3;
      int end = currentPosition + 3;
      
      if (start < 1) {
        start = 1;
        end = 7;
      } else if (end > totalAlbums) {
        end = totalAlbums;
        start = totalAlbums - 6;
      }
      
      for (int i = start; i <= end; i++) {
        visiblePositions.add(i);
      }
    }
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Flecha izquierda
        if (canNavigate && currentPosition > 1)
          GestureDetector(
            onTap: () => _navigateToAlbum(currentPosition - 1),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.chevron_left, color: Colors.white, size: 20),
            ),
          )
        else
          const SizedBox(width: 36),
        
        const SizedBox(width: 8),
        
        // Números
        ...visiblePositions.map((pos) {
          final isThisAlbum = pos == currentPosition;
          final isNavigable = canNavigate && !isThisAlbum;
          
          return GestureDetector(
            onTap: isNavigable ? () => _navigateToAlbum(pos) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isThisAlbum ? 48 : 36,
              height: isThisAlbum ? 56 : 44,
              decoration: BoxDecoration(
                color: isThisAlbum 
                    ? AppTheme.primaryColor 
                    : isNavigable 
                        ? Colors.white.withOpacity(0.25)
                        : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(isThisAlbum ? 10 : 8),
                border: isThisAlbum
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
                boxShadow: isThisAlbum
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  '$pos',
                  style: GoogleFonts.poppins(
                    fontSize: isThisAlbum ? 16 : 13,
                    fontWeight: FontWeight.bold,
                    color: isThisAlbum 
                        ? Colors.white 
                        : isNavigable
                            ? Colors.white.withOpacity(0.8)
                            : Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          );
        }),
        
        const SizedBox(width: 8),
        
        // Flecha derecha
        if (canNavigate && currentPosition < totalAlbums)
          GestureDetector(
            onTap: () => _navigateToAlbum(currentPosition + 1),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.chevron_right, color: Colors.white, size: 20),
            ),
          )
        else
          const SizedBox(width: 36),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Info adicional
          Row(
            children: [
              Expanded(
                child: _buildInfoTile(
                  icon: Icons.calendar_today,
                  label: 'Añadido',
                  value: _formatDate(_album.createdAt),
                ),
              ),
              const SizedBox(width: 12),
              if (_album.discogsId != null)
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.album,
                    label: 'Discogs ID',
                    value: '#${_album.discogsId}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white.withOpacity(0.7)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 
                    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

/// Visor de fotos con swipe horizontal (PageView)
class _PhotoPageViewer extends StatefulWidget {
  final List<AlbumPhotoModel> photos;
  final int initialIndex;

  const _PhotoPageViewer({
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_PhotoPageViewer> createState() => _PhotoPageViewerState();
}

class _PhotoPageViewerState extends State<_PhotoPageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // PageView de fotos
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              final photo = widget.photos[i];
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: photo.photoUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 48),
                  ),
                ),
              );
            },
          ),

          // Botón cerrar
          Positioned(
            top: padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close,
                    color: Colors.white, size: 22),
              ),
            ),
          ),

          // Indicador de posición (1/3)
          if (widget.photos.length > 1)
            Positioned(
              top: padding.top + 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.photos.length}',
                    style: GoogleFonts.robotoCondensed(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),

          // Caption de la foto actual
          if (widget.photos[_currentIndex].caption != null &&
              widget.photos[_currentIndex].caption!.isNotEmpty)
            Positioned(
              bottom: padding.bottom + 90,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.photos[_currentIndex].caption!,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // Tira de miniaturas abajo
          if (widget.photos.length > 1)
            Positioned(
              bottom: padding.bottom + 16,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 60,
                child: Center(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    itemCount: widget.photos.length,
                    itemBuilder: (_, i) {
                      final isActive = i == _currentIndex;
                      return GestureDetector(
                        onTap: () {
                          _pageController.animateToPage(i,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: isActive ? 60 : 48,
                          height: isActive ? 60 : 48,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActive
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                              width: isActive ? 2.5 : 1,
                            ),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.3),
                                      blurRadius: 8,
                                    )
                                  ]
                                : null,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Opacity(
                            opacity: isActive ? 1.0 : 0.5,
                            child: CachedNetworkImage(
                              imageUrl: widget.photos[i].photoUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                  color: Colors.grey[900]),
                              errorWidget: (_, __, ___) => Container(
                                  color: Colors.grey[900]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
