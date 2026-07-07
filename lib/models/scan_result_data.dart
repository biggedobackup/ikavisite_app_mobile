import 'dart:io';

class ScanResultData {
  final String? nom;
  final String? prenom;
  final String? dateNaissance;
  final String? lieuNaissance;
  final String? nationalite;
  final String? profession;
  final String? typeDocument;
  final String? numeroDocument;
  final String? paysDelivrance;
  final String? dateDelivrance;
  final String? lieuDelivrance;
  final String? dateExpiration;
  final String? sexe;
  final String? nip;
  final String? nomJeuneFille;
  final String? lieuResidence;
  final File? rectoImage;
  final File? versoImage;
  final File? portrait;

  ScanResultData({
    this.nom,
    this.prenom,
    this.dateNaissance,
    this.lieuNaissance,
    this.nationalite,
    this.profession,
    this.typeDocument,
    this.numeroDocument,
    this.paysDelivrance,
    this.dateDelivrance,
    this.lieuDelivrance,
    this.dateExpiration,
    this.sexe,
    this.nip,
    this.nomJeuneFille,
    this.lieuResidence,
    this.rectoImage,
    this.versoImage,
    this.portrait,
  });

  /// Copie les données en conservant tout, sauf le verso qui peut être surchargé.
  ScanResultData copyWith({File? documentVerso}) {
    return ScanResultData(
      nom: nom,
      prenom: prenom,
      dateNaissance: dateNaissance,
      lieuNaissance: lieuNaissance,
      nationalite: nationalite,
      profession: profession,
      typeDocument: typeDocument,
      numeroDocument: numeroDocument,
      paysDelivrance: paysDelivrance,
      dateDelivrance: dateDelivrance,
      lieuDelivrance: lieuDelivrance,
      dateExpiration: dateExpiration,
      sexe: sexe,
      nip: nip,
      nomJeuneFille: nomJeuneFille,
      lieuResidence: lieuResidence,
      rectoImage: rectoImage,
      versoImage: documentVerso ?? versoImage,
      portrait: portrait,
    );
  }
}
