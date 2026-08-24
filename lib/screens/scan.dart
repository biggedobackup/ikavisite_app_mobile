import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_document_reader_api/flutter_document_reader_api.dart' hide File;
import 'package:path_provider/path_provider.dart';
import '../constants/colors.dart';
import '../utils/text_styles.dart';
import '../models/scan_result_data.dart';
import '../services/local_ocr_service.dart';
import 'add_visit_screen.dart';

enum _ScanStep { initial, rectoDone, recap }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _documentReader = DocumentReader.instance;
  bool _isInitializing = true;
  bool _isScanning = false;
  _ScanStep _step = _ScanStep.initial;
  String _status = 'Initialisation du scanner...';
  Scenario _scenario = Scenario.OCR;
  ScanResultData? _scanData;

  /// Vrai quand les fichiers du scan ont ete transmis au formulaire : ils ne
  /// doivent alors pas etre supprimes a la fermeture de cet ecran.
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _initRegula();
  }

  @override
  void dispose() {
    // Le scan est termine (ou abandonne) : le moteur natif — environ 250 Mo —
    // n'a plus de raison de rester en memoire.
    unawaited(LocalOcrService().release());
    if (!_handedOff) {
      // Scan abandonne : ses images temporaires ne serviront a personne.
      for (final f in [_scanData?.rectoImage, _scanData?.versoImage, _scanData?.portrait]) {
        if (f != null) f.delete().catchError((_) => f);
      }
    }
    super.dispose();
  }

  /// Prepare le moteur de lecture des que l'ecran s'ouvre, sans jamais bloquer
  /// l'interface : tout le travail lourd se fait cote natif, en tache de fond.
  /// Les deux boutons restent donc utilisables pendant la preparation — celui
  /// qui ouvre directement le formulaire ne doit jamais attendre le scanner.
  /// Si l'utilisateur lance un scan avant la fin, [_startScan] rejoint la meme
  /// initialisation au lieu d'en demarrer une seconde.
  Future<void> _initRegula() async {
    if (await _documentReader.isReady) {
      if (!mounted) return;
      _scenario = _bestScenario;
      setState(() {
        _isInitializing = false;
        _status = 'Scanner prêt.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isInitializing = false;
      _status = 'Préparation du scanner...';
    });

    final ok = await LocalOcrService().initialize();
    if (!mounted) return;
    if (ok) _scenario = _bestScenario;
    setState(() {
      _status = ok
          ? 'Scanner prêt.'
          : 'Scanner indisponible. Utilisez « Continuer sans scan direct ».';
    });
  }

  Scenario get _bestScenario {
    final available = _documentReader.availableScenarios;
    const priority = [
      Scenario.FULL_PROCESS,
      Scenario.MRZ_OR_BARCODE_OR_OCR,
      Scenario.MRZ_OR_OCR,
      Scenario.OCR,
      Scenario.MRZ,
      Scenario.BARCODE,
    ];
    for (final s in priority) {
      if (available.any((a) => a.name.toLowerCase() == s.value.toLowerCase())) {
        return s;
      }
    }
    return Scenario.OCR;
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _status = 'Préparation de la caméra...';
    });
    try {
      if (!await _documentReader.isReady) {
        setState(() {
          _status = 'Initialisation du scanner (premier scan)...';
        });
        // Laisse la frame se peindre : l'initialisation qui suit bloque le
        // thread UI plusieurs secondes, le message doit etre visible avant.
        await WidgetsBinding.instance.endOfFrame;
        final localOcr = LocalOcrService();
        final ok = await localOcr.initialize();
        if (!ok || !await _documentReader.isReady) {
          throw StateError(localOcr.initError ?? 'Scanner non prêt');
        }
        if (!mounted) return;
        _scenario = _bestScenario;
      }
      setState(() {
        _status = 'Cadrez la pièce dans le rectangle.';
      });
      _documentReader.startScanner(
        ScannerConfig.withScenario(_scenario),
        _handleCompletion,
      );
    } catch (e) {
      debugPrint('[ScanScreen] startScanner error: $e');
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _status = e is StateError && e.message.isNotEmpty
            ? e.message
            : 'Ouverture caméra impossible.';
      });
    }
  }

  Future<ScanResultData?> _lancerOcrPipeline(File recto, File? verso) async {
    try {
      final localOcr = LocalOcrService();
      Map<String, dynamic>? result;
      try {
        result = await localOcr.scanLocalDocument(
          recto: recto,
          verso: verso,
        );
      } finally {
        localOcr.dispose();
      }

      if (result != null && result['success'] == true) {
        final champs = result['champs'] as Map<String, dynamic>;

        File? portraitFile;
        if (result['portrait'] != null) {
          try {
            final bytes = base64Decode(result['portrait']);
            final dir = await getTemporaryDirectory();
            portraitFile = File('${dir.path}/portrait_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await portraitFile.writeAsBytes(bytes);
          } catch (_) {}
        }

        return ScanResultData(
          nom: champs['Nom']?.toString().toUpperCase(),
          prenom: champs['Prénoms']?.toString(),
          dateNaissance: champs['Date de naissance']?.toString(),
          lieuNaissance: champs['Lieu de naissance']?.toString(),
          nationalite: champs['Nationalité']?.toString(),
          profession: champs['Profession']?.toString(),
          typeDocument: champs['Type de document']?.toString(),
          numeroDocument: champs['Numéro du document']?.toString().toUpperCase(),
          paysDelivrance: champs['Pays de délivrance']?.toString() ?? champs['pays_delivrance_doc']?.toString(),
          dateDelivrance: champs['Date de délivrance']?.toString() ?? champs['date_delivrance_doc']?.toString(),
          lieuDelivrance: champs['Lieu de délivrance']?.toString(),
          dateExpiration: champs['Date d\'expiration']?.toString(),
          sexe: champs['Sexe']?.toString(),
          nip: champs['NIP']?.toString(),
          nomJeuneFille: (champs['Nom de jeune fille']?.toString() ?? champs['nom_jeune_fille']?.toString())?.toUpperCase(),
          lieuResidence: champs['Pays de résidence']?.toString(),
          rectoImage: recto,
          versoImage: verso,
          portrait: portraitFile,
        );
      }
    } catch (e) {
      debugPrint('[ScanScreen] Erreur pipeline OCR : $e');
    }
    return null;
  }

  Future<void> _handleCompletion(
    DocReaderAction action,
    Results? results,
    DocReaderException? error,
  ) async {
    if (error != null) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _status = error.message;
      });
      return;
    }
    if (!action.stopped()) return;
    if (results == null) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _status = 'Scan annulé ou document non reconnu.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _status = 'Analyse du document en cours...';
    });

    if (_step == _ScanStep.initial) {
      final rectoFile = await _saveImage(
        results, GraphicFieldType.DOCUMENT_IMAGE, 'recto',
      );
      if (rectoFile == null) {
        if (!mounted) return;
        setState(() {
          _isScanning = false;
          _status = 'Erreur d\'enregistrement de l\'image recto.';
        });
        return;
      }

      final portraitFile = await _saveImage(
        results, GraphicFieldType.PORTRAIT, 'portrait',
      );

      final scannedData = await _lancerOcrPipeline(rectoFile, null);

      ScanResultData finalRectoData;
      if (scannedData != null) {
        finalRectoData = scannedData;
        if (finalRectoData.portrait == null && portraitFile != null) {
          finalRectoData = ScanResultData(
            nom: finalRectoData.nom,
            prenom: finalRectoData.prenom,
            dateNaissance: finalRectoData.dateNaissance,
            lieuNaissance: finalRectoData.lieuNaissance,
            nationalite: finalRectoData.nationalite,
            profession: finalRectoData.profession,
            typeDocument: finalRectoData.typeDocument,
            numeroDocument: finalRectoData.numeroDocument,
            paysDelivrance: finalRectoData.paysDelivrance,
            dateDelivrance: finalRectoData.dateDelivrance,
            lieuDelivrance: finalRectoData.lieuDelivrance,
            dateExpiration: finalRectoData.dateExpiration,
            sexe: finalRectoData.sexe,
            nip: finalRectoData.nip,
            nomJeuneFille: finalRectoData.nomJeuneFille,
            lieuResidence: finalRectoData.lieuResidence,
            rectoImage: rectoFile,
            versoImage: null,
            portrait: portraitFile,
          );
        }
      } else {
        finalRectoData = ScanResultData(
          rectoImage: rectoFile,
          portrait: portraitFile,
        );
      }

      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _scanData = finalRectoData;
        _step = _ScanStep.rectoDone;
        _status = 'Recto capturé. Vous pouvez scanner le verso maintenant.';
      });
    } else {
      final versoFile = await _saveImage(
        results,
        GraphicFieldType.DOCUMENT_IMAGE,
        'verso',
      );

      if (versoFile == null) {
        if (!mounted) return;
        setState(() {
          _isScanning = false;
        });
        _showRecap(_scanData);
        return;
      }

      ScanResultData? finalData;
      if (_scanData?.rectoImage != null) {
        final versoResult = await _lancerOcrPipeline(_scanData!.rectoImage!, versoFile);
        if (versoResult != null) {
          finalData = _mergeScanResults(_scanData!, versoResult, versoFile);
        }
      }

      if (finalData == null && _scanData != null) {
        finalData = _scanData!.copyWith(documentVerso: versoFile);
      }

      if (!mounted) return;
      setState(() {
        _isScanning = false;
      });
      _showRecap(finalData);
    }
  }

  ScanResultData _mergeScanResults(
      ScanResultData rectoData, ScanResultData versoResult, File versoFile) {
    bool hasValue(String? v) => v != null && v.trim().isNotEmpty;

    return ScanResultData(
      nom: hasValue(rectoData.nom) ? rectoData.nom : versoResult.nom,
      prenom: hasValue(rectoData.prenom) ? rectoData.prenom : versoResult.prenom,
      dateNaissance: hasValue(rectoData.dateNaissance) ? rectoData.dateNaissance : versoResult.dateNaissance,
      lieuNaissance: hasValue(rectoData.lieuNaissance) ? rectoData.lieuNaissance : versoResult.lieuNaissance,
      nationalite: hasValue(rectoData.nationalite) ? rectoData.nationalite : versoResult.nationalite,
      profession: hasValue(rectoData.profession) ? rectoData.profession : versoResult.profession,
      typeDocument: hasValue(rectoData.typeDocument) ? rectoData.typeDocument : versoResult.typeDocument,
      numeroDocument: hasValue(rectoData.numeroDocument) ? rectoData.numeroDocument : versoResult.numeroDocument,
      paysDelivrance: hasValue(rectoData.paysDelivrance) ? rectoData.paysDelivrance : versoResult.paysDelivrance,
      dateDelivrance: hasValue(rectoData.dateDelivrance) ? rectoData.dateDelivrance : versoResult.dateDelivrance,
      lieuDelivrance: hasValue(rectoData.lieuDelivrance) ? rectoData.lieuDelivrance : versoResult.lieuDelivrance,
      dateExpiration: hasValue(rectoData.dateExpiration) ? rectoData.dateExpiration : versoResult.dateExpiration,
      sexe: hasValue(rectoData.sexe) ? rectoData.sexe : versoResult.sexe,
      nip: hasValue(rectoData.nip) ? rectoData.nip : versoResult.nip,
      nomJeuneFille: hasValue(rectoData.nomJeuneFille) ? rectoData.nomJeuneFille : versoResult.nomJeuneFille,
      lieuResidence: hasValue(rectoData.lieuResidence) ? rectoData.lieuResidence : versoResult.lieuResidence,
      rectoImage: rectoData.rectoImage,
      versoImage: versoFile,
      portrait: rectoData.portrait ?? versoResult.portrait,
    );
  }

  void _showRecap(ScanResultData? data) {
    if (!mounted) return;
    setState(() {
      _scanData = data;
      _step = _ScanStep.recap;
      _status = 'Vérifiez les informations extraites avant de continuer.';
    });
  }

  void _resetScan() {
    setState(() {
      _scanData = null;
      _step = _ScanStep.initial;
      _isScanning = false;
      _status = 'Scanner prêt.';
    });
  }

  Future<File?> _saveImage(
    Results results,
    GraphicFieldType fieldType,
    String prefix,
  ) async {
    try {
      final bytes = await results.graphicFieldImageByType(fieldType);
      if (bytes == null) return null;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  void _openForm(ScanResultData? data) {
    if (!mounted) return;
    _handedOff = data != null;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AddVisitScreen(scanData: data),
      ),
    );
  }

  Widget _buildRectoDone() {
    final data = _scanData;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 28),
              const SizedBox(width: 10),
              Text(
                'RECTO CAPTURÉ',
                style: AppText.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (data != null) ...[
            _buildImagePreview(data.rectoImage, 'RECTO'),
            const SizedBox(height: 16),
            _row('Nom', data.nom ?? '-'),
            _row('Prénom', data.prenom ?? '-'),
            _row('Sexe', data.sexe ?? '-'),
            _row('Nom J.F.', data.nomJeuneFille ?? '-'),
            _row('Nationalité', data.nationalite ?? '-'),
            _row('N° pièce', data.numeroDocument ?? '-'),
            _row('NIP', data.nip ?? '-'),
            _row('Type doc', data.typeDocument ?? '-'),
            _row('Date naiss.', data.dateNaissance ?? '-'),
            _row('Lieu naiss.', data.lieuNaissance ?? '-'),
            _row('Profession', data.profession ?? '-'),
            _row('Pays déliv.', data.paysDelivrance ?? '-'),
            _row('Lieu déliv.', data.lieuDelivrance ?? '-'),
            _row('Date déliv.', data.dateDelivrance ?? '-'),
            _row('Date expir.', data.dateExpiration ?? '-'),
          ],
          const SizedBox(height: 16),
          Text(
            _status,
            style: AppText.inter(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: AppColors.info,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ikaBlue,
              ),
              onPressed: _isScanning ? null : _startScan,
              icon: _isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.camera_alt_outlined),
              label: Text(
                _isScanning ? 'Scan en cours...' : 'SCANNER LE VERSO',
                style: AppText.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () {
                if (data != null) _showRecap(data);
              },
              child: Text(
                'CONTINUER SANS VERSO',
                style: AppText.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: AppColors.slate600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecap() {
    final data = _scanData;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.success, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'RÉCAPITULATIF DU SCAN',
                  style: AppText.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data?.versoImage != null
                ? 'Recto et verso analysés. Contrôlez les données ci-dessous.'
                : 'Recto analysé. Contrôlez les données ci-dessous.',
            style: AppText.inter(
              height: 1.4,
              color: AppColors.slate600,
              fontSize: 13,
            ),
          ),
          if (data?.portrait != null) ...[
            const SizedBox(height: 16),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  data!.portrait!,
                  width: 96,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (data?.rectoImage != null)
                Expanded(child: _buildImagePreview(data!.rectoImage, 'RECTO')),
              if (data?.rectoImage != null && data?.versoImage != null)
                const SizedBox(width: 12),
              if (data?.versoImage != null)
                Expanded(child: _buildImagePreview(data!.versoImage, 'VERSO')),
            ],
          ),
          const SizedBox(height: 16),
          if (data != null) ...[
            _row('Nom', data.nom ?? '-'),
            _row('Prénom', data.prenom ?? '-'),
            _row('Sexe', data.sexe ?? '-'),
            _row('Nom J.F.', data.nomJeuneFille ?? '-'),
            _row('Nationalité', data.nationalite ?? '-'),
            _row('N° pièce', data.numeroDocument ?? '-'),
            _row('NIP', data.nip ?? '-'),
            _row('Type doc', data.typeDocument ?? '-'),
            _row('Date naiss.', data.dateNaissance ?? '-'),
            _row('Lieu naiss.', data.lieuNaissance ?? '-'),
            _row('Profession', data.profession ?? '-'),
            _row('Pays déliv.', data.paysDelivrance ?? '-'),
            _row('Lieu déliv.', data.lieuDelivrance ?? '-'),
            _row('Date déliv.', data.dateDelivrance ?? '-'),
            _row('Date expir.', data.dateExpiration ?? '-'),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ikaBlue,
              ),
              onPressed: data != null ? () => _openForm(data) : null,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(
                'CONTINUER',
                style: AppText.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _resetScan,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                'REFAIRE LE SCAN',
                style: AppText.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: AppColors.slate600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(File? image, String label) {
    if (image == null) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: AppColors.slate100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.slate200),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image_outlined, color: AppColors.slate400),
            const SizedBox(height: 4),
            Text(
              '$label non capturé',
              style: AppText.inter(fontSize: 11, color: AppColors.slate500),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.inter(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: AppColors.slate500,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            image,
            width: double.infinity,
            height: 110,
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppText.inter(
                color: AppColors.slate500,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppText.inter(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'SCAN DOCUMENT',
          style: AppText.inter(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            letterSpacing: 2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_step == _ScanStep.recap)
            _buildRecap()
          else if (_step == _ScanStep.rectoDone)
            _buildRectoDone()
          else
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.slate200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.document_scanner_outlined, size: 46),
                  const SizedBox(height: 16),
                  Text(
                    'Scanner une pièce d\'identité',
                    style: AppText.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Placez la pièce d\'identité dans le cadre rectangle. Quand le document est bien cadré, les informations sont lues automatiquement.',
                    style: AppText.inter(
                      height: 1.4,
                      color: AppColors.slate600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _status,
                    style: AppText.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ikaBlue,
                      ),
                      onPressed: _isInitializing || _isScanning
                          ? null
                          : _startScan,
                      icon: _isInitializing || _isScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        _isInitializing
                            ? 'Initialisation...'
                            : _isScanning
                            ? 'Scan en cours...'
                            : 'SCANNER LE RECTO',
                        style: AppText.inter(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _isScanning ? null : () => _openForm(null),
                      child: Text(
                        'CONTINUER SANS SCAN DIRECT',
                        style: AppText.inter(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: AppColors.slate600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
