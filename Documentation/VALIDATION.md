# Validation de Relais

Les résultats de Relais 1.0.2 build 5 figurent dans le [rapport de développement](PublicDistribution/A-DEVELOPPEMENT.md). Les fichiers de `TestEvidence/` décrivent des exécutions historiques ; leurs nombres et résultats ne remplacent pas les contrôles de la version courante.

## Protocole sur données synthétiques

Tous les essais utilisent un dossier temporaire privé ou un bundle de test avec une identité distincte. Aucun test ne doit ouvrir, exporter ou modifier le fichier de production.

| Contrôle | Résultat attendu |
| --- | --- |
| Installation neuve | La fenêtre de bienvenue apparaît avec deux champs vides. Aucun projet n’est créé automatiquement. |
| Validation | Un nom manquant ou deux noms équivalents après nettoyage et comparaison sans casse empêchent la validation. Les caractères Unicode sont acceptés. |
| Première configuration | Les deux noms sont sauvegardés avant de marquer la configuration comme terminée. Le panneau permet ensuite d’ajouter Projet Alpha. |
| Redémarrage | Les noms sont conservés et l’assistant ne réapparaît pas. |
| Migration 1.0.1 et 1.0.2 | Projets, identifiants, ordre, positions, libellés, notes, épingles, préférences et fenêtre restent intacts. Une ancienne installation sans projet ne repasse pas par l’assistant. |
| Notes | Ajouter trois notes dans Projet Alpha ; modifier la deuxième ; épingler/désépingler ; supprimer une note puis l’ensemble ; vérifier Projet Bêta et la persistance. |
| Interrupteurs | Les côtés de Projet Alpha, Projet Bêta et Projet Gamma restent indépendants. Les actions sur les notes ne changent aucun côté. |
| Panneau | Vérifier le premier plan, les flags Spaces, la hauteur naturelle, le défilement et le bord supérieur. |
| Mode réduit | Réduire en pastille 148 × 36, restaurer, répéter les cycles, conserver les positions et le mode après redémarrage ; masquer/réafficher reste distinct. |
| Icônes | Même géométrie application/panneau/pastille/menu, template monochrome, Retina et rendu natif clair/sombre. |
| Erreur de sauvegarde | Les valeurs saisies restent visibles, la configuration demeure incomplète et un nouvel essai reste possible. |
| Données illisibles | Le fichier original reste intact ; aucune configuration neuve ne peut l’écraser. Une erreur de note reste isolée du reste des projets. |
| Confidentialité | Sources, fixtures, ressources, journaux publiables, bundle et archive ne contiennent que des données synthétiques. |

## Commandes de contrôle

```sh
./Scripts/test.sh
./Scripts/geometry-test.sh
./Scripts/icon-test.sh
./Scripts/window-smoke-test.sh
./Scripts/security-test.sh
python3 ./Scripts/privacy-check.py
./Scripts/build.sh ./build/Relais.app
python3 ./Scripts/privacy-check.py --app ./build/Relais.app
./Scripts/package.sh ./build/Relais.app ./build/Relais-v1.0.2-macOS-AppleSilicon.zip
python3 ./Scripts/privacy-check.py --archive ./build/Relais-v1.0.2-macOS-AppleSilicon.zip
```

Le contrôle statique est complété par un scanner spécialisé de secrets sur l’état courant et l’historique Git. Les rapports détaillés susceptibles de contenir une valeur privée restent hors du dépôt.

## Limites à consigner séparément

Les raccourcis Entrée, Échap et Cmd+Z ont été validés manuellement pendant le développement des notes de la version 1.0.2. Cette confirmation est distincte des contrôles automatisés et des essais du premier lancement.

Une compilation ciblant macOS 14 ne valide pas à elle seule l’exécution sur macOS 14. Les changements réels de Space, le plein écran, Stage Manager, VoiceOver, les écrans physiques et l’installation sur un autre Mac demandent des essais explicites. Les résultats qui n’ont pas été obtenus ne doivent pas être annoncés comme réussis.

La signature locale ad hoc, sans Developer ID ni notarisation Apple, ne valide pas le parcours de distribution signé. Le lancement à la connexion conserve son statut système réel.
