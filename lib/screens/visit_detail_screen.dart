import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import '../providers/visit_provider.dart';
import '../models/visit.dart';
import '../services/visit_media.dart';
import '../widgets/skeleton_loader.dart';
import 'edit_visit_screen.dart';

class VisitDetailScreen extends StatefulWidget {
  final int visiteId;

  const VisitDetailScreen({super.key, required this.visiteId});

  @override
  State<VisitDetailScreen> createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends State<VisitDetailScreen> {
  Visit? _visit;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  final Map<String, Uint8List> _decodedImages = {};

  /// Visites deja enregistrees pour le meme visiteur, la plus recente en tete.
  List<Visit> _historique = const [];
  bool _historiqueEnCours = false;

  /// Signatures de sortie de l'historique. Elles vivent a part : le rechar-
  /// gement de la visite courante vide `_decodedImages`, pas celle-ci.
  final Map<String, Uint8List> _historiqueImages = {};

  static const _grey100 = Color(0xFFF5F5F5);
  static const _grey400 = Color(0xFFBDBDBD);
  static const _grey500 = Color(0xFF9E9E9E);
  static const _grey600 = Color(0xFF757575);
  static const _grey800 = Color(0xFF424242);

  @override
  void initState() {
    super.initState();
    _loadVisit();
  }

  String? _getToken() {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return null;
    return auth.accessToken;
  }

  Future<void> _loadVisit() async {
    final t = _getToken();
    if (t == null) return;

    setState(() {
      _isLoading = _visit == null;
      _isRefreshing = false;
      _error = null;
    });

    try {
      final visit = await context.read<VisitProvider>().getVisitDetail(
        t, widget.visiteId,
        onUnauthorized: () async => context.read<AuthProvider>().refreshAccessToken(),
      );
      // Les images sont decodees AVANT d'etre posees dans le state : sinon le
      // premier build les decodait lui-meme, sur le thread UI.
      final decoded = await _decodeImagesFor(visit);
      if (mounted) {
        setState(() {
          _visit = visit;
          _decodedImages
            ..clear()
            ..addAll(decoded);
          _isLoading = false;
          if (visit == null) {
            _error = 'Aucune donnée disponible hors ligne';
          }
        });

        // If we got data from cache/list, refresh from API in background
        if (visit != null && mounted) {
          setState(() => _isRefreshing = true);
          final refreshed = await context.read<VisitProvider>().refreshVisitDetail(
            t, widget.visiteId,
            onUnauthorized: () async => context.read<AuthProvider>().refreshAccessToken(),
          );
          final refreshedImages = await _decodeImagesFor(refreshed);
          if (mounted) {
            setState(() {
              if (refreshed != null) {
                _visit = refreshed;
                _decodedImages
                  ..clear()
                  ..addAll(refreshedImages);
              }
              _isRefreshing = false;
            });
          }
        }

        if (mounted && _visit != null) await _loadHistorique();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_visit == null) _error = e.toString();
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  /// Charge les visites deja enregistrees pour le meme visiteur, puis decode
  /// leurs signatures de sortie hors du thread UI.
  Future<void> _loadHistorique() async {
    final visiteur = _visit?.visiteur;
    if (visiteur == null) return;

    setState(() => _historiqueEnCours = true);
    final provider = context.read<VisitProvider>();
    final token = _getToken();
    final visites = await provider.getHistoriqueVisiteur(
      token,
      visiteurUuid: visiteur.uuid,
      visiteurId: visiteur.id,
    );

    final raws = <String>[];
    for (final v in visites) {
      final sig = v.signatureSortie;
      if (sig == null || sig.isEmpty || sig.startsWith('http') || sig.startsWith('/')) {
        continue;
      }
      if (VisitMedia.isLocal(sig)) continue;
      raws.add(sig);
    }
    final decodees = raws.isEmpty
        ? const <String, Uint8List>{}
        : _decodeBase64Images(raws);

    if (!mounted) return;
    setState(() {
      _historique = visites;
      _historiqueImages
        ..clear()
        ..addAll(decodees);
      _historiqueEnCours = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail de la visite'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          if (_visit != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditVisitScreen(visiteId: widget.visiteId),
                  ),
                );
                if (result == true) _loadVisit();
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadVisit,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const VisitDetailSkeleton()
          : _error != null
              ? _buildError()
              : Column(children: [
                  if (_isRefreshing)
                    const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
                  Expanded(child: _buildDetail()),
                ]),
    );
  }

  /// Au-dela de ce volume de base64, le decodage part sur un isolate. En
  /// dessous, le cout de demarrage de l'isolate depasserait le decodage.
  static const int _isolateDecodeThreshold = 256 * 1024;

  /// Decode les images base64 de la visite hors du thread UI quand elles sont
  /// volumineuses (photos venant du back-office, non redimensionnees).
  Future<Map<String, Uint8List>> _decodeImagesFor(Visit? visit) async {
    if (visit == null) return const {};

    final raws = <String>[];
    for (final raw in [
      visit.visiteur?.photo,
      visit.visiteur?.documentRecto,
      visit.visiteur?.documentVerso,
      visit.signatureEntree,
      visit.signatureSortie,
    ]) {
      if (raw == null || raw.isEmpty || raw.startsWith('http') || raw.startsWith('/')) continue;
      if (VisitMedia.isLocal(raw)) continue;
      raws.add(raw);
    }
    if (raws.isEmpty) return const {};

    final total = raws.fold<int>(0, (sum, raw) => sum + raw.length);
    return total > _isolateDecodeThreshold
        ? compute(_decodeBase64Images, raws)
        : _decodeBase64Images(raws);
  }

  static Map<String, Uint8List> _decodeBase64Images(List<String> raws) {
    final out = <String, Uint8List>{};
    for (final raw in raws) {
      if (raw.startsWith('data:image')) {
        try { out[raw] = base64.decode(raw.split(',').last); } catch (_) {}
      } else if (raw.length > 200 && !raw.contains('.')) {
        try {
          final decoded = base64.decode(raw);
          if (decoded.length > 100) out[raw] = decoded;
        } catch (_) {}
      }
    }
    return out;
  }

  Uint8List? _getDecodedImage(String raw) {
    if (VisitMedia.isLocal(raw)) return null;
    if (_decodedImages.containsKey(raw)) return _decodedImages[raw];
    if (_historiqueImages.containsKey(raw)) return _historiqueImages[raw];
    if (raw.startsWith('data:image')) {
      try {
        _decodedImages[raw] = base64.decode(raw.split(',').last);
      } catch (_) {
        _decodedImages[raw] = Uint8List(0);
      }
    } else if (raw.length > 200 && !raw.contains('.')) {
      try {
        final decoded = base64.decode(raw);
        if (decoded.length > 100) { _decodedImages[raw] = decoded; }
      } catch (_) {
        _decodedImages[raw] = Uint8List(0);
      }
    }
    return _decodedImages[raw];
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 64, color: _grey400),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center,
              style: TextStyle(color: _grey600)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadVisit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetail() {
    final v = _visit!;
    final statutColor = _statutColor(v.statut);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statutColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: statutColor.withValues(alpha: 0.15), width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statutColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person, size: 24, color: statutColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.visiteurNomComplet,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(v.visiteur?.telephone ?? '',
                          style: TextStyle(fontSize: 13, color: _grey600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statutColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(v.statut ?? '-',
                      style: TextStyle(fontSize: 12, color: statutColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSection('Photos & Documents', [
            _buildImageRow('Photo du visiteur', v.visiteur?.photo),
            _buildImageRow('Pièce d\'identité (recto)', v.visiteur?.documentRecto),
            _buildImageRow('Pièce d\'identité (verso)', v.visiteur?.documentVerso),
          ]),
          const SizedBox(height: 12),
          _buildSection('Données du visiteur', [
            _buildDetailRow(Icons.person, 'Nom', v.visiteur?.nom ?? '-'),
            _buildDetailRow(Icons.person_outline, 'Prénom', v.visiteur?.prenom ?? '-'),
            _buildDetailRow(Icons.wc, 'Genre', v.visiteur?.genre ?? '-'),
            _buildDetailRow(Icons.email, 'Email', v.visiteur?.email ?? '-'),
            _buildDetailRow(Icons.phone, 'Téléphone', v.visiteur?.telephone ?? '-'),
            _buildDetailRow(Icons.badge, 'N° Pièce', v.visiteur?.numeroPiece ?? '-'),
            _buildDetailRow(Icons.credit_card, 'NIP', v.visiteur?.numeroNip ?? '-'),
            _buildDetailRow(Icons.flag, 'Nationalité', v.visiteur?.nationalite ?? '-'),
            _buildDetailRow(Icons.work, 'Profession', v.visiteur?.profession ?? '-'),
            _buildDetailRow(Icons.home, 'Adresse', v.visiteur?.adresse ?? '-'),
            _buildDetailRow(Icons.credit_card, 'Pièce d\'identité', v.visiteur?.pieceIdentite ?? '-'),
            _buildDetailRow(Icons.cake, 'Date de naissance', v.visiteur?.dateNaissance ?? '-'),
            _buildDetailRow(Icons.location_city, 'Lieu de naissance', v.visiteur?.lieuNaissance ?? '-'),
            _buildDetailRow(Icons.flag_outlined, 'Pays de delivrance', v.visiteur?.paysDelivrance ?? '-'),
            _buildDetailRow(Icons.date_range, 'Date de delivrance', v.visiteur?.dateDelivrance ?? '-'),
          ]),
          const SizedBox(height: 12),
          _buildHistoriqueSection(),
        ],
      ),
    );
  }

  // ── Historique de visite ──

  static const _entetesHistorique = [
    'Date',
    'Heure A.',
    'Heure D.',
    'Type de visite',
    'Personne visitée',
    'Département',
    'Point entrée / Sortie',
    'N° Badge',
    'Signature',
  ];

  static const Map<int, TableColumnWidth> _largeursHistorique = {
    0: FixedColumnWidth(86),
    1: FixedColumnWidth(64),
    2: FixedColumnWidth(64),
    3: FixedColumnWidth(120),
    4: FixedColumnWidth(132),
    5: FixedColumnWidth(120),
    6: FixedColumnWidth(132),
    7: FixedColumnWidth(80),
    8: FixedColumnWidth(96),
  };

  /// Toutes les visites du meme visiteur, en tableau. La signature de sortie
  /// y figure en vignette : c'est la preuve de fin de visite.
  Widget _buildHistoriqueSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Text('Historique de visite',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _grey800)),
                const SizedBox(width: 8),
                if (_historiqueEnCours)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else
                  Text('(${_historique.length})',
                      style: TextStyle(fontSize: 12, color: _grey500)),
              ],
            ),
          ),
          Divider(height: 1, color: _grey100),
          if (_historique.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                  _historiqueEnCours
                      ? 'Chargement de l\'historique...'
                      : 'Aucune autre visite enregistrée pour ce visiteur',
                  style: TextStyle(fontSize: 12, color: _grey500)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Table(
                columnWidths: _largeursHistorique,
                border: TableBorder.all(color: const Color(0xFFCBD5E1), width: 0.7),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFDCE6F1)),
                    children: [
                      for (final entete in _entetesHistorique)
                        _celluleHistorique(entete, entete: true),
                    ],
                  ),
                  for (final v in _historique) _ligneHistorique(v),
                ],
              ),
            ),
        ],
      ),
    );
  }

  TableRow _ligneHistorique(Visit v) {
    final courante = v.id == widget.visiteId;
    return TableRow(
      decoration: courante
          ? BoxDecoration(color: const Color(0xFF1A237E).withValues(alpha: 0.04))
          : null,
      children: [
        _celluleHistorique(_formatDateCourte(v.dateVisite), enGras: courante),
        _celluleHistorique(_formatHeure(v.heureArrivee)),
        _celluleHistorique(_formatHeure(v.heureDepart)),
        _celluleHistorique(v.typeVisite?.nom ?? '-'),
        _celluleHistorique(v.personnelNomComplet.isEmpty ? '-' : v.personnelNomComplet),
        _celluleHistorique(v.personnel?.departement ?? '-'),
        _celluleHistorique(v.porteEntree?.titre ?? '-'),
        _celluleHistorique(v.numeroBadge ?? '-'),
        _celluleSignature(v.signatureSortie),
      ],
    );
  }

  Widget _celluleHistorique(String valeur, {bool entete = false, bool enGras = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(
        valeur,
        textAlign: entete ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          fontSize: 11,
          height: 1.25,
          color: entete ? _grey800 : Colors.black87,
          fontWeight: entete || enGras ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _celluleSignature(String? signature) {
    if (signature == null || signature.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text('-', style: TextStyle(fontSize: 11, color: _grey400)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: GestureDetector(
        onTap: () => _showFullImage(signature, 'Signature de sortie'),
        child: _buildImageWidget(signature,
            width: 84, height: 34, fit: BoxFit.contain),
      ),
    );
  }

  String _formatDateCourte(String? valeur) {
    if (valeur == null || valeur.isEmpty) return '-';
    final d = DateTime.tryParse(valeur);
    if (d == null) return valeur.length >= 10 ? valeur.substring(0, 10) : valeur;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _formatHeure(String? valeur) {
    if (valeur == null || valeur.isEmpty) return '-';
    final d = DateTime.tryParse(valeur);
    if (d != null) {
      return '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    }
    return valeur.length >= 5 ? valeur.substring(0, 5) : valeur;
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _grey800)),
          ),
          Divider(height: 1, color: _grey100),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: _grey400),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 12, color: _grey500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildImageRow(String label, String? imageData) {
    if (imageData == null || imageData.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(Icons.image_not_supported_outlined, size: 15, color: _grey400),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: Text(label, style: TextStyle(fontSize: 12, color: _grey500)),
            ),
            Text('Non disponible', style: TextStyle(fontSize: 12, color: _grey400)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image, size: 15, color: _grey400),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 12, color: _grey500)),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showFullImage(imageData, label),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _buildImageWidget(imageData, width: double.infinity, height: 180),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWidget(String imageData,
      {double? width, double height = 120, BoxFit fit = BoxFit.cover}) {
    // Image restée sur l'appareil : visite saisie hors ligne, pas encore
    // synchronisée. On la lit directement depuis le disque.
    final local = VisitMedia.resolve(imageData);
    if (local != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(local),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stack) => _imageErrorPlaceholder(height),
          cacheHeight: (height * 0.8).round(),
        ),
      );
    }

    final decoded = _getDecodedImage(imageData);
    if (decoded != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          decoded,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stack) => _imageErrorPlaceholder(height),
          cacheHeight: (height * 0.8).round(),
        ),
      );
    }

    String url = imageData;
    if (imageData.startsWith('/')) {
      url = '${ApiConfig.baseUrl}$imageData';
    } else if (!imageData.startsWith('http')) {
      url = '${ApiConfig.baseUrl}/$imageData';
    }

    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: width != null && width.isFinite ? (width * pixelRatio).round() : null,
        memCacheHeight: height.isFinite ? (height * pixelRatio).round() : null,
        placeholder: (_, _) => _imageLoadingPlaceholder(height),
        errorWidget: (_, _, _) => _imageErrorPlaceholder(height),
      ),
    );
  }

  Widget _imageLoadingPlaceholder(double height) {
    return Container(
      width: double.infinity,
      height: height,
      color: _grey100,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _imageErrorPlaceholder(double height) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: _grey100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined, size: 32, color: _grey400),
          const SizedBox(height: 4),
          const Text('Image non chargeable', style: TextStyle(fontSize: 11, color: _grey500)),
        ],
      ),
    );
  }

  void _showFullImage(String imageData, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(title),
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
          ),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: _buildImageWidget(imageData, height: MediaQuery.of(context).size.height * 0.8),
            ),
          ),
        ),
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
        return const Color(0xFF1A237E);
    }
  }
}
