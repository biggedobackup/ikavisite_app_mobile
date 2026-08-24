# -*- coding: utf-8 -*-
"""Seed de la base locale IkaVisite (ikavisite.db) avec des visites de test
« prêtes à synchroniser ».

Insère N visites datées du jour, réparties entre les listes de l'application
(today / en_cours / terminees / excedees), en reproduisant EXACTEMENT le
format d'une visite créée hors ligne par un agent dans l'application :

  - une ligne dans `pending_sync` (action='create_visite', même formes de
    clés que le formulaire d'ajout — voir add_visit_screen.dart), avec
    `_terminer_apres_creation`/`_termination_body` pour les visites déjà
    closes (même mécanisme que VisitProvider._terminerLocalPending) ;
  - une ligne dans `visits` avec est_local=1, id négatif, uuid `local_<id>`,
    exactement comme VisitProvider._visitFromPayload reconstruit une saisie
    hors ligne ;
  - le visiteur dans `visiteurs` ;
  - les rattachements dans `visit_listes`.

IMPORTANT — conséquence : parce que ces visites sont de véritables saisies
« en attente », l'application les enverra RÉELLEMENT au serveur configuré dès
que la connectivité reviendra (SyncProvider synchronise tout `pending_sync`
automatiquement à la reconnexion). Ne réactivez le réseau sur l'appareil que
lorsque vous êtes prêt à ce que ces N visites (et leurs images) soient
effectivement créées côté serveur.

Les heures d'arrivée/départ prévu sont calculées par rapport à l'heure
d'exécution du script (« maintenant ») pour rester cohérentes avec la
réalité : une visite « en cours » a un départ prévu dans le futur, une visite
« excédée » a un départ prévu déjà dépassé, une visite « terminée » a une
heure de départ réelle déjà passée.

Usage :
    python seed_visites_locales.py <chemin/ikavisite.db> [--en-cours 4000] [--terminees 3000] [--excedees 3000]

La base doit être au schéma v13 (tables visits / visit_listes / visits_meta /
pending_sync). Les images référencées (local:seed_photo_<i>.jpg, etc.)
doivent être dupliquées séparément dans le dossier `visites` de
l'application sur l'appareil — voir le script d'installation associé.
"""
import argparse
import json
import random
import sqlite3
import sys
from datetime import datetime

NOMS = ["Kouassi", "Traoré", "Ouattara", "Koné", "Diabaté", "Yao", "N'Guessan",
        "Bamba", "Coulibaly", "Touré", "Kouadio", "Soro", "Gnahoré", "Adjoua",
        "Assi", "Brou", "Diallo", "Fofana", "Gbagbo", "Konan"]
PRENOMS_H = ["Jean", "Yves", "Franck", "Serge", "Mamadou", "Ibrahim", "Paul",
             "Éric", "Didier", "Arnaud", "Junior", "Moussa", "Karim", "Hervé"]
PRENOMS_F = ["Awa", "Fatou", "Marie", "Aïcha", "Adjoua", "Nathalie", "Solange",
             "Mariam", "Estelle", "Chantal", "Aya", "Clarisse", "Josiane"]
PROFESSIONS = ["Commerçant(e)", "Ingénieur(e)", "Enseignant(e)", "Consultant(e)",
               "Comptable", "Étudiant(e)", "Avocat(e)", "Technicien(ne)",
               "Journaliste", "Entrepreneur(e)"]
MOTIFS = ["Réunion de travail", "Dépôt de dossier", "Entretien d'embauche",
          "Livraison de matériel", "Visite de courtoisie", "Signature de contrat",
          "Maintenance informatique", "Audit interne", "Formation", "Rendez-vous commercial"]
TYPES_VISITE = [
    {"id": 1, "nom": "Professionnelle", "description": "Visite professionnelle", "duree_max_minutes": 60},
    {"id": 2, "nom": "Familiale", "description": "Visite familiale", "duree_max_minutes": 45},
    {"id": 3, "nom": "Fournisseur", "description": "Visite fournisseur", "duree_max_minutes": 90},
    {"id": 4, "nom": "Officielle", "description": "Visite officielle", "duree_max_minutes": 120},
]
PORTES = [
    {"id": 1, "titre": "Porte Principale", "emplacement": "Entrée A"},
    {"id": 2, "titre": "Porte Nord", "emplacement": "Entrée B"},
    {"id": 3, "titre": "Porte Sud", "emplacement": "Entrée C"},
]
PERSONNELS = [
    {"id": i + 1, "nom": NOMS[i % len(NOMS)], "prenom": PRENOMS_H[i % len(PRENOMS_H)],
     "fonction": f, "departement": d, "departement_id": di}
    for i, (f, d, di) in enumerate([
        ("Directeur", "Direction Générale", 1), ("Chef de service", "Ressources Humaines", 2),
        ("Comptable", "Finances", 3), ("Responsable IT", "Informatique", 4),
        ("Assistante", "Secrétariat", 5), ("Chargé d'études", "Études et Projets", 6),
        ("Juriste", "Affaires Juridiques", 7), ("Logisticien", "Logistique", 8),
    ])
]
NATIONALITES = ["Ivoirienne", "Ivoirienne", "Ivoirienne", "Burkinabè", "Malienne",
                "Sénégalaise", "Guinéenne", "Française", "Ghanéenne"]


