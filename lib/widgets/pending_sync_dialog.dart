import 'package:flutter/material.dart';
import '../providers/sync_provider.dart';

class PendingSyncDialog extends StatefulWidget {
  final SyncProvider provider;
  final Future<void> Function(int id, String action) onDelete;

  const PendingSyncDialog({
    super.key,
    required this.provider,
    required this.onDelete,
  });

  static Future<void> show(
    BuildContext context, {
    required SyncProvider provider,
    required Future<void> Function(int id, String action) onDelete,
  }) {
    return showDialog(
      context: context,
      builder: (_) => PendingSyncDialog(provider: provider, onDelete: onDelete),
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

  Future<void> _delete(int id, String action) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Abandonner cette opération ?'),
        content: const Text(
            'L\'opération sera supprimée de la file de synchronisation et ne sera jamais envoyée au serveur.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Abandonner', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.onDelete(id, action);
      await _load();
    }
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
                  final id = item['id'] as int;
                  final action = item['action'] as String;
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.sync_rounded, size: 20),
                    title: Text(_actionLabel(action),
                        style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(_formatDate(item['created_at'] as String?),
                        style: const TextStyle(fontSize: 11.5)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      tooltip: 'Abandonner',
                      onPressed: () => _delete(id, action),
                    ),
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