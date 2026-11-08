# C. Distribution de Relais 1.0.2 — build 5

## Version officielle

Le dépôt public de référence est [Planssurlacomete/Relais](https://github.com/Planssurlacomete/Relais). La [release v1.0.2](https://github.com/Planssurlacomete/Relais/releases/tag/v1.0.2) fournit la version **1.0.2 build 5**.

L’archive [Relais-v1.0.2-macOS-AppleSilicon.zip](https://github.com/Planssurlacomete/Relais/releases/download/v1.0.2/Relais-v1.0.2-macOS-AppleSilicon.zip) contient l’application `Relais.app`, le guide d’installation, les notes de version, les rapports publics et les notices tierces. Elle ne contient aucune donnée utilisateur ni application de test. Les sources de cette version sont accessibles depuis son tag.

## Configuration et signature

Le binaire cible **Apple Silicon, macOS 14 ou ultérieur**. Il est compilé avec les outils Apple, sans dépendance externe, avec App Sandbox et Hardened Runtime. Il porte une **signature ad hoc**, sans certificat Developer ID et sans notarisation Apple.

Cette signature n’authentifie pas l’éditeur auprès de Gatekeeper. Après vérification de la provenance de l’archive, macOS peut proposer **Réglages Système → Confidentialité et sécurité → Ouvrir quand même**. Le [guide d’installation](../../INSTALLATION.txt) détaille la première ouverture et la récupération des données lors d’une mise à jour. Gatekeeper reste activé.

Le lancement à l’ouverture de session utilise ServiceManagement. macOS peut refuser l’enregistrement d’une application signée ad hoc ; Relais conserve et affiche le statut système réel. Le parcours sur un autre Mac, le plein écran, les changements physiques de Space et la déconnexion d’un écran restent des limites de validation distinctes des contrôles automatisés.

## Intégrité des archives

`Scripts/package.sh` vérifie la signature existante et applique la liste blanche du garde de confidentialité. Les fichiers d’état, sauvegardes, journaux, attributs étendus, fichiers AppleDouble et métadonnées ZIP supplémentaires sont exclus. Le script inspecte l’archive après assemblage ; il ne signe ni ne notarise l’application.

Pour calculer l’empreinte d’une archive téléchargée :

```sh
shasum -a 256 Relais-v1.0.2-macOS-AppleSilicon.zip
```

Comparer cette empreinte à celle fournie avec la release. Les fichiers distribués et les sommes de contrôle doivent provenir du dépôt officiel.

## Licences et attributions

Le dépôt ne fournit pas de licence générale pour le code applicatif de Relais. La notice MIT présente dans [THIRD-PARTY-NOTICES.txt](../../THIRD-PARTY-NOTICES.txt) concerne le commutateur adapté de Saiyed-Tanvir, publié sur Uiverse. Cette attribution et son texte complet accompagnent les sources et les ressources de l’application.

## Données et mises à jour

Une mise à jour conserve les projets, notes, positions, libellés et préférences des installations existantes. Le schéma 4 mémorise séparément les positions complète et réduite. Les utilisateurs déjà configurés ne repassent pas par l’assistant de bienvenue.

Avant une mise à jour, quitter Relais et conserver ensemble une copie de l’application et de son fichier de données. Un retour à une ancienne version nécessite de restaurer ces deux éléments correspondants, après sauvegarde des données plus récentes. Les archives publiques ne fournissent et ne remplacent aucun fichier d’état utilisateur.

Les résultats réellement obtenus et les contrôles manuels restants sont consignés dans les [notes de version](../../RAPPORT.md) et le [rapport de développement](A-DEVELOPPEMENT.md).
