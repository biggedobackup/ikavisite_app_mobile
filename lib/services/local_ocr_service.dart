import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_document_reader_api/flutter_document_reader_api.dart' hide File;

/// Lecture OCR d'une piece d'identite, hors ligne.
///
/// Regula a besoin d'une base de reference — `db.dat`, environ 72 Mo — qui
/// decrit le format des documents d'identite du monde entier. Ce n'est pas une
/// donnee de visiteur : rien de ce qui est scanne n'y est ecrit.
///
/// Cette base n'est volontairement PAS transmise depuis Dart via
/// `InitConfig.customDb`. Ce chemin coutait tres cher a chaque lancement :
/// les 72 Mo etaient lus dans le tas Dart, encodes en base64 (+33 %), passes
/// en texte par le canal de methodes, redecodes cote Java — six copies du
/// meme fichier, pres de 480 Mo de pic memoire et plusieurs secondes de
/// thread UI bloque. Pire, le SDK reecrivait les 72 Mo dans la memoire
/// interne a *chaque* initialisation.
///
/// Sans `customDb`, le SDK lit lui-meme `Regula/db.dat` depuis les assets
/// natifs (`android/app/src/main/assets/Regula/db.dat`) et le recopie en flux,
/// une seule fois par installation ou mise a jour de l'application. Rien ne
/// transite par Dart, et les lancements suivants ne copient plus rien.
class LocalOcrService {
  static final LocalOcrService _instance = LocalOcrService._internal();
  factory LocalOcrService() => _instance;
  LocalOcrService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  String? _initError;
  String? get initError => _initError;

  Future<bool>? _pendingInit;

  Future<InitConfig> _buildInitConfig() async {
    final licenseData = await rootBundle.load('assets/regula.license');
    final initConfig = InitConfig(licenseData);
    initConfig.delayedNNLoad = true;
    initConfig.licenseUpdate = false;
    // `customDb` reste nul : le SDK va chercher la base dans les assets
    // natifs. Voir la note de classe.
    return initConfig;
  }

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    if (_pendingInit != null) return _pendingInit!;

