---
title: "Le bloc matrix : un axe, trois cellules, une condition"
description: "axes, axis et values, la variable de l'axe dans le stage, la condition sur main et les pull requests, et un exemple à deux axes avec exclusion"
---

Le `pom.xml` de PetClinic demande Java 17 au minimum, et le pipeline compile avec Java 21. Mais une application vit plusieurs années : elle tournera un jour sur la prochaine version maintenue à long terme (**LTS**), Java 25. Le pipeline peut vérifier dès aujourd'hui qu'elle compile et passe ses tests sur chacune des trois.

## Pourquoi une matrice plutôt que trois stages

On pourrait écrire trois stages presque identiques, qui ne diffèrent que par l'image Maven. Le bloc `matrix` évite cette répétition : il décrit un stage **une seule fois**, et les **axes** de variation. Jenkins en déduit une **cellule** par combinaison de valeurs, et lance les cellules en parallèle.

```groovy
stage('Compatibilité Java') {
  matrix {
    axes {
      axis {
        name 'JDK'                     // le nom de l'axe, qui devient une variable
        values '17', '21', '25'        // une cellule par valeur
      }
    }
    agent { label 'maven' }            // chaque cellule obtient son propre agent
    stages {
      stage('Compiler et tester') {
        steps { ... }                  // la variable JDK vaut '17', '21' ou '25'
      }
    }
  }
}
```

| Élément | Rôle |
|---|---|
| `axes` | la liste des axes de variation |
| `axis { name … values … }` | un axe : son nom, et ses valeurs |
| `agent` | l'agent de chaque cellule, choisi comme pour une branche de `parallel` |
| `stages` | ce que chaque cellule exécute |

Dans chaque cellule, l'axe devient une variable d'environnement du même nom : `env.JDK` vaut `'17'`, `'21'` ou `'25'`. L'image Maven se déduit de cette valeur, puisque les tags officiels suivent tous la même forme : `maven:3.9.16-eclipse-temurin-17-noble`, `…-21-noble`, `…-25-noble`.

⚠️ **Piège — dans un bloc `script`, écrivez `${env.JDK}`.**
- *Symptôme :* les trois cellules échouent sur `Tag must follow the pattern '^:[a-zA-Z0-9_]([a-zA-Z0-9_.-]){0,127}'`.
- *Cause :* une valeur d'axe est une variable d'**environnement** de la cellule, et non une variable Groovy. Dans le code Groovy d'un bloc `script`, `${JDK}` ne l'a pas trouvée lors de nos essais, et le nom de l'image est devenu invalide. Le moyen sûr de lire une variable d'environnement en Groovy est l'objet `env`.
- *Correctif :* passer par l'objet `env`, qui contient les variables d'environnement de la cellule : `"maven:3.9.16-eclipse-temurin-${env.JDK}-noble"`.

