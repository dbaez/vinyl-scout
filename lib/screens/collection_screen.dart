import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/album_model.dart';
import '../services/album_service.dart';
import '../theme/app_theme.dart';
import 'album_detail_screen.dart';

/// Pantalla principal de Colección - Centro de gestión de álbumes
class CollectionScreen extends StatefulWidget {
  final VoidCallback? onNavigateToShelves;

  const CollectionScreen({super.key, this.onNavigateToShelves});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final AlbumService _albumService = AlbumService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<AlbumWithLocation> _albums = [];
  List<AlbumWithLocation> _filteredAlbums = [];
  bool _isLoading = true;
  String _sortBy = 'recent'; // recent, alpha, genre
  String? _activeGenreFilter; // Filtro de género/estilo activo
  List<String> _allTags = []; // Todos los géneros + estilos únicos
  
  @override
  void initState() {
    super.initState();
    _loadAlbums();
    _searchController.addListener(_filterAlbums);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadAlbums() async {
    setState(() => _isLoading = true);
    
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final albums = await _albumService.getUserAlbumsWithLocation(userId);
      
      if (mounted) {
        setState(() {
          _albums = albums;
          _extractAllTags();
          _sortAlbums();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Extrae todos los géneros y estilos únicos de la colección
  void _extractAllTags() {
    final tagSet = <String>{};
    for (final item in _albums) {
      tagSet.addAll(item.album.genres);
      tagSet.addAll(item.album.styles);
    }
    _allTags = tagSet.toList()..sort();
  }

  /// Filtra álbumes por texto de búsqueda + filtro de género activo
  void _filterAlbums() {
    final query = _searchController.text.toLowerCase().trim();
    
    setState(() {
      List<AlbumWithLocation> result = List.from(_albums);
      
      // Filtro por género/estilo activo
      if (_activeGenreFilter != null) {
        final tag = _activeGenreFilter!.toLowerCase();
        result = result.where((item) {
          final album = item.album;
          return album.genres.any((g) => g.toLowerCase() == tag) ||
                 album.styles.any((s) => s.toLowerCase() == tag);
        }).toList();
      }
      
      // Filtro por texto de búsqueda
      if (query.isNotEmpty) {
        result = result.where((item) {
          final album = item.album;
          return album.title.toLowerCase().contains(query) ||
                 album.artist.toLowerCase().contains(query) ||
                 album.genres.any((g) => g.toLowerCase().contains(query)) ||
                 album.styles.any((s) => s.toLowerCase().contains(query));
        }).toList();
      }
      
      _filteredAlbums = result;
    });
  }

  /// Activa/desactiva filtro por género o estilo
  void _toggleGenreFilter(String tag) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_activeGenreFilter == tag) {
        _activeGenreFilter = null;
      } else {
        _activeGenreFilter = tag;
      }
    });
    _filterAlbums();
    _sortAlbumsOnly();
  }

  void _sortAlbums() {
    // Aplica filtros primero, luego ordena
    _filterAlbums();
    _sortAlbumsOnly();
  }

  void _sortAlbumsOnly() {
    switch (_sortBy) {
      case 'alpha':
        _filteredAlbums.sort((a, b) => 
          '${a.album.artist} ${a.album.title}'.compareTo('${b.album.artist} ${b.album.title}')
        );
        break;
      case 'genre':
        _filteredAlbums.sort((a, b) {
          final aGenre = a.album.genres.isNotEmpty ? a.album.genres.first : 'ZZZ';
          final bGenre = b.album.genres.isNotEmpty ? b.album.genres.first : 'ZZZ';
          return aGenre.compareTo(bGenre);
        });
        break;
      case 'recent':
      default:
        _filteredAlbums.sort((a, b) => b.album.createdAt.compareTo(a.album.createdAt));
        break;
    }
  }

  void _showSortOptions() {
    HapticFeedback.lightImpact();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Ordenar por',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            _buildSortOption(
              icon: Icons.access_time,
              title: 'Fecha de incorporación',
              subtitle: 'Más recientes primero',
              value: 'recent',
            ),
            _buildSortOption(
              icon: Icons.sort_by_alpha,
              title: 'Alfabético',
              subtitle: 'Por artista y título',
              value: 'alpha',
            ),
            _buildSortOption(
              icon: Icons.category_rounded,
              title: 'Género',
              subtitle: 'Agrupar por estilo',
              value: 'genre',
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    final isSelected = _sortBy == value;
    
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _sortBy = value;
          _sortAlbums();
        });
        Navigator.pop(context);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withOpacity(0.1) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryColor : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppTheme.primaryColor : Colors.grey[800],
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),
            
            // Search bar
            _buildSearchBar(),
            
            // Genre/Style filter chips
            if (_allTags.isNotEmpty && !_isLoading)
              _buildGenreFilterChips(),
            
            // Content
            Expanded(
              child: _isLoading
                  ? _buildLoadingGrid()
                  : _albums.isEmpty
                      ? _buildEmptyState()
                      : _buildAlbumsGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          if (canPop) ...[
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.grey[700]),
              ),
            ),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MI COLECCIÓN',
                  style: GoogleFonts.archivoBlack(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryColor,
                  ),
                ),
                if (!_isLoading)
                  Text(
                    _activeGenreFilter != null
                        ? '${_filteredAlbums.length} de ${_albums.length} discos · $_activeGenreFilter'
                        : '${_albums.length} ${_albums.length == 1 ? 'disco' : 'discos'}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: _activeGenreFilter != null 
                          ? AppTheme.primaryColor 
                          : Colors.grey[500],
                    ),
                  ),
              ],
            ),
          ),
          
          // Sort button
          GestureDetector(
            onTap: _showSortOptions,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(Icons.sort_rounded, color: Colors.grey[700], size: 22),
            ),
          ),
          
          const SizedBox(width: 10),
          
          // Refresh button
          GestureDetector(
            onTap: _loadAlbums,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(Icons.refresh_rounded, color: Colors.grey[700], size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: GoogleFonts.poppins(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Buscar por artista, título o género...',
            hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
            prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400]),
            suffixIcon: _searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                    },
                    child: Icon(Icons.close, color: Colors.grey[400]),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildGenreFilterChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        scrollDirection: Axis.horizontal,
        itemCount: _allTags.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tag = _allTags[index];
          final isActive = _activeGenreFilter == tag;
          // Contar cuántos álbumes tienen este tag
          final count = _albums.where((item) =>
            item.album.genres.any((g) => g == tag) ||
            item.album.styles.any((s) => s == tag)
          ).length;
          
          return GestureDetector(
            onTap: () => _toggleGenreFilter(tag),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? AppTheme.primaryColor : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? AppTheme.primaryColor : Colors.grey[300]!,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tag,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.white.withOpacity(0.25)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isActive ? Colors.white : Colors.grey[500],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlbumsGrid() {
    return RefreshIndicator(
      onRefresh: _loadAlbums,
      color: AppTheme.primaryColor,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.72,
        ),
        itemCount: _filteredAlbums.length,
        itemBuilder: (context, index) {
          final item = _filteredAlbums[index];
          return _buildAlbumCard(item, index);
        },
      ),
    );
  }

  Widget _buildAlbumCard(AlbumWithLocation item, int index) {
    final album = item.album;
    
    return GestureDetector(
      onTap: () => _openAlbumDetail(item),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 300 + (index * 30)),
        curve: Curves.easeOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: 0.9 + (0.1 * value),
            child: Opacity(opacity: value, child: child),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover con Hero
              Expanded(
                child: Hero(
                  tag: 'album_cover_${album.id}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          album.coverUrl != null && album.coverUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: album.coverUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => _buildShimmerCover(),
                                  errorWidget: (_, __, ___) => _buildPlaceholderCover(),
                                )
                              : _buildPlaceholderCover(),
                          
                          // Location badge
                          if (item.hasLocation)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on, size: 12, color: Colors.white),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Z${item.zoneIndex}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              
              // Info
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
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
            ],
          ),
        ),
      ),
    );
  }

  void _openAlbumDetail(AlbumWithLocation item) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) {
          return AlbumDetailScreen(
            albumWithLocation: item,
            onAlbumUpdated: (updatedAlbum) {
              setState(() {
                final index = _albums.indexWhere((a) => a.album.id == updatedAlbum.id);
                if (index != -1) {
                  _albums[index] = AlbumWithLocation(
                    album: updatedAlbum,
                    shelfName: _albums[index].shelfName,
                    shelfId: _albums[index].shelfId,
                    zoneIndex: _albums[index].zoneIndex,
                  );
                  _extractAllTags();
                  _filterAlbums();
                  _sortAlbumsOnly();
                }
              });
            },
            onAlbumDeleted: (deletedId) {
              setState(() {
                _albums.removeWhere((a) => a.album.id == deletedId);
                _extractAllTags();
                _filterAlbums();
                _sortAlbumsOnly();
              });
            },
            onFilterByGenre: (genre) {
              _toggleGenreFilter(genre);
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Widget _buildShimmerCover() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(color: Colors.white),
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(Icons.album_rounded, size: 48, color: Colors.grey[400]),
      ),
    );
  }

  Widget _buildLoadingGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => _buildShimmerCard(),
    );
  }

  Widget _buildShimmerCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.album_outlined,
                size: 60,
                color: AppTheme.primaryColor.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Tu colección está vacía',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Escanea tus estanterías para empezar a catalogar tu colección de vinilos',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: widget.onNavigateToShelves,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(
                'Empezar a Escanear',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
