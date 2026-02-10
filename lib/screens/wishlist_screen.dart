import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../models/wishlist_item_model.dart';
import '../services/wishlist_service.dart';
import '../services/discogs_service.dart';
import '../config/env_config.dart';

/// Pantalla de la wishlist del usuario actual
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  final _wishlistService = WishlistService();
  final _discogsService = DiscogsService();

  List<WishlistItemModel> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWishlist();
  }

  Future<void> _loadWishlist() async {
    final items = await _wishlistService.getMyWishlist();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeItem(WishlistItemModel item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.primaryColor, width: 3),
        ),
        title: Text('ELIMINAR',
            style: GoogleFonts.archivoBlack(
                fontSize: 16, color: AppTheme.primaryColor)),
        content: Text(
          '¿Quitar "${item.title}" de tu wishlist?',
          style: GoogleFonts.robotoCondensed(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCELAR',
                style: GoogleFonts.archivoBlack(
                    fontSize: 12, color: Colors.grey)),
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
      final success = await _wishlistService.removeFromWishlist(item.id);
      if (success && mounted) {
        setState(() => _items.removeWhere((i) => i.id == item.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eliminado de la wishlist',
                style: GoogleFonts.poppins()),
            backgroundColor: AppTheme.primaryColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openAmazon(WishlistItemModel item) {
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

  Future<void> _showAddDialog() async {
    final searchController = TextEditingController();
    List<DiscogsAlbum> searchResults = [];
    bool isSearching = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    Text('AÑADIR A WISHLIST',
                        style: GoogleFonts.archivoBlack(
                            fontSize: 18, color: AppTheme.primaryColor)),
                    const SizedBox(height: 4),
                    Text('Busca un disco en Discogs',
                        style: GoogleFonts.robotoCondensed(
                            fontSize: 13, color: Colors.grey[600])),
                    const SizedBox(height: 16),

                    // Campo de búsqueda
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                            color: AppTheme.primaryColor, width: 3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              style: GoogleFonts.robotoCondensed(
                                  fontSize: 15,
                                  color: AppTheme.primaryColor),
                              decoration: InputDecoration(
                                hintText: 'Artista o álbum...',
                                hintStyle: GoogleFonts.robotoCondensed(
                                    color: Colors.grey[400]),
                                prefixIcon: const Icon(Icons.search,
                                    color: AppTheme.primaryColor),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onSubmitted: (_) async {
                                final query = searchController.text.trim();
                                if (query.isEmpty) return;
                                setSheetState(() => isSearching = true);
                                final results = await _discogsService
                                    .searchMultipleResults(query, limit: 10);
                                setSheetState(() {
                                  searchResults = results;
                                  isSearching = false;
                                });
                              },
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final query = searchController.text.trim();
                              if (query.isEmpty) return;
                              setSheetState(() => isSearching = true);
                              final results = await _discogsService
                                  .searchMultipleResults(query, limit: 10);
                              setSheetState(() {
                                searchResults = results;
                                isSearching = false;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: const BoxDecoration(
                                color: AppTheme.accentColor,
                                borderRadius: BorderRadius.only(
                                  topRight: Radius.circular(7),
                                  bottomRight: Radius.circular(7),
                                ),
                              ),
                              child: const Icon(Icons.search,
                                  color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Resultados
                    if (isSearching)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      Expanded(
                        child: searchResults.isEmpty
                            ? Center(
                                child: Text(
                                  searchController.text.isEmpty
                                      ? 'Escribe para buscar discos'
                                      : 'Sin resultados',
                                  style: GoogleFonts.robotoCondensed(
                                      fontSize: 14, color: Colors.grey[500]),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: searchResults.length,
                                itemBuilder: (_, i) {
                                  final album = searchResults[i];
                                  return _buildSearchResult(
                                      ctx, album, setSheetState);
                                },
                              ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSearchResult(
      BuildContext ctx, DiscogsAlbum album, StateSetter setSheetState) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.popCard(
          color: Colors.white,
          shadowColor: AppTheme.canaryYellow,
          radius: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: album.thumb != null
              ? CachedNetworkImage(
                  imageUrl: album.thumb!,
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
        title: Text(
          album.title,
          style: GoogleFonts.archivoBlack(
              fontSize: 12, color: AppTheme.primaryColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(album.artist,
                style: GoogleFonts.robotoCondensed(
                    fontSize: 12, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (album.year != null)
              Text('${album.year}',
                  style: GoogleFonts.robotoCondensed(
                      fontSize: 11, color: Colors.grey[400])),
          ],
        ),
        trailing: GestureDetector(
          onTap: () async {
            HapticFeedback.mediumImpact();
            // Pedir nota opcional
            final noteController = TextEditingController();
            final note = await showDialog<String>(
              context: ctx,
              builder: (dialogCtx) => AlertDialog(
                backgroundColor: AppTheme.backgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side:
                      const BorderSide(color: AppTheme.primaryColor, width: 3),
                ),
                title: Text('NOTA (OPCIONAL)',
                    style: GoogleFonts.archivoBlack(
                        fontSize: 14, color: AppTheme.primaryColor)),
                content: TextField(
                  controller: noteController,
                  maxLength: 100,
                  style: GoogleFonts.robotoCondensed(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ej: Me lo recomendó Diego',
                    hintStyle:
                        GoogleFonts.robotoCondensed(color: Colors.grey[400]),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, ''),
                    child: Text('SALTAR',
                        style: GoogleFonts.archivoBlack(
                            fontSize: 12, color: Colors.grey)),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(dialogCtx, noteController.text.trim()),
                    child: Text('AÑADIR',
                        style: GoogleFonts.archivoBlack(
                            fontSize: 12, color: AppTheme.accentColor)),
                  ),
                ],
              ),
            );

            if (note == null) return; // Canceló

            final result = await _wishlistService.addToWishlist(
              title: album.title,
              artist: album.artist,
              coverUrl: album.coverImage ?? album.thumb,
              year: album.year,
              discogsId: album.id,
              note: note.isNotEmpty ? note : null,
            );

            if (result != null && mounted) {
              Navigator.pop(ctx); // Cerrar bottom sheet
              _loadWishlist();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.favorite,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${album.title} añadido a tu wishlist',
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: AppTheme.secondaryColor,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primaryColor, width: 2),
            ),
            child: const Icon(Icons.favorite_border,
                color: Colors.white, size: 20),
          ),
        ),
      ),
    );
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
        title: Text('MI WISHLIST',
            style: GoogleFonts.archivoBlack(
                fontSize: 18, color: AppTheme.primaryColor)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(3),
          child: Divider(
              color: AppTheme.primaryColor, thickness: 3, height: 3),
        ),
        actions: [
          // Contador
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor, width: 2),
                ),
                child: Text('${_items.length}',
                    style: GoogleFonts.archivoBlack(
                        fontSize: 13, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: AppTheme.secondaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border,
                size: 64, color: AppTheme.primaryColor.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text('TU WISHLIST ESTÁ VACÍA',
                style: GoogleFonts.archivoBlack(
                    fontSize: 16, color: AppTheme.primaryColor),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Añade discos que te gustaría tener.\nTus amigos podrán verla si tu perfil es público.',
              style: GoogleFonts.robotoCondensed(
                  fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _showAddDialog,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor,
                  border: Border.all(color: AppTheme.primaryColor, width: 3),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow:
                      AppTheme.popShadow(AppTheme.primaryColor, offset: 3),
                ),
                child: Text('BUSCAR DISCOS',
                    style: GoogleFonts.archivoBlack(
                        fontSize: 13, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _items.length,
      itemBuilder: (_, i) => _buildWishlistCard(_items[i]),
    );
  }

  Widget _buildWishlistCard(WishlistItemModel item) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.errorColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete, color: Colors.white, size: 28),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.primaryColor, width: 3),
            ),
            title: Text('ELIMINAR',
                style: GoogleFonts.archivoBlack(
                    fontSize: 16, color: AppTheme.primaryColor)),
            content: Text('¿Quitar "${item.title}" de tu wishlist?',
                style: GoogleFonts.robotoCondensed(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('CANCELAR',
                    style: GoogleFonts.archivoBlack(
                        fontSize: 12, color: Colors.grey)),
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
      },
      onDismissed: (_) async {
        final success = await _wishlistService.removeFromWishlist(item.id);
        if (success && mounted) {
          setState(() => _items.removeWhere((i) => i.id == item.id));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: AppTheme.popCard(
            color: Colors.white,
            shadowColor: AppTheme.canaryYellow,
            radius: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openAmazon(item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Cover
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: item.coverUrl!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
                const SizedBox(width: 14),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: GoogleFonts.archivoBlack(
                              fontSize: 13, color: AppTheme.primaryColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(item.artist,
                          style: GoogleFonts.robotoCondensed(
                              fontSize: 12, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (item.year != null) ...[
                        const SizedBox(height: 2),
                        Text('${item.year}',
                            style: GoogleFonts.robotoCondensed(
                                fontSize: 11, color: Colors.grey[400])),
                      ],
                      if (item.note != null && item.note!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(item.note!,
                              style: GoogleFonts.robotoCondensed(
                                  fontSize: 11,
                                  color: AppTheme.accentColor,
                                  fontStyle: FontStyle.italic),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Amazon button
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9900),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTheme.primaryColor, width: 2),
                      ),
                      child: const Icon(Icons.shopping_bag_rounded,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(height: 4),
                    Text('COMPRAR',
                        style: GoogleFonts.archivoBlack(
                            fontSize: 7, color: Colors.grey[500])),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      color: Colors.grey[200],
      child: Icon(Icons.album, color: Colors.grey[400], size: 28),
    );
  }
}
