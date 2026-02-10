import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';
import '../services/wishlist_service.dart';
import 'shelves_screen.dart';
import 'listening_assistant_screen.dart';
import 'feed_screen.dart';
import 'wishlist_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  late final List<Widget> _screens = [
    const ListeningAssistantScreen(),
    const FeedScreen(),
    const ShelvesScreen(),
    const _ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.backgroundColor,
          border: Border(top: BorderSide(color: AppTheme.primaryColor, width: 3)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppTheme.backgroundColor,
          selectedItemColor: AppTheme.secondaryColor,
          unselectedItemColor: AppTheme.primaryColor.withOpacity(0.35),
          elevation: 0,
          selectedLabelStyle: GoogleFonts.archivoBlack(fontSize: 10, fontWeight: FontWeight.w900),
          unselectedLabelStyle: GoogleFonts.robotoCondensed(fontSize: 10, fontWeight: FontWeight.w700),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.album),
              label: 'COLECCIÓN',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore),
              label: 'FEED',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.shelves),
              label: 'ESTANTERÍAS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'PERFIL',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileScreen extends StatefulWidget {
  const _ProfileScreen();

  @override
  State<_ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<_ProfileScreen> {
  final _socialService = SocialService();
  final _supabase = Supabase.instance.client;

  bool _isPublic = false;
  bool _sharePhotos = false;
  String _username = '';
  String _bio = '';
  bool _isLoading = true;
  bool _isSaving = false;

  // Estanterías con su visibilidad
  List<Map<String, dynamic>> _shelves = [];

  late TextEditingController _usernameController;
  late TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _bioController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Cargar datos del usuario
      final userData = await _supabase
          .from('users')
          .select('is_public, share_photos, username, bio')
          .eq('id', userId)
          .maybeSingle();

      // Cargar estanterías
      final shelvesData = await _supabase
          .from('shelves')
          .select('id, name, is_public')
          .eq('user_id', userId)
          .order('created_at');

      if (mounted) {
        setState(() {
          _isPublic = userData?['is_public'] as bool? ?? false;
          _sharePhotos = userData?['share_photos'] as bool? ?? false;
          _username = userData?['username'] as String? ?? '';
          _bio = userData?['bio'] as String? ?? '';
          _usernameController.text = _username;
          _bioController.text = _bio;
          _shelves = (shelvesData as List)
              .map((s) => {
                    'id': s['id'],
                    'name': s['name'],
                    'is_public': s['is_public'] ?? false,
                  })
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    final newUsername = _usernameController.text.trim().toLowerCase();

    // Verificar username si cambió
    if (newUsername.isNotEmpty && newUsername != _username) {
      final available = await _socialService.isUsernameAvailable(newUsername);
      if (!available && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('El username "$newUsername" ya está en uso',
                style: GoogleFonts.poppins()),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        setState(() => _isSaving = false);
        return;
      }
    }

    final success = await _socialService.updatePublicProfile(
      isPublic: _isPublic,
      sharePhotos: _sharePhotos,
      username: newUsername,
      bio: _bioController.text.trim(),
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (success) _username = newUsername;
      });
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text('Perfil actualizado', style: GoogleFonts.poppins()),
              ],
            ),
            backgroundColor: const Color(0xFF00C853),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _toggleShelfVisibility(int index) async {
    final shelf = _shelves[index];
    final newValue = !(shelf['is_public'] as bool);

    final success = await _socialService.updateShelfVisibility(
      shelf['id'] as String,
      newValue,
    );

    if (success && mounted) {
      HapticFeedback.lightImpact();
      setState(() {
        _shelves[index] = {...shelf, 'is_public': newValue};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('PERFIL',
            style: GoogleFonts.archivoBlack(
                fontSize: 20, color: AppTheme.primaryColor)),
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(3),
          child: Divider(
              color: AppTheme.primaryColor, thickness: 3, height: 3),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar + nombre
                  Center(
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.primaryColor, width: 3),
                            boxShadow: AppTheme.popShadow(
                                AppTheme.secondaryColor,
                                offset: 4),
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundImage:
                                user?.userMetadata?['avatar_url'] != null
                                    ? NetworkImage(
                                        user!.userMetadata!['avatar_url']
                                            as String)
                                    : null,
                            child:
                                user?.userMetadata?['avatar_url'] == null
                                    ? const Icon(Icons.person, size: 50)
                                    : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          (user?.userMetadata?['full_name'] as String? ??
                                  user?.email?.split('@')[0] ??
                                  'Usuario')
                              .toUpperCase(),
                          style: GoogleFonts.archivoBlack(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? '',
                          style: GoogleFonts.robotoCondensed(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ─── SECCIÓN SOCIAL ───
                  Text('PERFIL PÚBLICO',
                      style: GoogleFonts.archivoBlack(
                          fontSize: 14, color: AppTheme.primaryColor)),
                  const SizedBox(height: 12),

                  // Toggle perfil público
                  Container(
                    decoration: AppTheme.popCard(
                        color: Colors.white,
                        shadowColor: AppTheme.accentColor,
                        radius: 8),
                    child: SwitchListTile(
                      title: Text('Perfil visible',
                          style: GoogleFonts.archivoBlack(
                              fontSize: 13,
                              color: AppTheme.primaryColor)),
                      subtitle: Text(
                          _isPublic
                              ? 'Otros usuarios pueden ver tu colección'
                              : 'Tu perfil es privado',
                          style: GoogleFonts.robotoCondensed(
                              color: Colors.grey[600])),
                      value: _isPublic,
                      activeColor: AppTheme.secondaryColor,
                      onChanged: (val) =>
                          setState(() => _isPublic = val),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Toggle compartir fotos en feed
                  Container(
                    decoration: AppTheme.popCard(
                        color: Colors.white,
                        shadowColor: AppTheme.accentColor,
                        radius: 8),
                    child: SwitchListTile(
                      title: Text('Publicar mis fotos',
                          style: GoogleFonts.archivoBlack(
                              fontSize: 13,
                              color: AppTheme.primaryColor)),
                      subtitle: Text(
                          _sharePhotos
                              ? 'Tus fotos de vinilos aparecen en el feed'
                              : 'Tus fotos son privadas',
                          style: GoogleFonts.robotoCondensed(
                              color: Colors.grey[600])),
                      value: _sharePhotos,
                      activeColor: AppTheme.secondaryColor,
                      onChanged: (val) =>
                          setState(() => _sharePhotos = val),
                      secondary: Icon(Icons.photo_camera_rounded,
                          color: _sharePhotos
                              ? AppTheme.secondaryColor
                              : Colors.grey[400]),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Username
                  Container(
                    decoration: AppTheme.popCard(
                        color: Colors.white,
                        shadowColor: AppTheme.accentColor,
                        radius: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _usernameController,
                      style: GoogleFonts.robotoCondensed(
                          fontSize: 15, color: AppTheme.primaryColor),
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: GoogleFonts.archivoBlack(
                            fontSize: 12, color: Colors.grey[500]),
                        hintText: 'tu_nombre_unico',
                        hintStyle: GoogleFonts.robotoCondensed(
                            color: Colors.grey[400]),
                        prefixIcon: const Icon(Icons.alternate_email,
                            size: 20, color: AppTheme.primaryColor),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Bio
                  Container(
                    decoration: AppTheme.popCard(
                        color: Colors.white,
                        shadowColor: AppTheme.accentColor,
                        radius: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _bioController,
                      maxLines: 2,
                      maxLength: 150,
                      style: GoogleFonts.robotoCondensed(
                          fontSize: 15, color: AppTheme.primaryColor),
                      decoration: InputDecoration(
                        labelText: 'Bio',
                        labelStyle: GoogleFonts.archivoBlack(
                            fontSize: 12, color: Colors.grey[500]),
                        hintText: 'Cuéntanos sobre tu colección...',
                        hintStyle: GoogleFonts.robotoCondensed(
                            color: Colors.grey[400]),
                        prefixIcon: const Icon(Icons.edit_note,
                            size: 20, color: AppTheme.primaryColor),
                        border: InputBorder.none,
                        counterStyle: GoogleFonts.robotoCondensed(
                            fontSize: 11, color: Colors.grey[400]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Botón guardar perfil
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor,
                        border: Border.all(
                            color: AppTheme.primaryColor, width: 3),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: AppTheme.popShadow(
                            AppTheme.primaryColor,
                            offset: 4),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveProfile,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2))
                            : const Icon(Icons.save_rounded,
                                color: Colors.white),
                        label: Text(
                          'GUARDAR PERFIL',
                          style: GoogleFonts.archivoBlack(
                              color: Colors.white, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ),

                  // ─── MI WISHLIST ───
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WishlistScreen()),
                      );
                    },
                    child: Container(
                      decoration: AppTheme.popCard(
                          color: Colors.white,
                          shadowColor: AppTheme.secondaryColor,
                          radius: 10),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppTheme.primaryColor, width: 2),
                            ),
                            child: const Icon(Icons.favorite,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('MI WISHLIST',
                                    style: GoogleFonts.archivoBlack(
                                        fontSize: 14,
                                        color: AppTheme.primaryColor)),
                                const SizedBox(height: 2),
                                Text(
                                  'Discos que quieres tener',
                                  style: GoogleFonts.robotoCondensed(
                                      fontSize: 12,
                                      color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: AppTheme.primaryColor),
                        ],
                      ),
                    ),
                  ),

                  // ─── ESTANTERÍAS PÚBLICAS ───
                  if (_shelves.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Text('ESTANTERÍAS PÚBLICAS',
                        style: GoogleFonts.archivoBlack(
                            fontSize: 14,
                            color: AppTheme.primaryColor)),
                    const SizedBox(height: 8),
                    Text(
                      'Elige qué estanterías aparecen en tu perfil público',
                      style: GoogleFonts.robotoCondensed(
                          fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_shelves.length, (i) {
                      final shelf = _shelves[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: AppTheme.popCard(
                            color: Colors.white,
                            shadowColor: AppTheme.canaryYellow,
                            radius: 8),
                        child: SwitchListTile(
                          title: Text(
                              (shelf['name'] as String).toUpperCase(),
                              style: GoogleFonts.archivoBlack(
                                  fontSize: 13,
                                  color: AppTheme.primaryColor)),
                          value: shelf['is_public'] as bool,
                          activeColor: AppTheme.secondaryColor,
                          onChanged: (_) =>
                              _toggleShelfVisibility(i),
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 32),

                  // ─── OPCIONES EXISTENTES ───
                  Text('OPCIONES',
                      style: GoogleFonts.archivoBlack(
                          fontSize: 14, color: AppTheme.primaryColor)),
                  const SizedBox(height: 12),
                  _buildOptionTile(
                    icon: Icons.album,
                    title: 'Vincular Discogs',
                    subtitle: 'Importa tu colección',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Próximamente: Integración con Discogs')),
                      );
                    },
                  ),
                  _buildOptionTile(
                    icon: Icons.sync,
                    title: 'Sincronizar',
                    subtitle: 'Actualizar datos',
                    onTap: () {},
                  ),
                  _buildOptionTile(
                    icon: Icons.settings,
                    title: 'Ajustes',
                    subtitle: 'Configuración de la app',
                    onTap: () {},
                  ),
                  const SizedBox(height: 24),

                  // Logout
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor,
                        border: Border.all(
                            color: AppTheme.primaryColor, width: 3),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: AppTheme.popShadow(
                            AppTheme.primaryColor,
                            offset: 4),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await _supabase.auth.signOut();
                        },
                        icon: const Icon(Icons.logout,
                            color: Colors.white),
                        label: Text(
                          (l10n?.logout ?? 'Cerrar sesión')
                              .toUpperCase(),
                          style: GoogleFonts.archivoBlack(
                              color: Colors.white, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: AppTheme.popCard(
          color: Colors.white,
          shadowColor: AppTheme.accentColor,
          radius: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.canaryYellow,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.primaryColor, width: 2),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 22),
        ),
        title: Text(title.toUpperCase(),
            style: GoogleFonts.archivoBlack(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: AppTheme.primaryColor)),
        subtitle: Text(subtitle,
            style: GoogleFonts.robotoCondensed(
                fontWeight: FontWeight.w500, color: Colors.grey[600])),
        trailing:
            const Icon(Icons.chevron_right, color: AppTheme.primaryColor),
        onTap: onTap,
      ),
    );
  }
}
