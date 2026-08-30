int? _toInt(dynamic val) => (val as num?)?.toInt();

class Visit {
  final int id;
  final String uuid;
  final TypeVisite? typeVisite;
  final int? typeVisiteId;
  final Visiteur? visiteur;
  final int? visiteurId;
  final String? genre;
  final PorteEntree? porteEntree;
  final int? porteEntreeId;
  final Personnel? personnel;
  final int? personnelId;
  final String? dateVisite;
  final String? heureArrivee;
  final String? dateDepartPrevue;
  final String? heureDepartPrevue;
  final String? dateDepart;
  final String? dateExpiration;
  final String? heureDepart;
  final String? numeroBadge;
  final String? motif;
  final String? observations;
  final String? signatureEntree;
  final String? signatureSortie;
  final String? statut;
  final int dureeMaxMinutes;
  final String? heureArriveeDt;
  final String? heureFinPrevueDt;
  final bool estExcedee;
  final String? createdAt;
  final String? updatedAt;

  Visit({
    required this.id,
    required this.uuid,
    this.typeVisite,
    this.typeVisiteId,
    this.visiteur,
    this.visiteurId,
    this.genre,
    this.porteEntree,
    this.porteEntreeId,
    this.personnel,
    this.personnelId,
    this.dateVisite,
    this.heureArrivee,
    this.dateDepartPrevue,
    this.heureDepartPrevue,
    this.dateDepart,
    this.dateExpiration,
    this.heureDepart,
    this.numeroBadge,
    this.motif,
    this.observations,
    this.signatureEntree,
    this.signatureSortie,
    this.statut,
    this.dureeMaxMinutes = 60,
    this.heureArriveeDt,
    this.heureFinPrevueDt,
    this.estExcedee = false,
    this.createdAt,
    this.updatedAt,
  });