    _pendingInit = _doInitialize();
    final result = await _pendingInit;
    _pendingInit = null;
    return result ?? false;
  }

  Future<bool> _doInitialize() async {

    try {
      final documentReader = DocumentReader.instance;

      // Le moteur natif reste initialise pour toute la duree du processus (et
      // survit a un hot restart). Inutile de relire puis de re-encoder les
      // ~75 Mo de db.dat dans ce cas : c'est ce transfert qui gele le thread UI.
      if (await documentReader.isReady) {
        _isInitialized = true;
        _initError = null;
        return true;
      }

      final initConfig = await _buildInitConfig();
      final (success, error) = await documentReader.initialize(initConfig);
      // Une base absente ou illisible n'empeche pas l'initialisation de
      // reussir : elle laisse simplement la liste des scenarios vide, et tout
      // scan echouera ensuite sans explication. On la trace donc une fois.
      debugPrint('[LocalOcrService] Scenarios reconnus : '
          '${documentReader.availableScenarios.length}');

      if (error != null) {
        if (error.message.contains("initialized already") ||
            error.message.contains("already initialized")) {
          try {
            documentReader.deinitializeReader();
            await Future.delayed(const Duration(milliseconds: 100));
            final (success2, error2) = await documentReader.initialize(initConfig);
            if (error2 == null && success2) {
              _isInitialized = true;
              _initError = null;
              return true;
            }
            _initError = error2?.message ?? 'Réinitialisation Regula échouée';
            return false;
          } catch (e) {
            _initError = e.toString();
            return false;
          }
        }
        _initError = "${error.code} - ${error.message}";
        return false;
      }

      _isInitialized = success;
      if (success) _initError = null;
      return success;
    } catch (e) {
      _initError = e.toString();
      return false;
    }
  }

  Future<Map<String, dynamic>?> scanLocalDocument({
    required File recto,
    File? verso,
  }) async {
    try {
      if (!_isInitialized) {
        final ok = await initialize();
        if (!ok) {
          return {
            'success': false,
            'error': 'license_missing',
            'message': 'Initialisation Regula échouée : $_initError'
          };
        }
      }

      final List<Uint8List> images = [];
      final rectoBytes = await recto.readAsBytes();
      images.add(rectoBytes);
      if (verso != null) {
        final versoBytes = await verso.readAsBytes();
        images.add(versoBytes);
      }

      final scenario = _getBestScenario();
      final config = RecognizeConfig.withScenario(scenario, images: images);
      final completer = Completer<Map<String, dynamic>?>();

      DocumentReader.instance.recognize(
        config,
        (DocReaderAction action, Results? results, DocReaderException? error) async {
          if (error != null) {
            if (!completer.isCompleted) completer.complete(null);
            return;
          }
          if (action.stopped()) {
            if (results != null) {
              final mapped = await _mapRegulaResults(results);
              if (!completer.isCompleted) completer.complete(mapped);
            } else {
              if (!completer.isCompleted) completer.complete(null);
            }
          }
        },
      );

      return await completer.future;
    } catch (e) {
      debugPrint('[LocalOcrService] Exception: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _mapRegulaResults(Results results) async {
    final Map<String, dynamic> champs = {};

    String? nom = await results.textFieldValueByType(FieldType.SURNAME);
    if (nom == null || nom.trim().isEmpty) {
      final surnameAndGiven = await results.textFieldValueByType(FieldType.SURNAME_AND_GIVEN_NAMES);
      if (surnameAndGiven != null && surnameAndGiven.contains('<<')) {
        nom = surnameAndGiven.split('<<').first.replaceAll('<', ' ').trim();
      } else {
        nom = surnameAndGiven;
      }
    }
    if (nom != null && nom.trim().isNotEmpty) {
      champs['Nom'] = nom.trim().toUpperCase();
    }

    String? prenoms = await results.textFieldValueByType(FieldType.GIVEN_NAMES);
    if (prenoms == null || prenoms.trim().isEmpty) {
      final surnameAndGiven = await results.textFieldValueByType(FieldType.SURNAME_AND_GIVEN_NAMES);
      if (surnameAndGiven != null && surnameAndGiven.contains('<<')) {
        final parts = surnameAndGiven.split('<<');
        if (parts.length > 1) {
          prenoms = parts[1].replaceAll('<', ' ').trim();
        }
      }
    }
    if (prenoms != null && prenoms.trim().isNotEmpty) {
      champs['Prénoms'] = prenoms.trim();
    }

    final dob = await results.textFieldValueByType(FieldType.DATE_OF_BIRTH);
    if (dob != null && dob.trim().isNotEmpty) {
      champs['Date de naissance'] = _formatRegulaDate(dob.trim());
    }

    final placeOfBirth = await results.textFieldValueByType(FieldType.PLACE_OF_BIRTH);
    if (placeOfBirth != null && placeOfBirth.trim().isNotEmpty) {
      champs['Lieu de naissance'] = placeOfBirth.trim();
    }

    final profession = await results.textFieldValueByType(FieldType.PROFESSION);
    if (profession != null && profession.trim().isNotEmpty) {
      champs['Profession'] = profession.trim();
    }

    final docNum = await results.textFieldValueByType(FieldType.DOCUMENT_NUMBER);
    if (docNum != null && docNum.trim().isNotEmpty) {
      champs['Numéro du document'] = docNum.trim().toUpperCase();
    }

    final nip = await results.textFieldValueByType(FieldType.PERSONAL_NUMBER);
    if (nip != null && nip.trim().isNotEmpty) {
      final nipClean = nip.trim().replaceAll('<', ' ').trim();
      if (nipClean.isNotEmpty) champs['NIP'] = nipClean.toUpperCase();
    }

    final nationality = await results.textFieldValueByType(FieldType.NATIONALITY);
    if (nationality != null && nationality.trim().isNotEmpty) {
      champs['Nationalité'] = nationality.trim();
    }

    final sex = await results.textFieldValueByType(FieldType.SEX);
    if (sex != null && sex.trim().isNotEmpty) {
      final s = sex.trim().toUpperCase();
      if (s == 'M' || s.startsWith('M') || s.contains('MALE')) {
        champs['Sexe'] = 'HOMME';
      } else if (s == 'F' || s.startsWith('F') || s.contains('FEMALE')) {
        champs['Sexe'] = 'FEMME';
      } else {
        champs['Sexe'] = s;
      }
    }

    champs['Type de document'] = await _detecterTypeDocument(results) ?? 'AUTRE';

    final addressCountry = await results.textFieldValueByType(FieldType.ADDRESS_COUNTRY);
    if (addressCountry != null && addressCountry.trim().isNotEmpty) {
      champs['Pays de résidence'] = addressCountry.trim();
    }

    final doi = await results.textFieldValueByType(FieldType.DATE_OF_ISSUE);
    if (doi != null && doi.trim().isNotEmpty) {
      champs['Date de délivrance'] = _formatRegulaDate(doi.trim());
    }

    final doe = await results.textFieldValueByType(FieldType.DATE_OF_EXPIRY);
    if (doe != null && doe.trim().isNotEmpty) {
      champs['Date d\'expiration'] = _formatRegulaDate(doe.trim());
    }

    String? lieuDelivrance = await results.textFieldValueByType(FieldType.PLACE_OF_ISSUE);
    if (lieuDelivrance == null || lieuDelivrance.trim().isEmpty) {
      lieuDelivrance = await results.textFieldValueByType(FieldType.AUTHORITY);
    }
    if (lieuDelivrance != null && lieuDelivrance.trim().isNotEmpty) {
      champs['Lieu de délivrance'] = lieuDelivrance.trim();
    }

    String? maidenName = await results.textFieldValueByType(FieldType.FAMILY_NAME);
    if (maidenName == null || maidenName.trim().isEmpty) {
      maidenName = await results.textFieldValueByType(FieldType.SURNAME_OF_SPOSE);
    }
    if (maidenName != null && maidenName.trim().isNotEmpty) {
      champs['Nom de jeune fille'] = maidenName.trim().toUpperCase();
    }

    final issuingState = await results.textFieldValueByType(FieldType.ISSUING_STATE_NAME);
    if (issuingState != null && issuingState.trim().isNotEmpty) {
      champs['Pays de délivrance'] = issuingState.trim();
    }

    String? portraitB64;
    try {
      final portraitBytes = await results.graphicFieldImageByType(GraphicFieldType.PORTRAIT);
      if (portraitBytes != null) {
        portraitB64 = base64Encode(portraitBytes);
      }
    } catch (_) {}

    return {
      'success': true,
      'champs': champs,
      'portrait': portraitB64,
    };
  }

  String _formatRegulaDate(String dateStr) {
    if (dateStr.length == 6) {
      return _formatMrzDate(dateStr);
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateStr)) {
      return dateStr;
    }
    final match = RegExp(r'^(\d{2})[\./-](\d{2})[\./-](\d{4})$').firstMatch(dateStr);
    if (match != null) {
      return '${match.group(3)}-${match.group(2)}-${match.group(1)}';
    }
    return dateStr;
  }

  String _formatMrzDate(String yymmdd) {
    if (yymmdd.length != 6) return yymmdd;
    int yy = int.tryParse(yymmdd.substring(0, 2)) ?? 0;
    String mm = yymmdd.substring(2, 4);
    String dd = yymmdd.substring(4, 6);
    int currentYear = DateTime.now().year % 100;
    int century = (yy <= currentYear + 5) ? 2000 : 1900;
    return '${century + yy}-$mm-$dd';
  }

  /// Nature du document scanne, cherchee dans l'ordre de fiabilite :
  /// le type reconnu par la base Regula, puis les champs de classe, puis la
  /// premiere lettre de la MRZ. Les champs texte `DOCUMENT_CLASS_*` sont vides
  /// dans les scenarios OCR et MRZ, ce qui renvoyait « AUTRE » quel que soit
  /// le document presente.
  Future<String?> _detecterTypeDocument(Results results) async {
    // 1) Type reconnu par la base de documents : le plus sur.
    for (final doc in results.documentType ?? const <DocumentType>[]) {
      final parEnum = _typeDepuisDocType(doc.type);
      if (parEnum != null) {
        debugPrint('[LocalOcrService] Type de document : ${doc.type.name} '
            '(${doc.name}) -> $parEnum');
        return parEnum;
      }
      final parNom = doc.name == null ? null : _getTypeFromDocName(doc.name!);
      if (parNom != null && parNom != 'AUTRE') {
        debugPrint('[LocalOcrService] Type de document (nom) : ${doc.name} -> $parNom');
        return parNom;
      }
    }

    // 2) Champs de classe du document, quand la base ne tranche pas.
    final docClassCode =
        await results.textFieldValueByType(FieldType.DOCUMENT_CLASS_CODE);
    final docClassName =
        await results.textFieldValueByType(FieldType.DOCUMENT_CLASS_NAME);
    debugPrint('[LocalOcrService] Classe du document : code=$docClassCode nom=$docClassName');
    if (docClassName != null) {
      final parNom = _getTypeFromDocName(docClassName);
      if (parNom != 'AUTRE') return parNom;
    }
    if (docClassCode != null && docClassCode.trim().isNotEmpty) {
      final parCode = _getTypeFromDocCode(docClassCode);
      if (parCode != 'AUTRE') return parCode;
    }

    // 3) MRZ : sa premiere lettre porte le code ICAO du document.
    final mrz = await results.textFieldValueByType(FieldType.MRZ_STRINGS);
    final parMrz = _typeDepuisMrz(mrz);
    if (parMrz != null) {
      debugPrint('[LocalOcrService] Type de document deduit de la MRZ : $parMrz');
      return parMrz;
    }
    return null;
  }

  /// Traduit l'enumeration Regula — une centaine de valeurs — en s'appuyant
  /// sur son libelle plutot que sur chaque code : `NationalIdentityCard`,
  /// `DiplomaticPassport` ou `CommercialDrivingLicense` se rangent ainsi
  /// d'eux-memes. L'ordre des tests compte : `ResidencePermitIdentityCard`
  /// est une carte d'identite, pas un permis.
  String? _typeDepuisDocType(DocType type) {
    final nom = type.name.toUpperCase();
    if (nom == 'NOTDEFINED' || nom == 'OTHER') return null;
    if (nom.contains('PASSPORT')) return 'PASSEPORT';
    if (nom.contains('IDENTITYCARD') || nom.contains('IDCARD')) return 'CNI';
    if (nom.contains('VISA')) return 'VISA';
    if (nom.contains('LICENSE') ||
        nom.contains('LICENCE') ||
        nom.contains('PERMIT')) {
      return 'PERMIS';
    }
    if (nom.contains('IDENTITY')) return 'CNI';
    return null;
  }

  /// Premiere ligne de la MRZ : `P` passeport, `V` visa, `A`/`C`/`I` carte
  /// d'identite ou titre de sejour, `D` permis.
  String? _typeDepuisMrz(String? mrz) {
    if (mrz == null) return null;
    final ligne = mrz
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (ligne.isEmpty) return null;
    final type = _getTypeFromDocCode(ligne.substring(0, 1));
    return type == 'AUTRE' ? null : type;
  }

  /// Code de classe ICAO 9303. Les cartes d'identite utilisent `I`, `ID`,
  /// `IN`, `C` ou `A` selon les pays — la CNI ivoirienne emet `I`, que
  /// l'ancien test `== ID` classait a tort en AUTRE.
  String _getTypeFromDocCode(String code) {
    code = code.toUpperCase();
    if (code.startsWith('P')) return 'PASSEPORT';
    if (code.startsWith('V')) return 'VISA';
    if (code.startsWith('D')) return 'PERMIS';
    if (code.startsWith('I') || code.startsWith('C') || code.startsWith('A')) {
      return 'CNI';
    }
    return 'AUTRE';
  }

  String _getTypeFromDocName(String name) {
    name = name.toUpperCase();
    if (name.contains('PASSPORT') || name.contains('PASSEPORT')) return 'PASSEPORT';
    if (name.contains('VISA')) return 'VISA';
    if (name.contains('DRIVING') || name.contains('DRIVER') || name.contains('PERMIS') || name.contains('LICENCE')) return 'PERMIS';
    if (name.contains('ID CARD') || name.contains('IDENTITY') || name.contains('CARTE') || name.contains('IDENTIT')) return 'CNI';
    return 'AUTRE';
  }

  Scenario _getBestScenario() {
    final available = DocumentReader.instance.availableScenarios;
    if (available.isEmpty) return Scenario.OCR;

    final priorityList = [
      Scenario.FULL_PROCESS,
      Scenario.MRZ_OR_BARCODE_OR_OCR,
      Scenario.MRZ_OR_OCR,
      Scenario.OCR,
      Scenario.MRZ,
      Scenario.BARCODE,
    ];

    for (var scenario in priorityList) {
      final isSupported = available.any((s) => s.name.toLowerCase() == scenario.value.toLowerCase());
      if (isSupported) return scenario;
    }

    return Scenario.OCR;
  }

  /// Libere le moteur natif — environ 250 Mo de memoire — quand le scan est
  /// termine. La base sur disque reste en place : la prochaine ouverture de
  /// l'ecran de scan reinitialisera le moteur en arriere-plan (~2 s).
  Future<void> release() async {
    try {
      await _pendingInit; // ne jamais couper une initialisation en cours
    } catch (_) {}
    try {
      DocumentReader.instance.deinitializeReader();
      _isInitialized = false;
      debugPrint('[LocalOcrService] Moteur libéré.');
    } catch (e) {
      debugPrint('[LocalOcrService] Libération impossible : $e');
    }
  }

  Future<bool> reinitialize() async {
    try {
      DocumentReader.instance.deinitializeReader();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 200));
    _isInitialized = false;
    return initialize();
  }

  void dispose() {}
}
