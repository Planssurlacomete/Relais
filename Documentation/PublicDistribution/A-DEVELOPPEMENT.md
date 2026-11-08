# A. Relais 1.0.2 build 5 — mode réduit et icônes

## Fonctionnement de la version

Le bouton **−** transforme désormais le panneau en une pastille de **148 × 36 points**, avec l’icône, le nom Relais et un contrôle d’agrandissement au premier clic. Le titre conserve sa zone de déplacement distincte. La pastille ne présente ni projets, ni interrupteurs, ni notes. **Masquer Relais**, dans le menu, reste une action séparée qui fait disparaître la fenêtre ; **Afficher Relais** retrouve le mode mémorisé.

Le même `NSPanel`, la même vue racine et le même gestionnaire d’annulation sont conservés. Il n’y a ni nouvelle fenêtre de panneau, ni timer permanent, ni rechargement du magasin de projets. Les brouillons de notes restent en mémoire pendant une réduction/restauration. Le mode réduit abandonne le focus clavier et la restauration ne demande pas d’activation.

Au premier passage, les deux modes partagent un bord supérieur gauche cohérent. Ensuite chacun retrouve son dernier emplacement. Le mode complet reprend sa hauteur naturelle, avec ancrage supérieur lors des changements de contenu et plafonnement à l’écran disponible. La récupération hors écran reste active.

## Identité graphique

Une géométrie vectorielle native commune, le rail horizontal et le levier à droite, sert à l’icône de l’application, au panneau complet, à la pastille et à la barre de menus. L’AppIcon régénérée est identique octet pour octet à la précédente. La barre de menus utilise un template monochrome de 18 points ; les variantes de panneau gardent le rail bleu. Les proportions sont conservées et le rendu Retina est vérifié.

## Données et compatibilité

Le schéma 4 ajoute le mode et une position de pastille distincte de la position complète existante. Les schémas 1, 2 et 3 migrent en mode complet, avec conservation des projets, identifiants, ordre, états, libellés, notes, épingles, préférences et marqueur de configuration. Une ancienne installation vide reste configurée. Les préférences récupérables endommagées sont isolées avec copie exacte de l’original avant modification ; les données globalement illisibles restent protégées.

La première ouverture universelle reste en place : deux noms choisis librement, champs initialement vides, validation Unicode et sauvegarde atomique avant le panneau. Le lancement automatique n’est pas reconfiguré par les transitions de mode. Pour revenir à une ancienne version, sauvegarder les données récentes puis restaurer ensemble le bundle antérieur et son état correspondant ; les anciens exécutables peuvent refuser le schéma 4.

## Tests exécutés

| Domaine | Résultat |
| --- | --- |
| Modèle, notes, première configuration et migrations | 316 assertions réussies, dont 96 nouvelles sur les modes et positions |
| Fenêtres réelles et commandes de menu | 47 contrôles AppKit réussis ; 12 cycles de mode, visibilité distincte, session et annulation conservées |
| Géométrie du vrai contrôleur | 36 assertions réussies ; 20 cycles, positions indépendantes, notes, récupération hors écran simulée et stabilité après vidage de la file principale |
| Icônes natives | 18 assertions réussies : template, transparence, proportions, Retina, Aqua et Dark Aqua |
| Confinement et permissions | 11 contrôles de migration/sandbox réussis sur identité synthétique |
| Garde de confidentialité | 14 tests réutilisables réussis ; sources et artefacts soumis aux contrôles décrits dans le rapport B |

Tous ces tests utilisent des données fictives et des emplacements isolés. Les changements de taille de la vue native ne sont pas laissés à d’anciens minima de la vue complète : le contrôleur pilote les deux dimensions.

## Contrôles graphiques et limites réelles

| Scénario demandé | Vérification réellement effectuée |
| --- | --- |
| Réduire et restaurer | Clic sur − puis sur l’agrandissement, pastille et panneau observés à l’écran |
| Répéter les cycles | Cycles AppKit/géométrie et plusieurs transitions à l’écran, sans changement des projets enregistrés |
| Déplacer la pastille à la souris | Deux tentatives de l’outil graphique non concluantes ; geste AppKit en place, validation manuelle restante |
| Conserver les positions | Écritures, positions séparées et relecture testées ; déplacement par API et récupération simulée |
| Redémarrer réduit | Redémarrage réel sur stockage fictif : pastille retrouvée, puis notes et épingle restaurées |
| Changer de Space | Flags de présence conservés et testés ; changement réel de Space non exécuté |
| Travailler dans une autre application | Une autre application est restée au premier plan avant/après réduction et restauration, vérifié en lecture seule ; pas de test imposant un changement d’application précis |
| Masquer et réafficher | Véritables handlers de menu exécutés dans le test AppKit ; masquage complet et mode choisi conservés |
| Écran externe | Écrans disponibles pris en compte ; déconnexion physique non exécutée |
| Plusieurs notes | Trois notes fictives, dont une épinglée, retrouvées avec leurs identifiants et contenus après restauration et redémarrage |
| Comparer les icônes | Aperçu natif et vues du panneau/pastille observés ; géométrie unique et AppIcon inchangée vérifiées |
| Clair et sombre | Rendus natifs Aqua/Dark Aqua et contraste contrôlés ; réglage global macOS non modifié |
| Migration et ancien utilisateur | Schémas 1/2/3, installation vide et non-réapparition de la configuration couverts |

Les interrupteurs et leurs animations ne sont pas modifiés. Les validations antérieures de l’utilisateur sur Entrée, Échap et Cmd+Z restent distinctes des tests nouveaux. Les gestes physiques d’écran, le plein écran, Stage Manager, VoiceOver et l’exécution sur macOS 14 restent à valider.

## Compilation et distribution

Version 1.0.2 build 5, cible Apple Silicon/macOS 14 minimum. Compilation optimisée et signature ad hoc, avec App Sandbox et Hardened Runtime. Le bundle de distribution est inspecté séparément des données utilisateur. Les contrôles graphiques utilisent une compilation de test avec une identité de conteneur distincte, sans manifeste de migration de production ; les changements de lancement automatique sont bloqués dans ce build.

L’application distribuée est disponible dans la [release v1.0.2](https://github.com/Planssurlacomete/Relais/releases/tag/v1.0.2). Les [conditions de distribution](C-PUBLICATION.md) détaillent la signature, les fichiers fournis et l’attribution du composant tiers. Les tests et le packaging n’utilisent aucune donnée de l’installation personnelle des utilisateurs.