  factory Visit.fromJson(Map<String, dynamic> json) {
    return Visit(
      id: _toInt(json['id']) ?? 0,
      uuid: json['uuid'] as String? ?? '',
      typeVisite: json['type_visite'] != null
          ? TypeVisite.fromJson(json['type_visite'] as Map<String, dynamic>)
          : null,
      typeVisiteId: _toInt(json['type_visite_id']),
      visiteur: json['visiteur'] != null
          ? Visiteur.fromJson(json['visiteur'] as Map<String, dynamic>)
          : null,
      visiteurId: _toInt(json['visiteur_id']),
      genre: json['genre'] as String?,
      porteEntree: json['porte_entree'] != null
          ? PorteEntree.fromJson(json['porte_entree'] as Map<String, dynamic>)
          : null,
      porteEntreeId: _toInt(json['porte_entree_id']),
      personnel: json['personnel'] != null
          ? Personnel.fromJson(json['personnel'] as Map<String, dynamic>)
          : null,
      personnelId: _toInt(json['personnel_id']),
      dateVisite: json['date_visite'] as String?,
      heureArrivee: json['heure_arrivee'] as String?,
      dateDepartPrevue: json['date_depart_prevue'] as String?,
      heureDepartPrevue: json['heure_depart_prevue'] as String?,
      dateDepart: json['date_depart'] as String?,
      dateExpiration: json['date_expiration'] as String?,
      heureDepart: json['heure_depart'] as String?,
      numeroBadge: json['numero_badge'] as String?,
      motif: json['motif'] as String?,
      observations: json['observations'] as String?,
      signatureEntree: json['signature_entree'] as String?,
      signatureSortie: json['signature_sortie'] as String?,
      statut: json['statut'] as String?,
      dureeMaxMinutes: _toInt(json['duree_max_minutes']) ?? 60,
      heureArriveeDt: json['heure_arrivee_dt'] as String?,
      heureFinPrevueDt: json['heure_fin_prevue_dt'] as String?,
      estExcedee: json['est_excedee'] as bool? ?? false,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'type_visite': typeVisite?.toJson(),
      'type_visite_id': typeVisiteId,
      'visiteur': visiteur?.toJson(),
      'visiteur_id': visiteurId,
      'genre': genre,
      'porte_entree': porteEntree?.toJson(),
      'porte_entree_id': porteEntreeId,
      'personnel': personnel?.toJson(),
      'personnel_id': personnelId,
      'date_visite': dateVisite,
      'heure_arrivee': heureArrivee,
      'date_depart_prevue': dateDepartPrevue,
      'heure_depart_prevue': heureDepartPrevue,
      'date_depart': dateDepart,
      'date_expiration': dateExpiration,
      'heure_depart': heureDepart,
      'numero_badge': numeroBadge,
      'motif': motif,
      'observations': observations,
      'signature_entree': signatureEntree,
      'signature_sortie': signatureSortie,
      'statut': statut,
      'duree_max_minutes': dureeMaxMinutes,
      'heure_arrivee_dt': heureArriveeDt,
      'heure_fin_prevue_dt': heureFinPrevueDt,
      'est_excedee': estExcedee,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Visit copyWith({
    int? id,
    String? uuid,
    TypeVisite? typeVisite,
    int? typeVisiteId,
    Visiteur? visiteur,
    int? visiteurId,
    String? genre,
    PorteEntree? porteEntree,
    int? porteEntreeId,
    Personnel? personnel,
    int? personnelId,
    String? dateVisite,
    String? heureArrivee,
    String? dateDepartPrevue,
    String? heureDepartPrevue,
    String? dateDepart,
    String? dateExpiration,
    String? heureDepart,
    String? numeroBadge,
    String? motif,
    String? observations,
    String? signatureEntree,
    String? signatureSortie,
    String? statut,
    int? dureeMaxMinutes,
    String? heureArriveeDt,
    String? heureFinPrevueDt,
    bool? estExcedee,
    String? createdAt,
    String? updatedAt,
  }) {
    return Visit(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      typeVisite: typeVisite ?? this.typeVisite,
      typeVisiteId: typeVisiteId ?? this.typeVisiteId,
      visiteur: visiteur ?? this.visiteur,
      visiteurId: visiteurId ?? this.visiteurId,
      genre: genre ?? this.genre,
      porteEntree: porteEntree ?? this.porteEntree,
      porteEntreeId: porteEntreeId ?? this.porteEntreeId,
      personnel: personnel ?? this.personnel,
      personnelId: personnelId ?? this.personnelId,
      dateVisite: dateVisite ?? this.dateVisite,
      heureArrivee: heureArrivee ?? this.heureArrivee,
      dateDepartPrevue: dateDepartPrevue ?? this.dateDepartPrevue,
      heureDepartPrevue: heureDepartPrevue ?? this.heureDepartPrevue,
      dateDepart: dateDepart ?? this.dateDepart,
      dateExpiration: dateExpiration ?? this.dateExpiration,
      heureDepart: heureDepart ?? this.heureDepart,
      numeroBadge: numeroBadge ?? this.numeroBadge,
      motif: motif ?? this.motif,
      observations: observations ?? this.observations,
      signatureEntree: signatureEntree ?? this.signatureEntree,
      signatureSortie: signatureSortie ?? this.signatureSortie,
      statut: statut ?? this.statut,
      dureeMaxMinutes: dureeMaxMinutes ?? this.dureeMaxMinutes,
      heureArriveeDt: heureArriveeDt ?? this.heureArriveeDt,
      heureFinPrevueDt: heureFinPrevueDt ?? this.heureFinPrevueDt,
      estExcedee: estExcedee ?? this.estExcedee,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get visiteurNomComplet {
    if (visiteur == null) return 'Inconnu';
    final parts = <String>[
      if (visiteur!.prenom != null && visiteur!.prenom!.isNotEmpty) visiteur!.prenom!,
      if (visiteur!.nom != null && visiteur!.nom!.isNotEmpty) visiteur!.nom!,
    ];
    return parts.isEmpty ? 'Inconnu' : parts.join(' ');
  }

  String get personnelNomComplet {
    if (personnel == null) return 'Non assigné';
    final parts = <String>[
      if (personnel!.prenom != null && personnel!.prenom!.isNotEmpty) personnel!.prenom!,
      if (personnel!.nom != null && personnel!.nom!.isNotEmpty) personnel!.nom!,
    ];
    return parts.isEmpty ? 'Non assigné' : parts.join(' ');
  }
}

class TypeVisite {
  final int id;
  final String uuid;
  final String? nom;
  final String? description;
  final int? dureeMaxMinutes;
  final String? statut;
  final String? createdAt;
  final String? updatedAt;

  TypeVisite({
    required this.id,
    required this.uuid,
    this.nom,
    this.description,
    this.dureeMaxMinutes,
    this.statut,
    this.createdAt,
    this.updatedAt,
  });

  factory TypeVisite.fromJson(Map<String, dynamic> json) {
    return TypeVisite(
      id: _toInt(json['id']) ?? 0,
      uuid: json['uuid'] as String? ?? '',
      nom: json['nom'] as String?,
      description: json['description'] as String?,
      dureeMaxMinutes: _toInt(json['duree_max_minutes']),
      statut: json['statut'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'nom': nom,
      'description': description,
      'duree_max_minutes': dureeMaxMinutes,
      'statut': statut,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class Visiteur {
  final int id;
  final String uuid;
  final String? nom;
  final String? prenom;
  final String? genre;
  final String? telephone;
  final String? email;
  final String? numeroPiece;
  final String? numeroNip;
  final String? nationalite;
  final String? profession;
  final String? adresse;
  final String? pieceIdentite;
  final String? dateNaissance;
  final String? lieuNaissance;
  final String? paysDelivrance;
  final String? dateDelivrance;
  final String? photo;
  final String? documentRecto;
  final String? documentVerso;
  final String? statut;

  Visiteur({
    required this.id,
    required this.uuid,
    this.nom,
    this.prenom,
    this.genre,
    this.telephone,
    this.email,
    this.numeroPiece,
    this.numeroNip,
    this.nationalite,
    this.profession,
    this.adresse,
    this.pieceIdentite,
    this.dateNaissance,
    this.lieuNaissance,
    this.paysDelivrance,
    this.dateDelivrance,
    this.photo,
    this.documentRecto,
    this.documentVerso,
    this.statut,
  });

  /// Reprend le visiteur en remplacant ses seules images. Sert a garder les
  /// fichiers restes sur l'appareil quand la visite passe cote serveur : ils
  /// s'affichent alors sans reseau.
  Visiteur copyWithImages({
    String? photo,
    String? documentRecto,
    String? documentVerso,
  }) {
    return Visiteur(
      id: id,
      uuid: uuid,
      nom: nom,
      prenom: prenom,
      genre: genre,
      telephone: telephone,
      email: email,
      numeroPiece: numeroPiece,
      numeroNip: numeroNip,
      nationalite: nationalite,
      profession: profession,
      adresse: adresse,
      pieceIdentite: pieceIdentite,
      dateNaissance: dateNaissance,
      lieuNaissance: lieuNaissance,
      paysDelivrance: paysDelivrance,
      dateDelivrance: dateDelivrance,
      photo: photo ?? this.photo,
      documentRecto: documentRecto ?? this.documentRecto,
      documentVerso: documentVerso ?? this.documentVerso,
      statut: statut,
    );
  }

  factory Visiteur.fromJson(Map<String, dynamic> json) {
    return Visiteur(
      id: _toInt(json['id']) ?? 0,
      uuid: json['uuid'] as String? ?? '',
      nom: json['nom'] as String?,
      prenom: json['prenom'] as String?,
      genre: json['genre'] as String?,
      telephone: json['telephone'] as String?,
      email: json['email'] as String?,
      numeroPiece: json['numero_piece'] as String?,
      numeroNip: json['numero_nip'] as String?,
      nationalite: json['nationalite'] as String?,
      profession: json['profession'] as String?,
      adresse: json['adresse'] as String?,
      pieceIdentite: json['piece_identite'] as String?,
      dateNaissance: json['date_naissance'] as String?,
      lieuNaissance: json['lieu_naissance'] as String?,
      paysDelivrance: json['pays_delivrance'] as String?,
      dateDelivrance: json['date_delivrance'] as String?,
      photo: json['photo'] as String?,
      documentRecto: json['document_recto'] as String?,
      documentVerso: json['document_verso'] as String?,
      statut: json['statut'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'nom': nom,
      'prenom': prenom,
      'genre': genre,
      'telephone': telephone,
      'email': email,
      'numero_piece': numeroPiece,
      'numero_nip': numeroNip,
      'nationalite': nationalite,
      'profession': profession,
      'adresse': adresse,
      'piece_identite': pieceIdentite,
      'date_naissance': dateNaissance,
      'lieu_naissance': lieuNaissance,
      'pays_delivrance': paysDelivrance,
      'date_delivrance': dateDelivrance,
      'photo': photo,
      'document_recto': documentRecto,
      'document_verso': documentVerso,
      'statut': statut,
    };
  }
}

class PorteEntree {
  final int id;
  final String? titre;
  final String? emplacement;

  PorteEntree({
    required this.id,
    this.titre,
    this.emplacement,
  });

  factory PorteEntree.fromJson(Map<String, dynamic> json) {
    return PorteEntree(
      id: _toInt(json['id']) ?? 0,
      titre: json['titre'] as String?,
      emplacement: json['emplacement'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titre': titre,
      'emplacement': emplacement,
    };
  }
}

class Personnel {
  final int id;
  final String? nom;
  final String? prenom;
  final String? fonction;
  final String? departement;
  final int? departementId;

  Personnel({
    required this.id,
    this.nom,
    this.prenom,
    this.fonction,
    this.departement,
    this.departementId,
  });

  factory Personnel.fromJson(Map<String, dynamic> json) {
    String? deptName;
    if (json['departement'] is String) {
      deptName = json['departement'] as String?;
    } else if (json['departement'] is Map) {
      deptName = (json['departement'] as Map<String, dynamic>)['nom'] as String?;
    }
    deptName ??= json['departement_nom'] as String?;

    return Personnel(
      id: _toInt(json['id']) ?? 0,
      nom: json['nom'] as String?,
      prenom: json['prenom'] as String?,
      fonction: json['fonction'] as String?,
      departement: deptName,
      departementId: _toInt(json['departement_id']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nom': nom,
      'prenom': prenom,
      'fonction': fonction,
      'departement': departement,
      'departement_id': departementId,
    };
  }
}

class VisitListResponse {
  final List<Visit> items;
  final int count;

  VisitListResponse({required this.items, required this.count});

  factory VisitListResponse.fromJson(Map<String, dynamic> json) {
    return VisitListResponse(
      items: (json['items'] as List? ?? [])
          .map((e) => Visit.fromJson(e as Map<String, dynamic>))
          .toList(),
      count: _toInt(json['count']) ?? 0,
    );
  }
}
