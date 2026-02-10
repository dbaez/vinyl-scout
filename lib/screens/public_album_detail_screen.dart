import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../models/album_model.dart';
import '../models/album_photo_model.dart';
import '../config/env_config.dart';
import '../services/discogs_service.dart';
import '../services/photo_service.dart';
import '../services/wishlist_service.dart';

/// Pantalla de detalle de un álbum de otro usuario (vista pública)
/// Muestra info básica, tracklist y enlace a Amazon
class PublicAlbumDetailScreen extends StatefulWidget {
  final AlbumModel album;

  const PublicAlbumDetailScreen({super.key, required this.album});

  @override
  State<PublicAlbumDetailScreen> createState() =>
      _PublicAlbumDetailScreenState();
}

class _PublicAlbumDetailScreenState extends State<PublicAlbumDetailScreen> {
  final _discogsService = DiscogsService();
  final _wishlistService = WishlistService();
  final _photoService = PhotoService();

  late AlbumModel _album;
  bool _isLoadingTracklist = false;
  bool _showTracklist = false;
  bool _isInWishlist = false;
  bool _addingToWishlist = false;

  // Fotos del vinilo (read-only)
  List<AlbumPhotoModel> _photos = [];
  bool _isLoadingPhotos = false;
  bool _photosLoaded = false;

  @override
  void initState() {
    super.initState();
    _album = widget.album;
    _checkWishlist();
    _loadPublicPhotos();
  }

  Future<void> _checkWishlist() async {
    final inWishlist = await _wishlistService.isInWishlist(
      discogsId: _album.discogsId,
      artist: _album.artist,
      title: _album.title,
    );
    if (mounted) setState(() => _isInWishlist = inWishlist);
  }

