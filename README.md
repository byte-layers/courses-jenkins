# courses-jenkins

Les contenus Jenkins de byte_layers. Un dossier par contenu, à plat.

**`jenkins-java-pipeline`** : le lab « Un pipeline Jenkins complet pour une application Java ». Un contenu autonome, de niveau intermédiaire, sur Spring PetClinic : une stack Jenkins préconfigurée par JCasC (deux agents, Gitea, Reposilite et un registre), et un `Jenkinsfile` construit chapitre par chapitre (stash, contrôles de sécurité en parallèle, publication depuis `main`, image, SBOM, matrice de versions de Java).

- `.layers/` : le lab ;
- `stack/` : la stack que l'apprenant télécharge, avec deux `# TODO` dans `jenkins/casc/jenkins.yaml` ;
- `solution/` : la stack complète et le `Jenkinsfile` de fin de chaque chapitre.

Le lab télécharge `stack/` depuis le tag `jenkins-java-pipeline/vN` de ce dépôt. Les objets sont préfixés `layers-jenkins`, les fichiers vont dans `~/byte-layers/jenkins/pipeline`, et les ports sont `28500`, `28530`, `28540` et `28550`.

Licence : CC BY-NC-SA 4.0.
