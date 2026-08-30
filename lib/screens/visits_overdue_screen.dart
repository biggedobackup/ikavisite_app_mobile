import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/visit.dart';
import '../providers/auth_provider.dart';
import '../providers/visit_provider.dart';
import '../providers/connectivity_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/visit_card.dart';
import '../widgets/terminate_visit_dialog.dart';
import '../constants/colors.dart';

class VisitsOverdueScreen extends StatefulWidget {
  const VisitsOverdueScreen({super.key});

  @override
  State<VisitsOverdueScreen> createState() => _VisitsOverdueScreenState();
}

class _VisitsOverdueScreenState extends State<VisitsOverdueScreen> {
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
      context.read<VisitProvider>().loadVisitesExcedees(t, onUnauthorized: () async {
        return await context.read<AuthProvider>().refreshAccessToken();
      });
    }
  }

  void _nextPage() async {
    final t = _getToken();
    if (t != null) {
      final err = await context.read<VisitProvider>().nextPageExcedees(t);
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
        title: const Text('Visites excédées'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: AppColors.ikaBlue), onPressed: _loadVisits),
        ],
      ),
      drawer: const AppDrawer(),
      body: Consumer<VisitProvider>(
        builder: (_, vp, _) {
          if (vp.error != null && vp.visitsExcedees.isEmpty) {
            return _buildError(vp.error!, _loadVisits);
          }

          if (vp.visitsExcedees.isEmpty && !vp.isRefreshing) {
            return _buildEmpty();
          }

          final hasMore = vp.pageExcedees < vp.totalPagesExcedees;

          return Column(
            children: [
              if (vp.isRefreshing)
                const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
              _buildHeader(vp.countExcedees),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _loadVisits(),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: vp.visitsExcedees.length + (hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == vp.visitsExcedees.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ikaRed),
                          ),
                        );
                      }
                      return VisitCard(
                        visit: vp.visitsExcedees[i],
                        statutColor: Colors.red,
                        statutLabel: 'excédée',
                        trailing: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _terminerVisite(vp.visitsExcedees[i]),
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: const Text('Clôturer la visite', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
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
      color: AppColors.ikaRed.withValues(alpha: 0.05),
      child: Row(
        children: [
          const Icon(Icons.list_rounded, size: 16, color: AppColors.ikaRed),
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
          const Icon(Icons.check_circle_rounded, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          const Text('Aucune visite excédée',
              style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
        ],
      ),
    );
  }
}