  Future<void> _toggleWishlist() async {
    if (_addingToWishlist) return;
    setState(() => _addingToWishlist = true);
    HapticFeedback.mediumImpact();

    if (_isInWishlist) {
      // No podemos eliminar desde aquí fácilmente (necesitamos el id),
      // así que simplemente informamos
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ya está en tu wishlist. Elimínalo desde tu perfil.',
                style: GoogleFonts.poppins(fontSize: 13)),
            backgroundColor: AppTheme.primaryColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _addingToWishlist = false);
      }
      return;
    }

    final result = await _wishlistService.addToWishlist(
      title: _album.title,
      artist: _album.artist,
      coverUrl: _album.coverUrl,
      year: _album.year,
      discogsId: _album.discogsId,
    );

    if (mounted) {
      setState(() {
        _addingToWishlist = false;
        if (result != null) _isInWishlist = true;
      });
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.favorite, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text('Añadido a tu wishlist',
                    style: GoogleFonts.poppins(fontSize: 13)),
              ],
            ),
            backgroundColor: AppTheme.secondaryColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _loadTracklist() async {
    if (_album.hasTracklist) return;
    if (_isLoadingTracklist) return;

    setState(() => _isLoadingTracklist = true);

    try {
      int? discogsId = _album.discogsId;

      // Si no tiene discogs_id, buscar (priorizando Vinyl/LP)
      if (discogsId == null) {
        final result = await _discogsService.searchVinylRelease(
          artist: _album.artist,
          title: _album.title,
        );
        if (result != null) discogsId = result.id;
      }

      if (discogsId == null) {
        if (mounted) setState(() => _isLoadingTracklist = false);
        return;
      }

      final tracklistData =
          await _discogsService.fetchReleaseTracklist(discogsId);

      if (tracklistData != null && tracklistData.isNotEmpty && mounted) {
        final tracks =
            tracklistData.map((t) => TrackEntry.fromJson(t)).toList();
        setState(() {
          _album = _album.copyWith(tracklist: tracks);
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

  void _openAmazon() {
    HapticFeedback.mediumImpact();
    final locale = WidgetsBinding.instance.platformDispatcher.locale.toString();
    final url = EnvConfig.amazonSearchUrl(
      artist: _album.artist,
      album: _album.title,
      locale: locale,
    );
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fondo difuminado
          if (_album.coverUrl != null && _album.coverUrl!.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: _album.coverUrl!,
                fit: BoxFit.cover,
                color: Colors.black.withOpacity(0.75),
                colorBlendMode: BlendMode.darken,
              ),
            ),

          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.arrow_back,
                              color: Colors.white, size: 22),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),

                // Contenido
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),

                        // Carátula
                        _buildCover(size),

                        const SizedBox(height: 28),

                        // Info
                        _buildAlbumInfo(),

                        const SizedBox(height: 24),

                        // Botones Amazon + Wishlist
                        _buildAmazonButton(),

                        const SizedBox(height: 10),

                        // Botón Wishlist
                        _buildWishlistButton(),

                        // Tracklist toggle
                        _buildTracklistToggle(),

                        // Fotos del vinilo (read-only)
                        _buildPublicPhotoGallery(),

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

  Widget _buildCover(Size size) {
    final coverSize = size.width * 0.6;
    return Container(
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
        child: _album.coverUrl != null && _album.coverUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: _album.coverUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: Colors.grey[900],
                  child: const Center(
                      child:
                          CircularProgressIndicator(color: Colors.white)),
                ),
                errorWidget: (_, __, ___) => _buildNoCover(),
              )
            : _buildNoCover(),
      ),
    );
  }

  Widget _buildNoCover() {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child:
            Icon(Icons.album_rounded, size: 60, color: Colors.grey[700]),
      ),
    );
  }

  Widget _buildAlbumInfo() {
    final textShadows = [
      Shadow(
          color: Colors.black.withOpacity(0.8),
          blurRadius: 8,
          offset: const Offset(0, 2)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            _album.title,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: textShadows,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            _album.artist,
            style: GoogleFonts.poppins(
              fontSize: 17,
              color: Colors.white,
              shadows: textShadows,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),

          // Tags
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_album.year != null) _buildTag('${_album.year}'),
              ..._album.genres.take(3).map((g) => _buildTag(g)),
              ..._album.styles.take(2).map((s) => _buildTag(s)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildAmazonButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _openAmazon,
          icon: const Icon(Icons.shopping_bag_rounded, size: 20),
          label: Text(
            'Comprar en Amazon',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9900), // Amazon orange
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 4,
          ),
        ),
      ),
    );
  }

  Widget _buildWishlistButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _toggleWishlist,
          icon: _addingToWishlist
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(
                  _isInWishlist ? Icons.favorite : Icons.favorite_border,
                  size: 20,
                ),
          label: Text(
            _isInWishlist ? 'En tu wishlist' : 'Añadir a mi wishlist',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                _isInWishlist ? AppTheme.secondaryColor : Colors.white,
            side: BorderSide(
              color: _isInWishlist
                  ? AppTheme.secondaryColor
                  : Colors.white.withOpacity(0.25),
            ),
            backgroundColor:
                _isInWishlist ? Colors.white.withOpacity(0.1) : null,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }

  // ─── FOTOS (READ-ONLY) ──────────────────────

  Future<void> _loadPublicPhotos() async {
    if (_isLoadingPhotos || _photosLoaded) return;
    setState(() => _isLoadingPhotos = true);
    try {
      final photos = await _photoService.getPublicAlbumPhotos(_album.id);
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

  void _openPhotoViewer(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoPageViewer(
          photos: _photos,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Widget _buildPublicPhotoGallery() {
    // Cargando
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

    // Sin fotos → no mostrar nada
    if (_photos.isEmpty) return const SizedBox.shrink();

    // Con fotos → mostrar directamente
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
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
                Text('FOTOS',
                    style: GoogleFonts.archivoBlack(
                      fontSize: 14,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    )),
                const Spacer(),
                Text('${_photos.length}',
                    style: GoogleFonts.robotoCondensed(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5))),
              ],
            ),
            const SizedBox(height: 12),
            // Thumbnails - toque abre visor con swipe
            SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                itemBuilder: (_, i) {
                  final photo = _photos[i];
                  return GestureDetector(
                    onTap: () => _openPhotoViewer(i),
                    child: Container(
                      width: 110,
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
                                        fontSize: 9, color: Colors.white),
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
            const SizedBox(height: 6),
            Center(
              child: Text('Toca para ver · Desliza para navegar',
                  style: GoogleFonts.robotoCondensed(
                      fontSize: 10, color: Colors.white.withOpacity(0.3))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTracklistToggle() {
    if (_showTracklist) {
      if (_album.hasTracklist) return _buildTracklistSection();
      if (_isLoadingTracklist) return _buildTracklistSection();
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() => _showTracklist = true);
            if (!_album.hasTracklist) _loadTracklist();
          },
          icon: const Icon(Icons.queue_music_rounded, size: 20),
          label: Text('Ver tracklist',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.25)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }

  Widget _buildTracklistSection() {
    final tracksBySide = _album.tracksBySide;
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
            // Header
            GestureDetector(
              onTap: () => setState(() => _showTracklist = false),
              child: Row(
                children: [
                  Icon(Icons.queue_music_rounded,
                      color: AppTheme.primaryColor == Colors.black
                          ? const Color(0xFFFF9900)
                          : AppTheme.primaryColor,
                      size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('TRACKLIST',
                        style: GoogleFonts.archivoBlack(
                          fontSize: 15,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        )),
                  ),
                  Icon(Icons.keyboard_arrow_up_rounded,
                      color: Colors.white.withOpacity(0.5), size: 24),
                ],
              ),
            ),

            if (_isLoadingTracklist) ...[
              const SizedBox(height: 20),
              const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFFF9900)),
                ),
              ),
            ] else ...[
              ...tracksBySide.entries.map((entry) {
                final side = entry.key;
                final tracks = entry.value;
                String sideLabel;
                if (useDiscFormat) {
                  final sideIndex =
                      tracksBySide.keys.toList().indexOf(side);
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9900).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFFF9900).withOpacity(0.4)),
                      ),
                      child: Text(sideLabel,
                          style: GoogleFonts.archivoBlack(
                            fontSize: 11,
                            color: const Color(0xFFFF9900),
                            letterSpacing: 1.0,
                          )),
                    ),
                    const SizedBox(height: 10),
                    ...tracks.map((track) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 32,
                                child: Text(track.position,
                                    style: GoogleFonts.robotoCondensed(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withOpacity(0.5),
                                    )),
                              ),
                              Expanded(
                                child: Text(track.title,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (track.duration != null &&
                                  track.duration!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(track.duration!,
                                    style: GoogleFonts.robotoCondensed(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.4),
                                    )),
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
}

// ─────────────────────────────────────────────
// Visor de fotos con swipe horizontal (PageView)
// ─────────────────────────────────────────────
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
