---
title: "Contrôler l'ensemble, nettoyer, et aller plus loin"
description: "Le contrôle final, la suppression de la stack, de ses volumes et de ses images, un récapitulatif, et les pistes pour la suite"
---

Avant de tout supprimer, un dernier contrôle reprend ce que le lab a construit.

## Contrôler le lab complet

Ce contrôle vérifie, dans l'ordre :

- les deux agents sont en ligne, déclarés par JCasC ;
- le dernier build de `main` a compilé, testé, lancé les quatre contrôles, publié le JAR, poussé l'image, archivé la SBOM et rejoué les tests sur trois versions de Java ;
- la branche `feature/welcome` est fusionnée, et les deux branches `try/` ont donné un build rouge et un build jaune.

```verify
P=$(cat "$HOME/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password" 2>/dev/null)
B="http://localhost:28500"
curl -fsS -o /dev/null -u "admin:$P" "$B/api/json" || { echo "Jenkins ne répond pas : la stack tourne-t-elle encore ?"; exit 1; }
N=$(curl -fsS -u "admin:$P" "$B/computer/api/json?tree=computer%5BdisplayName,offline%5D" 2>/dev/null | grep -oE '"displayName":"agent[12]","offline":false' | wc -l)
[ "$N" -eq 2 ] || { echo "Les deux agents ne sont pas en ligne."; exit 1; }
J="$B/job/petclinic/job/main/lastBuild"
C=$(curl -fsS -u "admin:$P" "$J/consoleText")
for s in "Uploaded to reposilite" "digest: sha256:" "\[Grype\] Created analysis result" "{ (Matrix - JDK = '25')" "\[Gitleaks\] Created analysis result"; do
  echo "$C" | grep -q "$s" || { echo "Le dernier build de main ne contient pas « $s » : relancez-le avec Build Now, puis vérifiez à nouveau."; exit 1; }
done
curl -fsS -u "admin:$P" "$B/job/petclinic/job/try%252Fbroken-test/lastBuild/api/json?tree=result" 2>/dev/null | grep -q '"result":"FAILURE"' || { echo "Le build de try/broken-test n'est pas rouge."; exit 1; }
curl -fsS -u "admin:$P" "$B/job/petclinic/job/try%252Fleaked-token/lastBuild/api/json?tree=result" 2>/dev/null | grep -q '"result":"UNSTABLE"' || { echo "Le build de try/leaked-token n'est pas jaune."; exit 1; }
echo "Le pipeline complet est en place : bravo."
```

## Arrêter la stack et supprimer ses volumes

Si vous voulez garder votre `Jenkinsfile`, copiez-le maintenant hors de `~/byte-layers` : la suite supprime Gitea, puis votre copie locale.

La commande `docker compose down` arrête et supprime les conteneurs et le réseau de la stack. L'option `-v` supprime aussi ses volumes nommés : la configuration et l'historique de Jenkins, le dépôt Gitea, les JAR de Reposilite, les images du registre, et le cache des agents, dont les 3 Go de la base de grype.

```exec "Arrêter la stack et supprimer ses volumes"
cd ~/byte-layers/jenkins/pipeline/stack && docker compose down -v
```

La sortie se termine par la suppression du réseau `layers-jenkins`.

## Supprimer les images

Trois groupes d'images restent sur votre moteur Docker. Les deux premières sont celles que `docker compose up --build` a construites au premier chapitre : `layers-jenkins-jenkins`, nommée par Compose d'après le projet et le service, et `layers-jenkins-agent:local`, nommée par la clé `image:` des agents dans `compose.yaml`. Supprimez-les :

```exec "Supprimer les images de la stack"
docker image rm layers-jenkins-jenkins layers-jenkins-agent:local
```

Supprimez ensuite les images de PetClinic que le pipeline a construites. Elles portent le nom du registre de la stack, avec un tag par build. La boucle suivante les liste par nom et tag, puis les supprime une par une :

```exec "Supprimer les images de PetClinic"
for i in $(docker images --format '{{.Repository}}:{{.Tag}}' localhost:28550/petclinic); do docker image rm "$i"; done
```

Restent les images téléchargées : Maven, les quatre scanners, syft et grype, Gitea, Reposilite, le registre et le JRE. Elles pèsent environ 7 Go. Si aucun autre projet ne s'en sert, supprimez-les :

