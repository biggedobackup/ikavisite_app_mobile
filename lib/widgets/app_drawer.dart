import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../constants/colors.dart';
import '../screens/scan.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    final display = '${user?.firstName ?? ''} ${user?.lastName ?? ''}'.trim().isNotEmpty
        ? '${user!.firstName} ${user.lastName}'
        : user?.username ?? 'Utilisateur';
    final initial = display.isNotEmpty ? display[0].toUpperCase() : '?';

    return Drawer(
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ---- En-tête utilisateur ----
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.ikaBlue, Color(0xFF0E5A99)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ikaBlue),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(display,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                            if ((user?.email ?? '').isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(user!.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5, color: Colors.white70)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ---- Navigation ----
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                children: [
                  _drawerItem(
                    context: context,
                    icon: Icons.dashboard_rounded,
                    label: 'Tableau de bord',
                    route: '/dashboard',
                    replace: true,
                  ),
                  _drawerItem(
                    context: context,
                    icon: Icons.add_circle_outline_rounded,
                    label: 'Ajouter une visite',
                    route: '/add-visit',
                    onTapOverride: () {
                      Navigator.pop(context);
                      Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ScanScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  _sectionLabel('Suivi des visites'),
                  _drawerItem(
                    context: context,
                    icon: Icons.today_rounded,
                    label: 'Visite du jour',
                    route: '/visits-today',
                    accent: AppColors.ikaBlue,
                  ),
                  _drawerItem(
                    context: context,
                    icon: Icons.sync_rounded,
                    label: 'Visites en cours',
                    route: '/visits-in-progress',
                    accent: const Color(0xFFEA580C),
                  ),
                  _drawerItem(
                    context: context,
                    icon: Icons.warning_amber_rounded,
                    label: 'Visites excédées',
                    route: '/visits-overdue',
                    accent: AppColors.ikaRed,
                  ),
                  _drawerItem(
                    context: context,
                    icon: Icons.task_alt_rounded,
                    label: 'Visites terminées',
                    route: '/visits-completed',
                    accent: const Color(0xFF16A34A),
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 6),
                  _drawerItem(
                    context: context,
                    icon: Icons.person_rounded,
                    label: 'Mon profil',
                    route: '/profile',
                  ),
                ],
              ),
            ),

            // ---- Pied : déconnexion ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: _drawerItem(
                context: context,
                icon: Icons.logout_rounded,
                label: 'Se déconnecter',
                onTapOverride: () => _confirmLogout(context),
                accent: AppColors.ikaRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6)),
    );
  }

  Widget _drawerItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    String route = '',
    Color accent = AppColors.ikaBlue,
    bool replace = false,
    VoidCallback? onTapOverride,
  }) {
    final isActive = _isCurrentRoute(context, route);
    final color = onTapOverride != null ? accent : accent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isActive ? AppColors.blueSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTapOverride ??
              () {
                Navigator.pop(context);
                if (replace) {
                  Navigator.pushReplacementNamed(context, route);
                } else {
                  Navigator.pushNamed(context, route);
                }
              },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 21, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                          color: AppColors.text)),
                ),
                if (isActive)
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.ikaBlue),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isCurrentRoute(BuildContext context, String route) {
    final current = ModalRoute.of(context)?.settings.name;
    return current == route;
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    Navigator.pop(context);

    final confirm = await showDialog<bool>(
      context: navigator.context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vous déconnecter ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(navigator.context, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(navigator.context, true),
            child: const Text('Se déconnecter',
                style: TextStyle(color: AppColors.ikaRed)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await auth.logout();
      navigator.pushReplacementNamed('/login');
    }
  }
}
