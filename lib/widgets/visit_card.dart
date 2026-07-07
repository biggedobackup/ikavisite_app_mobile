import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/api_config.dart';
import '../models/visit.dart';
import '../screens/visit_detail_screen.dart';

class VisitCard extends StatelessWidget {
  final Visit visit;
  final Color statutColor;
  final String statutLabel;
  final Widget? trailing;

  static const _grey400 = Color(0xFFBDBDBD);
  static const _grey500 = Color(0xFF9E9E9E);

  const VisitCard({
    super.key,
    required this.visit,
    required this.statutColor,
    required this.statutLabel,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => VisitDetailScreen(visiteId: visit.id),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: statutColor.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
          ],
          border: Border.all(color: statutColor.withValues(alpha: 0.1), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImageHeader(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(Icons.calendar_today, 'Date', visit.dateVisite ?? '-'),
                  _buildInfoRow(Icons.access_time, 'Arrivée', visit.heureArrivee ?? '-'),
                  _buildInfoRow(Icons.exit_to_app, 'Départ prévu', visit.heureDepartPrevue ?? '-'),
                  if (visit.motif != null && visit.motif!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildInfoRow(Icons.note, 'Motif', visit.motif!),
                  ],
                  if (visit.porteEntree != null) ...[
                    const SizedBox(height: 6),
                    _buildInfoRow(Icons.door_front_door, 'Porte', visit.porteEntree!.titre ?? '-'),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(height: 10),
                    trailing!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageHeader(BuildContext context) {
    final photo = visit.visiteur?.photo;
    final hasPhoto = photo != null && photo.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statutColor.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: hasPhoto
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: _resolveImageUrl(photo),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      memCacheWidth: (44 * MediaQuery.of(context).devicePixelRatio).round(),
                      memCacheHeight: (44 * MediaQuery.of(context).devicePixelRatio).round(),
                      placeholder: (ctx, url) => _avatarPlaceholder(),
                      errorWidget: (ctx, url, err) => _avatarPlaceholder(),
                    ),
                  )
                : _avatarPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(visit.visiteurNomComplet,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(visit.visiteur?.telephone ?? '',
                    style: TextStyle(fontSize: 12, color: _grey500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statutColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(statutLabel,
                style: TextStyle(fontSize: 10, color: statutColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: statutColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.person, size: 22, color: statutColor),
    );
  }

  String _resolveImageUrl(String path) {
    if (path.startsWith('http')) return path;
    if (path.startsWith('/')) return '${ApiConfig.baseUrl}$path';
    return '${ApiConfig.baseUrl}/$path';
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _grey400),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(fontSize: 12, color: _grey500)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
