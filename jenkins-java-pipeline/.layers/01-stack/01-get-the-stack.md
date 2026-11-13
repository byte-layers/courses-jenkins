---
title: "Récupérer la stack et générer ses secrets"
description: "Télécharger les fichiers de la stack, les parcourir, et créer les quatre mots de passe qu'elle attend"
---

La stack tient dans un dossier de dix fichiers : un fichier Compose, deux `Dockerfile` et quelques fichiers de configuration. Vous allez la télécharger, en faire le tour, puis créer les mots de passe qu'elle attend.

## Télécharger les fichiers de la stack

Créez d'abord le dossier du lab. L'option `-p` crée aussi les dossiers parents qui manquent, ici `~/byte-layers` et `~/byte-layers/jenkins` :

```exec "Créer le dossier du lab"
mkdir -p ~/byte-layers/jenkins/pipeline
```

Les fichiers de la stack sont publiés dans le dépôt de ce lab, sous un tag qui fige leur version. La commande suivante télécharge l'archive de ce tag avec `curl`, et la décompresse avec `tar` en ne gardant que le dossier `stack/` :

```exec "Télécharger la stack"
cd ~/byte-layers/jenkins/pipeline && curl -sSL https://github.com/byte-layers/courses-jenkins/archive/refs/tags/jenkins-java-pipeline/v1.tar.gz | tar -xz --strip-components=2 courses-jenkins-jenkins-java-pipeline-v1/jenkins-java-pipeline/stack
```

| Morceau | Rôle |
|---|---|
| `curl -sSL` | télécharge l'archive : `-L` suit la redirection de GitHub, `-sS` n'affiche que les erreurs |
| `tar -xz` | décompresse l'archive (`-x` extraire, `-z` format gzip) lue sur l'entrée standard |
| `--strip-components=2` | retire les deux premiers niveaux de chemins de l'archive, pour obtenir `stack/` directement dans votre dossier |
| le dernier argument | le seul dossier à extraire de l'archive |

Listez ce que vous avez obtenu :

```exec "Lister les fichiers de la stack"
cd ~/byte-layers/jenkins/pipeline && find stack -type f | sort
```

Vous devez lire ces dix fichiers :

```
stack/.gitignore
stack/agent/Dockerfile
stack/agent/connect-agent.sh
stack/compose.yaml
stack/gitea-init/init.sh
stack/jenkins/Dockerfile
stack/jenkins/casc/jenkins.yaml
stack/jenkins/casc/jobs.yaml
stack/jenkins/plugins.txt
stack/reposilite/configuration.shared.json
```

```verify
D="$HOME/byte-layers/jenkins/pipeline/stack"
for f in compose.yaml jenkins/Dockerfile jenkins/plugins.txt jenkins/casc/jenkins.yaml agent/Dockerfile agent/connect-agent.sh gitea-init/init.sh; do
  if [ ! -f "$D/$f" ]; then
    echo "Le fichier stack/$f manque. Relancez le téléchargement depuis ~/byte-layers/jenkins/pipeline."
    exit 1
  fi
done
echo "Les fichiers de la stack sont en place."
```

```hint
Si `tar` répond `Not found in archive`, l'archive n'a pas la structure attendue : vérifiez que la commande a été copiée en entier, sur une seule ligne, et lancée depuis `~/byte-layers/jenkins/pipeline`.
```

## Faire le tour des fichiers

Chaque fichier a un rôle précis. Vous en lirez plusieurs en détail au fil du chapitre ; ce tableau sert de carte :

