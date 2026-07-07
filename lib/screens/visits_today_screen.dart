import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/visit_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/visit_card.dart';
import '../constants/colors.dart';
import 'edit_visit_screen.dart';

class VisitsTodayScreen extends StatefulWidget {
  const VisitsTodayScreen({super.key});

  @override
  State<VisitsTodayScreen> createState() => _VisitsTodayScreenState();
}

class _VisitsTodayScreenState extends State<VisitsTodayScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVisits());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _nextPage();
    }
  }

  String? _getToken() {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return null;
    return auth.accessToken;
  }

  void _loadVisits() {
    final t = _getToken();
    if (t != null) {
      context.read<VisitProvider>().loadVisitesToday(t, onUnauthorized: () async {
        return await context.read<AuthProvider>().refreshAccessToken();
      });
    }
  }

  void _nextPage() async {
    final t = _getToken();
    if (t != null) {
      final err = await context.read<VisitProvider>().nextPageToday(t);
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visite du jour'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: AppColors.ikaBlue), onPressed: _loadVisits),
          IconButton(
            icon: const Icon(Icons.person_rounded, color: AppColors.ikaBlue),
            onPressed: () => Navigator.pushNamed(context, '/profile'),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Consumer<VisitProvider>(
        builder: (_, vp, _) {
          if (vp.error != null && vp.visitsToday.isEmpty) {
            return _buildError(vp.error!, _loadVisits);
          }

          if (vp.visitsToday.isEmpty && !vp.isRefreshing) {
            return _buildEmpty();
          }

          final hasMore = vp.pageToday < vp.totalPagesToday;

          return Column(
            children: [
              if (vp.isRefreshing)
                const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
              _buildHeader(vp.countToday),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _loadVisits(),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: vp.visitsToday.length + (hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == vp.visitsToday.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ikaBlue),
                          ),
                        );
                      }
                      final visit = vp.visitsToday[i];
                      final isEnCours = visit.statut?.toLowerCase() == 'en_cours' || visit.statut?.toLowerCase() == 'en cours';
                      return VisitCard(
                        visit: visit,
                        statutColor: _statutColor(visit.statut),
                        statutLabel: visit.statut ?? '',
                        trailing: isEnCours
                            ? SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EditVisitScreen(visiteId: visit.id),
                                      ),
                                    );
                                    if (result == true) _loadVisits();
                                  },
                                  icon: const Icon(Icons.edit_rounded, size: 16),
                                  label: const Text('Modifier', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.ikaBlue,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.ikaBlue.withValues(alpha: 0.05),
      child: Row(
        children: [
          const Icon(Icons.list_rounded, size: 16, color: AppColors.ikaBlue),
          const SizedBox(width: 6),
          Text('$count élément(s)',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildError(String msg, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.ikaBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.event_busy_rounded, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          const Text('Aucune visite prévue aujourd\'hui',
              style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
        ],
      ),
    );
  }

  Color _statutColor(String? statut) {
    switch (statut?.toLowerCase()) {
      case 'en_cours':
      case 'en cours':
        return Colors.orange;
      case 'terminee':
      case 'terminée':
      case 'termine':
        return Colors.green;
      case 'excedee':
      case 'excédée':
      case 'excédee':
        return Colors.red;
      default:
        return AppColors.ikaBlue;
    }
  }
}
