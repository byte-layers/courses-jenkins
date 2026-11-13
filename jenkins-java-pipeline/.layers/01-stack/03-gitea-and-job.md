---
title: "Cloner PetClinic depuis Gitea, et lire le job multibranch"
description: "Voir ce que gitea-init a préparé, comprendre le job multibranch créé par Job DSL, puis cloner le dépôt sur votre poste"
---

Les deux agents sont en ligne. Il reste à relier Jenkins au code : un dépôt dans Gitea, un job qui le surveille, et votre copie de travail. Les deux premiers existent déjà ; vous allez voir comment, puis cloner le dépôt.

## Ce que gitea-init a préparé

Le service `gitea-init` a lancé une seule fois le script [`stack/gitea-init/init.sh`](../../stack/gitea-init/init.sh). Relisez son journal :

```exec "Lire le journal de gitea-init"
cd ~/byte-layers/jenkins/pipeline/stack && docker compose logs gitea-init --no-log-prefix | tail -3
```

Vous devez lire ses trois étapes :

```
New user 'learner' has been successfully created!
spring-petclinic imported at 500158f
webhook to Jenkins created
```

| Étape | Ce qu'elle fait |
|---|---|
| le compte `learner` | un compte Gitea, avec le mot de passe du secret `gitea_password` |
| l'import de PetClinic | le dépôt `learner/spring-petclinic`, avec une seule branche, `main`, posée sur le commit `500158f` de PetClinic. Un commit précis, plutôt que la dernière version, garantit que tout le monde part du même code et voit les mêmes résultats que ce lab |
| le webhook | à chaque push, création de branche ou pull request, Gitea envoie une requête HTTP à `http://jenkins:8080/gitea-webhook/post` |

Un **webhook**, c'est un appel HTTP qu'un service envoie à un autre quand un événement se produit. Sans lui, Jenkins devrait interroger Gitea à intervalles réguliers pour découvrir les nouveaux commits (le *polling*), avec du retard et des requêtes inutiles.

Pour vous connecter à Gitea, il vous faut le mot de passe de `learner`. Affichez-le :

```exec "Afficher le mot de passe de learner"
cat ~/byte-layers/jenkins/pipeline/stack/secrets/gitea_password; echo
```

Ouvrez ensuite http://localhost:28530 et connectez-vous avec l'utilisateur `learner` et ce mot de passe. Dans le dépôt `spring-petclinic`, l'onglet **Settings › Webhooks** (*Paramètres › Déclencheurs Web* en français) montre le webhook vers Jenkins.

## Le job multibranch, décrit en code

Dans Jenkins, la page d'accueil montre un job, `spring-petclinic`. Il n'a pas été créé à la main : il est décrit dans [`stack/jenkins/casc/jobs.yaml`](../../stack/jenkins/casc/jobs.yaml), que JCasC charge avec le plugin **Job DSL** :

```groovy
multibranchPipelineJob('petclinic') {
  displayName('spring-petclinic')
  branchSources {
    branchSource {
      source {
        giteaSCMSource {
          serverUrl('http://gitea:3000')
          repoOwner('learner')
          repository('spring-petclinic')
          credentialsId('gitea')
          traits {
            giteaBranchDiscovery { strategyId(1) }
            giteaPullRequestDiscovery { strategyId(1) }
            giteaTagDiscovery()
          }
        }
      }
    }
  }
}
```

C'est un job **multibranch** (*Multibranch Pipeline*). Il ne construit rien lui-même : il parcourt le dépôt, et crée un sous-job pour chaque branche, chaque pull request et chaque tag qui contient un fichier `Jenkinsfile`. Le même `Jenkinsfile` sert donc à toutes les branches, et c'est lui qui décidera, au chapitre sur la publication, de ce qui tourne ou non selon la branche.

| Élément | Rôle |
|---|---|
| `giteaSCMSource` | la source du job : un dépôt Gitea, joint par son nom de service, `gitea`, sur le réseau Compose |
| `credentialsId('gitea')` | le mot de passe de `learner`, déclaré dans la section `credentials` de `jenkins.yaml` |
| `giteaBranchDiscovery` | découvrir les branches ; `strategyId(1)` ignore une branche tant qu'une pull request est ouverte depuis elle : c'est la pull request qui est construite à sa place, pour ne pas construire deux fois le même code |
| `giteaPullRequestDiscovery` | découvrir les pull requests ; `strategyId(1)` construit le résultat de la fusion de la pull request avec sa branche cible |
| `giteaTagDiscovery` | découvrir les tags. Le lab ne pousse aucun tag, mais c'est ainsi qu'un pipeline construirait une release, comme `v4.0.0` |

