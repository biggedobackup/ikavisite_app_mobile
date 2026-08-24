import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Gestion des images d'une visite.
///
/// Les photos ne sont plus stockées dans la base : le fichier reste sur le
/// disque, dans le dossier persistant de l'application, et seule une référence
/// courte voyage dans la base et dans la file d'envoi. L'encodage base64 —
/// coûteux, et 33 % plus lourd que le JPEG — n'a lieu qu'au moment de l'envoi
/// au serveur, puis est immédiatement libéré.
///
/// Auparavant, chaque image était conservée deux fois en base64 : dans
/// `pending_sync` et dans la visite elle-même. À 300 visites par jour, cela
/// représentait environ 200 Mo par jour.
class VisitMedia {
  VisitMedia._();

  /// Préfixe distinguant une image locale d'une URL renvoyée par le serveur.
  static const String scheme = 'local:';
  static const String _dossier = 'visites';

  static String? _root;

  /// À appeler une fois au démarrage. Le chemin doit être connu de manière
  /// synchrone pour que les widgets puissent afficher les fichiers sans
  /// attendre.
  static Future<void> ensureRoot() async {
    if (_root != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _root = '${dir.path}/$_dossier';
      await Directory(_root!).create(recursive: true);
    } catch (e) {
      debugPrint('[VisitMedia] Dossier des images indisponible : $e');
    }
  }

  static bool isLocal(String? value) =>
      value != null && value.startsWith(scheme);

  /// Chemin absolu d'une référence locale, ou `null` si la référence n'en est
  /// pas une. La référence stockée est relative : le dossier de données d'une
  /// application peut changer d'un appareil ou d'une restauration à l'autre.
  static String? resolve(String? value) {
    if (!isLocal(value) || _root == null) return null;
    return '$_root/${value!.substring(scheme.length)}';
  }

  /// Recopie une image dans le dossier persistant et renvoie sa référence.
  ///
  /// `image_picker` et le scanner écrivent dans des dossiers de cache
  /// qu'Android peut vider quand la place manque : une visite restée en
  /// attente plusieurs jours y perdrait ses pièces jointes.
  static Future<String?> persist(String? sourcePath, String prefixe) async {
    if (sourcePath == null || sourcePath.isEmpty) return null;
    if (sourcePath.startsWith(scheme)) return sourcePath; // déjà persistée
    try {
      await ensureRoot();
      if (_root == null) return null;
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      final nom = '${prefixe}_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await source.copy('$_root/$nom');
      return '$scheme$nom';
    } catch (e) {
      debugPrint('[VisitMedia] Copie impossible de $sourcePath : $e');
      return null;
    }
  }

  /// Correspondance entre la référence stockée localement et le champ attendu
  /// par l'API.
  static const Map<String, String> champs = {
    'photo_path': 'photo_base64',
    'document_recto_path': 'document_recto_base64',
    'document_verso_path': 'document_verso_base64',
  };

  /// Prépare le corps attendu par l'API : les références locales sont
  /// remplacées par le contenu encodé, juste avant l'envoi.
  static Future<Map<String, dynamic>> toApiBody(
      Map<String, dynamic> payload) async {
    final body = Map<String, dynamic>.from(payload);
    // Les clés privées (préfixe `_`) servent à l'affichage hors ligne et au
    // pilotage de la file d'envoi : elles ne concernent pas le serveur.
    body.removeWhere((k, _) => k.startsWith('_'));
    for (final entry in champs.entries) {
      final ref = body.remove(entry.key) as String?;
      if (ref == null || ref.isEmpty) continue;
      final encoded = await _encode(ref);
      if (encoded != null) body[entry.value] = encoded;
    }
    return body;
  }

  static Future<String?> _encode(String ref) async {
    final path = resolve(ref) ?? (isLocal(ref) ? null : ref);
    if (path == null) return null;
    try {
      if (!await File(path).exists()) {
        debugPrint('[VisitMedia] Image absente au moment de l\'envoi : $ref');
        return null;
      }
      return await compute(_encodeFile, path);
    } catch (e) {
      debugPrint('[VisitMedia] Encodage impossible de $ref : $e');
      return null;
    }
  }

  // Le préfixe déclaré reste `image/png` : c'est ce que l'API reçoit depuis
  // toujours, le changer romprait le traitement côté serveur.
  static String _encodeFile(String path) {
    final bytes = File(path).readAsBytesSync();
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }

  /// Supprime les fichiers qui ne sont plus référencés par aucune saisie en
  /// attente. Sert de filet : si l'application est interrompue entre l'envoi
  /// réussi et le nettoyage, le fichier resterait sinon sur le disque à vie.
  static Future<int> sweepOrphans(Iterable<String> referencesEnUsage) async {
    await ensureRoot();
    if (_root == null) return 0;
    final gardes = referencesEnUsage
        .where(isLocal)
        .map((r) => r.substring(scheme.length))
        .toSet();
    var supprimes = 0;
    try {
      final dossier = Directory(_root!);
      if (!await dossier.exists()) return 0;
      await for (final entree in dossier.list()) {
        if (entree is! File) continue;
        final nom = entree.uri.pathSegments.last;
        if (gardes.contains(nom)) continue;
        await entree.delete();
        supprimes++;
      }
    } catch (e) {
      debugPrint('[VisitMedia] Balayage des orphelines impossible : $e');
    }
    return supprimes;
  }

  /// Supprime les fichiers d'une visite désormais synchronisée. Sans cela le
  /// disque accumulerait indéfiniment — environ 90 Mo par jour de production.
  static Future<void> discard(Map<String, dynamic> payload) async {
    for (final key in champs.keys) {
      final path = resolve(payload[key] as String?);
      if (path == null) continue;
      try {
        final fichier = File(path);
        if (await fichier.exists()) await fichier.delete();
      } catch (e) {
        debugPrint('[VisitMedia] Suppression impossible de $path : $e');
      }
    }
  }
}
