import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import '../constants/colors.dart';
import '../providers/auth_provider.dart';
import '../providers/visit_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/visit_service.dart';
import '../models/visit.dart';
import '../database/database_helper.dart';

class EditVisitScreen extends StatefulWidget {
  final int visiteId;

  const EditVisitScreen({super.key, required this.visiteId});

  @override
  State<EditVisitScreen> createState() => _EditVisitScreenState();
}

class _EditVisitScreenState extends State<EditVisitScreen> {
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

  int? _selectedTypeVisiteId;
  int? _selectedPorteEntreeId;
  int? _selectedPersonnelId;
  int? _selectedDepartementId;
  String? _selectedGenre;
  String? _selectedNationalite;
  String? _selectedPays;
  String? _selectedTypePiece;

  List<Map<String, dynamic>> _typesVisite = [];
  List<Map<String, dynamic>> _portesEntree = [];
  List<Map<String, dynamic>> _personnel = [];
  List<Map<String, dynamic>> _departements = [];
  List<String> _nationalites = [];
  List<String> _pays = [];
  List<String> _typesPiece = [];
  bool _loading = true;
  bool _submitting = false;

  final _service = VisitService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
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
    super.dispose();
  }

  String? _getToken() {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return null;
    return auth.accessToken;
  }

  Future<void> _loadData() async {
    final t = _getToken();
    if (t == null) return;

    // 1. Charger d'abord les dropdowns depuis le cache local
    await _loadDropdownsFromCache();

    if (!mounted) return;
    // 2. Charger les détails de la visite (getVisitDetail charge depuis le cache en premier)
    final provider = context.read<VisitProvider>();
    final initialVisit = await provider.getVisitDetail(t, widget.visiteId);
    
    if (mounted) {
      if (initialVisit != null) {
        _fillFromVisit(initialVisit);
      }
      // Si on a des dropdowns et la visite (même en cache), on affiche l'interface
      if ((_typesVisite.isNotEmpty || _portesEntree.isNotEmpty) && initialVisit != null) {
        setState(() => _loading = false);
      }
    }

    if (!mounted) return;
    // 3. Charger silencieusement depuis le réseau si connecté
    final isConnected = context.read<ConnectivityProvider>().isConnected;
    if (isConnected) {
      try {
        final results = await Future.wait([
          _service.getTypesVisite(t),
          _service.getPortesEntree(t),
          _service.getPersonnel(t),
          _service.getDepartements(t),
          _service.getReferences(t),
          provider.refreshVisitDetail(t, widget.visiteId),
        ]);
        if (mounted) {
          setState(() {
            _typesVisite = results[0] as List<Map<String, dynamic>>;
            _portesEntree = results[1] as List<Map<String, dynamic>>;
            _personnel = results[2] as List<Map<String, dynamic>>;
            _departements = results[3] as List<Map<String, dynamic>>;
            final refs = results[4] as Map<String, dynamic>;
            _nationalites = (refs['nationalites'] as List?)?.cast<String>() ?? [];
            _pays = (refs['pays'] as List?)?.cast<String>() ?? [];
            _typesPiece = (refs['types_piece'] as List?)?.cast<String>() ?? [];
            
            final refreshedVisit = results[5] as Visit?;
            if (refreshedVisit != null) {
              _fillFromVisit(refreshedVisit);
            }
            _loading = false;
          });
          await _saveDropdownsToCache();
        }
      } catch (e) {
        debugPrint('[EditVisitScreen] Échec du rafraîchissement des dropdowns/détails : $e');
        if (mounted && _loading) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur de chargement : $e'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } else {
      if (mounted) {
        setState(() => _loading = false);
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
      }
    } catch (e) {
      debugPrint('Error loading dropdowns from cache: $e');
    }
  }

  void _fillFromVisit(Visit v) {
    _nomCtrl.text = v.visiteur?.nom ?? '';
    _prenomCtrl.text = v.visiteur?.prenom ?? '';
    _telephoneCtrl.text = v.visiteur?.telephone ?? '';
    _emailCtrl.text = v.visiteur?.email ?? '';
    _numeroPieceCtrl.text = v.visiteur?.numeroPiece ?? '';
    _nipCtrl.text = v.visiteur?.numeroNip ?? '';
    _adresseCtrl.text = v.visiteur?.adresse ?? '';
    _dateNaissanceCtrl.text = v.visiteur?.dateNaissance ?? '';
    _lieuNaissanceCtrl.text = v.visiteur?.lieuNaissance ?? '';
    _dateDelivranceCtrl.text = v.visiteur?.dateDelivrance ?? '';
    _professionCtrl.text = v.visiteur?.profession ?? '';
    if (v.visiteur?.dateNaissance != null) _dateNaissanceCtrl.text = v.visiteur!.dateNaissance!;
    _selectedGenre = v.visiteur?.genre?.toUpperCase();
    _selectedNationalite = v.visiteur?.nationalite;
    _selectedPays = v.visiteur?.paysDelivrance;
    _selectedTypePiece = v.visiteur?.pieceIdentite;
    if (_selectedNationalite != null && !_nationalites.contains(_selectedNationalite)) _nationalites = [..._nationalites, _selectedNationalite!];
    if (_selectedPays != null && !_pays.contains(_selectedPays)) _pays = [..._pays, _selectedPays!];
    if (_selectedTypePiece != null && !_typesPiece.contains(_selectedTypePiece)) _typesPiece = [..._typesPiece, _selectedTypePiece!];
    _selectedTypeVisiteId = v.typeVisiteId;
    _selectedPorteEntreeId = v.porteEntreeId;
    _selectedPersonnelId = v.personnelId;
    _motifCtrl.text = v.motif ?? '';
    _observationsCtrl.text = v.observations ?? '';
    _badgeCtrl.text = v.numeroBadge ?? '';
    _dateExpirationCtrl.text = v.dateExpiration ?? '';
    if (v.dateVisite != null && v.heureArrivee != null) {
      _arriveeCtrl.text = '${v.dateVisite} ${v.heureArrivee}';
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final t = _getToken();
    if (t == null) return;

    setState(() => _submitting = true);
    try {
      final arriveeParts = _arriveeCtrl.text.split(' ');
      final dateVisite = arriveeParts[0];
      final heureArrivee = arriveeParts.length > 1 ? arriveeParts[1] : '00:00';

      final body = <String, dynamic>{
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
        'motif': _motifCtrl.text,
        'observations': _observationsCtrl.text,
        'numero_badge': _badgeCtrl.text,
        'date_visite': dateVisite,
        'heure_arrivee': heureArrivee,
      };
      if (_selectedGenre != null) body['v_genre'] = _selectedGenre;
      if (_selectedTypeVisiteId != null) body['type_visite_id'] = _selectedTypeVisiteId;
      if (_selectedPorteEntreeId != null) body['porte_entree_id'] = _selectedPorteEntreeId;
      if (_selectedPersonnelId != null) body['personnel_id'] = _selectedPersonnelId;
      if (_selectedDepartementId != null) body['departement_id'] = _selectedDepartementId;
      if (_selectedNationalite != null) body['v_nationalite'] = _selectedNationalite;
      if (_selectedPays != null) body['v_pays_delivrance'] = _selectedPays;
      if (_selectedTypePiece != null) body['v_piece_identite'] = _selectedTypePiece;

      final success = await context.read<VisitProvider>().updateVisite(t, widget.visiteId, body);
      if (mounted) {
        final online = context.read<ConnectivityProvider>().isConnected;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!success
              ? 'Échec de l\'enregistrement local'
              : online
                  ? 'Visite modifiée avec succès'
                  : 'Modification enregistrée localement, synchronisation en attente'),
          backgroundColor: !success
              ? Colors.red
              : online
                  ? Colors.green
                  : Colors.orange,
        ));
        Navigator.pop(context, true);
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

  Widget _buildSectionTitle(String title) {
    return Row(children: [
      Container(width: 4, height: 20, decoration: BoxDecoration(
        color: AppColors.ikaBlue, borderRadius: BorderRadius.circular(2),
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

  Widget _buildField(String label, TextEditingController ctrl, {IconData? icon, int maxLines = 1, bool isDate = false, bool readOnly = false}) {
    final ro = isDate || readOnly;
    return TextFormField(
      controller: ctrl, maxLines: maxLines, readOnly: ro, onTap: isDate ? () => _pickDate(ctrl) : null,
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

  Widget _buildDropdown(String label, List<Map<String, dynamic>> items, int? selectedId, String fieldKey, ValueChanged<int?> onChanged) {
    final hasSelected = selectedId != null && items.any((item) => item['id'] == selectedId);
    final effectiveValue = hasSelected ? selectedId : null;

    return DropdownButtonFormField<int>(
      initialValue: effectiveValue, isExpanded: true,
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

  Widget _buildDropdownSimple(String label, List<String> items, String? selected, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: selected, isExpanded: true,
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

  Widget _buildDropdownSearch(String label, List<String> items, String? selected, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: selected, isExpanded: true,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier la visite'),
        backgroundColor: const Color(0xFFFFFFFF),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Informations du visiteur'),
                    const SizedBox(height: 8),
                    _buildCard([
                      _buildField('Nom', _nomCtrl, icon: Icons.person),
                      const SizedBox(height: 12),
                      _buildField('Prénom', _prenomCtrl, icon: Icons.person_outline),
                      const SizedBox(height: 12),
                      _buildDropdownSimple('Genre', ['HOMME', 'FEMME'], _selectedGenre, (v) => setState(() => _selectedGenre = v)),
                      const SizedBox(height: 12),
                      _buildField('Téléphone', _telephoneCtrl, icon: Icons.phone),
                      const SizedBox(height: 12),
                      _buildField('Email', _emailCtrl, icon: Icons.email),
                      const SizedBox(height: 12),
                      _buildDropdownSearch('Type de pièce', _typesPiece, _selectedTypePiece, (v) => setState(() => _selectedTypePiece = v)),
                      const SizedBox(height: 12),
                      _buildField('N° Pièce', _numeroPieceCtrl, icon: Icons.badge),
                      const SizedBox(height: 12),
                      _buildField('NIP', _nipCtrl, icon: Icons.credit_card),
                      const SizedBox(height: 12),
                      _buildDropdownSearch('Nationalité', _nationalites, _selectedNationalite, (v) => setState(() => _selectedNationalite = v)),
                      const SizedBox(height: 12),
                      _buildField('Adresse', _adresseCtrl, icon: Icons.home),
                      const SizedBox(height: 12),
                      _buildField('Date naissance', _dateNaissanceCtrl, icon: Icons.cake, isDate: true),
                      const SizedBox(height: 12),
                      _buildField('Lieu naissance', _lieuNaissanceCtrl, icon: Icons.location_city),
                      const SizedBox(height: 12),
                      _buildField('Profession', _professionCtrl, icon: Icons.work),
                      const SizedBox(height: 12),
                      _buildDropdownSearch('Pays de delivrance', _pays, _selectedPays, (v) => setState(() => _selectedPays = v)),
                      const SizedBox(height: 12),
                      _buildField('Date delivrance', _dateDelivranceCtrl, icon: Icons.date_range, isDate: true),
                      const SizedBox(height: 12),
                      _buildField('Date d\'expiration', _dateExpirationCtrl, icon: Icons.event, isDate: true),
                    ]),
                    const SizedBox(height: 20),

                    _buildSectionTitle('Détails de la visite'),
                    const SizedBox(height: 8),
                    _buildCard([
                      _buildDropdown('Type de visite', _typesVisite, _selectedTypeVisiteId, 'nom', (v) => setState(() => _selectedTypeVisiteId = v)),
                      const SizedBox(height: 12),
                      _buildDropdown('Porte d\'entrée', _portesEntree, _selectedPorteEntreeId, 'titre', (v) => setState(() => _selectedPorteEntreeId = v)),
                      const SizedBox(height: 12),
                      _buildDropdown('Personnel', _personnel, _selectedPersonnelId, 'nom', (v) {
                        setState(() {
                          _selectedPersonnelId = v;
                          if (v != null) {
                            final person = _personnel.firstWhere(
                              (p) {
                                final pid = p['id'];
                                if (pid is int) return pid == v;
                                if (pid is String) return int.tryParse(pid) == v;
                                return pid.toString() == v.toString();
                              },
                              orElse: () => {},
                            );
                            if (person.isNotEmpty) {
                              final depId = person['departement_id'];
                              if (depId is int) {
                                _selectedDepartementId = depId;
                              } else if (depId is String) {
                                _selectedDepartementId = int.tryParse(depId);
                              }
                            }
                          }
                        });
                      }),
                      const SizedBox(height: 12),
                      _buildDropdown('Département', _departements, _selectedDepartementId, 'nom', (v) => setState(() => _selectedDepartementId = v)),
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
                      _buildField('Date et heure d\'arrivée', _arriveeCtrl, icon: Icons.calendar_today),
                    ]),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 22),
                        label: Text(_submitting ? 'Enregistrement...' : 'Enregistrer les modifications',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
}
