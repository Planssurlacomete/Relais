# Relais 1.0.2 build 5 — notes de version

Le bouton **−** réduit maintenant Relais en une pastille flottante de **148 × 36 points**, avec son nom, son icône et un bouton d’agrandissement. **Masquer/Afficher** reste une commande distincte de la barre de menus. Le même panneau et la même session sont conservés ; les brouillons de notes restent présents au retour. Le mode et les positions des deux présentations sont mémorisés, avec récupération hors écran.

L’application, le panneau complet, la pastille et la barre de menus partagent une géométrie vectorielle unique de rail et de levier. L’AppIcon reste identique à la précédente ; le menu utilise un template monochrome de 18 points. Les variantes natives clair/sombre et Retina ont été contrôlées.

Les migrations des schémas 1/2/3 vers le schéma 4 préservent les données et évitent une nouvelle configuration des anciens utilisateurs. Le premier lancement universel, les interrupteurs, notes, épingles et fonctions d’annulation sont conservés.

Résultats : **316 assertions de modèle**, **47 contrôles AppKit**, **36 assertions de géométrie**, **18 contrôles d’icônes**, **11 contrôles de confinement** et **14 tests du garde de confidentialité**. À l’écran : réduction/restauration, brouillon intact, plusieurs notes conservées et redémarrage réduit ont été observés. Les fichiers et archives sont inspectés séparément du système de production.

Le déplacement à la souris par l’outil graphique n’a pas été concluant. Les changements physiques de Space, de plein écran et d’écran externe, ainsi que le réglage global clair/sombre, ne sont pas annoncés comme testés. Le détail des méthodes et limites figure dans le [rapport A](Documentation/PublicDistribution/A-DEVELOPPEMENT.md).

La [release v1.0.2](https://github.com/Planssurlacomete/Relais/releases/tag/v1.0.2) fournit l’application Apple Silicon et ses documents d’installation. La signature est ad hoc, sans Developer ID ni notarisation Apple. Les tests graphiques utilisent une application isolée ; les données utilisateur restent hors du dépôt et des archives. Voir le [rapport de confidentialité](Documentation/PublicDistribution/B-CONFIDENTIALITE.md) et les [conditions de distribution](Documentation/PublicDistribution/C-PUBLICATION.md). Aucune licence générale du code applicatif n’est fournie ; la notice MIT du composant tiers est conservée.
