---
title: "Compiler et tester dans un conteneur Maven, sur un agent"
description: "Écrire le Jenkinsfile, comprendre docker.image().inside et les réglages Maven, pousser, et lire le premier build"
---

Les agents ne contiennent ni Java ni Maven, seulement la CLI Docker. C'est voulu : chaque stage lancera l'outil dont il a besoin dans un conteneur, dans la version exacte que le `Jenkinsfile` demande. Changer de version de Maven ou de Java devient une modification du `Jenkinsfile`, et non une intervention sur les agents.

## Ce que fait chaque morceau du premier Jenkinsfile

Le premier `Jenkinsfile` a un seul stage. Voici sa forme, avant le détail :

```groovy
pipeline {
  agent { label 'maven' }                    // sur un agent qui porte le label maven
  environment { ... }                         // des variables pour tout le pipeline
  stages {
    stage('Compiler et tester') {
      steps {
        script {
          docker.image(...).inside(...) {     // dans un conteneur Maven
            configFileProvider(...) {         // avec les réglages Maven fournis par Jenkins
              sh 'mvn ... package'            // compiler, tester, produire le JAR
            }
          }
        }
      }
      post { always { junit '...' } }         // publier les résultats des tests, même en cas d'échec
    }
  }
}
```

Les trois sections qui suivent expliquent les morceaux nouveaux : le conteneur, les réglages Maven, et l'endroit où Maven range ses dépendances.

## Lancer Maven dans un conteneur avec `docker.image().inside`

Le plugin Docker Pipeline ajoute l'objet `docker` au `Jenkinsfile`. L'étape `docker.image('maven:…').inside { … }` démarre un conteneur de cette image, exécute dans ce conteneur toutes les étapes `sh` du bloc, puis le supprime.

| Ce que fait `inside` | Pourquoi |
|---|---|
| il monte le **workspace** dans le conteneur, au même chemin | Maven lit le code et écrit le JAR dans le workspace de l'agent |
| il lance le conteneur avec l'utilisateur de l'agent (`-u 1000:1000`) | les fichiers produits appartiennent à l'agent, qui pourra les relire et les supprimer |
| il remplace la commande de l'image par `cat` | le conteneur reste vivant, en attente, le temps d'exécuter les étapes du bloc |

L'agent tourne lui-même dans un conteneur. `inside` le détecte, et monte le workspace avec `--volumes-from` : le conteneur Maven reçoit les volumes de l'agent, et voit donc les mêmes fichiers. Vous le lirez dans le journal du build, sur une ligne `agent1 seems to be running inside container …`.

Le conteneur Maven démarre par défaut sur le réseau `bridge` de Docker, où les services de la stack sont introuvables. L'argument `--network layers-jenkins` le place sur le réseau de la stack, où Reposilite répond au nom `reposilite`. La section suivante dit pourquoi Maven en a besoin.

