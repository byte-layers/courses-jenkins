---
title: "Quatre contrôles en parallèle, après la compilation"
description: "Le bloc parallel, un agent par branche, un scanner par conteneur, les rapports SARIF lus par warnings-ng, et un seuil qui rend le build instable"
---

Les tests unitaires vérifient que le code fait ce qu'il doit. Ils ne disent rien d'une requête SQL construite à la main, d'une bibliothèque qui a une faille connue, d'un `Dockerfile` qui tourne en root ou d'un mot de passe oublié dans un fichier. Ce sont quatre familles de contrôles, et chacune a ses outils.

## Quatre familles de contrôles, un outil chacune

Le lab prend un outil par famille, choisi parce qu'il est libre, qu'il tourne dans un conteneur sans serveur à installer, et qu'il produit un rapport au format SARIF :

| Famille | Ce qu'elle cherche | Outil du lab |
|---|---|---|
| **SAST** (*Static Application Security Testing*) | des constructions dangereuses dans le code lui-même : injection, désérialisation, cryptographie faible | [semgrep](https://semgrep.dev/docs/), avec les règles publiques pour Java |
| **SCA** (*Software Composition Analysis*) | les dépendances qui ont une vulnérabilité connue, d'après les bases publiques de failles | [osv-scanner](https://google.github.io/osv-scanner/), de Google, qui interroge la base OSV |
| Configuration (**IaC**, *Infrastructure as Code*) | les mauvaises configurations dans les `Dockerfile`, fichiers Compose, manifestes Kubernetes | [KICS](https://docs.kics.io/), de Checkmarx |
| Secrets | un mot de passe, un jeton ou une clé écrits dans un fichier | [gitleaks](https://github.com/gitleaks/gitleaks) |

**SARIF** (*Static Analysis Results Interchange Format*) est un format JSON standard pour les résultats d'analyse. Les quatre outils le produisent, et le plugin **Warnings Next Generation** (`warnings-ng`) le lit : un seul format, une seule façon d'afficher les résultats dans Jenkins.

Chaque famille a d'autres outils, libres ou commerciaux : SonarQube ou SpotBugs pour le code, Trivy, Grype ou OWASP Dependency-Check pour les dépendances, Checkov ou Hadolint pour la configuration. Leur comparaison fera l'objet d'un contenu à part, à venir ; ce lab s'en tient à un outil par famille.

⚖️ semgrep est libre, mais les règles téléchargées par `--config p/java` sont publiées sous la *Semgrep Rules License*, qui interdit de les revendre dans un produit concurrent. Les utiliser dans votre propre CI est permis.

## Le bloc parallel, et un agent par branche

Un stage peut contenir un bloc `parallel` à la place de `steps` : chacun des stages de ce bloc, appelés ses **branches**, démarre en même temps que les autres. Le stage parent se termine quand toutes ses branches ont fini.

```groovy
stage('Contrôles') {
  parallel {
    stage('SAST : semgrep') {
      agent { label 'scan' }          // chaque branche choisit son agent
      steps { ... }
    }
    stage('Dépendances : osv-scanner') {
      agent { label 'scan' }
      steps { ... }
    }
    // ...
  }
}
```

Chaque branche déclare son propre `agent { label 'scan' }`. Jenkins donne à chacune un **exécuteur** libre parmi les agents qui portent ce label. Les deux agents ont deux exécuteurs chacun : les quatre branches tournent donc en même temps, deux sur `agent1` et deux sur `agent2`. Sur un même agent, la seconde branche travaille dans un workspace distinct, suffixé `@2`.

C'est la raison d'être du chapitre précédent : chaque branche commence par `fresh 'sources'`, pour reprendre le code dans son propre workspace.

> 📖 [Les stages parallèles](https://www.jenkins.io/doc/book/pipeline/syntax/#parallel)

## Un scanner par conteneur

Chaque branche lance son scanner comme le stage de compilation lance Maven : avec `docker.image(…).inside`. Les images de scanners ont deux particularités, qui expliquent les options du `Jenkinsfile` :

| Particularité | Conséquence dans le `Jenkinsfile` |
|---|---|
| leur **entrypoint** est le scanner lui-même : `docker run checkmarx/kics` lance `kics` | `inside('--entrypoint=')` vide l'entrypoint, pour que le conteneur exécute la commande `cat` d'`inside` et attende les étapes `sh` |
| certaines rangent leur binaire à la racine du système de fichiers, hors du `PATH` | on appelle osv-scanner par son chemin complet, `/osv-scanner` |

Un scanner qui trouve quelque chose renvoie souvent un code de sortie non nul, ce qui ferait échouer l'étape `sh`. Or on veut lire le rapport, pas interrompre le build. Chaque commande neutralise ce code à sa façon :

| Branche | Commande | Ce qui neutralise le code de sortie |
|---|---|---|
| semgrep | `semgrep scan --config p/java --metrics=off --sarif --output semgrep.sarif .` | rien à faire : semgrep renvoie 0 même avec des constats, tant qu'on ne lui passe pas `--error`. `p/java` télécharge les règles publiques pour Java ; `--metrics=off` n'envoie aucune statistique d'usage |
| osv-scanner | `/osv-scanner scan source --format sarif --output-file osv.sarif . \|\| [ $? -eq 1 ]` | osv-scanner renvoie 1 quand il trouve des vulnérabilités. `\|\| [ $? -eq 1 ]` transforme ce code 1 en succès, mais laisse échouer les autres codes, qui signalent une vraie erreur |
| kics | `kics scan -p . --type Dockerfile,DockerCompose --report-formats sarif -o kics --ignore-on-exit results --no-progress` | `--ignore-on-exit results` : kics ne change pas son code de sortie selon les résultats |
| gitleaks | `gitleaks dir . --report-format sarif --report-path gitleaks.sarif --exit-code 0` | `--exit-code 0` : le code de sortie quand une fuite est trouvée |

⚖️ `gitleaks dir` ne lit que les fichiers présents, pas l'historique Git : le stash `sources` ne contient pas le dossier `.git`. Un secret commité puis supprimé du fichier lui échappe. En entreprise, on lance aussi `gitleaks git` sur un clone complet, et surtout gitleaks avant chaque commit, sur le poste du développeur.

> 📖 [semgrep scan](https://semgrep.dev/docs/cli-reference) · [osv-scanner scan source](https://google.github.io/osv-scanner/usage/scan-source) · [kics scan](https://docs.kics.io/latest/commands/) · [gitleaks](https://github.com/gitleaks/gitleaks#usage)

## Lire les rapports, et décider du statut du build

L'étape `recordIssues` lit un rapport et l'attache au build. Chaque outil devient un onglet de la page du build, avec la liste des constats, leur sévérité et le fichier concerné :

```groovy
recordIssues tool: sarif(id: 'semgrep', name: 'Semgrep', pattern: 'semgrep.sarif'),
             qualityGates: [[threshold: 1, type: 'TOTAL', criticality: 'UNSTABLE']]
```

Il reste à décider de ce que les constats font au build. Jenkins connaît trois statuts principaux :

| Statut | Couleur | Ce qu'il veut dire |
|---|---|---|
| `SUCCESS` | vert | tout s'est bien passé |
| `UNSTABLE` | jaune | le build est allé au bout, mais quelque chose mérite d'être regardé |
| `FAILURE` | rouge | une étape a échoué ; les stages suivants ne tournent pas |

Le paramètre `qualityGates` fixe un **seuil** : avec `threshold: 1` et `type: 'TOTAL'`, un seul constat suffit à rendre le build `UNSTABLE`. On le pose sur semgrep et gitleaks, qui ne trouvent rien aujourd'hui dans PetClinic : tout nouveau constat se verra. On ne le pose pas sur osv-scanner et KICS, qui trouvent déjà des choses : le build serait instable en permanence, et un signal toujours allumé n'informe plus personne.

⚖️ Bloquer le build (`FAILURE`) dès le premier constat paraît plus sûr, mais pousse les équipes à désactiver le contrôle au premier faux positif. On commence souvent par `UNSTABLE`, on traite l'existant, puis on durcit le seuil. La version 13 de `warnings-ng` propose aussi un seuil sur les **nouveaux** constats seulement (`type: 'NEW'`), qui laisse l'existant de côté.

> 📖 [L'étape `recordIssues` et ses seuils](https://github.com/jenkinsci/warnings-ng-plugin/blob/main/doc/Documentation.md#quality-gate-configuration)

## Écrire les quatre branches

Le stage `Vérifier le JAR sur agent2` du chapitre précédent a joué son rôle : il disparaît. Le nouveau `Jenkinsfile` garde les deux premiers stages et ajoute le stage `Contrôles`. La branche semgrep est complète et sert de modèle ; pour les trois autres, la commande est donnée et vous écrivez ce qui l'entoure. Remplacez votre fichier par celui-ci :

```exec "Écrire le Jenkinsfile avec les contrôles"
cat > ~/byte-layers/jenkins/pipeline/petclinic/Jenkinsfile <<'EOF'
// spring-petclinic : quatre contrôles en parallèle, après la compilation

def fresh(String... stashes) {
  cleanWs()
  stashes.each { unstash it }
}

pipeline {
  agent none

  options {
    buildDiscarder(logRotator(numToKeepStr: '10'))
    skipDefaultCheckout()
  }

  environment {
    MAVEN_IMAGE = 'maven:3.9.16-eclipse-temurin-21-noble'
    NETWORK     = 'layers-jenkins'
    M2_REPO     = '/home/jenkins/caches/m2'
  }

  stages {
    stage('Récupérer le code') {
      agent { label 'maven' }
      steps {
        cleanWs()
        checkout scm
        stash name: 'sources'
      }
    }

    stage('Compiler et tester') {
      agent { label 'maven' }
      steps {
        fresh 'sources'
        script {
          docker.image(env.MAVEN_IMAGE).inside("--network ${env.NETWORK}") {
            configFileProvider([configFile(fileId: 'maven-settings', variable: 'MAVEN_SETTINGS')]) {
              sh 'mvn -B -s "$MAVEN_SETTINGS" -Dmaven.repo.local=$M2_REPO package'
            }
          }
        }
        stash name: 'jar', includes: 'target/spring-petclinic-*.jar'
      }
      post {
        always { junit 'target/surefire-reports/*.xml' }
      }
    }

    stage('Contrôles') {
      parallel {
        stage('SAST : semgrep') {
          agent { label 'scan' }
          steps {
            fresh 'sources'
            script {
              docker.image('semgrep/semgrep:1.181.1').inside('--entrypoint=') {
                sh 'semgrep scan --config p/java --metrics=off --sarif --output semgrep.sarif .'
              }
            }
            recordIssues tool: sarif(id: 'semgrep', name: 'Semgrep', pattern: 'semgrep.sarif'),
                         qualityGates: [[threshold: 1, type: 'TOTAL', criticality: 'UNSTABLE']]
          }
        }

        stage('Dépendances : osv-scanner') {
          // TODO : un agent scan, le code repris, l'image ghcr.io/google/osv-scanner:v2.6.0 avec l'entrypoint vidé
          //        commande : /osv-scanner scan source --format sarif --output-file osv.sarif . || [ $? -eq 1 ]
          //        rapport : osv.sarif, id osv, nom OSV-Scanner, sans seuil
        }

        stage('Configuration : kics') {
          // TODO : même modèle, image checkmarx/kics:v2.2.0
          //        commande : kics scan -p . --type Dockerfile,DockerCompose --report-formats sarif -o kics --ignore-on-exit results --no-progress
          //        rapport : kics/results.sarif, id kics, nom KICS, sans seuil
        }

        stage('Secrets : gitleaks') {
          // TODO : même modèle, image zricethezav/gitleaks:v8.30.1
          //        commande : gitleaks dir . --report-format sarif --report-path gitleaks.sarif --exit-code 0
          //        rapport : gitleaks.sarif, id gitleaks, nom Gitleaks, avec le même seuil que semgrep
        }
      }
    }
  }
}
EOF
```

Les versions des images sont fixées, comme toutes celles du lab : le résultat d'un scanner change avec sa version et avec ses règles, et un build doit pouvoir se rejouer à l'identique.

## Pousser, et lire les résultats

Committez et poussez :

```exec "Committer et pousser"
cd ~/byte-layers/jenkins/pipeline/petclinic && git commit -am "Add four security checks in parallel" && git push
```

Dans **Pipeline Overview**, les quatre branches du stage `Contrôles` s'affichent côte à côte et avancent ensemble. Le premier build télécharge les quatre images : comptez plusieurs minutes. Ensuite, chaque branche dure de quelques secondes (gitleaks) à une vingtaine de secondes (osv-scanner, qui résout les dépendances du `pom.xml` sur internet).

À la fin, la page du build résume les constats de chaque outil. À la date d'écriture de ce lab, sur le commit `500158f`, vous devez lire :

| Outil | Constats | Ce que c'est |
|---|---|---|
| Semgrep | 0 | aucune construction dangereuse dans le code Java de PetClinic |
| OSV-Scanner | 20 | des vulnérabilités connues dans six dépendances, surtout Tomcat embarqué (7) et la bibliothèque JSON Jackson (7), puis Spring MVC, Log4j et le pilote PostgreSQL |
| KICS | 14 | dans le `docker-compose.yml` de PetClinic : des mots de passe en clair, des conteneurs sans healthcheck ni restriction de capacités, des ports publiés sur toutes les interfaces. Dans `.devcontainer/Dockerfile` : pas d'instruction `USER`, l'usage de `sudo` |
| Gitleaks | 0 | aucun secret dans les fichiers |

Les chiffres d'osv-scanner peuvent augmenter si vous refaites le lab plus tard : de nouvelles failles sont publiées chaque semaine sur des versions qui, elles, ne changent pas. Le build reste `SUCCESS` : semgrep et gitleaks, les deux outils qui ont un seuil, n'ont rien trouvé. Ouvrez l'onglet **KICS Warnings** pour parcourir les constats, fichier par fichier.

```verify
D="$HOME/byte-layers/jenkins/pipeline/petclinic"
P=$(cat "$HOME/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password" 2>/dev/null)
J="http://localhost:28500/job/petclinic/job/main"
F=$(git -C "$D" show origin/main:Jenkinsfile 2>/dev/null)
if ! echo "$F" | grep -q "parallel"; then echo "Le Jenkinsfile poussé sur main n'a pas de bloc parallel."; exit 1; fi
R=$(curl -fsS -u "admin:$P" "$J/lastBuild/api/json?tree=result,building" 2>/dev/null)
if echo "$R" | grep -q '"building":true'; then echo "Le build est en cours : attendez qu'il se termine."; exit 1; fi
if echo "$R" | grep -q '"result":"FAILURE"'; then echo "Le dernier build de main a échoué. Lisez la branche en rouge dans Pipeline Overview."; exit 1; fi
C=$(curl -fsS -u "admin:$P" "$J/lastBuild/consoleText")
for t in Semgrep OSV-Scanner KICS Gitleaks; do
  if ! echo "$C" | grep -q "\[$t\] Created analysis result"; then
    echo "Le rapport de $t n'est pas publié : vérifiez son recordIssues, son nom et son fichier."
    exit 1
  fi
done
echo "Les quatre contrôles ont tourné, et leurs rapports sont publiés."
```

```hint
Si une branche échoue sur `/osv-scanner: not found` ou `kics: not found`, vérifiez le nom exact de l'image et la présence de `'--entrypoint='` dans `inside`.
```

```hint
Si `recordIssues` affiche `No files found for pattern`, le chemin du rapport ne correspond pas à l'option de la commande : `osv.sarif`, `kics/results.sarif` (kics écrit dans le dossier passé à `-o`), `gitleaks.sarif`.
```

````solution
```groovy
        stage('Dépendances : osv-scanner') {
          agent { label 'scan' }
          steps {
            fresh 'sources'
            script {
              docker.image('ghcr.io/google/osv-scanner:v2.6.0').inside('--entrypoint=') {
                sh '/osv-scanner scan source --format sarif --output-file osv.sarif . || [ $? -eq 1 ]'
              }
            }
            recordIssues tool: sarif(id: 'osv', name: 'OSV-Scanner', pattern: 'osv.sarif')
          }
        }

        stage('Configuration : kics') {
          agent { label 'scan' }
          steps {
            fresh 'sources'
            script {
              docker.image('checkmarx/kics:v2.2.0').inside('--entrypoint=') {
                sh 'kics scan -p . --type Dockerfile,DockerCompose --report-formats sarif -o kics --ignore-on-exit results --no-progress'
              }
            }
            recordIssues tool: sarif(id: 'kics', name: 'KICS', pattern: 'kics/results.sarif')
          }
        }

        stage('Secrets : gitleaks') {
          agent { label 'scan' }
          steps {
            fresh 'sources'
            script {
              docker.image('zricethezav/gitleaks:v8.30.1').inside('--entrypoint=') {
                sh 'gitleaks dir . --report-format sarif --report-path gitleaks.sarif --exit-code 0'
              }
            }
            recordIssues tool: sarif(id: 'gitleaks', name: 'Gitleaks', pattern: 'gitleaks.sarif'),
                         qualityGates: [[threshold: 1, type: 'TOTAL', criticality: 'UNSTABLE']]
          }
        }
```
Le fichier complet est [`solution/04-parallel-after-build/Jenkinsfile`](../../solution/04-parallel-after-build/Jenkinsfile).
````
