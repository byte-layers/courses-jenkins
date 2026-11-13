---
title: "Une image autour du JAR testé, marquée du commit, poussée dans le registre"
description: "Le Dockerfile d'exécution et son .dockerignore, le tag calculé au checkout, docker build et docker push depuis un agent"
---

Le JAR testé est publié. L'image doit contenir **ce même JAR**, et non une nouvelle compilation : c'est la garantie que ce qui tourne en production est exactement ce que les tests ont validé, au bit près. Le `Dockerfile` ne compile donc rien : il copie le JAR repris du stash dans une image qui sait l'exécuter.

## Ajouter le Dockerfile d'exécution au dépôt

PetClinic ne fournit pas de `Dockerfile`. Celui que vous allez ajouter est celui du lab « Livrer une application Java sécurisée », dans sa version « JAR compilé par la CI » ; si vous l'avez suivi, vous le reconnaîtrez. Il part d'une image de JRE à la version précise, crée un utilisateur sans droits, déclare un healthcheck, et copie le JAR en dernier pour profiter du cache de construction.

Créez-le à la racine de votre copie de PetClinic :

```exec "Créer le Dockerfile"
cat > ~/byte-layers/jenkins/pipeline/petclinic/Dockerfile <<'EOF'
# L'image d'exécution : un JRE seul, Java 21, Ubuntu 24.04 (noble)
FROM eclipse-temurin:21.0.13_9-jre-noble

# Les métadonnées de l'image, au format OCI
LABEL org.opencontainers.image.title="petclinic" \
      org.opencontainers.image.description="Spring PetClinic, image d'exécution" \
      org.opencontainers.image.source="https://github.com/spring-projects/spring-petclinic" \
      org.opencontainers.image.licenses="Apache-2.0"

# Un utilisateur système dédié, sans dossier personnel ni shell de connexion
RUN groupadd --system --gid 10001 petclinic \
 && useradd --system --uid 10001 --gid petclinic --no-create-home --shell /usr/sbin/nologin petclinic

WORKDIR /app

# La JVM prend 75 % de la mémoire accordée au conteneur
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"

EXPOSE 8080

# Un healthcheck par défaut, que celui qui lance le conteneur peut remplacer
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/actuator/health || exit 1

# Ce qui change à chaque version vient en dernier : le JAR, propriété de root
COPY target/spring-petclinic-*.jar /app/petclinic.jar

USER petclinic

ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
EOF
```

Ajoutez ensuite un fichier `.dockerignore`. Le **contexte de build**, ce que `docker build` envoie au moteur, serait sinon tout le workspace : le code, les rapports des scanners, le dossier `target/`. Ce fichier est écrit en **liste blanche** : `*` exclut tout, puis la ligne en `!` réintègre le seul fichier utile, le JAR :

```exec "Créer le .dockerignore"
printf '# Le contexte de build ne contient que le JAR\n*\n!target/spring-petclinic-*.jar\n' > ~/byte-layers/jenkins/pipeline/petclinic/.dockerignore
```

