---
title: "Démarrer la stack, puis déclarer le second agent dans JCasC"
description: "Lire comment le contrôleur reçoit ses plugins et sa configuration, démarrer la stack, constater qu'agent2 attend, et le déclarer dans jenkins.yaml"
---

Un Jenkins installé à la main se configure par son interface : l'assistant d'installation, les plugins à cocher, les agents à créer, les mots de passe à saisir. Rien de tout cela ne se relit ni ne se rejoue. Cette stack fait l'inverse : tout ce qui configure Jenkins est écrit dans des fichiers. Vous allez lire comment, démarrer la stack, et compléter vous-même la configuration.

## Les plugins sont installés dans l'image

Ouvrez [`stack/jenkins/Dockerfile`](../../stack/jenkins/Dockerfile). Il part de l'image officielle, en version LTS (*Long Term Support*, la version stable que l'on installe en production), et installe les plugins au moment de la construction de l'image :

```dockerfile
FROM jenkins/jenkins:2.580.2-lts-jdk21

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG=/casc
```

| Ligne | Rôle |
|---|---|
| `jenkins-plugin-cli` | l'outil fourni dans l'image officielle : il télécharge chaque plugin de la liste, avec ses dépendances |
| `runSetupWizard=false` | désactive l'assistant du premier démarrage : il n'y a pas de mot de passe initial à aller chercher dans le conteneur |
| `CASC_JENKINS_CONFIG=/casc` | dit au plugin JCasC où lire la configuration : le dossier `/casc`, que Compose monte depuis `stack/jenkins/casc` |

Ouvrez ensuite [`stack/jenkins/plugins.txt`](../../stack/jenkins/plugins.txt). Chaque ligne nomme un plugin et fixe sa version, comme un tag d'image précis. Voici ceux dont vous vous servirez :

| Plugin | Ce qu'il apporte au lab |
|---|---|
| `configuration-as-code` | **JCasC** (*Jenkins Configuration as Code*) : la configuration de Jenkins lue dans des fichiers YAML |
| `job-dsl` | décrire des jobs en code ; JCasC s'en sert pour créer le job de PetClinic |
| `workflow-aggregator` | les pipelines et le `Jenkinsfile` |
| `ws-cleanup` | l'étape `cleanWs()`, qui vide un workspace |
| `pipeline-graph-view` | la vue graphique d'un build, stage par stage |
| `gitea` | lire les branches et les pull requests d'un dépôt Gitea |
| `docker-workflow` | lancer des étapes dans un conteneur, avec `docker.image(...).inside` |
| `junit`, `warnings-ng` | afficher les résultats des tests et des scanners |
| `config-file-provider` | fournir au build un fichier de réglages Maven, avec ses mots de passe, sans les écrire dans le `Jenkinsfile` |
| `credentials-binding` | l'étape `withCredentials`, pour passer un mot de passe à une commande ; le lab ne s'en sert pas, mais elle sert dès qu'un outil attend un jeton |

Mettre les plugins dans l'image rend le contrôleur reproductible : deux démarrages donnent le même Jenkins, et changer un plugin passe par une modification de fichier, que l'on peut relire.

