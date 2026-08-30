import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/app_info.dart';
import '../widgets/app_drawer.dart';

/// Mode d'emploi de l'application : les gestes du quotidien, le fonctionnement
/// hors connexion, puis une foire aux questions.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const List<_Etape> _etapes = [
    _Etape(
      numero: 1,
      titre: 'Ouvrir le scan',
      detail: 'Depuis le tableau de bord, appuyez sur « Ajouter une visite ». '
          'Le lecteur de pièce d\'identité s\'ouvre directement.',
    ),
    _Etape(
      numero: 2,
      titre: 'Scanner la pièce d\'identité',
      detail: 'Présentez le recto, puis le verso quand l\'application le '
          'demande. Les informations du visiteur (nom, nationalité, numéro de '
          'pièce, date de naissance) sont remplies automatiquement. Vous pouvez '
          'aussi choisir « Continuer sans scanner » et tout saisir à la main.',
    ),
    _Etape(
      numero: 3,
      titre: 'Compléter le formulaire',
      detail: 'Vérifiez les données du visiteur, puis renseignez les champs '
          'obligatoires : type de document, nationalité, téléphone, type de '
          'visite et département. Selon le créneau, la personne à visiter est '
          'également demandée.',
    ),
    _Etape(
      numero: 4,
      titre: 'Enregistrer',
      detail: 'Appuyez sur « Enregistrer la visite ». L\'écran de confirmation '
          's\'affiche : « Ajouter une autre visite » relance directement le '
          'scan, sinon vous revenez au tableau de bord.',
    ),
    _Etape(
      numero: 5,
      titre: 'Clôturer la visite',
      detail: 'Dans « Visites en cours », appuyez sur « Clôturer ». Le visiteur '
          'signe sur l\'écran : cette signature de sortie est conservée dans '
          'son historique.',
    ),
  ];

  static const List<_Faq> _faq = [
    _Faq(
      question: 'Puis-je enregistrer une visite sans connexion Internet ?',
      reponse: 'Oui. Tout l\'enregistrement fonctionne hors connexion : la '
          'visite est écrite sur le téléphone et part dans la file de '
          'synchronisation. Le bandeau orange « Mode hors connexion » vous '
          'indique combien d\'opérations attendent d\'être envoyées.',
    ),
    _Faq(
      question: 'Quand mes visites hors connexion sont-elles envoyées ?',
      reponse: 'Dès que le réseau revient, l\'envoi démarre tout seul, dans '
          'l\'ordre où les opérations ont été créées. Vous n\'avez rien à '
          'lancer manuellement. Le bouton « Voir » du bandeau permet de '
          'consulter ce qu\'il reste à envoyer.',
    ),
    _Faq(
      question: 'Que faire si une opération reste bloquée en rouge ?',
      reponse: 'Une ligne rouge signifie que le serveur a refusé l\'opération '
          'après plusieurs tentatives (jeton expiré, donnée invalide). '
          'Reconnectez-vous, puis vérifiez la visite concernée. Si le blocage '
          'persiste, signalez-le à l\'administrateur en indiquant l\'opération '
          'et son heure.',
    ),
    _Faq(
      question: 'Le scan ne reconnaît pas la pièce, que faire ?',
      reponse: 'Posez la pièce à plat, sur un fond sombre et sans reflet, et '
          'laissez le cadre se stabiliser. Si la lecture échoue toujours, '
          'utilisez « Continuer sans scanner » et saisissez les informations '
          'manuellement : la visite reste valable.',
    ),
    _Faq(
      question: 'Pourquoi ne puis-je plus modifier une visite depuis la liste ?',
      reponse: 'Une visite en cours ne se modifie plus depuis la liste. Ouvrez '
          'sa fiche pour consulter le détail ; la clôture se fait avec le '
          'bouton « Clôturer ».',
    ),
    _Faq(
      question: 'Où voir les visites précédentes d\'un visiteur ?',
      reponse: 'Ouvrez le détail d\'une visite : le tableau « Historique de '
          'visite », en bas de la fiche, liste ses passages avec la date, les '
          'heures d\'arrivée et de départ, la personne visitée, le badge et la '
          'signature de sortie.',
    ),
    _Faq(
      question: 'Les photos ne s\'affichent pas hors connexion.',
      reponse: 'Les images d\'une visite déjà synchronisée sont stockées sur le '
          'serveur. Elles restent visibles hors connexion tant qu\'elles sont '
          'dans le cache du téléphone : ouvrez la fiche une fois en ligne pour '
          'les y placer.',
    ),
    _Faq(
      question: 'Que se passe-t-il si je me déconnecte avec des envois en attente ?',
      reponse: 'L\'application vous prévient. Les opérations restent stockées '
          'sur le téléphone et repartiront à la prochaine connexion du même '
          'utilisateur : ne désinstallez pas l\'application avant que la file '
          'soit vide.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.inputBg,
      appBar: AppBar(
        title: const Text('Aide'),
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _carte(
            titre: 'Enregistrer une visite',
            icone: Icons.playlist_add_check_rounded,
            enfants: [for (final e in _etapes) _ligneEtape(e)],
          ),
          const SizedBox(height: 12),
          _carte(
            titre: 'Travailler hors connexion',
            icone: Icons.cloud_off_rounded,
            enfants: const [
              _Paragraphe(
                  'L\'application garde une copie locale des visites et des '
                  'listes. Vous pouvez donc consulter le tableau de bord, '
                  'ouvrir les listes et enregistrer de nouvelles visites même '
                  'sans réseau.'),
              _Paragraphe(
                  'Chaque saisie faite hors connexion est mise en file '
                  'd\'attente, puis envoyée automatiquement au retour du '
                  'réseau. Rien n\'est perdu si vous fermez l\'application.'),
              _Paragraphe(
                  'Le bandeau orange du tableau de bord indique l\'état : '
                  '« Mode hors connexion - données en local » quand il n\'y a '
                  'rien à envoyer, sinon le nombre de visites en attente.'),
            ],
          ),
          const SizedBox(height: 12),
          _carte(
            titre: 'Questions fréquentes',
            icone: Icons.help_outline_rounded,
            enfants: [for (final f in _faq) _ligneFaq(f)],
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('${AppInfo.nom} — version ${AppInfo.version}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _carte({
    required String titre,
    required IconData icone,
    required List<Widget> enfants,
    EdgeInsets padding = const EdgeInsets.fromLTRB(16, 4, 16, 14),
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icone, size: 18, color: AppColors.ikaBlue),
                const SizedBox(width: 8),
                Text(titre,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(padding: padding, child: Column(children: enfants)),
        ],
      ),
    );
  }

  Widget _ligneEtape(_Etape e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.blueSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text('${e.numero}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ikaBlue)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.titre,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 3),
                Text(e.detail,
                    style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligneFaq(_Faq f) {
    return Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: AppColors.ikaBlue,
        title: Text(f.question,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text)),
        children: [
          Text(f.reponse,
              style: const TextStyle(
                  fontSize: 12.5, height: 1.45, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _Paragraphe extends StatelessWidget {
  final String texte;
  const _Paragraphe(this.texte);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(texte,
          style: const TextStyle(
              fontSize: 12.5, height: 1.45, color: AppColors.textMuted)),
    );
  }
}

class _Etape {
  final int numero;
  final String titre;
  final String detail;
  const _Etape({required this.numero, required this.titre, required this.detail});
}

class _Faq {
  final String question;
  final String reponse;
  const _Faq({required this.question, required this.reponse});
}
