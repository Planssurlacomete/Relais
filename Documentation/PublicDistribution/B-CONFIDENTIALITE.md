# B. Confidentialité de Relais 1.0.2 build 5

## Données locales

Relais conserve les projets, notes, positions, libellés et préférences sur le Mac de l’utilisateur. L’application n’a ni compte, ni serveur, ni synchronisation, ni télémétrie. Le mode réduit ajoute seulement une préférence et une position de fenêtre locales.

Aucun état utilisateur, sauvegarde ou journal local n’est inclus dans les sources ou les archives distribuées. Une installation neuve présente des champs vides et ne crée aucun projet de démonstration. Les données présentes dans les tests et exemples sont entièrement fictives.

## Contrôles du contenu distribué

`Scripts/privacy-check.py` examine les sources, tests, documents, configurations et ressources. Il recherche des catégories de chemins personnels, adresses, secrets et fichiers utilisateur. Il peut également inspecter un bundle ou une archive et recevoir une liste complémentaire de termes depuis un fichier local exclu du dépôt. Les résultats n’affichent aucune valeur détectée ni extrait de données.

Les 14 tests du garde de confidentialité utilisent uniquement des canaries synthétiques. Un scan spécialisé Gitleaks complète ce contrôle. Les scans documentés pour cette version n’ont détecté aucun secret ; leur portée et les limites du scanner restent à prendre en compte. Les contrôles sont réexécutés sur les fichiers définitifs avant assemblage et publication.

Le packaging utilise une liste blanche exacte pour le bundle et les documents joints. Il refuse les fichiers inattendus et les liens symboliques, retire les métadonnées ZIP supplémentaires et contrôle l’archive assemblée. Le bundle public comporte les sept fichiers attendus. Le build de test utilise un autre identifiant de conteneur et ne possède pas le manifeste de migration de production ; il est contrôlé séparément.

Les icônes sont dessinées à partir d’une géométrie vectorielle publique commune. Aucune ressource personnelle n’a été importée. Les contrôles des icônes, de la sandbox, des migrations et de la conservation des données figurent dans le [rapport de développement](A-DEVELOPPEMENT.md).

## Protections permanentes

`AGENTS.md` impose des exemples fictifs, le choix libre des intervenants, la préservation des installations existantes et des contrôles avant publication. `.gitignore` exclut les fichiers d’état, sauvegardes, journaux, listes locales de contrôle et rapports détaillés de scanners.

Les exclusions Git empêchent les ajouts accidentels courants ; elles ne retirent pas un fichier déjà suivi. Les contrôles s’appliquent donc aussi aux fichiers réellement présents dans l’instantané publié. Les tests utilisent des répertoires temporaires ou une identité sandbox distincte et n’ouvrent jamais le magasin de production.

## Limites

Une absence de détection ne prouve pas l’absence de toute information confidentielle ou de toute vulnérabilité. Les clones, caches, téléchargements et copies réalisés par des tiers sont indépendants du dépôt courant ; leur effacement ne peut pas être garanti.

Le JSON local reste lisible par le compte de l’utilisateur. App Sandbox et Hardened Runtime réduisent les permissions de l’application, mais ne chiffrent pas les notes. Voir la [documentation de sécurité](../SECURITE.md) et les [conditions de distribution](C-PUBLICATION.md).