```exec "Supprimer les images téléchargées"
docker image rm maven:3.9.16-eclipse-temurin-17-noble maven:3.9.16-eclipse-temurin-21-noble maven:3.9.16-eclipse-temurin-25-noble semgrep/semgrep:1.181.1 ghcr.io/google/osv-scanner:v2.6.0 checkmarx/kics:v2.2.0 zricethezav/gitleaks:v8.30.1 anchore/syft:v1.54.1-debug anchore/grype:v0.120.1-debug gitea/gitea:28.2.0 dzikoysk/reposilite:3.6.4 registry:3.1.1 eclipse-temurin:21.0.13_9-jre-noble jenkins/jenkins:2.580.2-lts-jdk21 jenkins/inbound-agent:3395.v6e5377b_0fb_3c-2-jdk21
```

Une image utilisée par un conteneur d'un autre projet ne sera pas supprimée : Docker le signale, et continue avec les suivantes.

## Supprimer le dossier du lab

Le dossier `~/byte-layers/jenkins/pipeline` contient la stack, ses secrets et votre copie de PetClinic. Supprimez-le :

```exec "Supprimer le dossier du lab"
rm -rf ~/byte-layers/jenkins/pipeline
```

```verify
if docker ps -a --format '{{.Names}}' | grep -q '^layers-jenkins-'; then
  echo "Des conteneurs layers-jenkins existent encore : lancez docker compose down -v dans le dossier de la stack."
  exit 1
fi
if docker volume ls --format '{{.Name}}' | grep -q '^layers-jenkins_'; then
  echo "Des volumes layers-jenkins_ existent encore : lancez docker compose down -v."
  exit 1
fi
if [ -d "$HOME/byte-layers/jenkins/pipeline" ]; then
  echo "Le dossier ~/byte-layers/jenkins/pipeline existe encore."
  exit 1
fi
echo "Le poste est nettoyé."
```

## Récap

- **Une instance décrite par du code.** Les plugins sont dans l'image, la configuration dans `jenkins.yaml`, le job dans du Job DSL : un Jenkins se reconstruit à l'identique, et se modifie par une revue de fichiers. Le contrôleur orchestre ; les agents travaillent, chacun avec ses labels et ses exécuteurs.
- **Les outils dans des conteneurs.** Maven et les scanners tournent dans des images de version fixe, lancées par `docker.image().inside` : les agents restent nus, et changer de version se fait dans le `Jenkinsfile`.
- **Les fichiers voyagent par stash.** Un seul checkout, un `stash` par contenu utile, et des workspaces vidés au début de chaque stage.
- **Le parallèle coûte peu.** Ce qui ne dépend pas du JAR tourne pendant la compilation ; une matrice décrit une variation une fois, et Jenkins en déduit les cellules.
- **Le statut dit quoi faire.** Rouge quand le code est faux, jaune quand un constat demande un jugement ; et seul `main` livre, grâce à `when`.

## Pour aller plus loin

Le lab s'arrête là où un vrai projet continuerait. Voici les pistes les plus courantes, dans l'ordre où on les rencontre :

| Piste | De quoi il s'agit |
|---|---|
| Une **shared library** | les fonctions répétées d'un `Jenkinsfile` à l'autre (`fresh`, le lancement de Maven, les quatre scanners) rangées dans un dépôt Git à part, et appelées par `@Library` depuis chaque projet |
| Des **agents éphémères** | des agents créés pour un build puis détruits, par le plugin Docker ou le plugin Kubernetes, à la place des agents permanents et du socket monté |
| La **signature de l'image** | signer l'image poussée avec cosign, et y attacher la SBOM comme attestation, pour que celui qui déploie puisse vérifier sa provenance |
| La **provenance SLSA** | le cadre [SLSA](https://slsa.dev/) décrit des niveaux de confiance dans une chaîne de construction : qui a construit quoi, à partir de quel code, sur quelle machine |
| Le **déploiement continu** | un stage qui déploie l'image sur un environnement de recette, après le build de `main`, puis une validation humaine avec l'étape `input` avant la production |
| La comparaison avec **GitLab CI** et **GitHub Actions** | les mêmes notions sous d'autres noms : runners pour les agents, jobs et stages, artefacts et cache, règles pour `when` |

> 📖 [Les shared libraries](https://www.jenkins.io/doc/book/pipeline/shared-libraries/) · [Le plugin Kubernetes](https://plugins.jenkins.io/kubernetes/) · [cosign](https://docs.sigstore.dev/cosign/signing/signing_with_containers/) · [SLSA](https://slsa.dev/spec/v1.0/)