> 📖 [La référence du Dockerfile](https://docs.docker.com/reference/dockerfile/) · [Le fichier `.dockerignore`](https://docs.docker.com/build/concepts/context/#dockerignore-files)

## Donner à chaque image un tag qui dit d'où elle vient

Un tag comme `latest` ne dit rien : impossible de savoir quel code contient l'image, ni de revenir à la précédente. Le lab marque chaque image avec le début de l'empreinte du commit, puis le numéro du build, par exemple `b83e416-8`. On retrouve ainsi le code exact de l'image (`git show b83e416`), et le build qui l'a produite.

Le numéro de build est dans la variable `BUILD_NUMBER`. L'empreinte du commit demande plus de soin : le stash `sources` ne contient pas le dossier `.git`, et la commande `git rev-parse` ne marcherait donc pas dans le stage de l'image. La bonne source est le checkout lui-même. L'étape `checkout scm` renvoie une table de valeurs, dont `GIT_COMMIT`, l'empreinte complète du commit récupéré. Dans le stage `Récupérer le code`, remplacez la ligne `checkout scm` par ce bloc :

```groovy
        script {
          def scmVars = checkout scm
          env.IMAGE_TAG = "${scmVars.GIT_COMMIT.take(7)}-${env.BUILD_NUMBER}"   // par exemple 1a2b3c4-12
        }
```

`take(7)` garde les sept premiers caractères. Une variable affectée dans `env` reste disponible pour tous les stages qui suivent, quel que soit leur agent.

## Pousser vers le registre de la stack

Le registre de la stack est publié sur le port 28550 de votre poste. Les commandes `docker build` et `docker push` passent par la CLI de l'agent, mais c'est le **moteur de votre poste** qui construit l'image et qui la pousse, puisque l'agent pilote ce moteur par le socket. Du point de vue du moteur, le registre est donc à l'adresse `localhost:28550`.

Ce détail compte : Docker refuse par défaut de pousser vers un registre en HTTP, sans TLS, sauf si son adresse est `localhost` ou `127.0.0.1`. Le registre de la stack, en HTTP, est donc accepté sans aucun réglage du moteur.

🏢 Un vrai registre est en HTTPS, et demande une authentification : on ajoute alors `docker login`, ou le bloc `docker.withRegistry(url, credentialsId) { … }` du plugin Docker Pipeline, avec un credential déclaré comme celui de Reposilite.

Ajoutez la variable `IMAGE` au bloc `environment` :

```groovy
    IMAGE       = 'localhost:28550/petclinic'   // le registre, vu par le moteur Docker
```

Puis collez ce stage après `Publier le JAR`, au même endroit que lui : juste avant l'accolade qui ferme le bloc `stages`. Complétez ses `// TODO` :

```groovy
    stage("Construire l'image") {
      // TODO : seulement sur la branche main, condition évaluée avant d'attribuer l'agent
      agent { label 'docker' }
      steps {
        // TODO : vider le workspace, puis reprendre sources (pour le Dockerfile) et jar
        // TODO : construire l'image "$IMAGE:$IMAGE_TAG" depuis le dossier courant
        // TODO : pousser cette image
      }
    }
```

Le nom du stage est entre guillemets doubles parce qu'il contient une apostrophe. Pour les commandes, des guillemets simples suffisent, comme pour Maven : c'est le shell qui remplace `$IMAGE` et `$IMAGE_TAG`.

Committez le `Dockerfile`, le `.dockerignore` et le `Jenkinsfile`, puis poussez :

```exec "Committer et pousser"
cd ~/byte-layers/jenkins/pipeline/petclinic && git add Dockerfile .dockerignore Jenkinsfile && git commit -m "Build and push the runtime image" && git push
```

## Lire le tag de l'image dans le registre

Dans le journal du stage `Construire l'image`, la ligne `transferring context` montre la taille du contexte de build, environ 66 Mo, c'est-à-dire le JAR seul. Le push se termine par l'empreinte de l'image :

```
#5 transferring context: 65.85MB 0.7s done
...
b83e416-8: digest: sha256:f69b566a50d859c3df5317cb8a39fc767f714407b1ae6ece1c16de700a26aeee size: 856
```

Le registre n'a pas d'interface web, mais il répond à une API HTTP. Listez les tags de l'image :

```exec "Lister les tags de l'image"
curl -s http://localhost:28550/v2/petclinic/tags/list; echo
```

Vous devez lire le tag du build, avec votre propre empreinte de commit :

```
{"name":"petclinic","tags":["b83e416-8"]}
```

Regardez aussi le nombre de constats de KICS sur ce build : toujours 14. Le scanner lit pourtant votre nouveau `Dockerfile` ; il n'y trouve rien à redire.

⚖️ L'image est poussée sans avoir été lancée une seule fois. Un vrai pipeline ajouterait un **test de fumée** : démarrer le conteneur, attendre que son healthcheck passe, interroger `/actuator/health`. Le lab « Livrer une application Java sécurisée » le fait pas à pas, avec cette même image.

```verify
D="$HOME/byte-layers/jenkins/pipeline/petclinic"
P=$(cat "$HOME/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password" 2>/dev/null)
J="http://localhost:28500/job/petclinic/job/main"
for f in Dockerfile .dockerignore; do
  if ! git -C "$D" ls-tree --name-only origin/main | grep -qx "$f"; then echo "$f n'est pas poussé sur main."; exit 1; fi
done
R=$(curl -fsS -u "admin:$P" "$J/lastBuild/api/json?tree=result,building,number")
if echo "$R" | grep -q '"building":true'; then echo "Le build est en cours : attendez qu'il se termine."; exit 1; fi
N=$(echo "$R" | grep -o '"number":[0-9]*' | cut -d: -f2)
C=$(git -C "$D" rev-parse --short=7 origin/main)
if ! curl -fsS http://localhost:28550/v2/petclinic/tags/list 2>/dev/null | grep -q "\"$C-$N\""; then
  echo "Le registre n'a pas de tag $C-$N (commit de main, puis numéro du dernier build). Lisez le stage « Construire l'image » du dernier build."
  exit 1
fi
echo "L'image $C-$N est dans le registre."
```

```hint
Si `docker build` échoue sur `COPY failed: no source files were specified`, le JAR n'est pas dans le workspace : vérifiez `fresh 'sources', 'jar'`, et l'orthographe de la ligne `!target/spring-petclinic-*.jar` du `.dockerignore`.
```

```hint
Si `docker build` échoue sur `invalid reference format`, la variable `IMAGE_TAG` est vide, et le nom de l'image se termine par `:`. Vérifiez que le bloc `script` qui calcule `env.IMAGE_TAG` remplace bien l'ancien `checkout scm`, dans le stage `Récupérer le code`.
```

````solution
```groovy
    stage("Construire l'image") {
      when { beforeAgent true; branch 'main' }
      agent { label 'docker' }
      steps {
        fresh 'sources', 'jar'
        sh 'docker build -t "$IMAGE:$IMAGE_TAG" .'
        sh 'docker push "$IMAGE:$IMAGE_TAG"'
      }
    }
```
Les fichiers complets sont [`solution/06-image/Jenkinsfile`](../../solution/06-image/Jenkinsfile), [`solution/06-image/Dockerfile`](../../solution/06-image/Dockerfile) et [`solution/06-image/.dockerignore`](../../solution/06-image/.dockerignore).
````
