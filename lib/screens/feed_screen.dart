import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../services/social_service.dart';
import '../services/photo_service.dart';
import '../models/user_model.dart';
import '../models/album_photo_model.dart';
import '../models/album_model.dart';
import 'public_profile_screen.dart';
import 'public_album_detail_screen.dart';

/// Pantalla de Feed social: estanterías de usuarios que sigues + descubrir
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  final _socialService = SocialService();
  final _photoService = PhotoService();
  late TabController _tabController;

  // Feed data (shelves + photos mezclados)
  List<FeedItem> _followingFeed = [];
  List<FeedItem> _discoverFeed = [];
  List<PhotoFeedItem> _followingPhotos = [];
  List<PhotoFeedItem> _discoverPhotos = [];
  bool _isLoadingFollowing = true;
  bool _isLoadingDiscover = true;

  // Búsqueda
  final _searchController = TextEditingController();
  List<PublicUserProfile> _searchResults = [];
  bool _isSearching = false;
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadFeeds();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFeeds() async {
    // Cargar shelves + photos en paralelo
    final followingFuture = _socialService.getFollowingFeed();
    final discoverFuture = _socialService.getDiscoverFeed();
    final followingPhotosFuture = _photoService.getPhotoFeed();
    final discoverPhotosFuture = _photoService.getDiscoverPhotoFeed();

    final following = await followingFuture;
    final followingPhotos = await followingPhotosFuture;
    if (mounted) {
      setState(() {
        _followingFeed = following;
        _followingPhotos = followingPhotos;
        _isLoadingFollowing = false;
      });
    }

    final discover = await discoverFuture;
    final discoverPhotos = await discoverPhotosFuture;
    if (mounted) {
      setState(() {
        _discoverFeed = discover;
        _discoverPhotos = discoverPhotos;
        _isLoadingDiscover = false;
      });
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    final results = await _socialService.searchUsers(query);
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (mounted) {
      setState(() {
        _searchResults = results.where((u) => u.id != myId).toList();
        _isSearching = false;
      });
    }
  }

  Future<void> _toggleFollow(PublicUserProfile user) async {
    HapticFeedback.mediumImpact();
    bool success;
    if (user.isFollowedByMe) {
      success = await _socialService.unfollowUser(user.id);
    } else {
      success = await _socialService.followUser(user.id);
    }

    if (success && mounted) {
      // Actualizar estado local
      setState(() {
        final index = _searchResults.indexWhere((u) => u.id == user.id);
        if (index != -1) {
          _searchResults[index] = PublicUserProfile(
            id: user.id,
            displayName: user.displayName,
            photoUrl: user.photoUrl,
            username: user.username,
            bio: user.bio,
            albumCount: user.albumCount,
            followerCount: user.followerCount,
            followingCount: user.followingCount,
            isFollowedByMe: !user.isFollowedByMe,
          );
        }
      });
      // Recargar feed de siguiendo
      _loadFeeds();
    }
  }

  void _openProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(userId: userId),
      ),
    );
  }

  /// Navega al detalle público de un álbum (read-only, con wishlist y comprar)
  Future<void> _openAlbumDetail(PhotoFeedItem item) async {
    try {
      // Buscar álbum completo en la BD
      final result = await Supabase.instance.client
          .from('albums')
          .select()
          .eq('id', item.albumId)
          .maybeSingle();

      if (result != null && mounted) {
        final album = AlbumModel.fromJson(result);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PublicAlbumDetailScreen(album: album),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error opening album detail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('FEED',
            style: GoogleFonts.archivoBlack(
                fontSize: 20, color: AppTheme.primaryColor)),
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close : Icons.search,
              color: AppTheme.primaryColor,
            ),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  _searchResults = [];
                }
              });
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              const Divider(
                  color: AppTheme.primaryColor, thickness: 3, height: 3),
              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.secondaryColor,
                indicatorWeight: 3,
                labelColor: AppTheme.primaryColor,
                unselectedLabelColor: AppTheme.primaryColor.withOpacity(0.4),
                labelStyle: GoogleFonts.archivoBlack(fontSize: 12),
                unselectedLabelStyle:
                    GoogleFonts.robotoCondensed(fontSize: 12, fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: 'SIGUIENDO'),
                  Tab(text: 'DESCUBRIR'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _showSearch ? _buildSearchView() : _buildFeedView(),
    );
  }

  Widget _buildSearchView() {
    return Column(
      children: [
        // Campo de búsqueda (mismo estilo que smart input de mood)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: AppTheme.popCard(
                      color: Colors.white,
                      shadowColor: AppTheme.accentColor,
                      radius: 10),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: GoogleFonts.robotoCondensed(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87),
                    onChanged: (q) => _searchUsers(q),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o @username...',
                      hintStyle: GoogleFonts.robotoCondensed(
                          fontSize: 13, color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.search,
                          color: AppTheme.secondaryColor, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _isSearching
                  ? Container(
                      width: 42,
                      height: 42,
                      decoration: AppTheme.popCard(
                          color: AppTheme.secondaryColor,
                          shadowColor: AppTheme.primaryColor,
                          radius: 10),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        ),
                      ),
                    )
                  : GestureDetector(
                      onTap: () {
                        if (_searchController.text.isNotEmpty) {
                          _searchController.clear();
                          _searchUsers('');
                        }
                      },
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: AppTheme.popCard(
                            color: AppTheme.secondaryColor,
                            shadowColor: AppTheme.primaryColor,
                            radius: 10),
                        child: Center(
                          child: Icon(
                            _searchController.text.isNotEmpty
                                ? Icons.close
                                : Icons.person_search_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),

        // Resultados
        Expanded(
          child: _searchResults.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline,
                          size: 48,
                          color: AppTheme.primaryColor.withOpacity(0.2)),
                      const SizedBox(height: 12),
                      Text(
                        _searchController.text.isEmpty
                            ? 'Busca usuarios por nombre o username'
                            : 'No se encontraron usuarios',
                        style: GoogleFonts.robotoCondensed(
                            fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) =>
                      _buildUserSearchResult(_searchResults[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildUserSearchResult(PublicUserProfile user) {
    return GestureDetector(
      onTap: () => _openProfile(user.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: AppTheme.popCard(
            color: Colors.white,
            shadowColor: AppTheme.canaryYellow,
            radius: 8),
        child: ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundImage:
                user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
            child: user.photoUrl == null
                ? const Icon(Icons.person, color: Colors.grey)
                : null,
          ),
          title: Text(
            user.displayName.toUpperCase(),
            style: GoogleFonts.archivoBlack(
                fontSize: 13, color: AppTheme.primaryColor),
          ),
          subtitle: user.username != null
              ? Text('@${user.username}',
                  style: GoogleFonts.robotoCondensed(
                      color: Colors.grey[600], fontSize: 13))
              : null,
          trailing: _buildFollowButton(user),
        ),
      ),
    );
  }

  Widget _buildFollowButton(PublicUserProfile user) {
    final isFollowing = user.isFollowedByMe;
    return GestureDetector(
      onTap: () => _toggleFollow(user),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isFollowing ? Colors.white : AppTheme.secondaryColor,
          border: Border.all(
              color: isFollowing
                  ? AppTheme.primaryColor
                  : AppTheme.secondaryColor,
              width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          isFollowing ? 'SIGUIENDO' : 'SEGUIR',
          style: GoogleFonts.archivoBlack(
            fontSize: 11,
            color: isFollowing ? AppTheme.primaryColor : Colors.white,
          ),
        ),
      ),
    );
  }

  /// Mezcla estanterías y fotos en una lista unificada ordenada por fecha
  List<_MixedFeedEntry> _buildMixedFeed(
      List<FeedItem> shelves, List<PhotoFeedItem> photos) {
    final entries = <_MixedFeedEntry>[];
    for (final s in shelves) {
      entries.add(_MixedFeedEntry(
          date: s.createdAt, shelf: s, photo: null));
    }
    for (final p in photos) {
      entries.add(_MixedFeedEntry(
          date: p.createdAt, shelf: null, photo: p));
    }
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  Widget _buildFeedView() {
    return TabBarView(
      controller: _tabController,
      children: [
        // Tab Siguiendo
        _buildMixedFeedList(
          shelves: _followingFeed,
          photos: _followingPhotos,
          isLoading: _isLoadingFollowing,
          emptyIcon: Icons.people_outline,
          emptyTitle: 'Aún no sigues a nadie',
          emptySubtitle:
              'Busca usuarios con el icono de lupa y síguelos para ver sus estanterías aquí',
        ),
        // Tab Descubrir
        _buildMixedFeedList(
          shelves: _discoverFeed,
          photos: _discoverPhotos,
          isLoading: _isLoadingDiscover,
          emptyIcon: Icons.explore_off,
          emptyTitle: 'No hay contenido público',
          emptySubtitle:
              'Sé el primero en hacer tu perfil público desde Perfil',
        ),
      ],
    );
  }

  Widget _buildMixedFeedList({
    required List<FeedItem> shelves,
    required List<PhotoFeedItem> photos,
    required bool isLoading,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final mixed = _buildMixedFeed(shelves, photos);

    if (mixed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon,
                  size: 64,
                  color: AppTheme.primaryColor.withOpacity(0.15)),
              const SizedBox(height: 16),
              Text(emptyTitle,
                  style: GoogleFonts.archivoBlack(
                      fontSize: 16, color: AppTheme.primaryColor),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(emptySubtitle,
                  style: GoogleFonts.robotoCondensed(
                      fontSize: 14, color: Colors.grey[500]),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFeeds,
      color: AppTheme.secondaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: mixed.length,
        itemBuilder: (context, index) {
          final entry = mixed[index];
          if (entry.shelf != null) {
            return _buildFeedCard(entry.shelf!);
          } else {
            return _buildPhotoFeedCard(entry.photo!);
          }
        },
      ),
    );
  }

  Widget _buildFeedCard(FeedItem item) {
    return GestureDetector(
      onTap: () => _openProfile(item.userId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: AppTheme.popCard(
            color: Colors.white,
            shadowColor: AppTheme.secondaryColor,
            radius: 12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto de la estantería
            AspectRatio(
              aspectRatio: 16 / 10,
              child: CachedNetworkImage(
                imageUrl: item.masterPhotoUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey[200],
                  child: Icon(Icons.shelves,
                      size: 48, color: Colors.grey[400]),
                ),
              ),
            ),
            // Info del usuario y estantería
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: item.userPhotoUrl != null
                        ? NetworkImage(item.userPhotoUrl!)
                        : null,
                    child: item.userPhotoUrl == null
                        ? const Icon(Icons.person, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Nombre + estantería
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.userDisplayName.toUpperCase(),
                          style: GoogleFonts.archivoBlack(
                              fontSize: 13,
                              color: AppTheme.primaryColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          item.shelfName,
                          style: GoogleFonts.robotoCondensed(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Badge tipo
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppTheme.accentColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shelves,
                            size: 12, color: AppTheme.accentColor),
                        const SizedBox(width: 4),
                        Text('ESTANTERÍA',
                            style: GoogleFonts.archivoBlack(
                                fontSize: 8,
                                color: AppTheme.accentColor)),
                      ],
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

  Widget _buildPhotoFeedCard(PhotoFeedItem item) {
    return GestureDetector(
      onTap: () => _openAlbumDetail(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: AppTheme.popCard(
            color: Colors.white,
            shadowColor: AppTheme.canaryYellow,
            radius: 12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto del vinilo
            AspectRatio(
              aspectRatio: 1,
              child: CachedNetworkImage(
                imageUrl: item.photoUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey[200],
                  child: Icon(Icons.photo,
                      size: 48, color: Colors.grey[400]),
                ),
              ),
            ),
            // Info: álbum + usuario
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Mini cover del álbum
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: item.albumCoverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: item.albumCoverUrl!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 40,
                              height: 40,
                              color: Colors.grey[200],
                              child: const Icon(Icons.album,
                                  size: 20, color: Colors.grey),
                            ),
                          )
                        : Container(
                            width: 40,
                            height: 40,
                            color: Colors.grey[200],
                            child: const Icon(Icons.album,
                                size: 20, color: Colors.grey),
                          ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.albumTitle,
                          style: GoogleFonts.archivoBlack(
                              fontSize: 12,
                              color: AppTheme.primaryColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${item.albumArtist} · ${item.userDisplayName}',
                          style: GoogleFonts.robotoCondensed(
                              fontSize: 12,
                              color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.caption != null && item.caption!.isNotEmpty)
                          Text(
                            item.caption!,
                            style: GoogleFonts.robotoCondensed(
                                fontSize: 11,
                                color: AppTheme.accentColor,
                                fontStyle: FontStyle.italic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Badge tipo
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppTheme.secondaryColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_camera,
                            size: 12, color: AppTheme.secondaryColor),
                        const SizedBox(width: 4),
                        Text('FOTO',
                            style: GoogleFonts.archivoBlack(
                                fontSize: 8,
                                color: AppTheme.secondaryColor)),
                      ],
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
}

/// Entrada mixta del feed para ordenar estanterías y fotos por fecha
class _MixedFeedEntry {
  final DateTime date;
  final FeedItem? shelf;
  final PhotoFeedItem? photo;

  const _MixedFeedEntry({
    required this.date,
    this.shelf,
    this.photo,
  });
}
