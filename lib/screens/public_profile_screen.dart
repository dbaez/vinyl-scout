import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../models/user_model.dart';
import '../models/album_model.dart';
import '../models/shelf_model.dart';
import '../models/wishlist_item_model.dart';
import '../services/social_service.dart';
import '../services/wishlist_service.dart';
import '../config/env_config.dart';
import 'public_album_detail_screen.dart';

/// Pantalla de perfil público de otro usuario
class PublicProfileScreen extends StatefulWidget {
  final String userId;

  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final _socialService = SocialService();
  final _wishlistService = WishlistService();

  PublicUserProfile? _profile;
  List<ShelfModel> _shelves = [];
  List<AlbumModel> _albums = [];
  List<WishlistItemModel> _wishlist = [];
  bool _isLoading = true;
  int _viewIndex = 0; // 0 = estanterías, 1 = colección, 2 = wishlist

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _socialService.getPublicProfile(widget.userId);
    final shelves = await _socialService.getPublicShelves(widget.userId);

    if (mounted) {
      setState(() {
        _profile = profile;
        _shelves = shelves;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAlbums() async {
    if (_albums.isNotEmpty) return; // Ya cargados

    final albums = await _socialService.getPublicAlbums(widget.userId);
    if (mounted) {
      setState(() => _albums = albums);
    }
  }

  Future<void> _loadWishlist() async {
    if (_wishlist.isNotEmpty) return; // Ya cargados

    final items = await _wishlistService.getPublicWishlist(widget.userId);
    if (mounted) {
      setState(() => _wishlist = items);
    }
  }

  Future<void> _toggleFollow() async {
    if (_profile == null) return;
    HapticFeedback.mediumImpact();

    bool success;
    if (_profile!.isFollowedByMe) {
      success = await _socialService.unfollowUser(widget.userId);
    } else {
      success = await _socialService.followUser(widget.userId);
    }

    if (success && mounted) {
      setState(() {
        _profile = PublicUserProfile(
          id: _profile!.id,
          displayName: _profile!.displayName,
          photoUrl: _profile!.photoUrl,
          username: _profile!.username,
          bio: _profile!.bio,
          albumCount: _profile!.albumCount,
          followerCount: _profile!.followerCount + (_profile!.isFollowedByMe ? -1 : 1),
          followingCount: _profile!.followingCount,
          isFollowedByMe: !_profile!.isFollowedByMe,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.primaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _profile?.username != null ? '@${_profile!.username}' : 'PERFIL',
          style: GoogleFonts.archivoBlack(
              fontSize: 18, color: AppTheme.primaryColor),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(3),
          child:
              Divider(color: AppTheme.primaryColor, thickness: 3, height: 3),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? _buildNotFound()
              : _buildContent(),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_off,
              size: 64, color: AppTheme.primaryColor.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text('Perfil no disponible',
              style: GoogleFonts.archivoBlack(
                  fontSize: 18, color: AppTheme.primaryColor)),
          const SizedBox(height: 8),
          Text('Este usuario no tiene un perfil público',
              style: GoogleFonts.robotoCondensed(
                  fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final p = _profile!;

    return CustomScrollView(
      slivers: [
        // Header del perfil
        SliverToBoxAdapter(child: _buildProfileHeader(p)),

        // Toggle estanterías / colección / wishlist
        SliverToBoxAdapter(child: _buildViewToggle()),

        // Contenido
        if (_viewIndex == 0)
          _buildShelvesGrid()
        else if (_viewIndex == 1)
          _buildAlbumsGrid()
        else
          _buildWishlistGrid(),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildProfileHeader(PublicUserProfile p) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryColor, width: 3),
              boxShadow:
                  AppTheme.popShadow(AppTheme.secondaryColor, offset: 4),
            ),
            child: CircleAvatar(
              radius: 44,
              backgroundImage:
                  p.photoUrl != null ? NetworkImage(p.photoUrl!) : null,
              child: p.photoUrl == null
                  ? const Icon(Icons.person, size: 44)
                  : null,
            ),
          ),
          const SizedBox(height: 14),

          // Nombre
          Text(
            p.displayName.toUpperCase(),
            style: GoogleFonts.archivoBlack(
                fontSize: 22, color: AppTheme.primaryColor),
            textAlign: TextAlign.center,
          ),

          if (p.username != null) ...[
            const SizedBox(height: 2),
            Text('@${p.username}',
                style: GoogleFonts.robotoCondensed(
                    fontSize: 14, color: Colors.grey[500])),
          ],

          if (p.bio != null && p.bio!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(p.bio!,
                style: GoogleFonts.robotoCondensed(
                    fontSize: 14, color: Colors.grey[700]),
                textAlign: TextAlign.center),
          ],

          const SizedBox(height: 18),

          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStat('${p.albumCount}', 'DISCOS'),
              const SizedBox(width: 28),
              _buildStat('${p.followerCount}', 'SEGUIDORES'),
              const SizedBox(width: 28),
              _buildStat('${p.followingCount}', 'SIGUIENDO'),
            ],
          ),

          const SizedBox(height: 18),

          // Botón seguir (ocultar si es mi propio perfil)
          if (Supabase.instance.client.auth.currentUser?.id != widget.userId)
          GestureDetector(
            onTap: _toggleFollow,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              decoration: BoxDecoration(
                color: p.isFollowedByMe
                    ? Colors.white
                    : AppTheme.secondaryColor,
                border: Border.all(
                    color: p.isFollowedByMe
                        ? AppTheme.primaryColor
                        : AppTheme.secondaryColor,
                    width: 3),
                borderRadius: BorderRadius.circular(8),
                boxShadow: AppTheme.popShadow(
                    p.isFollowedByMe
                        ? AppTheme.primaryColor
                        : AppTheme.secondaryColor,
                    offset: 3),
              ),
              child: Text(
                p.isFollowedByMe ? 'SIGUIENDO' : 'SEGUIR',
                style: GoogleFonts.archivoBlack(
                  fontSize: 14,
                  color: p.isFollowedByMe
                      ? AppTheme.primaryColor
                      : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.archivoBlack(
                fontSize: 20, color: AppTheme.primaryColor)),
        Text(label,
            style: GoogleFonts.robotoCondensed(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.grey[500],
                letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildViewToggle() {
    Widget buildTab(String label, int index, {BorderRadius? borderRadius}) {
      final selected = _viewIndex == index;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            setState(() => _viewIndex = index);
            if (index == 1) _loadAlbums();
            if (index == 2) _loadWishlist();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primaryColor : Colors.white,
              border: Border.all(color: AppTheme.primaryColor, width: 3),
              borderRadius: borderRadius,
            ),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.archivoBlack(
                  fontSize: 11,
                  color: selected ? Colors.white : AppTheme.primaryColor,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          buildTab('ESTANTERÍAS', 0,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              )),
          buildTab('COLECCIÓN', 1),
          buildTab('WISHLIST', 2,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              )),
        ],
      ),
    );
  }

  Widget _buildShelvesGrid() {
    if (_shelves.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Text('No tiene estanterías públicas',
                style: GoogleFonts.robotoCondensed(
                    fontSize: 14, color: Colors.grey[500])),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildShelfCard(_shelves[index]),
          childCount: _shelves.length,
        ),
      ),
    );
  }

  Widget _buildShelfCard(ShelfModel shelf) {
    return Container(
      decoration: AppTheme.popCard(
          color: Colors.white,
          shadowColor: AppTheme.canaryYellow,
          radius: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CachedNetworkImage(
              imageUrl: shelf.masterPhotoUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (_, __) => Container(
                color: Colors.grey[200],
                child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (_, __, ___) => Container(
                color: Colors.grey[200],
                child:
                    Icon(Icons.shelves, size: 36, color: Colors.grey[400]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              shelf.name.toUpperCase(),
              style: GoogleFonts.archivoBlack(
                  fontSize: 12, color: AppTheme.primaryColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumsGrid() {
    if (_albums.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: _viewIndex == 1
                ? const CircularProgressIndicator()
                : Text('No tiene discos públicos',
                    style: GoogleFonts.robotoCondensed(
                        fontSize: 14, color: Colors.grey[500])),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAlbumCard(_albums[index]),
          childCount: _albums.length,
        ),
      ),
    );
  }

  Widget _buildWishlistGrid() {
    if (_wishlist.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: _viewIndex == 2 && _wishlist.isEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.favorite_border,
                          size: 48,
                          color: AppTheme.primaryColor.withOpacity(0.15)),
                      const SizedBox(height: 12),
                      Text('No tiene discos en su wishlist',
                          style: GoogleFonts.robotoCondensed(
                              fontSize: 14, color: Colors.grey[500])),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildWishlistCard(_wishlist[index]),
          childCount: _wishlist.length,
        ),
      ),
    );
  }

  Widget _buildWishlistCard(WishlistItemModel item) {
    return GestureDetector(
      onTap: () => _openAmazonForWishlist(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: AppTheme.popCard(
            color: Colors.white,
            shadowColor: AppTheme.canaryYellow,
            radius: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.coverUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 56,
                          height: 56,
                          color: Colors.grey[200],
                          child: const Icon(Icons.album, color: Colors.grey),
                        ),
                      )
                    : Container(
                        width: 56,
                        height: 56,
                        color: Colors.grey[200],
                        child: const Icon(Icons.album, color: Colors.grey),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: GoogleFonts.archivoBlack(
                            fontSize: 12, color: AppTheme.primaryColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(item.artist,
                        style: GoogleFonts.robotoCondensed(
                            fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (item.note != null && item.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('"${item.note!}"',
                          style: GoogleFonts.robotoCondensed(
                              fontSize: 11,
                              color: AppTheme.accentColor,
                              fontStyle: FontStyle.italic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Botón regalar / comprar
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9900),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryColor, width: 2),
                ),
                child: const Icon(Icons.card_giftcard,
                    color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAmazonForWishlist(WishlistItemModel item) {
    HapticFeedback.mediumImpact();
    final locale =
        WidgetsBinding.instance.platformDispatcher.locale.toString();
    final url = EnvConfig.amazonSearchUrl(
      artist: item.artist,
      album: item.title,
      locale: locale,
    );
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget _buildAlbumCard(AlbumModel album) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PublicAlbumDetailScreen(album: album),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primaryColor, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: album.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: album.coverUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.album, color: Colors.grey),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.album, color: Colors.grey),
                      ),
                    )
                  : Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.album, color: Colors.grey),
                    ),
            ),
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.archivoBlack(
                          fontSize: 9, color: AppTheme.primaryColor)),
                  Text(album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.robotoCondensed(
                          fontSize: 9, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