Ouvrez le job `spring-petclinic`, puis cliquez sur **Scan Multibranch Pipeline Now** dans le menu de gauche, et ouvrez **Scan Multibranch Pipeline Log**. La fin du journal explique pourquoi aucun sous-job n'existe encore :

```
    Checking branch main
      ‘Jenkinsfile’ not found
    Does not meet criteria
```

La branche `main` n'a pas de `Jenkinsfile` : le prochain chapitre en écrit un.

> 📖 [Les pipelines multibranch](https://www.jenkins.io/doc/book/pipeline/multibranch/) · [Le plugin Gitea](https://plugins.jenkins.io/gitea/) · [Le plugin Job DSL](https://plugins.jenkins.io/job-dsl/)

## Cloner le dépôt sur votre poste

Vous travaillerez dans une copie du dépôt, à côté de la stack. Pour ne pas retaper le mot de passe à chaque push, la commande le place dans l'adresse du dépôt, en le lisant dans le fichier du secret :

```exec "Cloner PetClinic depuis Gitea"
cd ~/byte-layers/jenkins/pipeline && git clone "http://learner:$(cat stack/secrets/gitea_password)@localhost:28530/learner/spring-petclinic.git" petclinic
```

⚖️ Ce raccourci écrit le mot de passe en clair dans `petclinic/.git/config`. Il est acceptable pour un compte de lab, sur votre poste, mais pas pour un vrai compte : on utilise alors une clé SSH, ou un gestionnaire d'identifiants (`git config credential.helper`).

Contrôlez que votre copie est bien posée sur le commit importé :

```exec "Afficher le dernier commit"
cd ~/byte-layers/jenkins/pipeline/petclinic && git log --oneline -1
```

Vous devez lire le commit `500158f` :

```
500158f (HEAD -> main, origin/main, origin/HEAD) added redirection to the page when the user types a page that is out of bounds
```

Si Git ne connaît pas encore votre nom, vos commits échoueront avec `Please tell me who you are`. Le bloc suivant règle un nom et une adresse pour ce dépôt seulement, sans toucher à votre configuration globale ; remplacez-les par les vôtres si vous le souhaitez :

```exec "Donner une identité Git au dépôt"
cd ~/byte-layers/jenkins/pipeline/petclinic && git config user.name "learner" && git config user.email "learner@example.test"
```

```verify
D="$HOME/byte-layers/jenkins/pipeline/petclinic"
if [ ! -d "$D/.git" ]; then
  echo "Le dépôt n'est pas cloné dans ~/byte-layers/jenkins/pipeline/petclinic."
  exit 1
fi
if ! git -C "$D" remote get-url origin | grep -q "localhost:28530/learner/spring-petclinic"; then
  echo "Le dépôt cloné ne vient pas de Gitea (localhost:28530/learner/spring-petclinic)."
  exit 1
fi
if ! git -C "$D" merge-base --is-ancestor 500158f HEAD 2>/dev/null; then
  echo "Votre copie ne contient pas le commit 500158f : clonez le dépôt de Gitea, pas celui de GitHub."
  exit 1
fi
echo "PetClinic est cloné depuis Gitea."
```

## Ce que contient PetClinic

Pour la suite, vous n'avez besoin de connaître que quelques fichiers du dépôt :

| Fichier ou dossier | Ce que c'est |
|---|---|
| `pom.xml` | le fichier de **Maven**, l'outil de construction des projets Java : les dépendances du projet, sa version (`4.0.0-SNAPSHOT`) et la version minimale de Java (17) |
| `src/main/java` | le code de l'application |
| `src/test/java` | les tests, que Maven lance avant de produire le JAR |
| `docker-compose.yml`, `.devcontainer/` | des fichiers fournis par PetClinic pour lancer ses bases de données et un environnement de développement. Le pipeline n'en a pas besoin, mais l'un des scanners les lira |

Le **JAR** est le fichier que produit la compilation : l'application et toutes ses dépendances dans un seul fichier, qui se lance avec `java -jar`.
