# Sécurité de Relais

Relais reste une application native sans dépendance externe, minuteur périodique, compte, serveur ni télémétrie. Ces protections n’ajoutent aucun service en arrière-plan.

## Protections appliquées

- **App Sandbox** : le seul entitlement distribué est `com.apple.security.app-sandbox = true`. Aucune permission réseau, caméra, microphone, automatisation, fichiers sélectionnés ou exception sur le dossier personnel n’est ajoutée. Le lien d’attribution ouvre le navigateur uniquement sur votre clic.
- **Hardened Runtime** : activé dans le projet Xcode et dans la signature du script de compilation, sans exception JIT, injection de bibliothèques ou débogage.
- **Chargement borné** : fichier JSON de 2 Mio maximum, 500 projets, noms de 1 024 octets et libellés de 512 octets maximum en UTF-8. Un état dépassant ces limites reste intact et bloque les modifications ; il n’est pas tronqué.
- **Sauvegarde locale** : dossier privé, fichiers privés, remplacement atomique et publication d’une modification seulement après sauvegarde réussie. Un fichier illisible, trop volumineux ou de format futur est préservé et ne peut pas être remplacé par une configuration neuve. Une erreur limitée aux notes préserve le reste des projets et une copie exacte de l’original avant récupération.
- **Premier lancement** : les deux noms sont choisis librement dans des champs vides. La configuration n’est marquée comme terminée qu’après sauvegarde réussie. Une installation existante valide reste configurée, même sans projet ; ses libellés sont conservés. Les changements de taille et visibilité ne doivent pas configurer une installation neuve prématurément.
- **Interface de test séparée** : les arguments de test et le code de test de fenêtre sont absents de la compilation distribuée. L’application publique refuse les options longues de ligne de commande avant d’ouvrir son magasin.

Les données sont du JSON en clair, accessibles à votre compte : Relais n’est pas un coffre de mots de passe. La sandbox limite les conséquences possibles d’une compromission ; elle ne constitue pas une garantie d’absence de faille.

## Publications et tests

Les fixtures sont synthétiques. Les tests utilisent des dossiers temporaires ou des identités sandbox distinctes et ne doivent jamais lire le magasin de production. `.gitignore` exclut les états, sauvegardes et journaux locaux. Ces exclusions ne retirent pas des fichiers déjà suivis et ne nettoient pas l’historique.

`Scripts/privacy-check.py` contrôle l’état courant des sources, fixtures, configurations, ressources et documents. Il peut aussi inspecter un bundle ou une archive et utiliser une liste de termes interdits conservée uniquement en local. Il ne rapporte jamais les valeurs détectées. Le packaging applique une liste blanche et refuse les fichiers inattendus. Les archives n’embarquent ni dossiers personnels, ni état utilisateur, ni journaux de développement.

Un outil spécialisé de recherche de secrets complète le contrôle statique, y compris sur les références Git accessibles. Les résultats détaillés restent hors du dépôt ; seuls les nombres et catégories anonymisés sont publiables. Aucun de ces contrôles ne garantit l’effacement des caches, clones ou copies tierces. Voir le [rapport de confidentialité](PublicDistribution/B-CONFIDENTIALITE.md) et les [conditions de distribution](PublicDistribution/C-PUBLICATION.md).

## Mise à jour depuis 1.0.0

1. Quittez Relais et gardez une copie de `~/Library/Application Support/Relais/state.json` avant de remplacer l’application.
2. Installez la nouvelle application et ouvrez-la. Le manifeste `container-migration.plist` demande à macOS de déplacer ce seul fichier vers le dossier protégé, à la création initiale du conteneur.
3. Vérifiez vos projets avant de les modifier.

Le nouvel emplacement est :

```text
~/Library/Containers/org.relaisapp.Relais/Data/Library/Application Support/Relais/state.json
```

Si vos projets ne réapparaissent pas, quittez Relais. Conservez également une copie du fichier de destination s’il existe, puis copiez votre ancien `state.json` dans ce dossier. Relancez Relais. **Ne supprimez pas le conteneur pour relancer la migration**, qui ne s’exécute qu’à sa création. Cette récupération manuelle évite de donner à l’application un accès permanent au dossier personnel.

Depuis macOS 14, l’identité du conteneur dépend aussi de la signature. Une mise à jour signée ad hoc peut provoquer une demande native d’accès au conteneur existant. Vérifiez qu’elle concerne la copie de Relais que vous venez d’installer.

## Signature et validation

La signature fournie est **ad hoc**, sans certificat Developer ID ni notarisation Apple. Hardened Runtime et App Sandbox sont activés ; ils n’authentifient pas l’éditeur. Le parcours Gatekeeper sur un autre Mac et le lancement à l’ouverture de session restent à vérifier avec une signature de distribution appropriée.

Les scripts `test.sh`, `window-smoke-test.sh`, `geometry-test.sh` et `security-test.sh` vérifient le modèle, la persistance, le panneau et les restrictions effectives dans une identité de test distincte. Les résultats réellement obtenus figurent dans [VALIDATION.md](VALIDATION.md).

Références Apple : [configuration App Sandbox](https://help.apple.com/xcode/mac/current/en.lproj/devbd04af149.html), [migration du fichier vers le conteneur](https://developer.apple.com/documentation/security/migrating-your-app-s-files-to-its-app-sandbox-container), [accès au conteneur et identité de signature](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime).