> 📖 [L'image Docker officielle de Jenkins et `jenkins-plugin-cli`](https://github.com/jenkinsci/docker#preinstalling-plugins) · [Le plugin Configuration as Code](https://plugins.jenkins.io/configuration-as-code/)

## Donner aux agents l'accès au moteur Docker

Les agents pilotent le moteur Docker par son socket, comme l'explique la fin de ce chapitre. Ils tournent avec l'utilisateur `jenkins`, et le service ajoute à cet utilisateur le groupe propriétaire du socket, par la ligne `group_add: ["${DOCKER_GID:-0}"]` de `compose.yaml`. Le numéro de ce groupe dépend de l'installation : 0 avec Docker Desktop (Mac, Windows), celui du groupe `docker` sous Linux, qui varie d'une machine à l'autre.

Plutôt que de chercher ce numéro, nous allons le demander au moteur lui-même, et l'écrire dans un fichier `.env`, que Compose lit au démarrage. C'est encore une étape de préparation : lancez-la avec ▶ quel que soit votre système.

```exec "Écrire le groupe du socket dans .env"
cd ~/byte-layers/jenkins/pipeline/stack && echo "DOCKER_GID=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock alpine:3.22 stat -c %g /var/run/docker.sock)" > .env
```

> 🔍 **Comprendre la commande**
>
> | Morceau | Rôle |
> |---|---|
> | `docker run --rm … alpine:3.22` | lance un petit conteneur Alpine, supprimé dès qu'il a fini (`--rm`) |
> | `-v /var/run/docker.sock:/var/run/docker.sock` | lui monte le socket du moteur, comme le fait `compose.yaml` pour les agents |
> | `stat -c %g /var/run/docker.sock` | affiche le numéro du groupe propriétaire du socket (`%g`), vu de l'intérieur d'un conteneur, donc tel que les agents le verront |
> | `$( … )` | la substitution : le shell exécute la commande entre parenthèses et met sa sortie à sa place |
> | `echo "DOCKER_GID=…" > .env` | écrit la ligne obtenue dans le fichier `.env` ; `>` remplace le fichier s'il existait |
>
> Pourquoi un conteneur, et pas `stat` directement sur votre poste ? Parce que le moteur n'est pas toujours sur votre machine : sur un poste du lab hébergé, il tourne dans un conteneur voisin, et son socket n'existe pas dans votre terminal. Le conteneur voit le socket comme les agents le verront, partout.

Affichez le fichier pour voir le numéro obtenu :

```exec "Afficher le fichier .env"
cat ~/byte-layers/jenkins/pipeline/stack/.env
```

Avec Docker Desktop, vous lisez `DOCKER_GID=0` ; sur un poste du lab hébergé, `DOCKER_GID=2375`.

## Démarrer la stack

Lancez la stack depuis son dossier. L'option `--build` construit d'abord les deux images locales, celle du contrôleur et celle des agents. La première fois, comptez trois à cinq minutes pour les téléchargements :

```exec "Démarrer la stack"
cd ~/byte-layers/jenkins/pipeline/stack && docker compose up -d --build
```

Vérifiez ensuite l'état des services. L'option `-a` montre aussi les conteneurs arrêtés :

```exec "Afficher l'état des services"
cd ~/byte-layers/jenkins/pipeline/stack && docker compose ps -a
```

Au bout d'une trentaine de secondes, les colonnes `SERVICE` et `STATUS` doivent ressembler à ceci :

```
SERVICE      STATUS
agent1       Up 20 seconds
agent2       Up 20 seconds
gitea        Up 35 seconds (healthy)
gitea-init   Exited (0) 25 seconds ago
jenkins      Up 35 seconds (healthy)
registry     Up 35 seconds
reposilite   Up 35 seconds (healthy)
```

`gitea-init` est arrêté avec le code `0`, et c'est normal : il ne tourne qu'une fois, pour remplir Gitea, puis s'arrête. Le chapitre suivant regarde ce qu'il a fait.

```verify
cd "$HOME/byte-layers/jenkins/pipeline/stack" 2>/dev/null || { echo "Le dossier ~/byte-layers/jenkins/pipeline/stack n'existe pas."; exit 1; }
if ! curl -fsS -o /dev/null http://localhost:28500/login; then
  echo "Jenkins ne répond pas sur http://localhost:28500. Lancez docker compose ps -a et docker compose logs jenkins."
  exit 1
fi
if [ "$(docker inspect -f '{{.State.ExitCode}}' layers-jenkins-gitea-init-1 2>/dev/null)" != "0" ]; then
  echo "gitea-init ne s'est pas terminé avec le code 0. Lisez docker compose logs gitea-init."
  exit 1
fi
echo "La stack tourne."
```

```hint
Si `docker compose up` échoue sur `port is already allocated`, un autre programme utilise l'un des ports 28500, 28530, 28540 ou 28550. Si c'est un conteneur, `docker ps` le montre. Sinon, `lsof -iTCP:28500 -sTCP:LISTEN` (sous Linux et macOS) donne le programme qui écoute sur ce port. Arrêtez-le, puis relancez la commande.
```

## Se connecter, et constater qu'un agent manque

Pour vous connecter, il vous faut le mot de passe du compte `admin`, que vous avez généré dans le fichier `secrets/jenkins_admin_password`. Affichez-le :

```exec "Afficher le mot de passe d'admin"
cat ~/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password; echo
```

Le `echo` final ajoute seulement un retour à la ligne, puisque le fichier n'en contient pas.

Ouvrez http://localhost:28500 et connectez-vous avec l'utilisateur `admin` et ce mot de passe. Aucun assistant ne s'affiche : en haut de la page d'accueil, le message système dit que l'instance est décrite par JCasC.

Ouvrez maintenant **Administrer Jenkins › Nodes** (*Nœuds* si votre navigateur est en français). Vous devez y voir le contrôleur, `Built-In Node`, et un seul agent, `agent1`. Le service `agent2` tourne pourtant. Lisez son journal :

```exec "Lire le journal d'agent2"
cd ~/byte-layers/jenkins/pipeline/stack && docker compose logs agent2 --tail 3
```

Il répète la même ligne toutes les cinq secondes :

```
agent2-1  | waiting for http://jenkins:8080/computer/agent2/jenkins-agent.jnlp ...
```

Pour comprendre cette ligne, il faut savoir comment un agent rejoint le contrôleur.

## Comment un agent inbound rejoint le contrôleur

Un agent **inbound** se connecte lui-même au contrôleur, avec l'image officielle `jenkins/inbound-agent`, à l'inverse d'un agent SSH, auquel le contrôleur se connecte. Il lui faut deux choses : que le contrôleur connaisse un nœud à son nom, et le **secret** de ce nœud. Ce secret, le contrôleur le calcule lui-même à partir du nom du nœud et d'une clé qu'il génère au premier démarrage. On ne peut donc pas l'écrire à l'avance dans `compose.yaml`.

Le script [`stack/agent/connect-agent.sh`](../../stack/agent/connect-agent.sh) règle ce problème. Au démarrage de l'agent, il demande son secret au contrôleur, puis lance l'agent habituel :

```bash
url="$JENKINS_URL/computer/$JENKINS_AGENT_NAME/jenkins-agent.jnlp"
until jnlp=$(curl -fsS -u "agent-connector:$password" "$url" 2>/dev/null); do
  echo "waiting for $url ..."
  sleep 5
done
```

| Élément | Rôle |
|---|---|
| `/computer/agent2/jenkins-agent.jnlp` | une page du contrôleur qui contient la commande de connexion du nœud `agent2`, secret compris |
| `agent-connector` | un compte technique qui n'a que deux droits : lire, et connecter un agent. Son mot de passe est le secret `agent_connector_password` |
| la boucle `until` | réessaie toutes les cinq secondes, tant que la page n'existe pas |

La page n'existe pas parce que **le contrôleur ne connaît aucun nœud `agent2`** : c'est à vous de le déclarer, dans la configuration JCasC.

## Lire la configuration JCasC

Ouvrez [`stack/jenkins/casc/jenkins.yaml`](../../stack/jenkins/casc/jenkins.yaml) dans votre éditeur. Chaque clé de premier niveau correspond à une partie de l'écran **Administrer Jenkins** :

| Clé | Ce qu'elle configure |
|---|---|
| `jenkins.numExecutors: 0` | le contrôleur n'exécute aucun build : il orchestre, les agents travaillent. C'est la recommandation de la documentation Jenkins, pour la sécurité et pour la charge |
| `jenkins.securityRealm` | les utilisateurs : `admin` et `agent-connector` |
| `jenkins.authorizationStrategy` | les droits, par une matrice : `admin` administre tout, `agent-connector` lit et connecte des agents |
| `jenkins.nodes` | les agents. `agent1` y est déclaré, `agent2` est votre `# TODO` |
| `credentials` | les mots de passe que les builds pourront utiliser, ici celui de Gitea |
| `unclassified` | les réglages des plugins : l'adresse de Jenkins, le serveur Gitea, le fichier de réglages Maven |

Les mots de passe n'y sont jamais écrits en clair. La valeur `"${jenkins_admin_password}"` est une **variable** que JCasC résout au chargement : il cherche une variable d'environnement de ce nom, puis un fichier de ce nom dans `/run/secrets/`, l'endroit où Compose monte les secrets. Le fichier YAML peut donc être versionné sans danger.

Le bloc `nodes`, plus bas, contient la déclaration d'`agent1`, que vous allez reproduire. Voici le rôle de chacun de ses champs :

| Champ | Rôle |
|---|---|
| `permanent` | un nœud permanent, qui existe tant que la configuration le déclare |
| `name` | le nom du nœud : c'est celui que l'agent donne en se connectant (`JENKINS_AGENT_NAME` dans `compose.yaml`) |
| `labelString` | ses labels, séparés par des espaces. Un stage choisit un agent par label : `maven`, `docker` ou `scan` |
| `numExecutors: 2` | le nombre de stages que l'agent peut exécuter en même temps |
| `remoteFS` | le dossier de travail de l'agent, où vivent les workspaces |
| `launcher.inbound.webSocket: true` | l'agent se connecte lui-même, par WebSocket sur le port HTTP de Jenkins : pas besoin d'ouvrir le port 50000 |

🚧 **À compléter** dans `stack/jenkins/casc/jenkins.yaml`, à la place du `# TODO` :

```yaml
  nodes:
    - permanent:
        name: agent1
        labelString: "maven docker scan"
        numExecutors: 2
        remoteFS: /home/jenkins/agent
        launcher:
          inbound:
            webSocket: true
    # TODO : déclarez le nœud agent2, sur le modèle d'agent1 (mêmes labels, mêmes exécuteurs, même dossier)
```

Respectez l'indentation : le second `- permanent:` s'aligne sur le premier.

> 📖 [Les exemples de configuration JCasC](https://github.com/jenkinsci/configuration-as-code-plugin/tree/master/demos) · [La gestion des secrets dans JCasC](https://github.com/jenkinsci/configuration-as-code-plugin/blob/master/docs/features/secrets.adoc) · [Les agents inbound](https://github.com/jenkinsci/docker-agents/blob/master/README_inbound-agent.md)

## Recharger la configuration sans redémarrer

Le dossier `casc` est monté dans le conteneur : Jenkins voit déjà votre fichier modifié. Il reste à lui demander de le relire. Ouvrez **Administrer Jenkins › Configuration as Code**, puis cliquez sur le bouton ↻ en haut à droite, dont l'infobulle dit **Reload configuration**. La ligne *Last time applied* se met à jour.

Il n'y a rien à faire du côté d'`agent2` : son script réessaie toutes les cinq secondes, et la page de connexion existe maintenant. Relisez son journal :

```exec "Relire le journal d'agent2"
cd ~/byte-layers/jenkins/pipeline/stack && docker compose logs agent2 --tail 2
```

Les deux dernières lignes doivent annoncer la connexion :

```
agent2-1  | INFO: WebSocket connection open
agent2-1  | INFO: Connected
```

Dans **Administrer Jenkins › Nodes**, `agent2` apparaît, en ligne, à côté d'`agent1`.

```verify
P=$(cat "$HOME/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password" 2>/dev/null)
R=$(curl -fsS -u "admin:$P" "http://localhost:28500/computer/api/json?tree=computer%5BdisplayName,offline%5D" 2>/dev/null) || { echo "Jenkins ne répond pas, ou le mot de passe d'admin ne correspond pas."; exit 1; }
for a in agent1 agent2; do
  if ! echo "$R" | grep -q "\"displayName\":\"$a\",\"offline\":false"; then
    echo "$a n'est pas en ligne. Vérifiez sa déclaration dans jenkins.yaml, rechargez la configuration, puis lisez docker compose logs $a."
    exit 1
  fi
done
echo "agent1 et agent2 sont en ligne."
```

```hint
Si le rechargement affiche une erreur de syntaxe, comparez l'indentation de votre bloc avec celle d'`agent1` : en YAML, deux espaces de trop ou de moins changent le sens du fichier.
```

````solution
```yaml
  nodes:
    - permanent:
        name: agent1
        labelString: "maven docker scan"
        numExecutors: 2
        remoteFS: /home/jenkins/agent
        launcher:
          inbound:
            webSocket: true
    - permanent:
        name: agent2
        labelString: "maven docker scan"
        numExecutors: 2
        remoteFS: /home/jenkins/agent
        launcher:
          inbound:
            webSocket: true
```
Le fichier complet est [`solution/stack/jenkins/casc/jenkins.yaml`](../../solution/stack/jenkins/casc/jenkins.yaml).
````

🏢 En entreprise, ce fichier vit dans un dépôt Git, et une modification passe par une revue comme du code. Rejouer la configuration d'un Jenkins de secours, ou en monter un second pour tester une mise à jour de plugin, devient une question de minutes.

## Les agents utilisent le moteur Docker de votre poste

Ouvrez [`stack/compose.yaml`](../../stack/compose.yaml) au service `agent1`. Son premier volume monte le **socket Docker** de votre poste, `/var/run/docker.sock`, le fichier par lequel la CLI parle au moteur (le daemon, `dockerd`). L'image de l'agent contient la CLI Docker : quand un stage lance un conteneur, c'est le moteur de votre poste qui le crée.

⚠️ **À ne pas reproduire en production.** Quiconque peut écrire dans ce socket pilote le moteur, et peut donc lancer un conteneur privilégié qui lit tout le disque de l'hôte : c'est l'équivalent d'un accès root. Sur un vrai serveur, on préfère des agents éphémères créés à la demande par un plugin (Docker, Kubernetes), ou un moteur dédié aux builds, isolé de la machine qui héberge Jenkins.