def clamp_min(m):
    return max(0, min(int(m), 23 * 60 + 59))


def hhmm(m):
    m = clamp_min(m)
    return f"{m // 60:02d}:{m % 60:02d}"


def build_creation_body(i, kind, today, now_min):
    """Corps de création — même clés que add_visit_screen.dart envoie à
    VisitProvider.createVisite (labels privés `_xxx` compris, indispensables
    pour l'affichage hors ligne)."""
    rng = random.Random(i)  # reproductible
    genre = rng.choice(["M", "F"])
    prenom = rng.choice(PRENOMS_H if genre == "M" else PRENOMS_F)
    nom = rng.choice(NOMS)
    tv = rng.choice(TYPES_VISITE)
    porte = rng.choice(PORTES)
    perso = rng.choice(PERSONNELS)
    duree = tv["duree_max_minutes"]

    # Heures calculées par rapport à MAINTENANT pour rester cohérentes avec
    # les statuts : une visite « en cours » n'est pas encore due, une
    # « excédée » l'est déjà, une « terminée » a un vrai départ passé.
    depart_min = None
    if kind == "terminee":
        fin_prevue_min = clamp_min(now_min - rng.randint(10, 600))
        arrivee_min = clamp_min(fin_prevue_min - duree)
        depart_min = clamp_min(fin_prevue_min + rng.randint(-15, 10))
        if depart_min >= now_min:
            depart_min = max(0, now_min - 2)
    elif kind == "excedee":
        fin_prevue_min = clamp_min(now_min - rng.randint(5, 240))
        arrivee_min = clamp_min(fin_prevue_min - duree)
    else:  # en_cours, pas encore due
        fin_prevue_min = clamp_min(now_min + rng.randint(5, 180))
        arrivee_min = clamp_min(fin_prevue_min - duree)

    telephone = f"+225 07 {rng.randint(10,99)} {rng.randint(10,99)} {rng.randint(10,99)} {rng.randint(10,99)}"
    numero_piece = f"CI{rng.randint(100000000, 999999999)}"
    date_naissance = f"{rng.randint(1960, 2004)}-{rng.randint(1,12):02d}-{rng.randint(1,28):02d}"
    date_delivrance = f"{rng.randint(2015, 2024)}-{rng.randint(1,12):02d}-{rng.randint(1,28):02d}"

    body = {
        "date_visite": today,
        "heure_arrivee": hhmm(arrivee_min),
        "date_depart_prevue": today,
        "heure_depart_prevue": hhmm(fin_prevue_min),
        "genre": genre, "v_genre": genre,
        "type_visite_id": tv["id"],
        "_type_visite_nom": tv["nom"], "_type_visite_description": tv["description"],
        "porte_entree_id": porte["id"],
        "_porte_entree_titre": porte["titre"], "_porte_entree_emplacement": porte["emplacement"],
        "personnel_id": perso["id"],
        "_personnel_nom": perso["nom"], "_personnel_prenom": perso["prenom"],
        "_personnel_fonction": perso["fonction"], "_personnel_departement": perso["departement"],
        "departement_id": perso["departement_id"],
        "numero_badge": f"B-{i:05d}", "motif": rng.choice(MOTIFS),
        "v_nom": nom, "v_prenom": prenom, "v_telephone": telephone,
        "v_email": f"{prenom.lower()}.{nom.lower().replace(chr(39), '')}{i}@exemple.ci",
        "v_numero_piece": numero_piece, "v_nip": "",
        "v_adresse": f"Abidjan, Cocody, Rue {rng.randint(1, 99)}",
        "v_date_naissance": date_naissance, "v_lieu_naissance": "Abidjan",
        "v_profession": rng.choice(PROFESSIONS), "v_date_delivrance": date_delivrance,
        "v_nationalite": rng.choice(NATIONALITES),
        "v_pays_delivrance": "Côte d'Ivoire", "v_piece_identite": "CNI",
        "photo_path": f"local:seed_photo_{i}.jpg",
        "document_recto_path": f"local:seed_recto_{i}.jpg",
        "document_verso_path": f"local:seed_verso_{i}.jpg",
    }

    if kind == "terminee":
        body["_terminer_apres_creation"] = True
        body["_termination_body"] = {
            "date_depart": today, "heure_depart": hhmm(depart_min), "observations": "",
        }

    return body, tv, porte, perso


