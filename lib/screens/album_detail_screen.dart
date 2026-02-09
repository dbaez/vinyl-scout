import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/album_model.dart';
import '../models/shelf_zone_model.dart';
import '../services/album_service.dart';
import '../services/discogs_service.dart';
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
            Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
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
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FIND MY VINYL',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        location.locationText,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (location.shelfId != null)
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white.withOpacity(0.5),
                    size: 18,
                  ),
              ],
            ),
            
            // Visualización de posición
            if (position != null) ...[
              const SizedBox(height: 20),
              
              // Indicador visual de posición
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      'Posición en la estantería',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Visualización de discos (navegable)
                    _buildAlbumCarousel(position),
                    
                    const SizedBox(height: 12),
                    
                    // Texto explicativo — usa el mismo position que el carrusel
                    Text(
                      'Disco #$position desde la izquierda',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Botón para ir a la zona
              if (_album.zoneId != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _navigateToZone,
                    icon: const Icon(Icons.grid_view_rounded, size: 18),
                    label: Text('Ver zona completa', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ],
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
