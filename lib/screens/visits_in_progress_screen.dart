import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/visit_provider.dart';
import '../providers/connectivity_provider.dart';
import '../models/visit.dart';
import '../widgets/app_drawer.dart';
import '../widgets/visit_card.dart';
import '../widgets/terminate_visit_dialog.dart';
import '../constants/colors.dart';
import 'edit_visit_screen.dart';

class VisitsInProgressScreen extends StatefulWidget {
  const VisitsInProgressScreen({super.key});

  @override
  State<VisitsInProgressScreen> createState() => _VisitsInProgressScreenState();
}

class _VisitsInProgressScreenState extends State<VisitsInProgressScreen> {
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
      context.read<VisitProvider>().loadVisitesEnCours(t, onUnauthorized: () async {
        return await context.read<AuthProvider>().refreshAccessToken();
      });
    }
  }

  void _nextPage() async {
    final t = _getToken();
    if (t != null) {
      final err = await context.read<VisitProvider>().nextPageEnCours(t);
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _terminerVisite(Visit visit) async {
    final result = await TerminateVisitDialog.show(context, visit.visiteurNomComplet);
    if (result == null || !mounted) return;

    final auth = context.read<AuthProvider>();
    final t = auth.accessToken;
    if (t != null && t.isNotEmpty) {
      final success = await context.read<VisitProvider>().terminerVisite(
        t, visit.id,
        body: result.body,
        onUnauthorized: () async => auth.refreshAccessToken(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? (context.read<ConnectivityProvider>().isConnected
                  ? 'Visite clôturée'
                  : 'Visite clôturée localement, synchronisation en attente')
              : 'Erreur lors de la clôture'),
          backgroundColor: success ? Colors.green : Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visites en cours'),
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
          if (vp.error != null && vp.visitsEnCours.isEmpty) {
            return _buildError(vp.error!, _loadVisits);
          }

          if (vp.visitsEnCours.isEmpty && !vp.isRefreshing) {
            return _buildEmpty();
          }

          final hasMore = vp.pageEnCours < vp.totalPagesEnCours;

          return Column(
            children: [
              if (vp.isRefreshing)
                const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
              _buildHeader(vp.countEnCours),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _loadVisits(),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: vp.visitsEnCours.length + (hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == vp.visitsEnCours.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEA580C)),
                          ),
                        );
                      }
                      return VisitCard(
                        visit: vp.visitsEnCours[i],
                        statutColor: Colors.orange,
                        statutLabel: 'en cours',
                        trailing: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EditVisitScreen(visiteId: vp.visitsEnCours[i].id),
                                    ),
                                  );
                                  if (result == true) _loadVisits();
                                },
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: const Text('Modifier', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.ikaBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _terminerVisite(vp.visitsEnCours[i]),
                                icon: const Icon(Icons.check_circle, size: 16),
                                label: const Text('Clôturer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
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
      color: const Color(0xFFEA580C).withValues(alpha: 0.05),
      child: Row(
        children: [
          const Icon(Icons.list_rounded, size: 16, color: Color(0xFFEA580C)),
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
          const Icon(Icons.check_circle_outline_rounded, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          const Text('Aucune visite en cours',
              style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
        ],
      ),
    );
  }
}
