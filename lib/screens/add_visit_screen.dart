import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:sqflite/sqflite.dart';
import '../providers/auth_provider.dart';
import '../providers/visit_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/visit_media.dart';
import '../services/visit_service.dart';
import '../widgets/app_drawer.dart';
import '../database/database_helper.dart';
import '../models/scan_result_data.dart';
import '../constants/colors.dart';

class AddVisitScreen extends StatefulWidget {
  final ScanResultData? scanData;

  const AddVisitScreen({super.key, this.scanData});

  @override
  State<AddVisitScreen> createState() => _AddVisitScreenState();
}

class _AddVisitScreenState extends State<AddVisitScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _numeroPieceCtrl = TextEditingController();
  final _nipCtrl = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _dateNaissanceCtrl = TextEditingController();
  final _lieuNaissanceCtrl = TextEditingController();
  final _dateDelivranceCtrl = TextEditingController();
  final _professionCtrl = TextEditingController();
  final _dateExpirationCtrl = TextEditingController();
  final _motifCtrl = TextEditingController();
  final _observationsCtrl = TextEditingController();
  final _badgeCtrl = TextEditingController();
  final _arriveeCtrl = TextEditingController();
  final _departPrevuCtrl = TextEditingController();
  int _dureeMoyenneVisites = 60;

  int? _selectedTypeVisiteId;
  int? _selectedPorteEntreeId;
  int? _agentPorteEntreeId;
  int? _selectedPersonnelId;
  int? _selectedDepartementId;
  String? _selectedGenre;
  String? _selectedNationalite;
  String? _selectedPays;
  String? _selectedTypePiece;
  bool _isHorsNormes = true;
  Timer? _visitorLookupDebounce;

  List<Map<String, dynamic>> get _filteredPersonnel {
    if (_selectedDepartementId == null) return [];
    return _personnel.where((p) {
      final did = p['departement_id'];
      final didInt = did is int ? did : int.tryParse(did?.toString() ?? '');
      return didInt == _selectedDepartementId;
    }).toList();
  }

  List<Map<String, dynamic>> _typesVisite = [];
  List<Map<String, dynamic>> _portesEntree = [];
  List<Map<String, dynamic>> _personnel = [];
  List<Map<String, dynamic>> _departements = [];
  List<Map<String, dynamic>> _creneaux = [];
  List<String> _nationalites = [];
  List<String> _pays = [];
  List<String> _typesPiece = [];
  bool _loadingDropdowns = true;
  bool _submitting = false;

  String? _photoPath;
  String? _docRectoPath;
  String? _docVersoPath;
  late final SignatureController _signatureController;

  final _service = VisitService();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _signatureController = SignatureController(
      penStrokeWidth: 2.5,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    // Porte d'entree de l'agent connecte : le champ ayant ete retire du
    // formulaire, c'est elle qui rattache la visite, et non la premiere porte
    // de la liste.
    _agentPorteEntreeId = context.read<AuthProvider>().user?.porteEntreeId;
    _initArrivee();
    _fillFromScanData();
    _numeroPieceCtrl.addListener(_scheduleVisitorLookup);
    // Un agent peut identifier le visiteur par son NIP plutôt que par le
    // numéro de pièce : les deux champs déclenchent la recherche.
    _nipCtrl.addListener(_scheduleVisitorLookup);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDropdowns();
      _checkVisitMode();
      _scheduleVisitorLookup();
    });
  }

  void _fillFromScanData() {
    final data = widget.scanData;
    if (data == null) return;
    if (data.nom != null) _nomCtrl.text = data.nom!;
    if (data.prenom != null) _prenomCtrl.text = data.prenom!;
    if (data.dateNaissance != null) _dateNaissanceCtrl.text = data.dateNaissance!;
    if (data.lieuNaissance != null) _lieuNaissanceCtrl.text = data.lieuNaissance!;
    if (data.profession != null) _professionCtrl.text = data.profession!;
    if (data.numeroDocument != null) _numeroPieceCtrl.text = data.numeroDocument!;
    if (data.dateDelivrance != null) _dateDelivranceCtrl.text = data.dateDelivrance!;
    if (data.dateExpiration != null) _dateExpirationCtrl.text = data.dateExpiration!;
    if (data.nip != null) _nipCtrl.text = data.nip!;
    if (data.sexe != null) _selectedGenre = data.sexe;
    if (data.rectoImage != null) _docRectoPath = data.rectoImage!.path;
    if (data.versoImage != null) _docVersoPath = data.versoImage!.path;
    if (data.portrait != null) _photoPath = data.portrait!.path;

    // Stocke les valeurs brutes du scan pour matching approximatif
    // après le chargement des dropdowns.
    _scanNationalite = data.nationalite;
    _scanPays = data.paysDelivrance;
    _scanTypePiece = data.typeDocument;
  }

  String? _scanNationalite;
  String? _scanPays;
  String? _scanTypePiece;

  /// Recherche approximative : ignore la casse et les accents pour trouver
  /// la meilleure correspondance dans une liste de dropdown.
  String? _matchDropdownValue(List<String> items, String? scanValue) {
    if (scanValue == null || scanValue.isEmpty || items.isEmpty) return null;

    // 1) Correspondance exacte (insensible à la casse)
    final exact = items.where((i) => i.toLowerCase() == scanValue.toLowerCase());
    if (exact.length == 1) return exact.first;

    // 2) Correspondance en ignorant les accents
    String normalize(String s) {
      const accentMap = {
        'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
        'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
        'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'į': 'i', 'ı': 'i',
        'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ō': 'o', 'ő': 'o', 'ø': 'o', 'œ': 'oe',
        'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
        'ç': 'c', 'ć': 'c', 'č': 'c',
        'ñ': 'n', 'ń': 'n', 'ň': 'n',
        'š': 's', 'ś': 's', 'ź': 'z', 'ž': 'z', 'ż': 'z',
        'ÿ': 'y', 'ý': 'y', 'ŷ': 'y',
      };
      var result = s.toLowerCase();
      accentMap.forEach((accent, clean) {
        result = result.replaceAll(accent, clean);
      });
      return result;
    }
    final normScan = normalize(scanValue);
    final normMatch = items.where((i) => normalize(i) == normScan);
    if (normMatch.length == 1) return normMatch.first;

    // 3) contains (scanValue inclus dans un item)
    final contains = items.where((i) => i.toLowerCase().contains(scanValue.toLowerCase()));
    if (contains.length == 1) return contains.first;

    // 4) contains normalisé
    final containsNorm = items.where((i) => normalize(i).contains(normScan));
    if (containsNorm.length == 1) return containsNorm.first;

    // 5) startsWith normalisé
    final startsNorm = items.where((i) => normalize(i).startsWith(normScan));
    if (startsNorm.length == 1) return startsNorm.first;

    return null;
  }

  /// Applique la valeur issue du scan sans jamais ecraser un choix deja fait
  /// par l'utilisateur. Le formulaire charge ses listes en deux passes, cache
  /// puis reseau : sans cette garde, une selection faite pendant la seconde qui
  /// suit l'ouverture etait remplacee par la valeur du scan a l'arrivee de la
  /// reponse reseau. Un choix devenu absent de la liste rafraichie est en
  /// revanche abandonne, car le menu ne saurait plus l'afficher.
  String? _keepOrMatch(String? current, List<String> items, String? scanValue) {
    if (current != null && items.contains(current)) return current;
    return _matchDropdownValue(items, scanValue);
  }

  /// Libelles admis pour chaque nature de piece renvoyee par le scan. Le
  /// serveur nomme ses types comme il l'entend (« Carte nationale d'identite »,
  /// « Permis de conduire »…) : sans cette passerelle, le rapprochement
  /// echouait et le formulaire retombait sur « AUTRE ».
  static const Map<String, List<String>> _synonymesTypePiece = {
    'CNI': [
      'CNI', 'CARTE NATIONALE', 'CARTE D IDENTITE', 'CARTE IDENTITE',
      'IDENTITE', 'ID CARD', 'IDENTITY',
    ],
    'PASSEPORT': ['PASSEPORT', 'PASSPORT'],
    'PERMIS': ['PERMIS', 'CONDUIRE', 'DRIVING', 'LICENCE', 'LICENSE'],
    'VISA': ['VISA'],
    'ATTESTATION': ['ATTESTATION'],
    'CONSULAIRE': ['CONSULAIRE', 'CONSULAR'],
  };

  /// Rapprochement du type de piece scanne avec la liste du serveur : la
  /// recherche generique d'abord, les synonymes ensuite.
  String? _keepOrMatchTypePiece(
      String? current, List<String> items, String? scanValue) {
    final direct = _keepOrMatch(current, items, scanValue);
    if (direct != null) return direct;
    if (scanValue == null || scanValue.isEmpty || items.isEmpty) return null;

    String sansAccents(String v) => v
        .toUpperCase()
        .replaceAll(RegExp(r'[ÀÁÂÃÄÅ]'), 'A')
        .replaceAll(RegExp(r'[ÈÉÊË]'), 'E')
        .replaceAll(RegExp(r'[ÌÍÎÏ]'), 'I')
        .replaceAll(RegExp(r'[ÒÓÔÕÖ]'), 'O')
        .replaceAll(RegExp(r'[ÙÚÛÜ]'), 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp(r"[^A-Z0-9]+"), ' ')
        .trim();

    final cle = sansAccents(scanValue);
    final motsCles = _synonymesTypePiece[cle];
    if (motsCles == null) return null;
    for (final mot in motsCles) {
      for (final item in items) {
        if (sansAccents(item).contains(mot)) return item;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _visitorLookupDebounce?.cancel();
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    _telephoneCtrl.dispose();
    _emailCtrl.dispose();
    _numeroPieceCtrl.dispose();
    _nipCtrl.dispose();
    _adresseCtrl.dispose();
    _dateNaissanceCtrl.dispose();
    _lieuNaissanceCtrl.dispose();
    _dateDelivranceCtrl.dispose();
    _professionCtrl.dispose();
    _dateExpirationCtrl.dispose();
    _motifCtrl.dispose();
    _observationsCtrl.dispose();
    _badgeCtrl.dispose();
    _arriveeCtrl.dispose();
    _departPrevuCtrl.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  String? _getToken() {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return null;
    return auth.accessToken;
  }

  Future<void> _loadDropdowns() async {
    final t = _getToken();
    if (t == null) return;

    // 1. Charger depuis le cache SQLite d'abord
    await _loadDropdownsFromCache();
    if (mounted && (_typesVisite.isNotEmpty || _portesEntree.isNotEmpty)) {
      setState(() {
        _loadingDropdowns = false;
        // Matching approximatif des valeurs du scan dans les dropdowns
        _selectedNationalite = _keepOrMatch(_selectedNationalite, _nationalites, _scanNationalite);
        _selectedPays = _keepOrMatch(_selectedPays, _pays, _scanPays);
        _selectedTypePiece =
            _keepOrMatchTypePiece(_selectedTypePiece, _typesPiece, _scanTypePiece);
        _applyDefaultPorteEntree();
      });
    }

    if (!mounted) return;
    // 2. Si connecté, recharger silencieusement depuis le réseau
    final isConnected = context.read<ConnectivityProvider>().isConnected;
    if (isConnected) {
      try {
        final results = await Future.wait([
          _service.getTypesVisite(t),
          _service.getPortesEntree(t),
          _service.getPersonnel(t),
          _service.getDepartements(t),
          _service.getReferences(t),
          _service.getCreneaux(t),
        ]);
        if (mounted) {
          setState(() {
            _typesVisite = results[0] as List<Map<String, dynamic>>;
            _portesEntree = results[1] as List<Map<String, dynamic>>;
            _personnel = results[2] as List<Map<String, dynamic>>;
            _departements = results[3] as List<Map<String, dynamic>>;
            final refs = results[4] as Map<String, dynamic>;
            _creneaux = results[5] as List<Map<String, dynamic>>;
            _nationalites = (refs['nationalites'] as List?)?.cast<String>() ?? [];
            _pays = (refs['pays'] as List?)?.cast<String>() ?? [];
            _typesPiece = (refs['types_piece'] as List?)?.cast<String>() ?? [];
            _dureeMoyenneVisites = refs['duree_moyenne_visites'] as int? ?? 60;

            // Recalculer les valeurs du scan correspondantes
            _selectedNationalite = _keepOrMatch(_selectedNationalite, _nationalites, _scanNationalite);
            _selectedPays = _keepOrMatch(_selectedPays, _pays, _scanPays);
            _selectedTypePiece = _keepOrMatchTypePiece(
                _selectedTypePiece, _typesPiece, _scanTypePiece);
            debugPrint('[AddVisit] Type de piece scanne=$_scanTypePiece '
                'retenu=$_selectedTypePiece parmi $_typesPiece');
            _applyDefaultPorteEntree();

            _loadingDropdowns = false;
          });
          await _saveDropdownsToCache();
        }
      } catch (e) {
        debugPrint('[AddVisitScreen] Échec de la mise à jour silencieuse des dropdowns: $e');
        if (mounted && _typesVisite.isEmpty && _portesEntree.isEmpty) {
          // Si le cache était vide et que le réseau échoue
          setState(() => _loadingDropdowns = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur chargement: $e'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } else {
      if (mounted) {
        setState(() => _loadingDropdowns = false);
        if (_typesVisite.isEmpty && _portesEntree.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Aucune connexion Internet et aucune donnée en cache'),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
  }

  Future<void> _saveDropdownsToCache() async {
    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      final now = DateTime.now().toIso8601String();
      
      final dataMap = {
        'types_visite': jsonEncode(_typesVisite),
        'portes_entree': jsonEncode(_portesEntree),
        'personnel': jsonEncode(_personnel),
        'departements': jsonEncode(_departements),
        'references': jsonEncode({
          'nationalites': _nationalites,
          'pays': _pays,
          'types_piece': _typesPiece,
        }),
        'creneaux': jsonEncode(_creneaux),
      };

      await db.transaction((txn) async {
        for (final entry in dataMap.entries) {
          await txn.insert(
            'dropdown_cache',
            {
              'cache_key': entry.key,
              'data_json': entry.value,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (e) {
      debugPrint('Error saving dropdowns cache: $e');
    }
  }

  Future<void> _loadDropdownsFromCache() async {
    final db = DatabaseHelper();
    try {
      final tv = await db.getFirst('dropdown_cache',
          where: 'cache_key = ?', whereArgs: ['types_visite']);
      if (tv != null) {
        _typesVisite = (jsonDecode(tv['data_json'] as String) as List)
            .cast<Map<String, dynamic>>();
      }
      final pe = await db.getFirst('dropdown_cache',
          where: 'cache_key = ?', whereArgs: ['portes_entree']);
      if (pe != null) {
        _portesEntree = (jsonDecode(pe['data_json'] as String) as List)
            .cast<Map<String, dynamic>>();
      }
      final p = await db.getFirst('dropdown_cache',
          where: 'cache_key = ?', whereArgs: ['personnel']);
      if (p != null) {
        _personnel = (jsonDecode(p['data_json'] as String) as List)
            .cast<Map<String, dynamic>>();
      }
      final d = await db.getFirst('dropdown_cache',
          where: 'cache_key = ?', whereArgs: ['departements']);
      if (d != null) {
        _departements = (jsonDecode(d['data_json'] as String) as List)
            .cast<Map<String, dynamic>>();
      }
      final refs = await db.getFirst('dropdown_cache',
          where: 'cache_key = ?', whereArgs: ['references']);
      if (refs != null) {
        final data = jsonDecode(refs['data_json'] as String) as Map<String, dynamic>;
          _nationalites = (data['nationalites'] as List?)?.cast<String>() ?? [];
          _pays = (data['pays'] as List?)?.cast<String>() ?? [];
          _typesPiece = (data['types_piece'] as List?)?.cast<String>() ?? [];
          _dureeMoyenneVisites = data['duree_moyenne_visites'] as int? ?? 60;
      }
      final cren = await db.getFirst('dropdown_cache',
          where: 'cache_key = ?', whereArgs: ['creneaux']);
      if (cren != null) {
        _creneaux = (jsonDecode(cren['data_json'] as String) as List)
            .cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error loading dropdowns from cache: $e');
    }
  }

  Future<void> _pickImage(String type) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Caméra'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(source: source, maxWidth: 800, imageQuality: 85);
    if (picked != null) {
      setState(() {
        switch (type) {
          case 'photo': _photoPath = picked.path; break;
          case 'recto': _docRectoPath = picked.path; break;
          case 'verso': _docVersoPath = picked.path; break;
        }
      });
    }
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      ctrl.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  void _initArrivee() {
    final now = DateTime.now();
    _arriveeCtrl.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    _updateDepartPrevue();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    _arriveeCtrl.text = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    _updateDepartPrevue();
    _checkVisitMode();
  }

  void _updateDepartPrevue() {
    if (_arriveeCtrl.text.isEmpty || _dureeMoyenneVisites <= 0) return;
    final parts = _arriveeCtrl.text.split(' ');
    if (parts.length != 2) return;
    final dateParts = parts[0].split('-');
    final timeParts = parts[1].split(':');
    if (dateParts.length != 3 || timeParts.length != 2) return;
    final dt = DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
    final dep = dt.add(Duration(minutes: _dureeMoyenneVisites));
    _departPrevuCtrl.text = '${dep.year}-${dep.month.toString().padLeft(2, '0')}-${dep.day.toString().padLeft(2, '0')} ${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _checkVisitMode() async {
    final parts = _arriveeCtrl.text.split(' ');
    if (parts.length != 2) return;
    final t = _getToken();
    if (t == null) return;
    try {
      final mode = await _service.checkMode(t, date: parts[0], heure: parts[1]);
      if (!mounted) return;
      setState(() =>
          _isHorsNormes = _horsCreneau || mode['mode'] == 'HORS_NORMES');
    } catch (e) {
      debugPrint('[AddVisitScreen] check-mode indisponible (mode inconnu): $e');
    }
  }

  void _scheduleVisitorLookup() {
    _visitorLookupDebounce?.cancel();
    _visitorLookupDebounce = Timer(const Duration(milliseconds: 400), _lookupVisitor);
  }

  Future<void> _lookupVisitor() async {
    final piece = _numeroPieceCtrl.text.trim();
    final number = piece.isNotEmpty ? piece : _nipCtrl.text.trim();
    if (number.isEmpty) return;

    final visitProvider = context.read<VisitProvider>();
    final connected = context.read<ConnectivityProvider>().isConnected;
    final t = _getToken();

    if (connected && t != null) {
      try {
        final results = await _service.searchVisiteurs(t, query: number);
        if (!mounted) return;
        if (results.isNotEmpty) {
          Map<String, dynamic> best = results.first;
          final upper = number.toUpperCase();
          for (final v in results) {
            final np = (v['numero_piece'] as String?)?.toUpperCase();
            final nip = (v['numero_nip'] as String?)?.toUpperCase();
            if (np == upper || nip == upper) {
              best = v;
              break;
            }
          }
          _applyVisiteurConnu(best);
          return;
        }
      } catch (e) {
        debugPrint('[AddVisitScreen] Recherche visiteur indisponible: $e');
      }
    }

    // Repli sur le répertoire local : hors ligne, ou serveur injoignable,
    // l'appareil connaît déjà les visiteurs enregistrés ici.
    final local = await visitProvider.findVisiteurLocal(number);
    if (local != null && mounted) _applyVisiteurConnu(local);
  }

  /// Ne remplit que les champs encore vides : une saisie de l'agent n'est
  /// jamais écrasée par une valeur retrouvée.
  void _applyVisiteurConnu(Map<String, dynamic> data) {
    setState(() {
      final phone = data['telephone'] as String?;
      if (phone != null && phone.trim().isNotEmpty && _telephoneCtrl.text.trim().isEmpty) {
        _telephoneCtrl.text = phone;
      }
      final nat = data['nationalite'] as String?;
      if (nat != null && nat.trim().isNotEmpty && _selectedNationalite == null) {
        final matched = _matchDropdownValue(_nationalites, nat);
        if (matched != null) _selectedNationalite = matched;
      }
    });
  }

  int? _asId(Object? raw) => raw is int ? raw : int.tryParse(raw?.toString() ?? '');

  /// Liste proposee pour « Personnel » : restreinte au departement choisi, ou
  /// l'effectif complet tant qu'aucun departement ne l'est. C'est ce qui rend
  /// possibles les deux sens de saisie demandes — partir du departement pour
  /// filtrer les personnes, ou partir d'une personne et laisser son
  /// departement se deduire.
  List<Map<String, dynamic>> get _personnelChoices =>
      _selectedDepartementId == null ? _personnel : _filteredPersonnel;

  void _onDepartementChanged(int? v) {
    setState(() {
      _selectedDepartementId = v;
      // Une personne deja choisie qui ne releve pas du nouveau departement est
      // retiree plutot que laissee dans un etat incoherent.
      if (_selectedPersonnelId != null &&
          !_personnelChoices.any((p) => _asId(p['id']) == _selectedPersonnelId)) {
        _selectedPersonnelId = null;
      }
    });
  }

  void _onPersonnelChanged(int? v) {
    setState(() {
      _selectedPersonnelId = v;
      if (v == null) return;
      final person = _personnel.firstWhere(
        (p) => _asId(p['id']) == v,
        orElse: () => <String, dynamic>{},
      );
      final depId = _asId(person['departement_id']);
      if (depId != null) _selectedDepartementId = depId;
    });
  }

  /// Le champ « porte d'entree » a ete retire du formulaire : la visite est
  /// rattachee a la porte affectee a l'agent connecte. Le repli sur la
  /// premiere porte de la liste n'a lieu que si son profil n'en declare aucune.
  void _applyDefaultPorteEntree() {
    if (_selectedPorteEntreeId != null || _portesEntree.isEmpty) return;

    final agentPorte = _agentPorteEntreeId;
    if (agentPorte != null && _portesEntree.any((p) => _asId(p['id']) == agentPorte)) {
      _selectedPorteEntreeId = agentPorte;
      return;
    }
    _selectedPorteEntreeId = _asId(_portesEntree.first['id']);
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Ce champ est obligatoire' : null;
  String? _requiredSelection(String? v) => (v == null || v.isEmpty) ? 'Veuillez selectionner une valeur' : null;
  String? _requiredId(int? v) => v == null ? 'Veuillez selectionner une valeur' : null;

  /// Nom et prenom : lettres, accents, tiret, apostrophe et espace.
  static final RegExp _lettresSeules = RegExp(r"^[A-Za-zÀ-ÿ' -]+$");
  static final RegExp _formatEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$');
  static final RegExp _formatReference = RegExp(r'^[A-Za-z0-9./-]+$');

  String? _requiredNom(String? v) {
    final erreur = _required(v);
    if (erreur != null) return erreur;
    if (!_lettresSeules.hasMatch(v!.trim())) {
      return 'Chiffres et symboles ne sont pas admis';
    }
    return null;
  }

  /// Le telephone n'accepte que des chiffres — la saisie elle-meme filtre les
  /// lettres — et il en faut au moins huit pour un numero exploitable.
  String? _requiredTelephone(String? v) {
    final erreur = _required(v);
    if (erreur != null) return erreur;
    final chiffres = v!.replaceAll(RegExp(r'[^0-9]'), '');
    if (chiffres.length < 8) return 'Numero incomplet (8 chiffres minimum)';
    if (chiffres.length > 15) return 'Numero trop long';
    return null;
  }

  /// L'email reste facultatif, mais s'il est saisi il doit etre valide : une
  /// adresse fautive part au serveur et casse la fiche du visiteur.
  String? _emailFacultatif(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return _formatEmail.hasMatch(v.trim()) ? null : 'Adresse email invalide';
  }

  /// Numero de piece : lettres, chiffres, tiret, point et barre.
  String? _requiredReference(String? v) {
    final erreur = _required(v);
    if (erreur != null) return erreur;
    if (!_formatReference.hasMatch(v!.trim())) return 'Caracteres non admis';
    return null;
  }
  String? _requiredDateTime(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ce champ est obligatoire';
    if (v.length < 16) return 'Format de date invalide';
    return null;
  }

  static const List<String> _joursSemaine = ['LUNDI','MARDI','MERCREDI','JEUDI','VENDREDI','SAMEDI','DIMANCHE'];

  /// Seule une date d'arrivée illisible bloque : être hors créneau n'est
  /// plus un motif de refus (la visite passe alors en mode hors normes).
  String? _validateArrivee() {
    final parts = _arriveeCtrl.text.split(' ');
    if (parts.length != 2) return 'Format de date d\'arrivee invalide';
    final dateParts = parts[0].split('-');
    final timeParts = parts[1].split(':');
    if (dateParts.length != 3 || timeParts.length < 2) return 'Format de date d\'arrivee invalide';
    return null;
  }

  /// Vrai quand l'heure d'arrivée ne tombe dans aucun créneau actif. Sans
  /// créneaux connus (jamais synchronisés), on considère être dans les normes.
  bool get _horsCreneau {
    if (_creneaux.isEmpty) return false;
    final parts = _arriveeCtrl.text.split(' ');
    if (parts.length != 2) return false;
    final dateParts = parts[0].split('-');
    final timeParts = parts[1].split(':');
    if (dateParts.length != 3 || timeParts.length < 2) return false;
    final dt = DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
    final jour = _joursSemaine[dt.weekday - 1];
    final heureArrivee = '${timeParts[0]}:${timeParts[1]}';
    return !_creneaux.any((c) =>
      c['jour_semaine'] == jour &&
      c['statut'] == 'ACTIF' &&
      c['heure_debut'] != null &&
      c['heure_fin'] != null &&
      (c['heure_debut'] as String).compareTo(heureArrivee) <= 0 &&
      (c['heure_fin'] as String).compareTo(heureArrivee) >= 0,
    );
  }

  /// Libellés joints à la saisie (clés privées, jamais envoyées à l'API) :
  /// sans eux, la fiche d'une visite hors ligne n'afficherait ni la porte
  /// d'entrée, ni le personnel, ni le type de visite.
  void _ajouterLibelles(Map<String, dynamic> body) {
    Map<String, dynamic> trouve(List<Map<String, dynamic>> items, int? id) =>
        items.firstWhere((e) => _asId(e['id']) == id,
            orElse: () => const <String, dynamic>{});

    final tv = trouve(_typesVisite, _selectedTypeVisiteId);
    if (tv['nom'] != null) body['_type_visite_nom'] = tv['nom'];
    if (tv['description'] != null) {
      body['_type_visite_description'] = tv['description'];
    }

    final pe = trouve(_portesEntree, _selectedPorteEntreeId);
    if (pe['titre'] != null) body['_porte_entree_titre'] = pe['titre'];
    if (pe['emplacement'] != null) {
      body['_porte_entree_emplacement'] = pe['emplacement'];
    }

    final p = trouve(_personnel, _selectedPersonnelId);
    if (p['nom'] != null) body['_personnel_nom'] = p['nom'];
    if (p['prenom'] != null) body['_personnel_prenom'] = p['prenom'];
    if (p['fonction'] != null) body['_personnel_fonction'] = p['fonction'];
    final dep = p['departement_nom'] ?? p['departement'];
    if (dep is String) body['_personnel_departement'] = dep;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final arriveeError = _validateArrivee();
    if (arriveeError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(arriveeError),
        backgroundColor: Colors.red,
      ));
      return;
    }

    // Hors créneau, l'enregistrement passe quand même — mais le personnel à
    // visiter devient obligatoire.
    if (_horsCreneau || _isHorsNormes) {
      if (!_isHorsNormes) setState(() => _isHorsNormes = true);
      if (_selectedPersonnelId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Visite hors créneau : le personnel à visiter est obligatoire.'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

    final t = _getToken();
    if (t == null) return;

    setState(() => _submitting = true);
    try {
      final provider = context.read<VisitProvider>();
      final arriveeParts = _arriveeCtrl.text.split(' ');
      final dateVisite = arriveeParts[0];
      final heureArrivee = arriveeParts.length > 1 ? arriveeParts[1] : '00:00';

      final body = <String, dynamic>{
        'statut': 'EN_COURS',
        'date_visite': dateVisite,
        'heure_arrivee': heureArrivee,
        'motif': _motifCtrl.text,
        'observations': _observationsCtrl.text,
        'numero_badge': _badgeCtrl.text,
        'v_nom': _nomCtrl.text,
        'v_prenom': _prenomCtrl.text,
        'v_telephone': _telephoneCtrl.text,
        'v_email': _emailCtrl.text,
        'v_numero_piece': _numeroPieceCtrl.text,
        'v_nip': _nipCtrl.text,
        'v_adresse': _adresseCtrl.text,
        'v_date_naissance': _dateNaissanceCtrl.text,
        'v_lieu_naissance': _lieuNaissanceCtrl.text,
        'v_profession': _professionCtrl.text,
        'v_date_delivrance': _dateDelivranceCtrl.text,
        'date_expiration': _dateExpirationCtrl.text,
      };

      if (_departPrevuCtrl.text.isNotEmpty) {
        final depParts = _departPrevuCtrl.text.split(' ');
        body['date_depart_prevue'] = depParts[0];
        body['heure_depart_prevue'] = depParts.length > 1 ? depParts[1] : '00:00';
      }
      if (_selectedGenre != null) { body['v_genre'] = _selectedGenre; body['genre'] = _selectedGenre; }
      if (_selectedTypeVisiteId != null) body['type_visite_id'] = _selectedTypeVisiteId;
      if (_selectedPorteEntreeId != null) body['porte_entree_id'] = _selectedPorteEntreeId;
      if (_selectedPersonnelId != null) body['personnel_id'] = _selectedPersonnelId;
      if (_selectedDepartementId != null) body['departement_id'] = _selectedDepartementId;
      if (_selectedNationalite != null) body['v_nationalite'] = _selectedNationalite;
      if (_selectedPays != null) body['v_pays_delivrance'] = _selectedPays;
      if (_selectedTypePiece != null) body['v_piece_identite'] = _selectedTypePiece;
      _ajouterLibelles(body);

      // Les images sont recopiées dans le dossier persistant ; seule leur
      // référence part en base. L'encodage base64 n'aura lieu qu'à l'envoi.
      final images = await Future.wait([
        VisitMedia.persist(_photoPath, 'photo'),
        VisitMedia.persist(_docRectoPath, 'recto'),
        VisitMedia.persist(_docVersoPath, 'verso'),
      ]);
      if (images[0] != null) body['photo_path'] = images[0];
      if (images[1] != null) body['document_recto_path'] = images[1];
      if (images[2] != null) body['document_verso_path'] = images[2];

      await provider.createVisite(t, body);

      // Les originaux (cache du scanner ou du selecteur d'images) ont ete
      // recopies dans le dossier persistant : ils ne servent plus a rien.
      for (final chemin in [_photoPath, _docRectoPath, _docVersoPath]) {
        if (chemin != null && !chemin.startsWith(VisitMedia.scheme)) {
          File(chemin).delete().catchError((_) => File(chemin));
        }
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/visit-success');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter une visite'),
        backgroundColor: const Color(0xFFFFFFFF),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_rounded, color: Color(0xFF1270B8)),
            onPressed: () => Navigator.pushNamed(context, '/profile'),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: _loadingDropdowns
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Photos & Documents'),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _buildImagePicker('Photo', _photoPath, 'photo')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildImagePicker('Recto', _docRectoPath, 'recto')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildImagePicker('Verso', _docVersoPath, 'verso')),
                    ]),
                    const SizedBox(height: 20),

                    _buildSectionTitle('Informations du visiteur'),
                    const SizedBox(height: 8),
                    _buildCard([
                      _buildField('Nom *', _nomCtrl,
                          icon: Icons.person,
                          validator: _requiredNom,
                          formatters: [FilteringTextInputFormatter.deny(RegExp(r'[0-9]'))]),
                      const SizedBox(height: 12),
                      _buildField('Prénom *', _prenomCtrl,
                          icon: Icons.person_outline,
                          validator: _requiredNom,
                          formatters: [FilteringTextInputFormatter.deny(RegExp(r'[0-9]'))]),
                      const SizedBox(height: 12),
                      _buildDropdownSimple('Genre *', ['HOMME', 'FEMME'], _selectedGenre, (v) => setState(() => _selectedGenre = v), validator: _requiredSelection),
                      const SizedBox(height: 12),
                      _buildDropdownSearch('Pays de delivrance', _pays, _selectedPays, (v) => setState(() => _selectedPays = v)),
                      const SizedBox(height: 12),
                      _buildDropdownSearch('Type de pièce *', _typesPiece, _selectedTypePiece,
                          (v) => setState(() => _selectedTypePiece = v),
                          validator:
                              _typesPiece.isEmpty ? null : _requiredSelection),
                      const SizedBox(height: 12),
                      _buildField('Profession', _professionCtrl, icon: Icons.work),
                      const SizedBox(height: 12),
                      _buildField('N° Pièce *', _numeroPieceCtrl,
                          icon: Icons.badge,
                          validator: _requiredReference,
                          formatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))]),
                      const SizedBox(height: 12),
                      _buildField('NIP', _nipCtrl, icon: Icons.credit_card),
                      const SizedBox(height: 12),
                      _buildField('Date naissance', _dateNaissanceCtrl, icon: Icons.cake, isDate: true),
                      const SizedBox(height: 12),
                      _buildField('Lieu naissance', _lieuNaissanceCtrl, icon: Icons.location_city),
                      const SizedBox(height: 12),
                      _buildField('Date delivrance', _dateDelivranceCtrl, icon: Icons.date_range, isDate: true),
                      const SizedBox(height: 12),
                      _buildField('Date d\'expiration', _dateExpirationCtrl, icon: Icons.event, isDate: true),
                      const SizedBox(height: 12),
                      _buildDropdownSearch('Nationalité *', _nationalites, _selectedNationalite,
                          (v) => setState(() => _selectedNationalite = v),
                          validator:
                              _nationalites.isEmpty ? null : _requiredSelection),
                      const SizedBox(height: 12),
                      _buildField('Adresse', _adresseCtrl, icon: Icons.home),
                      const SizedBox(height: 12),
                      _buildField('Téléphone *', _telephoneCtrl,
                          icon: Icons.phone,
                          validator: _requiredTelephone,
                          keyboardType: TextInputType.phone,
                          formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]'))]),
                      const SizedBox(height: 12),
                      _buildField('Email', _emailCtrl,
                          icon: Icons.email,
                          validator: _emailFacultatif,
                          keyboardType: TextInputType.emailAddress,
                          formatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))]),
                    ]),
                    const SizedBox(height: 20),

                    _buildSectionTitle('Détails de la visite'),
                    const SizedBox(height: 8),
                    _buildCard([
                      _buildDropdown('Type de visite *', _typesVisite,
                          _selectedTypeVisiteId, 'nom',
                          (v) => setState(() => _selectedTypeVisiteId = v),
                          validator: _typesVisite.isEmpty ? null : _requiredId),
                      const SizedBox(height: 12),
                      // Le departement est demande dans tous les cas : seule la
                      // personne a visiter depend du creneau.
                      _buildDropdown('Département *', _departements,
                          _selectedDepartementId, 'nom', _onDepartementChanged,
                          validator: _departements.isEmpty ? null : _requiredId),
                      if (_isHorsNormes) ...[
                        const SizedBox(height: 12),
                        _buildDropdown(
                          _selectedDepartementId == null
                              ? 'Personnel * (tous départements)'
                              : 'Personnel *',
                          _personnelChoices,
                          _selectedPersonnelId,
                          'nom',
                          _onPersonnelChanged,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildField('Badge', _badgeCtrl, icon: Icons.badge),
                      const SizedBox(height: 12),
                      _buildField('Motif', _motifCtrl, icon: Icons.flag, maxLines: 2),
                      const SizedBox(height: 12),
                      _buildField('Observations', _observationsCtrl, icon: Icons.note, maxLines: 2),
                    ]),
                    const SizedBox(height: 16),

                    _buildSectionTitle('Horaires'),
                    const SizedBox(height: 8),
                    _buildCard([
                      _buildDateTimeField('Date et heure d\'arrivée *', _arriveeCtrl, validator: _requiredDateTime),
                      const SizedBox(height: 12),
                      _buildDateTimeField('Date et heure de départ prévu', _departPrevuCtrl, readOnly: true),
                    ]),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.add_circle_outline, size: 22),
                        label: Text(_submitting ? 'Création...' : 'Créer la visite',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.ikaBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(children: [
      Container(width: 4, height: 20, decoration: BoxDecoration(
        color: const Color(0xFF1A237E), borderRadius: BorderRadius.circular(2),
      )),
      const SizedBox(width: 10),
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildImagePicker(String label, String? path, String type) {
    final hasImage = path != null;
    return GestureDetector(
      onTap: () => _pickImage(type),
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: hasImage ? Colors.green.withValues(alpha: 0.05) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasImage ? Colors.green.withValues(alpha: 0.3) : Colors.grey.shade300, width: 1.5,
          ),
        ),
        child: hasImage
            ? Stack(alignment: Alignment.center, children: [
                ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(path), width: double.infinity, height: double.infinity, fit: BoxFit.cover)),
                Positioned(top: 4, right: 4, child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.edit, size: 14, color: Colors.white),
                )),
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_a_photo_outlined, size: 24, color: Colors.grey.shade400),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl,
      {IconData? icon,
      int maxLines = 1,
      bool isDate = false,
      bool readOnly = false,
      String? Function(String?)? validator,
      TextInputType? keyboardType,
      List<TextInputFormatter>? formatters}) {
    final ro = isDate || readOnly;
    return TextFormField(
      controller: ctrl, maxLines: maxLines, readOnly: ro, onTap: isDate ? () => _pickDate(ctrl) : null,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      style: const TextStyle(fontSize: 14.5, color: AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        prefixIcon: icon != null ? Icon(icon, color: AppColors.textMuted, size: 20) : null,
        suffixIcon: isDate ? const Icon(Icons.calendar_today, color: AppColors.textMuted, size: 18) : null,
        filled: true,
        fillColor: AppColors.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.ikaBlue, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.ikaRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.ikaRed, width: 1.6),
        ),
      ),
    );
  }

  Widget _buildDateTimeField(String label, TextEditingController ctrl, {bool readOnly = false, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl, readOnly: true, onTap: readOnly ? null : _pickDateTime,
      validator: validator,
      style: const TextStyle(fontSize: 14.5, color: AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        prefixIcon: const Icon(Icons.calendar_today, color: AppColors.textMuted, size: 20),
        filled: true,
        fillColor: AppColors.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.ikaBlue, width: 1.6),
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, List<Map<String, dynamic>> items,
      int? selectedId, String fieldKey, ValueChanged<int?> onChanged,
      {String? Function(int?)? validator}) {
    final hasSelected = selectedId != null && items.any((item) => item['id'] == selectedId);
    final effectiveValue = hasSelected ? selectedId : null;

    return DropdownButtonFormField<int>(
      initialValue: effectiveValue, isExpanded: true,
      validator: validator,
      style: const TextStyle(fontSize: 14.5, color: AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.ikaBlue, width: 1.6),
        ),
      ),
      items: items.map((item) {
        final id = item['id'] as int;
        final name = item[fieldKey] as String? ?? '-';
        return DropdownMenuItem(value: id, child: Text(name, style: const TextStyle(fontSize: 13)));
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownSimple(String label, List<String> items, String? selected, ValueChanged<String?> onChanged, {String? Function(String?)? validator}) {
    return DropdownButtonFormField<String>(
      initialValue: selected, isExpanded: true,
      validator: validator,
      style: const TextStyle(fontSize: 14.5, color: AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.ikaBlue, width: 1.6),
        ),
      ),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(fontSize: 13)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownSearch(String label, List<String> items, String? selected, ValueChanged<String?> onChanged, {String? Function(String?)? validator}) {
    return DropdownButtonFormField<String>(
      initialValue: selected, isExpanded: true,
      validator: validator,
      style: const TextStyle(fontSize: 14.5, color: AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.ikaBlue, width: 1.6),
        ),
      ),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(fontSize: 13)))).toList(),
      onChanged: onChanged,
    );
  }
}
