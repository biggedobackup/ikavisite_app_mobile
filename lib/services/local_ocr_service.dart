import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_document_reader_api/flutter_document_reader_api.dart' hide File;

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

    try {
      final dbData = await rootBundle.load('assets/Regula/db.dat');
      initConfig.customDb = dbData;
      debugPrint('[LocalOcrService] Base db.dat chargée (${dbData.lengthInBytes} octets).');
    } catch (e) {
      debugPrint('[LocalOcrService] db.dat introuvable dans les assets Flutter : $e');
      _initError = 'Base Regula absente (assets/Regula/db.dat).';
    }

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
      final initConfig = await _buildInitConfig();
      if (initConfig.customDb == null) return false;

      final (success, error) = await documentReader.initialize(initConfig);

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

  Future<bool> downloadDatabase(void Function(double progress) onProgress) async {
    try {
      final documentReader = DocumentReader.instance;
      final (success, error) = await documentReader.prepareDatabase("Full", (progress) {
        final percentage = progress.progress / 100.0;
        onProgress(percentage);
      });
      if (error != null) {
        _initError = "Téléchargement échoué: ${error.code} - ${error.message}";
        return false;
      }
      return success;
    } catch (e) {
      _initError = "Exception de téléchargement: $e";
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

    final docClassCode = await results.textFieldValueByType(FieldType.DOCUMENT_CLASS_CODE);
    final docClassName = await results.textFieldValueByType(FieldType.DOCUMENT_CLASS_NAME);
    String? typeDoc;
    if (docClassCode != null) {
      typeDoc = _getTypeFromDocCode(docClassCode);
    } else if (docClassName != null) {
      typeDoc = _getTypeFromDocName(docClassName);
    }
    champs['Type de document'] = typeDoc ?? 'AUTRE';

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

  String _getTypeFromDocCode(String code) {
    code = code.toUpperCase();
    if (code.startsWith('P')) return 'PASSEPORT';
    if (code.startsWith('V')) return 'VISA';
    if (code.startsWith('DL')) return 'PERMIS';
    if (code.startsWith('ID')) return 'CNI';
    return 'AUTRE';
  }

  String _getTypeFromDocName(String name) {
    name = name.toUpperCase();
    if (name.contains('PASSPORT') || name.contains('PASSEPORT')) return 'PASSEPORT';
    if (name.contains('VISA')) return 'VISA';
    if (name.contains('DRIVING') || name.contains('DRIVER') || name.contains('PERMIS') || name.contains('LICENCE')) return 'PERMIS';
    if (name.contains('ID CARD') || name.contains('IDENTITY') || name.contains('CARTE')) return 'CNI';
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
