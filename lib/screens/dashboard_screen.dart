import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/visit_provider.dart';
import '../providers/sync_provider.dart';
import '../models/dashboard_stats.dart';
import '../widgets/app_drawer.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/pending_sync_dialog.dart';
import 'scan.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with RouteAware {
  // Palette partagée avec la page de connexion
  static const Color kIkaBlue = Color(0xFF1270B8);
  static const Color kIkaRed = Color(0xFFDC2626);
  static const Color kCard = Color(0xFFFFFFFF);
  static const Color kInputBg = Color(0xFFF8FAFC);
  static const Color kBorder = Color(0xFFE2E8F0);
  static const Color kText = Color(0xFF0F172A);
  static const Color kTextMuted = Color(0xFF64748B);
  static const Color kBlueSoft = Color(0xFFEFF6FF);

  late DashboardProvider _dashboardProvider;

  /// Totaux de la base locale pour les quatre listes, toujours affichés en
  /// priorité sur les tuiles du tableau de bord (voir
  /// `_refreshLocalPendingCount`).
  Map<String, int>? _localCounts;

  @override
  void initState() {
    super.initState();
    _dashboardProvider = context.read<DashboardProvider>();
    _dashboardProvider.clearStats();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStats();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _dashboardProvider.cancelPending();
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadStats();
  }

