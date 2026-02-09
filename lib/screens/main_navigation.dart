import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'shelves_screen.dart';
import 'listening_assistant_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  late final List<Widget> _screens = [
    const ListeningAssistantScreen(),
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

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('PERFIL', style: GoogleFonts.archivoBlack(fontSize: 20, color: AppTheme.primaryColor)),
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(3),
          child: Divider(color: AppTheme.primaryColor, thickness: 3, height: 3),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Avatar — Pop Art style
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryColor, width: 3),
                boxShadow: AppTheme.popShadow(AppTheme.secondaryColor, offset: 4),
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundImage: user?.userMetadata?['avatar_url'] != null
                    ? NetworkImage(user!.userMetadata!['avatar_url'] as String)
                    : null,
                child: user?.userMetadata?['avatar_url'] == null
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            
            // Nombre
            Text(
              (user?.userMetadata?['full_name'] as String? ?? 
              user?.email?.split('@')[0] ?? 
              'Usuario').toUpperCase(),
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
            const SizedBox(height: 32),

            // Opciones
            _buildOptionTile(
              icon: Icons.album,
              title: 'Vincular Discogs',
              subtitle: 'Importa tu colección',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Próximamente: Integración con Discogs')),
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
            
            // Logout — Pop Art style
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.errorColor,
                  border: Border.all(color: AppTheme.primaryColor, width: 3),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: AppTheme.popShadow(AppTheme.primaryColor, offset: 4),
                ),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                  },
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: Text(
                    (l10n?.logout ?? 'Cerrar sesión').toUpperCase(),
                    style: GoogleFonts.archivoBlack(color: Colors.white, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
      decoration: AppTheme.popCard(color: Colors.white, shadowColor: AppTheme.accentColor, radius: 8),
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
        title: Text(title.toUpperCase(), style: GoogleFonts.archivoBlack(fontWeight: FontWeight.w900, fontSize: 14, color: AppTheme.primaryColor)),
        subtitle: Text(subtitle, style: GoogleFonts.robotoCondensed(fontWeight: FontWeight.w500, color: Colors.grey[600])),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.primaryColor),
        onTap: onTap,
      ),
    );
  }
}
