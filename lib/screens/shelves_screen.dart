import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shelf_model.dart';
import '../services/shelf_service.dart';
import '../services/social_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'shelf_detail_screen.dart';

class ShelvesScreen extends StatefulWidget {
  const ShelvesScreen({super.key});

  @override
  State<ShelvesScreen> createState() => _ShelvesScreenState();
}

class _ShelvesScreenState extends State<ShelvesScreen> with SingleTickerProviderStateMixin {
  final ShelfService _shelfService = ShelfService();
  final StorageService _storageService = StorageService();
  
  List<ShelfModel> _shelves = [];
  bool _isLoading = true;
  bool _isCreating = false;
  
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _loadShelves();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadShelves() async {
    setState(() => _isLoading = true);
    
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      final shelves = await _shelfService.getUserShelves(userId);
      setState(() {
        _shelves = shelves;
        _isLoading = false;
      });
      _animController.forward();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createNewShelf() async {
    final source = await _showImageSourceDialog();
    if (source == null) return;

    XFile? imageFile;
    if (source == ImageSource.gallery) {
      imageFile = await _storageService.pickImageFromGallery();
    } else {
      imageFile = await _storageService.takePhoto();
    }

    if (imageFile == null) return;

    final shelfName = await _showNameDialog();
    if (shelfName == null || shelfName.isEmpty) return;

    setState(() => _isCreating = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Usuario no autenticado');

      final imageUrl = await _storageService.uploadImage(
        file: imageFile,
        bucket: 'shelves',
        userId: userId,
      );

      if (imageUrl == null) throw Exception('Error subiendo imagen');

      final newShelf = await _shelfService.createShelf(
        userId: userId,
        name: shelfName,
        masterPhotoUrl: imageUrl,
      );

      if (newShelf != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShelfDetailScreen(shelf: newShelf),
          ),
        ).then((_) => _loadShelves());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
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
              Text('AÑADIR ESTANTERÍA',
                  style: GoogleFonts.archivoBlack(
                      fontSize: 16, color: AppTheme.primaryColor)),
              const SizedBox(height: 4),
              Text('Toma una foto de tu mueble de vinilos',
                  style: GoogleFonts.robotoCondensed(
                      fontSize: 13, color: Colors.grey[600])),
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
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
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
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Nombre de la estantería',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Ej: Salón, Habitación...',
            hintStyle: TextStyle(color: Colors.grey[600]),
            filled: true,
            fillColor: Colors.grey[800],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.secondaryColor, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Crear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: CustomScrollView(
        slivers: [
          // Header con gradiente
          _buildHeader(),
          
          // Contenido
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.secondaryColor),
              ),
            )
          else if (_shelves.isEmpty)
            SliverFillRemaining(child: _buildEmptyState())
          else
            _buildShelvesGrid(),
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildHeader() {
    final totalZones = _shelves.fold<int>(0, (sum, s) => sum + (s.zones?.length ?? 0));
    final totalVinyls = _shelves.fold<int>(0, (sum, s) =>
      sum + (s.zones?.fold<int>(0, (zSum, z) => zSum + z.albumCount) ?? 0));
    
    return SliverToBoxAdapter(
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16,
          left: 20,
          right: 20,
          bottom: 24,
        ),
        decoration: const BoxDecoration(
          color: AppTheme.backgroundColor,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MIS ESTANTERÍAS',
                      style: GoogleFonts.archivoBlack(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Organiza tu colección',
                      style: GoogleFonts.robotoCondensed(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Stats
            Row(
              children: [
                _buildStatCard(
                  icon: Icons.shelves,
                  value: '${_shelves.length}',
                  label: 'Estanterías',
                  color: AppTheme.secondaryColor,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  icon: Icons.grid_view_rounded,
                  value: '$totalZones',
                  label: 'Zonas',
                  color: AppTheme.accentColor,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  icon: Icons.album,
                  value: '$totalVinyls',
                  label: 'Vinilos',
                  color: Colors.purpleAccent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: AppTheme.popCard(color: Colors.white, shadowColor: color, radius: 10),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.archivoBlack(
                color: AppTheme.primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.robotoCondensed(
                color: Colors.grey[600],
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Ilustración animada
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.secondaryColor.withOpacity(0.2),
                          AppTheme.secondaryColor.withOpacity(0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.secondaryColor.withOpacity(0.15),
                          border: Border.all(
                            color: AppTheme.secondaryColor.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.shelves,
                          size: 48,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            const Text(
              '¡Empieza tu colección!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Añade tu primera estantería tomando una foto de tu mueble de vinilos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[500],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _createNewShelf,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 8,
                shadowColor: AppTheme.secondaryColor.withOpacity(0.5),
              ),
              icon: const Icon(Icons.add_a_photo, color: Colors.white),
              label: const Text(
                'Añadir estantería',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShelvesGrid() {
    // Si solo hay una estantería, centrarla
    if (_shelves.length == 1) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                final rawValue = _animController.value.clamp(0.0, 1.0);
                final curveValue = Curves.easeOutBack.transform(rawValue);
                final opacity = curveValue.clamp(0.0, 1.0);
                return Transform.scale(
                  scale: curveValue,
                  child: Opacity(
                    opacity: opacity,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.55,
                      child: AspectRatio(
                        aspectRatio: 0.6,
                        child: _buildShelfCard(_shelves[0]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.6, // Más vertical para fotos de móvil
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                final delay = index * 0.1;
                final rawValue = ((_animController.value - delay) / (1 - delay)).clamp(0.0, 1.0);
                // easeOutBack puede dar valores > 1.0 (overshoot), clampeamos para Opacity
                final curveValue = Curves.easeOutBack.transform(rawValue);
                final opacity = curveValue.clamp(0.0, 1.0);
                return Transform.scale(
                  scale: curveValue, // Scale puede pasar de 1.0 (efecto bounce)
                  child: Opacity(
                    opacity: opacity, // Opacity debe estar entre 0.0 y 1.0
                    child: _buildShelfCard(_shelves[index]),
                  ),
                );
              },
            );
          },
          childCount: _shelves.length,
        ),
      ),
    );
  }

  Widget _buildShelfCard(ShelfModel shelf) {
    final zonesCount = shelf.zones?.length ?? 0;
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShelfDetailScreen(shelf: shelf),
          ),
        ).then((_) => _loadShelves());
      },
      onLongPress: () => _showEditShelfDialog(shelf),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primaryColor, width: 3),
          boxShadow: AppTheme.popShadow(AppTheme.secondaryColor, offset: 5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Imagen
              Positioned.fill(
                child: Image.network(
                  shelf.masterPhotoUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[800],
                      child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                    );
                  },
                ),
              ),
              // Gradiente
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.8),
                      Colors.black.withOpacity(0.95),
                    ],
                    stops: const [0.0, 0.4, 0.75, 1.0],
                  ),
                ),
              ),
              // Contenido
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shelf.name.toUpperCase(),
                        style: GoogleFonts.archivoBlack(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.grid_view, color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  '$zonesCount zonas',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
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
              // Badge pública
              if (shelf.isPublic)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.public, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text('PÚBLICA',
                            style: GoogleFonts.archivoBlack(
                                color: Colors.white, fontSize: 9)),
                      ],
                    ),
                  ),
                ),
              // Icono de flecha
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditShelfDialog(ShelfModel shelf) async {
    HapticFeedback.mediumImpact();
    final nameController = TextEditingController(text: shelf.name);
    bool isPublic = shelf.isPublic;
    final socialService = SocialService();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          title: Text('EDITAR ESTANTERÍA',
              style: GoogleFonts.archivoBlack(
                  fontSize: 16, color: AppTheme.primaryColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nombre
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primaryColor, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: nameController,
                  style: GoogleFonts.robotoCondensed(
                      fontSize: 15, color: AppTheme.primaryColor),
                  decoration: InputDecoration(
                    labelText: 'Nombre',
                    labelStyle: GoogleFonts.archivoBlack(
                        fontSize: 12, color: Colors.grey[500]),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Toggle público
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primaryColor, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SwitchListTile(
                  title: Text('Pública',
                      style: GoogleFonts.archivoBlack(
                          fontSize: 13, color: AppTheme.primaryColor)),
                  subtitle: Text(
                      isPublic
                          ? 'Visible en tu perfil público'
                          : 'Solo tú puedes verla',
                      style: GoogleFonts.robotoCondensed(
                          fontSize: 12, color: Colors.grey[600])),
                  value: isPublic,
                  activeColor: AppTheme.secondaryColor,
                  onChanged: (val) => setDialogState(() => isPublic = val),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCELAR',
                  style: GoogleFonts.archivoBlack(
                      fontSize: 12, color: Colors.grey[500])),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, {
                'name': nameController.text.trim(),
                'is_public': isPublic,
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('GUARDAR',
                  style: GoogleFonts.archivoBlack(
                      fontSize: 12, color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      final newName = result['name'] as String;
      final newIsPublic = result['is_public'] as bool;

      try {
        final updates = <String, dynamic>{};
        if (newName.isNotEmpty && newName != shelf.name) {
          updates['name'] = newName;
        }
        if (newIsPublic != shelf.isPublic) {
          updates['is_public'] = newIsPublic;
        }
        if (updates.isNotEmpty) {
          await Supabase.instance.client
              .from('shelves')
              .update(updates)
              .eq('id', shelf.id);
          _loadShelves();
        }
      } catch (e) {
        debugPrint('Error updating shelf: $e');
      }
    }

    nameController.dispose();
  }

  Widget _buildFAB() {
    if (_isCreating) {
      return FloatingActionButton(
        onPressed: null,
        backgroundColor: AppTheme.secondaryColor,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryColor, width: 3),
        boxShadow: AppTheme.popShadow(AppTheme.primaryColor, offset: 4),
        color: AppTheme.secondaryColor,
      ),
      child: FloatingActionButton.extended(
        onPressed: _createNewShelf,
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
        label: Text(
          'NUEVA',
          style: GoogleFonts.archivoBlack(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
