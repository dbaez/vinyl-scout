import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_localizations.dart';
import '../models/shelf_model.dart';
import '../models/shelf_zone_model.dart';
import '../services/shelf_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/interactive_card.dart';
import 'add_zone_screen.dart';
import 'zone_scanner_screen.dart';
import 'scan_results_screen.dart';
import 'zone_inventory_screen.dart';

class ShelfDetailScreen extends StatefulWidget {
  final ShelfModel shelf;

  const ShelfDetailScreen({super.key, required this.shelf});

  @override
  State<ShelfDetailScreen> createState() => _ShelfDetailScreenState();
}

class _ShelfDetailScreenState extends State<ShelfDetailScreen>
    with TickerProviderStateMixin {
  final ShelfService _shelfService = ShelfService();
  final StorageService _storageService = StorageService();
  late ShelfModel _shelf;
  bool _isLoading = true;
  bool _showZoneMarkers = true;
  ShelfZoneModel? _selectedZone;

  // Controllers
  late ScrollController _scrollController;
  final Map<String, GlobalKey> _zoneCardKeys = {};

  // Animaciones
  late AnimationController _fabAnimationController;
  late Animation<double> _fabScaleAnimation;
  late Animation<double> _fabRotationAnimation;

  // Animación de pulso para marcadores
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Control de visibilidad del FAB
  bool _isFabVisible = true;
  double _lastScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _shelf = widget.shelf;
    _initializeAnimations();
    _initializeScrollController();
    _loadShelfDetails();
  }

  void _initializeAnimations() {
    // Configurar animación del FAB
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fabScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fabAnimationController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _fabRotationAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _fabAnimationController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    // Animación de pulso continuo para marcadores sin escanear
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Iniciar animación del FAB después de un delay
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _fabAnimationController.forward();
    });
  }

  void _initializeScrollController() {
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final currentOffset = _scrollController.offset;

    // Ocultar FAB al hacer scroll hacia abajo, mostrar al hacer scroll hacia arriba
    if (currentOffset > _lastScrollOffset && currentOffset > 100) {
      if (_isFabVisible) {
        setState(() => _isFabVisible = false);
      }
    } else if (currentOffset < _lastScrollOffset) {
      if (!_isFabVisible) {
        setState(() => _isFabVisible = true);
      }
    }
    _lastScrollOffset = currentOffset;
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadShelfDetails() async {
    setState(() => _isLoading = true);

    // Simular un pequeño delay para mostrar el shimmer
    await Future.delayed(const Duration(milliseconds: 300));

    final shelf = await _shelfService.getShelfById(_shelf.id);
    if (shelf != null && mounted) {
      setState(() {
        _shelf = shelf;
        _isLoading = false;
        // Crear keys para cada zona
        for (var zone in shelf.zones ?? []) {
          _zoneCardKeys[zone.id] = GlobalKey();
        }
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  /// Scroll animado sincronizado hasta la tarjeta de zona correspondiente
  void _scrollToZoneCard(ShelfZoneModel zone) {
    final key = _zoneCardKeys[zone.id];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
        alignment: 0.2,
      );
    }
  }

  Future<void> _deleteShelf() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          l10n.deleteShelf,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${l10n.confirmDeleteShelf} "${_shelf.name}"?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              l10n.cancel,
              style: GoogleFonts.poppins(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(l10n.delete,
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _shelfService.deleteShelf(_shelf.id);
      if (success && mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _editShelfName() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _shelf.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          l10n.editName,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.poppins(),
          decoration: InputDecoration(
            hintText: l10n.shelfName,
            hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: GoogleFonts.poppins(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(l10n.save,
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != _shelf.name) {
      final success = await _shelfService.updateShelfName(_shelf.id, newName);
      if (success && mounted) {
        setState(() {
          _shelf = _shelf.copyWith(name: newName);
        });
      }
    }
  }

  void _selectZone(ShelfZoneModel zone) {
    final hasAlbums = (zone.albums?.length ?? 0) > 0;
    
    // Si tiene álbumes, abrir el inventario
    if (hasAlbums) {
      ZoneInventoryScreen.show(
        context,
        zone: zone,
        shelfName: _shelf?.name ?? 'Estantería',
      );
    } else {
      // Si no tiene álbumes, toggle selection
      setState(() {
        _selectedZone = _selectedZone?.id == zone.id ? null : zone;
      });
    }
  }

  /// Abrir el escáner para una zona (soporta multi-foto)
  Future<void> _scanZone(ShelfZoneModel zone) async {
    final result = await ZoneScannerScreen.show(
      context,
      zone: zone,
    );

    if (result != null && mounted) {
      final l10n = AppLocalizations.of(context)!;
      
      // Mostrar indicador de carga
      _showUploadingSnackBar(l10n);
      
      try {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        
        if (userId == null) {
          throw Exception('Usuario no autenticado');
        }

        final List<String> imageUrls = [];

        // Subir todas las imágenes a Supabase Storage (siempre como bytes comprimidos)
        final List<Uint8List>? imageBytesList = result['imageBytesList'] != null
            ? List<Uint8List>.from(result['imageBytesList'])
            : null;
        if (imageBytesList != null) {
          for (int i = 0; i < imageBytesList.length; i++) {
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text('Subiendo foto ${i + 1} de ${imageBytesList.length} (${(imageBytesList[i].length / 1024).toStringAsFixed(0)} KB)...', style: GoogleFonts.poppins()),
                    ],
                  ),
                  backgroundColor: AppTheme.primaryColor,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(16),
                  duration: const Duration(seconds: 30),
                ),
              );
            }
            final url = await _storageService.uploadImageBytes(
              bytes: imageBytesList[i],
              bucket: 'zone-photos',
              userId: userId,
              folder: 'scans',
            );
            if (url != null) imageUrls.add(url);
          }
        }

        // Ocultar SnackBar de carga
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

        if (imageUrls.isNotEmpty) {
          // Guardar la primera foto como foto de detalle de la zona
          await _shelfService.updateZonePhoto(zone.id, imageUrls.first);
          
          // Marcar la zona como escaneada
          await _shelfService.markZoneAsScanned(zone.id);
          
          // Mostrar pantalla de resultados con análisis de Gemini (multi-foto)
          if (mounted) {
            final saved = await ScanResultsScreen.show(
              context,
              zone: zone,
              imageUrls: imageUrls,
            );
            
            // Si se guardaron álbumes, recargar datos
            if (saved == true) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${l10n.zone} ${zone.zoneIndex + 1} - ¡Colección actualizada!',
                          style: GoogleFonts.poppins(),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: const Color(0xFF00C853),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.all(16),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
            
            // Recargar datos siempre (las fotos ya se guardaron)
            _loadShelfDetails();
          }
        } else {
          throw Exception('Error subiendo las imágenes');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Error: ${e.toString()}',
                      style: GoogleFonts.poppins(),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    }
  }
  
  void _showUploadingSnackBar(AppLocalizations l10n) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Subiendo foto...',
              style: GoogleFonts.poppins(),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 30), // Larga duración, se oculta manualmente
      ),
    );
  }

  void _addAlbumToZone(ShelfZoneModel zone) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddAlbumToZoneSheet(
        zoneId: zone.id,
        currentAlbumCount: zone.albumCount,
        onAlbumAdded: (_) {
          // Refrescar la estantería completa para actualizar conteos
          _loadShelfDetails();
        },
      ),
    );
  }

  Future<void> _deleteZone(ShelfZoneModel zone) async {
    final l10n = AppLocalizations.of(context)!;
    final hasAlbums = (zone.albums?.length ?? 0) > 0;
    final albumCount = zone.albums?.length ?? 0;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasAlbums
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                hasAlbums ? Icons.warning_amber_rounded : Icons.delete_outline,
                color: hasAlbums ? Colors.orange : Colors.red,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                hasAlbums ? l10n.attention : l10n.deleteZone,
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.confirmDeleteZone} ${zone.zoneIndex + 1}?',
              style: GoogleFonts.poppins(fontSize: 15),
            ),
            if (hasAlbums) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.album, color: Colors.orange, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${l10n.zoneHasAlbums} $albumCount ${albumCount == 1 ? l10n.albumAssociated : l10n.albumsAssociated}. ${l10n.albumsWillNotBeDeleted}',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              l10n.cancel,
              style: GoogleFonts.poppins(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: hasAlbums ? Colors.orange : Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              hasAlbums ? l10n.deleteAnyway : l10n.delete,
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _shelfService.deleteZone(zone.id);
      if (success && mounted) {
        if (_selectedZone?.id == zone.id) {
          setState(() => _selectedZone = null);
        }
        _loadShelfDetails();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  '${l10n.zone} ${zone.zoneIndex + 1} - ${l10n.zoneDeleted}',
                  style: GoogleFonts.poppins(),
                ),
              ],
            ),
            backgroundColor: AppTheme.primaryColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App bar con imagen interactiva
          _buildSliverAppBar(),

          // Contenido
          SliverToBoxAdapter(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: ShelfDetailSkeleton(),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Info de la estantería con glassmorphism premium
                        _buildPremiumGlassCard(),
                        const SizedBox(height: 24),

                        // Zona seleccionada
                        if (_selectedZone != null) ...[
                          _buildSelectedZoneCard(),
                          const SizedBox(height: 24),
                        ],

                        // Sección de zonas
                        _buildZonesSection(),

                        // Espacio extra para el FAB
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: _buildAnimatedFAB(),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: MediaQuery.of(context).size.height * 0.45,
      pinned: true,
      stretch: true,
      backgroundColor: AppTheme.primaryColor,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          _shelf.name,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            shadows: [
              const Shadow(color: Colors.black54, blurRadius: 12),
            ],
          ),
        ),
        titlePadding: const EdgeInsets.only(left: 16, bottom: 16, right: 60),
        background: GestureDetector(
          onTap: _openFullScreenImage,
          child: _buildInteractiveImage(),
        ),
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.fullscreen_rounded),
          onPressed: _openFullScreenImage,
          tooltip: AppLocalizations.of(context)?.viewFullImage ?? 'View',
        ),
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _showZoneMarkers ? Icons.visibility : Icons.visibility_off,
              key: ValueKey(_showZoneMarkers),
            ),
          ),
          onPressed: () => setState(() => _showZoneMarkers = !_showZoneMarkers),
          tooltip: AppLocalizations.of(context)?.showHideZones ?? 'Toggle',
        ),
        IconButton(
          icon: const Icon(Icons.edit_rounded),
          onPressed: _editShelfName,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (value) {
            if (value == 'delete') _deleteShelf();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_rounded, color: Colors.red),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.delete ?? 'Delete',
                    style: GoogleFonts.poppins(color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Imagen interactiva con marcadores de zonas animados
  Widget _buildInteractiveImage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Imagen de fondo con cache
            Hero(
              tag: 'shelf_image_${_shelf.id}',
              child: CachedNetworkImage(
                imageUrl: _shelf.masterPhotoUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[300],
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.secondaryColor,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.broken_image, size: 64),
                ),
              ),
            ),

            // Gradiente oscuro elegante
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.25),
                    Colors.transparent,
                    Colors.black.withOpacity(0.75),
                  ],
                  stops: const [0.0, 0.35, 1.0],
                ),
              ),
            ),

            // Marcadores de zonas con animaciones
            if (_showZoneMarkers && _shelf.zones != null && !_isLoading)
              ..._shelf.zones!.map((zone) {
                return Positioned(
                  left: zone.centerX * constraints.maxWidth - 22,
                  top: zone.centerY * constraints.maxHeight - 22,
                  child: _buildAnimatedZoneMarker(zone),
                );
              }),
          ],
        );
      },
    );
  }

  /// Marcador de zona con efecto de pulso y feedback visual
  Widget _buildAnimatedZoneMarker(ShelfZoneModel zone) {
    final isSelected = _selectedZone?.id == zone.id;
    final hasAlbums = (zone.albums?.length ?? 0) > 0;
    final isScanned = zone.hasBeenScanned;

    // Color según estado
    Color markerColor;
    double opacity;
    if (hasAlbums) {
      markerColor = const Color(0xFF00C853); // Verde vibrante
      opacity = 1.0;
    } else if (isScanned) {
      markerColor = AppTheme.accentColor;
      opacity = 0.95;
    } else {
      markerColor = Colors.white;
      opacity = 0.7; // Semi-transparente si no tiene álbumes
    }

    return GestureDetector(
      onTap: () {
        _selectZone(zone);
        _scrollToZoneCard(zone);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(milliseconds: 400 + (zone.zoneIndex * 80)),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Efecto de pulso para zonas sin álbumes (invitar a escanear)
                if (!hasAlbums && !isScanned)
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Container(
                        width: 44 * _pulseAnimation.value,
                        height: 44 * _pulseAnimation.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.secondaryColor.withOpacity(
                            0.25 * (2.25 - _pulseAnimation.value),
                          ),
                        ),
                      );
                    },
                  ),

                // Anillo de selección
                if (isSelected)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.8, end: 1.0),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, scale, child) {
                      return Container(
                        width: 58 * scale,
                        height: 58 * scale,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: markerColor.withOpacity(0.25),
                          border: Border.all(
                            color: markerColor.withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                      );
                    },
                  ),

                // Marcador principal
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasAlbums
                        ? markerColor
                        : markerColor.withOpacity(opacity),
                    border: Border.all(
                      color: Colors.white,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (hasAlbums ? markerColor : Colors.black)
                            .withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: hasAlbums
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 22)
                        : Text(
                            '${zone.zoneIndex + 1}',
                            style: GoogleFonts.poppins(
                              color: hasAlbums ? Colors.white : AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),

                // Badge con número si tiene check
                if (hasAlbums)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryColor,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${zone.zoneIndex + 1}',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Card de zona seleccionada con Hero animation
  Widget _buildSelectedZoneCard() {
    final l10n = AppLocalizations.of(context);
    final hasAlbums = (_selectedZone!.albums?.length ?? 0) > 0;

    return Hero(
      tag: 'zone_card_${_selectedZone!.id}',
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: hasAlbums
                  ? [const Color(0xFF00C853), const Color(0xFF69F0AE)]
                  : [AppTheme.secondaryColor, AppTheme.secondaryColor.withOpacity(0.85)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: (hasAlbums ? const Color(0xFF00C853) : AppTheme.secondaryColor)
                    .withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(
                    '${_selectedZone!.zoneIndex + 1}',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n?.zone ?? 'Zone'} ${_selectedZone!.zoneIndex + 1}',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_selectedZone!.albums?.length ?? 0} ${l10n?.albums ?? 'albums'}',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              InteractiveButton(
                onPressed: () => setState(() => _selectedZone = null),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Card con efecto glassmorphism premium
  Widget _buildPremiumGlassCard() {
    final l10n = AppLocalizations.of(context);
    final zonesCount = _shelf.zones?.length ?? 0;
    final albumsCount = _shelf.zones?.fold<int>(
          0,
          (sum, zone) => sum + (zone.albums?.length ?? 0),
        ) ??
        0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.9),
                Colors.white.withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(0.8),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.8),
                blurRadius: 0,
                spreadRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildGlassStatItem(
                icon: Icons.grid_view_rounded,
                value: zonesCount.toString(),
                label: l10n?.zones ?? 'Zones',
                color: AppTheme.primaryColor,
              ),
              _buildGlassDivider(),
              _buildGlassStatItem(
                icon: Icons.album_rounded,
                value: albumsCount.toString(),
                label: l10n?.albums ?? 'Albums',
                color: AppTheme.secondaryColor,
              ),
              _buildGlassDivider(),
              _buildGlassStatItem(
                icon: Icons.calendar_today_rounded,
                value: _formatDate(_shelf.createdAt),
                label: l10n?.created ?? 'Created',
                color: AppTheme.accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return InteractiveCard(
      pressedScale: 0.96,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A2E),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassDivider() {
    return Container(
      width: 1,
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey.withOpacity(0.05),
            Colors.grey.withOpacity(0.15),
            Colors.grey.withOpacity(0.05),
          ],
        ),
      ),
    );
  }

  /// FAB animado que se oculta/muestra con el scroll
  Widget _buildAnimatedFAB() {
    final l10n = AppLocalizations.of(context);
    return AnimatedSlide(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      offset: _isFabVisible ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isFabVisible ? 1.0 : 0.0,
        child: AnimatedBuilder(
          animation: _fabAnimationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _fabScaleAnimation.value,
              child: Transform.rotate(
                angle: (1 - _fabRotationAnimation.value) * 0.5,
                child: InteractiveButton(
                  pressedScale: 0.92,
                  onPressed: _isFabVisible ? _addZone : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.secondaryColor, Color(0xFFFF6B6B)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.secondaryColor.withOpacity(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_location_alt_rounded,
                            color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          l10n?.addZone ?? 'Add zone',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildZonesSection() {
    final l10n = AppLocalizations.of(context);
    final zones = _shelf.zones ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n?.zones ?? 'Zones',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 18),
        if (zones.isEmpty)
          _buildEmptyZonesState()
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: zones.length,
            itemBuilder: (context, index) {
              final zone = zones[index];
              return _buildPremiumZoneCard(zone);
            },
          ),
      ],
    );
  }

  /// Tarjeta de zona con diseño premium y Hero animation
  Widget _buildPremiumZoneCard(ShelfZoneModel zone) {
    final l10n = AppLocalizations.of(context);
    final hasAlbums = (zone.albums?.length ?? 0) > 0;
    final albumCount = zone.albums?.length ?? 0;

    return Hero(
      tag: 'zone_${zone.id}',
      child: Material(
        color: Colors.transparent,
        child: InteractiveCard(
          key: _zoneCardKeys[zone.id],
          onTap: () => _selectZone(zone),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // Número de zona con degradado
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: hasAlbums
                        ? [const Color(0xFF00C853), const Color(0xFF69F0AE)]
                        : [AppTheme.primaryColor, AppTheme.primaryColor.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: (hasAlbums
                              ? const Color(0xFF00C853)
                              : AppTheme.primaryColor)
                          .withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: hasAlbums
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 28)
                      : Text(
                          '${zone.zoneIndex + 1}',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${l10n?.zone ?? 'Zone'} ${zone.zoneIndex + 1}',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: -0.3,
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                        if (hasAlbums) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00C853).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$albumCount',
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF00C853),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (hasAlbums)
                      Text(
                        '$albumCount ${l10n?.albums ?? 'albums'}',
                        style: GoogleFonts.poppins(
                          color: Colors.grey[500],
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 16,
                                  color: AppTheme.accentColor.withOpacity(0.8),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    l10n?.readyToDiscover ??
                                        'Ready to discover your treasures?',
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey[400],
                                      fontSize: 13,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botón de escanear rápido
                          InteractiveButton(
                            pressedScale: 0.92,
                            onPressed: () => _scanZone(zone),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.accentColor,
                                    AppTheme.accentColor.withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accentColor.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.qr_code_scanner_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    l10n?.scan ?? 'Scan',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              // Menú de opciones
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: Colors.grey[400]),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'scan') {
                    _scanZone(zone);
                  } else if (value == 'add_album') {
                    _addAlbumToZone(zone);
                  } else if (value == 'delete') {
                    _deleteZone(zone);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'add_album',
                    child: Row(
                      children: [
                        Icon(Icons.album_rounded,
                            color: AppTheme.accentColor, size: 22),
                        const SizedBox(width: 12),
                        Text(
                          'Añadir disco',
                          style: GoogleFonts.poppins(
                            color: AppTheme.accentColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'scan',
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_scanner_rounded,
                            color: AppTheme.secondaryColor, size: 22),
                        const SizedBox(width: 12),
                        Text(
                          l10n?.scanZone ?? 'Escanear zona',
                          style: GoogleFonts.poppins(
                            color: AppTheme.secondaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            color: Colors.red[400], size: 22),
                        const SizedBox(width: 12),
                        Text(
                          l10n?.deleteZone ?? 'Eliminar zona',
                          style: GoogleFonts.poppins(
                            color: Colors.red[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyZonesState() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.grid_view_rounded,
              size: 52,
              color: AppTheme.secondaryColor.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n?.noZonesDefined ?? 'No zones defined',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n?.divideShelfIntoZones ??
                'Divide your shelf into zones to better organize your vinyls',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[500],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_rounded, size: 16, color: Colors.grey[400]),
              const SizedBox(width: 6),
              Text(
                l10n?.useButtonBelow ?? 'Use the button below to get started',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[400],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addZone() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddZoneScreen(shelf: _shelf),
      ),
    );

    if (result != null) {
      _loadShelfDetails();
    }
  }

  void _openFullScreenImage() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            _FullScreenImageView(
          imageUrl: _shelf.masterPhotoUrl,
          title: _shelf.name,
          zones: _shelf.zones,
          showMarkers: _showZoneMarkers,
          heroTag: 'shelf_image_${_shelf.id}',
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// Vista de imagen a pantalla completa con zoom y Hero animation
class _FullScreenImageView extends StatefulWidget {
  final String imageUrl;
  final String title;
  final List<ShelfZoneModel>? zones;
  final bool showMarkers;
  final String heroTag;

  const _FullScreenImageView({
    required this.imageUrl,
    required this.title,
    this.zones,
    this.showMarkers = true,
    required this.heroTag,
  });

  @override
  State<_FullScreenImageView> createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<_FullScreenImageView> {
  final TransformationController _controller = TransformationController();
  bool _showMarkers = true;

  @override
  void initState() {
    super.initState();
    _showMarkers = widget.showMarkers;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _controller.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _showMarkers ? Icons.visibility : Icons.visibility_off,
                key: ValueKey(_showMarkers),
              ),
            ),
            onPressed: () => setState(() => _showMarkers = !_showMarkers),
            tooltip: l10n?.showHideZones ?? 'Show/hide zones',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out_map_rounded),
            onPressed: _resetZoom,
            tooltip: l10n?.resetZoom ?? 'Reset zoom',
          ),
        ],
      ),
      body: InteractiveViewer(
        transformationController: _controller,
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Imagen con Hero
                  Hero(
                    tag: widget.heroTag,
                    child: CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Colors.grey,
                      ),
                    ),
                  ),

                  // Marcadores de zonas
                  if (_showMarkers && widget.zones != null)
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, imageConstraints) {
                          return Stack(
                            children: widget.zones!.map((zone) {
                              final hasAlbums = (zone.albums?.length ?? 0) > 0;
                              return Positioned(
                                left: zone.centerX * imageConstraints.maxWidth - 22,
                                top: zone.centerY * imageConstraints.maxHeight - 22,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: hasAlbums
                                        ? const Color(0xFF00C853)
                                        : AppTheme.secondaryColor.withOpacity(0.9),
                                    border: Border.all(color: Colors.white, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.5),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: hasAlbums
                                        ? const Icon(Icons.check_rounded,
                                            color: Colors.white, size: 22)
                                        : Text(
                                            '${zone.zoneIndex + 1}',
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