> 📖 [La directive `matrix`](https://www.jenkins.io/doc/book/pipeline/syntax/#declarative-matrix) · [Les tags de l'image `maven`](https://hub.docker.com/_/maven/tags)

## Quand lancer la matrice

Trois compilations complètes coûtent du temps et de la mémoire : environ 1 Go par conteneur Maven, trois à la fois. On ne les lance pas sur chaque push d'une branche de travail, mais sur ce qui compte : `main`, et les pull requests, avant la fusion. La condition `anyOf` est vraie dès que l'une de ses conditions l'est, et `changeRequest()` est vraie pour un build de pull request :

```groovy
when { beforeAgent true; anyOf { branch 'main'; changeRequest() } }
```

Comme pour la publication, `beforeAgent true` évite d'attribuer un agent à un stage qui sera sauté.

## Ajouter la matrice

Collez ce stage après `SBOM et scan de l'image`, juste avant l'accolade qui ferme le bloc `stages`, et complétez ses `// TODO` :

```groovy
    stage('Compatibilité Java') {
      // TODO : sur main, ou sur une pull request, condition évaluée avant d'attribuer l'agent
      matrix {
        axes {
          // TODO : un axe JDK, avec les valeurs 17, 21 et 25
        }
        agent { label 'maven' }
        stages {
          stage('Compiler et tester') {
            steps {
              fresh 'sources'
              script {
                // TODO : l'image maven:3.9.16-eclipse-temurin-<valeur de l'axe>-noble, sur le réseau de la stack
                  configFileProvider([configFile(fileId: 'maven-settings', variable: 'MAVEN_SETTINGS')]) {
                    sh 'mvn -B -s "$MAVEN_SETTINGS" -Dmaven.repo.local=$M2_REPO verify'
                  }
                // TODO : fermer le bloc inside
              }
            }
          }
        }
      }
    }
```

La commande Maven utilise la phase `verify` au lieu de `package` : elle va un cran plus loin dans les phases de Maven. Pour PetClinic, elle ajoute le rapport de couverture de code de JaCoCo (`jacoco:report`) ; c'est surtout la phase d'usage pour « tout vérifier sans rien livrer ». Le JAR produit par chaque cellule n'est ni gardé ni publié : la matrice vérifie la compatibilité, elle ne livre rien.

Committez et poussez :

```exec "Committer et pousser"
cd ~/byte-layers/jenkins/pipeline/petclinic && git commit -am "Test three Java versions with a matrix" && git push
```

## Lire les trois cellules

Dans **Pipeline Overview**, le stage `Compatibilité Java` s'ouvre sur trois cellules, `JDK = '17'`, `JDK = '21'` et `JDK = '25'`, qui avancent ensemble sur les deux agents. Chacune se termine par le même résumé :

```
[INFO] Tests run: 79, Failures: 0, Errors: 0, Skipped: 2
[INFO] BUILD SUCCESS
```

PetClinic passe ses tests sur les trois versions. Le build reste jaune, `UNSTABLE`, à cause des vulnérabilités critiques que grype a trouvées : la matrice ne change rien à ce statut.

```verify
P=$(cat "$HOME/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password" 2>/dev/null)
J="http://localhost:28500/job/petclinic/job/main"
R=$(curl -fsS -u "admin:$P" "$J/lastBuild/api/json?tree=result,building")
if echo "$R" | grep -q '"building":true'; then echo "Le build est en cours : attendez qu'il se termine."; exit 1; fi
C=$(curl -fsS -u "admin:$P" "$J/lastBuild/consoleText")
for v in 17 21 25; do
  if ! echo "$C" | grep -q "{ (Matrix - JDK = '$v')"; then
    echo "La cellule JDK = '$v' n'apparaît pas dans le dernier build de main : vérifiez l'axe JDK et la condition when."
    exit 1
  fi
done
if echo "$R" | grep -q '"result":"FAILURE"'; then
  echo "Le dernier build de main a échoué. Ouvrez la cellule en rouge dans Pipeline Overview."
  exit 1
fi
N=$(echo "$C" | grep -c "Tests run: 79, Failures: 0, Errors: 0")
if [ "$N" -lt 4 ]; then
  echo "Les tests ne passent pas dans toutes les cellules : lisez leur journal."
  exit 1
fi
echo "PetClinic compile et passe ses tests sur Java 17, 21 et 25."
```

````solution
```groovy
    stage('Compatibilité Java') {
      when { beforeAgent true; anyOf { branch 'main'; changeRequest() } }
      matrix {
        axes {
          axis {
            name 'JDK'
            values '17', '21', '25'
          }
        }
        agent { label 'maven' }
        stages {
          stage('Compiler et tester') {
            steps {
              fresh 'sources'
              script {
                docker.image("maven:3.9.16-eclipse-temurin-${env.JDK}-noble").inside("--network ${env.NETWORK}") {
                  configFileProvider([configFile(fileId: 'maven-settings', variable: 'MAVEN_SETTINGS')]) {
                    sh 'mvn -B -s "$MAVEN_SETTINGS" -Dmaven.repo.local=$M2_REPO verify'
                  }
                }
              }
            }
          }
        }
      }
    }
```
Le fichier complet, le pipeline final du lab, est [`solution/09-matrix/Jenkinsfile`](../../solution/09-matrix/Jenkinsfile).
````

## Pour aller plus loin : deux axes, et une exclusion

Une matrice peut avoir plusieurs axes : Jenkins crée alors une cellule par combinaison. L'exemple suivant croise les trois versions de Java avec deux bases de données, soit six cellules, puis en exclut une avec `excludes`. Il n'est pas à ajouter au pipeline : PetClinic lancerait ses tests PostgreSQL avec Testcontainers, qui n'a pas accès au moteur Docker depuis le conteneur Maven. Il montre seulement la syntaxe, que Jenkins valide :

```groovy
    matrix {
      axes {
        axis {
          name 'JDK'
          values '17', '21', '25'
        }
        axis {
          name 'DB'
          values 'h2', 'postgres'
        }
      }
      excludes {
        exclude {                       // pas de cellule Java 17 avec PostgreSQL
          axis {
            name 'JDK'
            values '17'
          }
          axis {
            name 'DB'
            values 'postgres'
          }
        }
      }
      // agent et stages : comme plus haut, avec env.JDK et env.DB
    }
```

Les six combinaisons moins une exclusion donnent cinq cellules. Une matrice grandit vite : trois axes de trois valeurs font déjà vingt-sept cellules. Gardez seulement les combinaisons que vous livrez vraiment.