| Fichier | Ce qu'il contient |
|---|---|
| [`compose.yaml`](../../stack/compose.yaml) | les sept services de la stack : `jenkins`, `agent1`, `agent2`, `gitea`, `gitea-init`, `reposilite` et `registry` |
| [`jenkins/Dockerfile`](../../stack/jenkins/Dockerfile) | l'image du contrôleur : l'image officielle `jenkins/jenkins` en version LTS, plus les plugins |
| [`jenkins/plugins.txt`](../../stack/jenkins/plugins.txt) | la liste des plugins, chacun avec sa version |
| [`jenkins/casc/jenkins.yaml`](../../stack/jenkins/casc/jenkins.yaml) | la configuration de Jenkins, écrite en YAML : utilisateurs, droits, agents, mots de passe, serveur Gitea |
| [`jenkins/casc/jobs.yaml`](../../stack/jenkins/casc/jobs.yaml) | le job qui construira PetClinic, décrit en code |
| [`agent/Dockerfile`](../../stack/agent/Dockerfile) | l'image des agents : l'image officielle `jenkins/inbound-agent`, plus la CLI Docker |
| [`agent/connect-agent.sh`](../../stack/agent/connect-agent.sh) | le script qui connecte un agent au contrôleur |
| [`gitea-init/init.sh`](../../stack/gitea-init/init.sh) | le script qui remplit Gitea au premier démarrage |
| [`reposilite/configuration.shared.json`](../../stack/reposilite/configuration.shared.json) | les dépôts Maven de Reposilite |
| `.gitignore` | exclut le dossier `secrets/`, si vous versionnez un jour ce dossier |

Tous les services exposent leur port sur `127.0.0.1` seulement : ils ne sont joignables que depuis votre poste.

| Service | Adresse depuis votre navigateur | Adresse depuis les autres conteneurs |
|---|---|---|
| Jenkins | http://localhost:28500 | `http://jenkins:8080` |
| Gitea | http://localhost:28530 | `http://gitea:3000` |
| Reposilite | http://localhost:28540 | `http://reposilite:8080` |
| Registre | `localhost:28550` (pas d'interface web) | `registry:5000` |

Un même service a donc deux adresses. Entre conteneurs, on utilise le nom du service, que le DNS du réseau Compose résout. Depuis votre poste, on passe par le port publié sur `localhost`. Gardez ce tableau en tête : c'est la source de plusieurs réglages du lab.

## Générer les quatre secrets

La stack a besoin de quatre mots de passe, qu'elle lit dans des fichiers du dossier `secrets/` :

| Fichier | À quoi il sert |
|---|---|
| `jenkins_admin_password` | le mot de passe du compte `admin` de Jenkins, celui avec lequel vous vous connectez |
| `agent_connector_password` | le mot de passe d'un compte technique, `agent-connector`, que les agents utilisent pour se connecter |
| `gitea_password` | le mot de passe du compte `learner` de Gitea, avec lequel vous clonez et poussez |
| `reposilite_token` | le jeton avec lequel Jenkins publie dans Reposilite |

Compose les monte dans les conteneurs sous `/run/secrets/`, comme des **secrets Compose** : ils n'apparaissent ni dans les variables d'environnement ni dans `docker inspect`. Créez le dossier :

```exec "Créer le dossier des secrets"
mkdir -p ~/byte-layers/jenkins/pipeline/stack/secrets
```

Générez maintenant un mot de passe aléatoire par fichier. `openssl rand -hex 12` produit 24 caractères hexadécimaux, et `tr -d '\n'` retire le saut de ligne final, pour que le fichier contienne le mot de passe et rien d'autre :

```exec "Générer les quatre secrets"
cd ~/byte-layers/jenkins/pipeline/stack && for s in jenkins_admin_password agent_connector_password gitea_password reposilite_token; do openssl rand -hex 12 | tr -d '\n' > "secrets/$s"; done
```

Vous aurez besoin du mot de passe d'`admin` pour vous connecter à Jenkins. Affichez-le :

```exec "Afficher le mot de passe d'admin"
cat ~/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password; echo
```

Le `echo` final ajoute seulement un retour à la ligne, puisque le fichier n'en contient pas.

```verify
D="$HOME/byte-layers/jenkins/pipeline/stack/secrets"
for s in jenkins_admin_password agent_connector_password gitea_password reposilite_token; do
  if [ ! -s "$D/$s" ]; then
    echo "Le secret secrets/$s manque ou est vide. Relancez la génération des secrets."
    exit 1
  fi
done
echo "Les quatre secrets sont créés."
```

⚖️ Ces mots de passe sont générés sur votre poste et ne quittent jamais la stack. Ne les committez jamais : c'est le rôle du `.gitignore`. En entreprise, ils viendraient d'un coffre comme HashiCorp Vault, ou du gestionnaire de secrets de l'hébergeur.

> 📖 [Les secrets dans Compose](https://docs.docker.com/compose/how-tos/use-secrets/) · [`openssl rand`](https://docs.openssl.org/master/man1/openssl-rand/)