def visit_json_from_body(pending_id, body, kind, today, now_iso):
    """Reproduit VisitProvider._visitFromPayload (Dart) : c'est le JSON que
    l'application affiche hors ligne pour cette saisie en attente. Enrichi de
    `date_depart_prevue`/`heure_depart_prevue`/`duree_max_minutes`, que la
    vraie fonction Dart n'alimente pas (limite existante, non modifiée ici) —
    ne pas s'étonner si une VRAIE visite créée hors ligne dans l'app affiche
    « Départ prévu : - » alors que ces visites de test l'affichent."""
    uuid = f"local_{pending_id}"
    statut = "TERMINEE" if kind == "terminee" else "EN_COURS"
    term = body.get("_termination_body") or {}
    return {
        "id": -pending_id, "uuid": uuid,
        "type_visite": {
            "id": body.get("type_visite_id"), "uuid": "",
            "nom": body.get("_type_visite_nom"), "description": body.get("_type_visite_description"),
            "duree_max_minutes": None, "statut": None, "created_at": None, "updated_at": None,
        },
        "type_visite_id": body.get("type_visite_id"),
        "visiteur": {
            "id": -pending_id, "uuid": uuid,
            "nom": body.get("v_nom"), "prenom": body.get("v_prenom"),
            "genre": body.get("v_genre") or body.get("genre"),
            "telephone": body.get("v_telephone"), "email": body.get("v_email"),
            "numero_piece": body.get("v_numero_piece"), "numero_nip": body.get("v_nip"),
            "nationalite": body.get("v_nationalite"), "profession": body.get("v_profession"),
            "adresse": body.get("v_adresse"), "piece_identite": body.get("v_piece_identite"),
            "date_naissance": body.get("v_date_naissance"), "lieu_naissance": body.get("v_lieu_naissance"),
            "pays_delivrance": body.get("v_pays_delivrance"), "date_delivrance": body.get("v_date_delivrance"),
            "photo": body.get("photo_path"), "document_recto": body.get("document_recto_path"),
            "document_verso": body.get("document_verso_path"), "statut": "ACTIF",
        },
        "visiteur_id": -pending_id,
        "genre": body.get("genre"),
        "porte_entree": {
            "id": body.get("porte_entree_id"), "titre": body.get("_porte_entree_titre"),
            "emplacement": body.get("_porte_entree_emplacement"),
        },
        "porte_entree_id": body.get("porte_entree_id"),
        "personnel": {
            "id": body.get("personnel_id"), "nom": body.get("_personnel_nom"),
            "prenom": body.get("_personnel_prenom"), "fonction": body.get("_personnel_fonction"),
            "departement": body.get("_personnel_departement"), "departement_id": body.get("departement_id"),
        },
        "personnel_id": body.get("personnel_id"),
        "date_visite": body.get("date_visite", today),
        "heure_arrivee": body.get("heure_arrivee", "00:00"),
        "date_depart_prevue": body.get("date_depart_prevue"),
        "heure_depart_prevue": body.get("heure_depart_prevue"),
        "date_depart": term.get("date_depart"),
        "date_expiration": None,
        "heure_depart": term.get("heure_depart"),
        "numero_badge": body.get("numero_badge"), "motif": body.get("motif"),
        "observations": term.get("observations"), "signature_entree": None, "signature_sortie": None,
        "statut": statut, "duree_max_minutes": 60,
        "heure_arrivee_dt": None, "heure_fin_prevue_dt": None,
        "est_excedee": kind == "excedee",
        "created_at": now_iso, "updated_at": now_iso,
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("db")
    p.add_argument("--en-cours", type=int, default=4000)
    p.add_argument("--terminees", type=int, default=3000)
    p.add_argument("--excedees", type=int, default=3000)
    p.add_argument("--date", default=None, help="AAAA-MM-JJ (défaut : aujourd'hui)")
    args = p.parse_args()

    now = datetime.now()
    today = args.date or now.strftime("%Y-%m-%d")
    now_iso = now.isoformat()
    now_min = now.hour * 60 + now.minute
    total = args.en_cours + args.terminees + args.excedees

    plan = (["en_cours"] * args.en_cours
            + ["terminee"] * args.terminees
            + ["excedee"] * args.excedees)

    con = sqlite3.connect(args.db)
    cur = con.cursor()
    version = cur.execute("PRAGMA user_version").fetchone()[0]
    if version < 13:
        sys.exit(f"Schéma v{version} trouvé, v13 requis : lancez d'abord l'application une fois.")

    # On repart d'une base de visites propre. `pending_sync` n'est purgée que
    # de ses éventuelles anciennes saisies « seed-*» d'un essai précédent
    # (repérables à leur payload), pas des vraies saisies de l'agent.
    cur.execute("DELETE FROM visit_listes")
    cur.execute("DELETE FROM visits")
    cur.execute("DELETE FROM visiteurs")
    cur.execute("DELETE FROM visits_meta")
    cur.execute("DELETE FROM pending_sync WHERE payload LIKE '%seed_photo_%'")

    ordres = {"today": 0, "en_cours": 0, "terminees": 0, "excedees": 0}
    ordre_today = list(range(total))
    random.Random(42).shuffle(ordre_today)

    for i, kind in enumerate(plan):
        body, tv, porte, perso = build_creation_body(i, kind, today, now_min)

        cur.execute(
            "INSERT INTO pending_sync (action, payload, created_at, status, tentatives) "
            "VALUES ('create_visite', ?, ?, 0, 0)",
            (json.dumps(body, ensure_ascii=False), now_iso))
        pending_id = cur.lastrowid

        visit = visit_json_from_body(pending_id, body, kind, today, now_iso)
        visiteur = visit["visiteur"]
        vuuid = visit["uuid"]

        cur.execute(
            "INSERT OR REPLACE INTO visiteurs (uuid, id, nom, prenom, genre, telephone, email, "
            "numero_piece, numero_nip, nationalite, profession, adresse, piece_identite, "
            "date_naissance, lieu_naissance, pays_delivrance, date_delivrance, updated_at) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (vuuid, visiteur["id"], visiteur["nom"], visiteur["prenom"], visiteur["genre"],
             visiteur["telephone"], visiteur["email"], visiteur["numero_piece"], visiteur["numero_nip"],
             visiteur["nationalite"], visiteur["profession"], visiteur["adresse"], visiteur["piece_identite"],
             visiteur["date_naissance"], visiteur["lieu_naissance"], visiteur["pays_delivrance"],
             visiteur["date_delivrance"], now_iso))

        cur.execute(
            "INSERT OR REPLACE INTO visits (id, uuid, visiteur_uuid, est_local, statut, "
            "date_visite, heure_arrivee, personnel_id, updated_at, data_json) "
            "VALUES (?,?,?,1,?,?,?,?,?,?)",
            (visit["id"], vuuid, vuuid, visit["statut"], today, visit["heure_arrivee"],
             visit["personnel_id"], now_iso, json.dumps(visit, ensure_ascii=False)))

        # Rattachement : les trois catégories restent mutuellement
        # exclusives (4000 / 3000 / 3000 = 10000), comme demandé. La vraie
        # création hors ligne ne rattache une saisie qu'à `en_cours` (+
        # `today`) — jamais à `terminees`/`excedees`, classements sans
        # existence locale dans l'app réelle (calculés côté serveur). On
        # reproduit ce rattachement pour les « terminées » (place réellement
        # prise après clôture) et on ajoute `excedees` uniquement pour
        # l'affichage local de ces données de test.
        liste = {"en_cours": "en_cours", "terminee": "terminees", "excedee": "excedees"}[kind]
        cur.execute("INSERT OR REPLACE INTO visit_listes (liste, visit_id, ordre) VALUES (?,?,?)",
                    (liste, visit["id"], ordres[liste]))
        ordres[liste] += 1
        cur.execute("INSERT OR REPLACE INTO visit_listes (liste, visit_id, ordre) VALUES (?,?,?)",
                    ("today", visit["id"], ordre_today[i]))

    con.commit()
    print("Visites par liste :")
    for liste, n in cur.execute(
            "SELECT liste, COUNT(*) FROM visit_listes GROUP BY liste ORDER BY liste"):
        print(f"  {liste}: {n}")
    n_local = cur.execute("SELECT COUNT(*) FROM visits WHERE est_local=1").fetchone()[0]
    n_pending = cur.execute("SELECT COUNT(*) FROM pending_sync WHERE action='create_visite'").fetchone()[0]
    print(f"  visits (est_local=1): {n_local}")
    print(f"  pending_sync (create_visite): {n_pending}")
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    con.execute("VACUUM")
    con.close()
    print(f"OK — {total} visites du {today} insérées dans {args.db}, prêtes à synchroniser.")


if __name__ == "__main__":
    main()