> 📖 [Utiliser Docker dans un pipeline](https://www.jenkins.io/doc/book/pipeline/docker/) · [Le plugin Docker Pipeline](https://plugins.jenkins.io/docker-workflow/)

## Les réglages Maven fournis par Jenkins

Pour compiler PetClinic, Maven télécharge plusieurs centaines de dépendances depuis **Maven Central**, le dépôt public des bibliothèques Java. Dans une entreprise, on ne laisse pas chaque build aller sur internet : le gestionnaire d'artefacts sert de **proxy**. Il télécharge chaque dépendance une seule fois, la garde, et la resservira aux builds suivants, même si Maven Central est indisponible.

Dans la stack, c'est le rôle du dépôt `releases` de Reposilite, configuré dans [`stack/reposilite/configuration.shared.json`](../../stack/reposilite/configuration.shared.json) avec Maven Central en amont. Il faut encore le dire à Maven, et c'est le rôle d'un fichier `settings.xml`. Celui-ci est déclaré dans `jenkins.yaml`, comme un **fichier géré** (*managed file*) du plugin Config File Provider :

```yaml
          id: maven-settings
          content: |
            <settings>
              <mirrors>
                <mirror>
                  <id>reposilite</id>
                  <mirrorOf>central</mirrorOf>
                  <url>http://reposilite:8080/releases</url>
                </mirror>
              </mirrors>
            </settings>
```

Un **miroir** (`mirror`) remplace un dépôt par un autre : `mirrorOf central` envoie vers Reposilite toutes les requêtes destinées à Maven Central. Dans le `Jenkinsfile`, l'étape `configFileProvider` écrit ce fichier dans un emplacement temporaire, et met son chemin dans la variable `MAVEN_SETTINGS`. L'option `-s "$MAVEN_SETTINGS"` de Maven le lit.

> 📖 [Le plugin Config File Provider](https://plugins.jenkins.io/config-file-provider/) · [Les miroirs dans Maven](https://maven.apache.org/guides/mini/guide-mirror-settings.html)

## Ranger le dépôt Maven local hors du workspace

Maven garde les dépendances téléchargées dans un dossier, le **dépôt local**, `~/.m2/repository` par défaut. Dans le conteneur, l'utilisateur 1000 n'a pas de dossier personnel utilisable. On choisit donc l'emplacement avec l'option `-Dmaven.repo.local`.

⚠️ **Piège — le dépôt local dans le workspace fait échouer le build.**
- *Symptôme :* le build s'arrête sur `There are 1634 errors reported by Checkstyle … with src/checkstyle/nohttp-checkstyle.xml ruleset`, suivi de lignes `NoHttp: http:// URLs are not allowed` dans des fichiers `.m2/org/…/*.pom`.
- *Cause :* PetClinic lance un contrôle, **nohttp**, qui refuse toute adresse en `http://` dans **tout le dossier du projet**. Avec un dépôt local dans le workspace, il lit aussi les fichiers des dépendances téléchargées, dont beaucoup contiennent de telles adresses.
- *Correctif :* ranger le dépôt local hors du workspace. Les agents ont un volume partagé, `caches`, monté sur `/home/jenkins/caches`. Le conteneur Maven le reçoit aussi, grâce à `--volumes-from`. Le `Jenkinsfile` utilise `/home/jenkins/caches/m2`, et les deux agents partagent ainsi le même cache.

⚖️ Un dépôt Maven local n'est pas fait pour être écrit par plusieurs builds à la fois : deux téléchargements simultanés du même fichier peuvent, rarement, le corrompre. Pour un lab, ce cache commun reste un bon compromis. En entreprise, on donne souvent un dépôt local à chaque exécuteur, et c'est le proxy du gestionnaire d'artefacts qui sert de cache partagé.

## Écrire le Jenkinsfile

Le tableau suivant détaille les options de la commande Maven, puis vous complétez le fichier :

| Option | Rôle |
|---|---|
| `mvn -B` | le mode non interactif, celui d'une CI : pas de couleurs ni de barres de progression dans le journal |
| `-s "$MAVEN_SETTINGS"` | les réglages fournis par `configFileProvider` |
| `-Dmaven.repo.local=$M2_REPO` | le dépôt local, hors du workspace |
| `package` | compiler, lancer les tests unitaires, et produire le JAR dans `target/`. Si un test échoue, Maven s'arrête et l'étape échoue |

Maven avance par **phases**, dans un ordre fixe : `validate`, `compile`, `test`, `package`, `verify`, `install`, `deploy`. Demander une phase exécute toutes celles qui la précèdent : `package` compile, teste, puis produit le JAR.

Les tests écrivent leurs résultats dans `target/surefire-reports/*.xml`, au format JUnit. L'étape `junit` les lit, et Jenkins affiche alors le nombre de tests et le détail de chaque échec. On la place dans `post { always { … } }`, pour qu'elle publie les résultats **même quand un test échoue**, ce qui est justement le cas où on veut les lire.

Créez le fichier de départ à la racine de votre copie de PetClinic :

```exec "Créer le Jenkinsfile de départ"
cat > ~/byte-layers/jenkins/pipeline/petclinic/Jenkinsfile <<'EOF'
// spring-petclinic : compiler et tester dans un conteneur Maven, sur un agent

pipeline {
  // TODO : un agent qui porte le label maven

  environment {
    MAVEN_IMAGE = 'maven:3.9.16-eclipse-temurin-21-noble'
    NETWORK     = 'layers-jenkins'              // le réseau de la stack : reposilite et registry y sont joignables
    M2_REPO     = '/home/jenkins/caches/m2'     // hors du workspace, que le checkstyle de petclinic analyse
  }

  stages {
    stage('Compiler et tester') {
      steps {
        script {
          // TODO : un conteneur de l'image MAVEN_IMAGE, sur le réseau NETWORK : docker.image(...).inside("--network ...") { ... }
            configFileProvider([configFile(fileId: 'maven-settings', variable: 'MAVEN_SETTINGS')]) {
              // TODO : mvn en mode non interactif, avec les réglages MAVEN_SETTINGS, le dépôt local M2_REPO, et la phase package
            }
          // TODO : fermer le bloc inside
        }
      }
      post {
        // TODO : toujours, publier les résultats des tests de target/surefire-reports/*.xml
      }
    }
  }
}
EOF
```

Complétez les cinq `// TODO` dans votre éditeur. Deux détails de syntaxe comptent :

- `docker.image(env.MAVEN_IMAGE)` s'écrit sans guillemets : `env.MAVEN_IMAGE` est une variable, et `'MAVEN_IMAGE'` entre guillemets désignerait une image qui porte ce nom ;
- dans `inside("--network ${env.NETWORK}")`, les guillemets doubles permettent à Groovy de remplacer `${env.NETWORK}` par sa valeur ;
- dans `sh 'mvn … $M2_REPO …'`, les guillemets simples laissent `$M2_REPO` intact : c'est le shell de l'agent qui le remplace, puisque Jenkins exporte chaque variable d'`environment` dans l'environnement des étapes `sh`.

> 📖 [La syntaxe des pipelines déclaratifs](https://www.jenkins.io/doc/book/pipeline/syntax/) · [L'étape `junit`](https://www.jenkins.io/doc/pipeline/steps/junit/) · [L'image `maven`](https://hub.docker.com/_/maven)

## Pousser, et suivre le premier build

💡 **Valider avant de pousser.** Chaque faute de frappe coûte un commit, un push et un build. Jenkins sait vérifier la syntaxe d'un `Jenkinsfile` déclaratif sans le lancer, par son adresse `/pipeline-model-converter/validate`. Le premier `curl` demande un jeton anti-CSRF (le *crumb*) et garde le cookie de session dans `~/byte-layers/jenkins/pipeline/cookies`, le second envoie le fichier :

```bash
cd ~/byte-layers/jenkins/pipeline/petclinic && P=$(cat ../stack/secrets/jenkins_admin_password) && C=$(curl -s -c ../cookies -u admin:$P 'http://localhost:28500/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,":",//crumb)') && curl -s -b ../cookies -u admin:$P -H "$C" -F "jenkinsfile=<Jenkinsfile" http://localhost:28500/pipeline-model-converter/validate
```

Il répond `Jenkinsfile successfully validated.`, ou la ligne et la nature de l'erreur. Il ne vérifie que la syntaxe : une image mal nommée ne se verra qu'au build.

Committez le `Jenkinsfile` et poussez-le dans Gitea :

```exec "Committer et pousser le Jenkinsfile"
cd ~/byte-layers/jenkins/pipeline/petclinic && git add Jenkinsfile && git commit -m "Add the Jenkins pipeline" && git push
```

Le webhook prévient Jenkins dans la seconde. Ouvrez le job `spring-petclinic` : un sous-job `main` est apparu, et son premier build démarre. Ouvrez ce build, puis **Pipeline Overview** pour la vue graphique, ou **Console Output** pour le journal complet.

Le premier build dure trois à cinq minutes : l'agent télécharge l'image Maven, puis Maven télécharge les dépendances au travers de Reposilite. Les lignes `Downloading from reposilite: http://reposilite:8080/releases/…` du journal montrent le miroir au travail. Vers la fin, Maven résume les tests :

```
[INFO] Tests run: 79, Failures: 0, Errors: 0, Skipped: 2
[INFO] BUILD SUCCESS
```

Les deux tests sautés ont besoin de lancer eux-mêmes une base MySQL dans Docker (avec la bibliothèque Testcontainers), ce que le conteneur Maven n'a pas le droit de faire ici. Le build se termine par `Finished: SUCCESS`, et la page du build affiche **Test Result** : 77 tests réussis et 2 sautés.

```verify
D="$HOME/byte-layers/jenkins/pipeline/petclinic"
P=$(cat "$HOME/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password" 2>/dev/null)
J="http://localhost:28500/job/petclinic/job/main"
if ! git -C "$D" ls-tree --name-only origin/main 2>/dev/null | grep -qx Jenkinsfile; then
  echo "Le Jenkinsfile n'est pas poussé sur la branche main de Gitea. Committez-le, puis lancez git push."
  exit 1
fi
R=$(curl -fsS -u "admin:$P" "$J/lastBuild/api/json?tree=result,building" 2>/dev/null) || { echo "Le sous-job main n'existe pas encore. Attendez quelques secondes, ou lancez Scan Multibranch Pipeline Now."; exit 1; }
if echo "$R" | grep -q '"building":true'; then
  echo "Le build est en cours : attendez qu'il se termine, puis vérifiez à nouveau."
  exit 1
fi
if ! echo "$R" | grep -q '"result":"SUCCESS"'; then
  echo "Le dernier build de main n'a pas réussi. Lisez la fin de son Console Output."
  exit 1
fi
T=$(curl -fsS -u "admin:$P" "$J/lastBuild/testReport/api/json?tree=passCount" 2>/dev/null | grep -o '"passCount":[0-9]*' | cut -d: -f2)
if [ -z "$T" ] || [ "$T" -eq 0 ]; then
  echo "Le build a réussi, mais aucun résultat de test n'est publié : l'étape junit manque dans post { always { … } }."
  exit 1
fi
echo "Le build de main a réussi, et $T tests sont publiés."
```

```hint
Si le build échoue sur `No such DSL method 'inside'` ou `groovy.lang.MissingPropertyException`, vérifiez que `docker.image(...)` est bien dans le bloc `script { … }` : la syntaxe déclarative n'accepte cet objet que dans un bloc `script`.
```

```hint
Si le build échoue avec `Could not transfer artifact` ou `Unknown host reposilite`, l'argument `--network` manque à `inside`, ou le nom du réseau est mal écrit : il doit valoir `layers-jenkins`.
```

````solution
```groovy
pipeline {
  agent { label 'maven' }

  environment {
    MAVEN_IMAGE = 'maven:3.9.16-eclipse-temurin-21-noble'
    NETWORK     = 'layers-jenkins'
    M2_REPO     = '/home/jenkins/caches/m2'
  }

  stages {
    stage('Compiler et tester') {
      steps {
        script {
          docker.image(env.MAVEN_IMAGE).inside("--network ${env.NETWORK}") {
            configFileProvider([configFile(fileId: 'maven-settings', variable: 'MAVEN_SETTINGS')]) {
              sh 'mvn -B -s "$MAVEN_SETTINGS" -Dmaven.repo.local=$M2_REPO package'
            }
          }
        }
      }
      post {
        always { junit 'target/surefire-reports/*.xml' }
      }
    }
  }
}
```
Le fichier complet est [`solution/02-first-pipeline/Jenkinsfile`](../../solution/02-first-pipeline/Jenkinsfile).
````

> **🧪 Manip — le cache du dépôt Maven**
>
> 1. Notez la durée du premier build, en haut de sa page.
> 2. Relancez-le avec **Build Now** (*Lancer un build*) sur la page du sous-job `main`.
> 3. Comparez les durées.
>
> *Observé : le premier build a duré environ 2 min 45 s, le second moins de 30 secondes. L'image Maven est déjà sur le moteur, et les dépendances sont dans `/home/jenkins/caches/m2` : Maven ne télécharge plus rien.*
