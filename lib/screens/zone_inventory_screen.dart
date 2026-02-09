import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

import '../models/shelf_zone_model.dart';
import '../models/album_model.dart';
import '../services/album_service.dart';
import '../services/discogs_service.dart';
import '../theme/app_theme.dart';
import 'album_detail_screen.dart';

/// Pantalla de inventario de una zona - muestra todos los álbumes
class ZoneInventoryScreen extends StatefulWidget {
  final ShelfZoneModel zone;
  final String shelfName;

  const ZoneInventoryScreen({
    super.key,
    required this.zone,
    required this.shelfName,
  });

  /// Abre la pantalla con Hero animation
  static Future<void> show(
    BuildContext context, {
    required ShelfZoneModel zone,
    required String shelfName,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) {
          return ZoneInventoryScreen(zone: zone, shelfName: shelfName);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<ZoneInventoryScreen> createState() => _ZoneInventoryScreenState();
}

class _ZoneInventoryScreenState extends State<ZoneInventoryScreen> {
  final AlbumService _albumService = AlbumService();
  final DiscogsService _discogsService = DiscogsService();
  
  List<AlbumModel> _albums = [];
  List<AlbumModel> _filteredAlbums = [];
  bool _isLoading = true;
  
  // Tracking de carátulas que se están cargando
  final Set<String> _loadingCovers = {};
  
  // Filtros
  String? _selectedGenre;
  int? _selectedYear;
  List<String> _availableGenres = [];
  List<int> _availableYears = [];

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    setState(() => _isLoading = true);
    
    try {
      final albums = await _albumService.getZoneAlbums(widget.zone.id);
      
      // Extraer géneros y años únicos para filtros
      final genres = <String>{};
      final years = <int>{};
      
      for (final album in albums) {
        genres.addAll(album.genres);
        if (album.year != null) years.add(album.year!);
      }
      
      if (mounted) {
        setState(() {
          _albums = albums;
          _filteredAlbums = albums;
          _availableGenres = genres.toList()..sort();
          _availableYears = years.toList()..sort((a, b) => b.compareTo(a));
          _isLoading = false;
        });
        
        // Buscar carátulas faltantes en segundo plano
        _fetchMissingCovers();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Busca carátulas faltantes en Discogs y las guarda en Supabase
  Future<void> _fetchMissingCovers() async {
    final albumsWithoutCover = _albums.where(
      (a) => a.coverUrl == null || a.coverUrl!.isEmpty
    ).toList();
    
    if (albumsWithoutCover.isEmpty) return;
    
    for (final album in albumsWithoutCover) {
      if (!mounted) break;
      
      // Marcar como cargando
      setState(() => _loadingCovers.add(album.id));
      
      try {
        final result = await _discogsService.searchAlbum(
          artist: album.artist,
          title: album.title,
        );
        
        if (result != null && result.imageUrl != null && mounted) {
          // Guardar en Supabase para persistir (no repetir búsqueda)
          await _albumService.updateAlbumCover(album.id, result.imageUrl!);
          
          // Actualizar estado local
          setState(() {
            final index = _albums.indexWhere((a) => a.id == album.id);
            if (index != -1) {
              _albums[index] = album.copyWith(coverUrl: result.imageUrl);
              _applyFilters(); // Re-aplicar filtros para actualizar _filteredAlbums
            }
            _loadingCovers.remove(album.id);
          });
        } else {
          setState(() => _loadingCovers.remove(album.id));
        }
      } catch (e) {
        if (mounted) {
          setState(() => _loadingCovers.remove(album.id));
        }
      }
      
      // Pequeña pausa para no saturar la API
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredAlbums = _albums.where((album) {
        // Filtro por género
        if (_selectedGenre != null && !album.genres.contains(_selectedGenre)) {
          return false;
        }
        // Filtro por año
        if (_selectedYear != null && album.year != _selectedYear) {
          return false;
        }
        return true;
      }).toList();
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedGenre = null;
      _selectedYear = null;
      _filteredAlbums = _albums;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Header con imagen de la zona
          _buildHeader(),
          
          // Filtros
          if (_availableGenres.isNotEmpty || _availableYears.isNotEmpty)
            _buildFiltersSection(),
          
          // Grid de álbumes
          _buildAlbumsGrid(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final zoneNumber = widget.zone.zoneIndex + 1;
    final hasPhoto = widget.zone.detailPhotoUrl != null;
    
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      stretch: true,
      backgroundColor: AppTheme.primaryColor,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
      ),
      actions: [
        IconButton(
          onPressed: _loadAlbums,
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
        background: Hero(
          tag: 'zone_${widget.zone.id}',
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Imagen de fondo
              if (hasPhoto)
                CachedNetworkImage(
                  imageUrl: widget.zone.detailPhotoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: AppTheme.primaryColor.withOpacity(0.3),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                  errorWidget: (_, __, ___) => _buildPlaceholderBackground(),
                )
              else
                _buildPlaceholderBackground(),
              
              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.3),
                      Colors.black.withOpacity(0.8),
                    ],
                    stops: const [0.0, 0.4, 0.7, 1.0],
                  ),
                ),
              ),
              
              // Info de la zona
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Badge de estantería
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Text(
                        widget.shelfName,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Título de la zona
                    Text(
                      'Zona $zoneNumber',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    
                    // Contador de discos
                    Row(
                      children: [
                        Icon(
                          Icons.album_rounded,
                          color: Colors.white.withOpacity(0.9),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_albums.length} ${_albums.length == 1 ? 'disco' : 'discos'}',
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_filteredAlbums.length != _albums.length) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_filteredAlbums.length} filtrados',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withOpacity(0.7),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.library_music_rounded,
          size: 80,
          color: Colors.white.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildFiltersSection() {
    final hasActiveFilters = _selectedGenre != null || _selectedYear != null;
    
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list_rounded, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Filtros rápidos',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const Spacer(),
                if (hasActiveFilters)
                  GestureDetector(
                    onTap: _clearFilters,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, size: 14, color: Colors.red[400]),
                          const SizedBox(width: 4),
                          Text(
                            'Limpiar',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.red[400],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Chips de filtros
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Filtros de año
                  if (_availableYears.isNotEmpty) ...[
                    _buildFilterDropdown(
                      label: 'Año',
                      icon: Icons.calendar_today_rounded,
                      value: _selectedYear?.toString(),
                      items: _availableYears.map((y) => y.toString()).toList(),
                      onSelected: (value) {
                        setState(() {
                          _selectedYear = value != null ? int.parse(value) : null;
                        });
                        _applyFilters();
                      },
                    ),
                    const SizedBox(width: 10),
                  ],
                  
                  // Filtros de género
                  ..._availableGenres.take(5).map((genre) {
                    final isSelected = _selectedGenre == genre;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(genre),
                        labelStyle: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.grey[700],
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedGenre = selected ? genre : null;
                          });
                          _applyFilters();
                        },
                        backgroundColor: Colors.grey[100],
                        selectedColor: AppTheme.primaryColor,
                        checkmarkColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required Function(String?) onSelected,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: value != null ? AppTheme.primaryColor : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: value != null ? AppTheme.primaryColor : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: value != null ? Colors.white : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Text(
              value ?? label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: value != null ? Colors.white : Colors.grey[700],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: value != null ? Colors.white : Colors.grey[600],
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: null,
          child: Text('Todos los $label', style: GoogleFonts.poppins(fontSize: 14)),
        ),
        const PopupMenuDivider(),
        ...items.map((item) => PopupMenuItem<String>(
          value: item,
          child: Text(item, style: GoogleFonts.poppins(fontSize: 14)),
        )),
      ],
    );
  }

  Widget _buildAlbumsGrid() {
    if (_isLoading) {
      return SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.75,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildShimmerAlbum(),
            childCount: 9,
          ),
        ),
      );
    }

    if (_filteredAlbums.isEmpty) {
      return SliverFillRemaining(
        child: _buildEmptyState(),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.72,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final album = _filteredAlbums[index];
            return _buildAlbumCard(album, index);
          },
          childCount: _filteredAlbums.length,
        ),
      ),
    );
  }

  Widget _buildAlbumCard(AlbumModel album, int index) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showAlbumDetail(album);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 300 + (index * 50)),
        curve: Curves.easeOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: 0.8 + (0.2 * value),
            child: Opacity(
              opacity: value,
              child: child,
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover con badge de posición
            Expanded(
              child: Stack(
                children: [
                  // Cover
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _loadingCovers.contains(album.id)
                          ? _buildLoadingCover()
                          : album.coverUrl != null && album.coverUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: album.coverUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  placeholder: (_, __) => _buildLoadingCover(),
                                  errorWidget: (_, __, ___) => _buildCoverPlaceholder(),
                                )
                              : _buildCoverPlaceholder(),
                    ),
                  ),
                  
                  // Badge de posición "Find My Vinyl"
                  if (album.positionIndex != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 12,
                              color: AppTheme.primaryColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${album.positionIndex}',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Título
            Text(
              album.title,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            
            // Artista
            Text(
              album.artist,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey[500],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCover() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        color: Colors.white,
        child: Center(
          child: Icon(
            Icons.search_rounded,
            size: 28,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: 36,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildShimmerAlbum() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 12,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 10,
            width: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilters = _selectedGenre != null || _selectedYear != null;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasFilters ? Icons.filter_alt_off : Icons.album_outlined,
                size: 48,
                color: AppTheme.primaryColor.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              hasFilters ? 'Sin resultados' : 'Zona vacía',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'No hay discos que coincidan con los filtros seleccionados'
                  : 'Escanea esta zona para descubrir los tesoros que contiene',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            if (hasFilters) ...[
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear_all),
                label: Text('Limpiar filtros', style: GoogleFonts.poppins()),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAlbumDetail(AlbumModel album) {
    HapticFeedback.lightImpact();
    
    // Crear AlbumWithLocation con los datos de la zona actual
    final albumWithLocation = AlbumWithLocation(
      album: album,
      shelfName: widget.shelfName,
      shelfId: widget.zone.shelfId,
      zoneIndex: widget.zone.zoneIndex,
    );
    
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => AlbumDetailScreen(
          albumWithLocation: albumWithLocation,
          totalAlbumsInZone: _albums.length,
          zoneAlbums: _albums, // Pasar lista para navegación
          onAlbumUpdated: (updatedAlbum) {
            setState(() {
              final index = _albums.indexWhere((a) => a.id == updatedAlbum.id);
              if (index != -1) {
                _albums[index] = updatedAlbum;
                _applyFilters();
              }
            });
          },
          onAlbumDeleted: (deletedId) {
            setState(() {
              _albums.removeWhere((a) => a.id == deletedId);
              _applyFilters();
            });
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }
}