void _loadStats() {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    final t = auth.accessToken;
    if (t != null && t.isNotEmpty) {
      context.read<DashboardProvider>().loadStats(t, onUnauthorized: () async {
        final a = context.read<AuthProvider>();
        return await a.refreshAccessToken();
      });
      context.read<VisitProvider>().prefetchAndCacheDropdowns(t);
    }
    context.read<SyncProvider>().refreshPendingCount();
    _refreshLocalPendingCount();
  }

  /// Les quatre tuiles affichent toujours le total de la base locale — la
  /// même formule que l'en-tête « N élément(s) » de chaque écran de liste
  /// (compte serveur en cache + saisies locales non synchronisées) — plutôt
  /// que les statistiques d'un endpoint séparé. Ce dernier ne connaît pas les
  /// saisies hors ligne et peut renvoyer des chiffres bien plus bas dès que
  /// le réseau revient, ce qui faisait retomber les tuiles à zéro à chaque
  /// bascule en ligne/hors ligne alors que la base locale, elle, ne change
  /// pas.
  Future<void> _refreshLocalPendingCount() async {
    final visitProvider = context.read<VisitProvider>();
    // Les saisies hors ligne peuvent n'avoir jamais été chargées si aucune
    // liste n'a été ouverte : on s'en assure avant de compter.
    await visitProvider.ensureLocalVisitsLoaded();

    final counts = {
      'visits-today': await visitProvider.getListTotalCount('today'),
      'visits-in-progress': await visitProvider.getListTotalCount('en_cours'),
      'visits-completed': await visitProvider.getListTotalCount('terminees'),
      'visits-overdue': await visitProvider.getListTotalCount('excedees'),
    };

    if (mounted && counts.toString() != _localCounts?.toString()) {
      setState(() => _localCounts = counts);
    }
  }

  Color _toneColor(String tone) {
    switch (tone) {
      case 'danger':
        return kIkaRed;
      case 'success':
        return const Color(0xFF16A34A);
      case 'warning':
        return const Color(0xFFEA580C);
      default:
        return kIkaBlue;
    }
  }

  IconData _iconFromName(String name) {
    switch (name) {
      case 'calendar':
        return Icons.calendar_today;
      case 'today':
        return Icons.today;
      case 'clock':
        return Icons.access_time;
      case 'check':
        return Icons.check_circle;
      case 'alert':
        return Icons.warning;
      case 'users':
        return Icons.people;
      case 'building':
        return Icons.business;
      case 'door':
        return Icons.door_front_door;
      case 'shield':
        return Icons.shield;
      case 'box':
        return Icons.inventory_2;
      default:
        return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kInputBg,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        backgroundColor: kCard,
        foregroundColor: kText,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: kIkaBlue),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: Selector<DashboardProvider, DashboardStats?>(
        selector: (_, p) => p.stats,
        builder: (_, stats, _) {
          if (stats == null) {
            return Selector<DashboardProvider, bool>(
              selector: (_, p) => p.isLoading,
              builder: (_, isLoading, _) {
                if (isLoading) return const DashboardSkeleton();
                return Consumer<DashboardProvider>(
                  builder: (_, p, _) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(p.error ?? 'Aucune donnée disponible',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kTextMuted, fontSize: 14)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadStats,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kIkaBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }

          return RefreshIndicator(
            color: kIkaBlue,
            onRefresh: () async => _loadStats(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(child: _buildWelcomeHeader()),
                  const SliverToBoxAdapter(child: SizedBox(height: 14)),
                  SliverToBoxAdapter(child: _buildConnectivityBanner()),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(child: _buildSectionTitle('Statistiques')),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  _buildStatsSliverGrid(stats.stats),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                  SliverToBoxAdapter(child: _buildActionButtons()),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- En-tête de bienvenue ----
  Widget _buildWelcomeHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: kIkaBlue.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Consumer<AuthProvider>(
        builder: (_, auth, _) {
          final user = auth.user;
          final name = user?.firstName != null
              ? '${user!.firstName} ${user.lastName}'
              : user?.username ?? 'Utilisateur';
          return Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: kBlueSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.person_rounded, color: kIkaBlue, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('👋 Bonjour,',
                        style: TextStyle(fontSize: 12.5, color: kTextMuted, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(name,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: kText)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConnectivityBanner() {
    return Consumer2<DashboardProvider, SyncProvider>(
      builder: (_, dashboard, syncProv, _) {
        if (!dashboard.isConnected) {
          final count = syncProv.pendingCount;
          final msg = count > 0
              ? 'Mode hors connexion - $count visite${count > 1 ? "s" : ""} en attente de synchronisation'
              : 'Mode hors connexion - données en local';
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_off, size: 18, color: Color(0xFFEA580C)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(msg,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412))),
                ),
                if (count > 0)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF9A3412),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => PendingSyncDialog.show(
                      context,
                      provider: syncProv,
                    ),
                    child: const Text('Voir', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: kIkaBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
      ],
    );
  }

  String _toneForStat(String icon, String label, String tone) {
    final l = label.toLowerCase();
    if (l.contains('cours')) return 'success';
    if (l.contains('excéd') || l.contains('exced')) return 'danger';
    if (icon == 'check' || l.contains('termin')) return 'danger';
    return tone;
  }

  String? _getScreenFromIconOrLabel(String icon, String label) {
    final l = label.toLowerCase();
    // L'icône prime sur le libellé, et les libellés les plus spécifiques sont
    // testés d'abord : « Visites terminées du jour » contient à la fois
    // « termin » et « jour », l'ordre décidait donc du résultat — et le
    // rattachait à tort à la liste du jour.
    if (icon == 'today') return 'visits-today';
    if (icon == 'clock') return 'visits-in-progress';
    if (icon == 'check' || icon == 'check-circle') return 'visits-completed';
    if (icon == 'alert') return 'visits-overdue';
    if (l.contains('termin')) return 'visits-completed';
    if (l.contains('excéd') || l.contains('exced')) return 'visits-overdue';
    if (l.contains('cours')) return 'visits-in-progress';
    if (l.contains('jour')) return 'visits-today';
    return null;
  }

  Widget _buildStatsSliverGrid(List<StatItem> items) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate(
        (_, i) {
          final item = items[i];
          final screen = item.screen ?? _getScreenFromIconOrLabel(item.icon, item.label);
          final tone = _toneForStat(item.icon, item.label, item.tone);
          // La base locale fait foi, en ligne comme hors ligne (voir
          // `_refreshLocalPendingCount`).
          final value = _localCounts?[screen] ?? item.value;
          return _buildStatCard(
            item.icon, tone, item.label, value, item.sub,
            onTap: screen != null ? () => _navigateToScreen(screen) : null,
          );
        },
        childCount: items.length,
      ),
    );
  }

  void _navigateToScreen(String screen) {
    final route = switch (screen) {
      'visits-today' => '/visits-today',
      'visits-in-progress' => '/visits-in-progress',
      'visits-completed' => '/visits-completed',
      'visits-overdue' => '/visits-overdue',
      'add-visit' => '/add-visit',
      'profile' => '/profile',
      _ => null,
    };
    if (route != null) {
      Navigator.pushNamed(context, route);
    }
  }

  Widget _buildStatCard(String icon, String tone, String label, int value, String sub, {VoidCallback? onTap}) {
    final color = _toneColor(tone);
    final card = Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: kIkaBlue.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(_iconFromName(icon), size: 18, color: color),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(sub,
                      style: TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const Spacer(),
            Text('$value',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: color.withValues(alpha: 0.92))),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: kTextMuted,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              );
              if (result == true) {
                _loadStats();
              }
            },
            icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
            label: const Text('Ajouter une visite',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kIkaBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/visits-in-progress'),
            icon: const Icon(Icons.sync_rounded, size: 22),
            label: const Text('Visite en cours',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }
}
