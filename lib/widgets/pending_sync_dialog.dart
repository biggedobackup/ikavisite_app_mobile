import 'package:flutter/material.dart';
import '../providers/sync_provider.dart';

class PendingSyncDialog extends StatefulWidget {
  final SyncProvider provider;

  const PendingSyncDialog({
    super.key,
    required this.provider,
  });

  static Future<void> show(
    BuildContext context, {
    required SyncProvider provider,
  }) {
    return showDialog(
      context: context,
      builder: (_) => PendingSyncDialog(provider: provider),
    );
  }

  @override
  State<PendingSyncDialog> createState() => _PendingSyncDialogState();
}

class _PendingSyncDialogState extends State<PendingSyncDialog> {
  List<Map<String, dynamic>> _items = [];

  String _actionLabel(String action) {
    switch (action) {
      case 'create_visite':
        return 'Création de visite';
      case 'update_visite':
        return 'Modification de visite';
      case 'terminer_visite':
        return 'Clôture de visite';
      case 'update_profile':
        return 'Mise à jour du profil';
      default:
        return action;
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    final items = await widget.provider.getPendingItems();
    if (mounted) setState(() => _items = items);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Synchronisation en attente'),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: _items.isEmpty
            ? const Center(child: Text('Aucune opération en attente'))
            : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final item = _items[i];
                  final action = item['action'] as String;
                  final bloque = (item['status'] as int? ?? 0) == 2;
                  final tentatives = item['tentatives'] as int? ?? 0;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                        bloque ? Icons.error_outline_rounded : Icons.sync_rounded,
                        size: 20,
                        color: bloque ? Colors.red : null),
                    title: Text(_actionLabel(action),
                        style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                        bloque
                            ? '${_formatDate(item['created_at'] as String?)} · refusé après $tentatives tentatives'
                            : _formatDate(item['created_at'] as String?),
                        style: TextStyle(
                            fontSize: 11.5,
                            color: bloque ? Colors.red : null)),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
