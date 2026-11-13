---
title: "L'inventaire de l'image finale avec syft, puis le scan avec grype"
description: "Ce qu'est une SBOM, pourquoi la faire sur l'image et non sur le code, syft qui lit le registre, grype qui lit la SBOM, catchError et l'archive"
---

osv-scanner a lu le `pom.xml` : il connaît les bibliothèques Java de PetClinic, et rien d'autre. L'image que vous livrez contient bien plus : un système Ubuntu avec ses paquets, un JRE, et le JAR. Une faille dans OpenSSL ou dans le JRE ne se voit pas dans le `pom.xml`. Pour savoir ce que vous livrez vraiment, il faut faire l'inventaire de l'image finale.

## Ce qu'est une SBOM

Une **SBOM** (*Software Bill of Materials*, la nomenclature logicielle) est la liste de tous les composants d'un logiciel, avec leur version, dans un format lisible par une machine. C'est l'équivalent de la liste des ingrédients sur un emballage. Deux formats standard existent : **CycloneDX**, porté par l'OWASP, et **SPDX**, porté par la Linux Foundation. Le lab utilise CycloneDX, en JSON.

Une SBOM sert deux fois. Le jour du build, un scanner la compare aux bases de vulnérabilités. Les mois suivants, quand une nouvelle faille est publiée, on retrouve en quelques secondes les images qui contiennent la bibliothèque concernée, sans les reconstruire. C'est pourquoi on la garde avec le build.

PetClinic produit déjà une SBOM de son code : le journal de compilation montre une ligne `CycloneDX: Writing and validating BOM (JSON)`, et le fichier finit dans le JAR. Elle ne couvre que les bibliothèques Java. Celle que vous allez produire couvre l'image entière.

## Deux outils : syft fait l'inventaire, grype cherche les failles

Le lab sépare les deux métiers, avec deux outils du même éditeur, Anchore :

| Outil | Ce qu'il lit | Ce qu'il produit |
|---|---|---|
| [syft](https://github.com/anchore/syft) | l'image, dans le registre | la SBOM, `petclinic.cdx.json` |
| [grype](https://github.com/anchore/grype) | la SBOM | la liste des vulnérabilités connues, en SARIF |

Séparer les deux permet de rescanner plus tard une SBOM archivée, sans l'image. D'autres outils font les deux en une commande, comme Trivy ; leur comparaison viendra dans un contenu à part, à venir.

Les deux images ont la même particularité : leur version normale ne contient que le binaire, sans shell, et `inside` ne pourrait pas y lancer `cat`. Le lab prend donc leur variante `-debug`, qui ajoute un shell minimal (BusyBox). Leur binaire est à la racine : `/syft` et `/grype`.

⚖️ La variante `-debug` n'est là que pour `inside`. On peut garder les images normales, plus petites, en les lançant directement avec `sh 'docker run --rm …'` ; il faut alors monter soi-même le workspace, avec `--volumes-from` et le nom du conteneur de l'agent, ce qui alourdit la commande.

## syft lit l'image dans le registre

syft tourne dans un conteneur, sur le réseau de la stack. Pour lui, le registre n'est pas `localhost:28550`, qui désignerait son propre conteneur, mais `registry:5000`, le nom du service sur le réseau Compose. C'est le tableau des deux adresses du premier chapitre, appliqué :

```bash
/syft registry:registry:5000/petclinic:$IMAGE_TAG -o cyclonedx-json=petclinic.cdx.json
```

| Morceau | Rôle |
|---|---|
| `registry:` (le préfixe) | la **source** de syft : lire l'image directement dans un registre, sans moteur Docker |
| `registry:5000/petclinic:$IMAGE_TAG` | l'image poussée au chapitre précédent, vue depuis le réseau de la stack |
| `-o cyclonedx-json=petclinic.cdx.json` | le format de sortie, et le fichier où l'écrire |

Deux variables complètent la commande, passées au conteneur par `inside` :

| Variable | Rôle |
|---|---|
| `SYFT_REGISTRY_INSECURE_USE_HTTP=true` | autorise syft à parler au registre en HTTP |
| `SYFT_CACHE_DIR=/home/jenkins/caches/syft` | son cache, dans le volume partagé des agents |

## grype lit la SBOM, et catchError fixe le statut du build

grype lit la SBOM avec la source `sbom:`, et compare chaque composant à sa base de vulnérabilités. Cette base pèse environ 3 Go une fois décompressée : la variable `GRYPE_DB_CACHE_DIR` la range dans le volume partagé, pour ne la télécharger qu'une fois pour les deux agents.

```bash
/grype sbom:petclinic.cdx.json -o sarif --file grype.sarif --fail-on critical
```

L'option `--fail-on critical` fait renvoyer à grype le code 2 s'il trouve au moins une vulnérabilité **critique**. L'étape `sh` échoue alors, et avec elle le build. Comme pour les scanners du chapitre 4, on préfère ici un build instable : le JAR et l'image sont déjà publiés, et on veut lire le rapport. L'étape `catchError` attrape l'échec et fixe le statut :

```groovy
catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
  sh '/grype sbom:petclinic.cdx.json -o sarif --file grype.sarif --fail-on critical'
}
```

| Paramètre | Rôle |
|---|---|
| `buildResult: 'UNSTABLE'` | le statut du build si le bloc échoue |
| `stageResult: 'UNSTABLE'` | le statut du stage, en jaune dans **Pipeline Overview** |

Le rapport et la SBOM se publient dans un bloc `post { always { … } }`, pour être gardés quel que soit le résultat :

| Étape | Rôle |
|---|---|
| `archiveArtifacts artifacts: 'petclinic.cdx.json'` | garde la SBOM avec le build : elle apparaît sous **Build Artifacts** |
| `recordIssues enabledForFailure: true, …` | publie le rapport de grype. Sans `enabledForFailure`, `warnings-ng` ne publie rien quand le build est en échec |

> 📖 [syft](https://github.com/anchore/syft#readme) · [grype et `--fail-on`](https://github.com/anchore/grype#readme) · [L'étape `catchError`](https://www.jenkins.io/doc/pipeline/steps/workflow-basic-steps/#catcherror-catch-error-and-set-build-result-to-failure) · [CycloneDX](https://cyclonedx.org/)

## Ajouter le stage SBOM et scan

Collez ce stage après `Construire l'image`, juste avant l'accolade qui ferme le bloc `stages`, et complétez ses `// TODO` :

```groovy
    stage("SBOM et scan de l'image") {
      when { beforeAgent true; branch 'main' }
      agent { label 'scan' }
      steps {
        cleanWs()
        script {
          // syft lit l'image dans le registre, sur le réseau de la stack
          docker.image('anchore/syft:v1.54.1-debug').inside("--entrypoint= --network ${env.NETWORK} -e SYFT_REGISTRY_INSECURE_USE_HTTP=true -e SYFT_CACHE_DIR=/home/jenkins/caches/syft") {
            // TODO : produire petclinic.cdx.json, au format cyclonedx-json, depuis l'image registry:5000/petclinic:$IMAGE_TAG
          }
          docker.image('anchore/grype:v0.120.1-debug').inside('--entrypoint= -e GRYPE_DB_CACHE_DIR=/home/jenkins/caches/grype') {
            // TODO : une vulnérabilité critique rend le build et le stage instables, au lieu de les arrêter
            //        commande : /grype sbom:petclinic.cdx.json -o sarif --file grype.sarif --fail-on critical
          }
        }
      }
      post {
        always {
          // TODO : archiver petclinic.cdx.json (allowEmptyArchive: true, pour ne pas échouer si syft n'a rien produit)
          // TODO : publier grype.sarif (id grype, nom Grype), même si le build est en échec
        }
      }
    }
```

Ce stage ne reprend aucun stash : il n'a besoin que du nom de l'image, dans `IMAGE_TAG`.

Committez et poussez :

```exec "Committer et pousser"
cd ~/byte-layers/jenkins/pipeline/petclinic && git commit -am "Produce the SBOM and scan the image" && git push
```

## Lire le résultat : un build jaune

Le premier scan dure une à deux minutes, le temps de télécharger la base de grype. Le journal se termine ainsi :

```
+ /grype sbom:petclinic.cdx.json -o sarif --file grype.sarif --fail-on critical
[0081] ERROR discovered vulnerabilities at or above the severity threshold
ERROR: script returned exit code 2
...
[Grype] Created analysis result for 163 issues (found 0 new issues, fixed 0 issues)
Finished: UNSTABLE
```

Le build est jaune : `UNSTABLE`. À la date d'écriture de ce lab, grype trouve 163 vulnérabilités dans l'image, dont 15 critiques et 21 élevées. Ouvrez l'onglet **Grype Warnings** : les critiques ne sont pas dans Ubuntu ni dans le JRE, mais dans deux bibliothèques Java, Tomcat embarqué et Spring MVC. Ce sont les mêmes familles qu'osv-scanner avait signalées sur le `pom.xml`. PetClinic est épinglé sur un commit qui a quelques mois, et ses dépendances ont eu des correctifs depuis.

🏢 Le correctif ne se fait pas dans le pipeline, mais dans le code : monter la version de Spring Boot dans le `pom.xml`, ce qui entraîne Tomcat et Spring MVC. Le pipeline a fait son travail : il a vu le problème, il l'a rendu visible, et il garde la SBOM pour la prochaine faille.

Téléchargez enfin la SBOM depuis **Build Artifacts**, et ouvrez-la : chaque composant y figure avec son nom, sa version et un identifiant normalisé, le **purl** (*package URL*), comme `pkg:maven/org.apache.tomcat.embed/tomcat-embed-core@11.0.22`.

```verify
P=$(cat "$HOME/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password" 2>/dev/null)
J="http://localhost:28500/job/petclinic/job/main"
R=$(curl -fsS -u "admin:$P" "$J/lastBuild/api/json?tree=result,building,artifacts%5BfileName%5D")
if echo "$R" | grep -q '"building":true'; then echo "Le build est en cours : attendez qu'il se termine."; exit 1; fi
if ! echo "$R" | grep -q '"fileName":"petclinic.cdx.json"'; then
  echo "La SBOM n'est pas archivée sur le dernier build de main : vérifiez syft et archiveArtifacts."
  exit 1
fi
if echo "$R" | grep -q '"result":"FAILURE"'; then
  echo "Le build est en échec, et non instable : la commande grype doit être dans un bloc catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE')."
  exit 1
fi
if ! curl -fsS -u "admin:$P" "$J/lastBuild/consoleText" 2>/dev/null | grep -q "\[Grype\] Created analysis result"; then
  echo "Le rapport de grype n'est pas publié : vérifiez recordIssues enabledForFailure: true."
  exit 1
fi
echo "La SBOM est archivée, et le rapport de grype publié."
```

```hint
Si syft échoue sur `connection refused` ou `http: server gave HTTP response to HTTPS client`, vérifiez l'adresse `registry:5000` (et non `localhost:28550`), l'argument `--network` et la variable `SYFT_REGISTRY_INSECURE_USE_HTTP=true`.
```

````solution
```groovy
          docker.image('anchore/syft:v1.54.1-debug').inside("--entrypoint= --network ${env.NETWORK} -e SYFT_REGISTRY_INSECURE_USE_HTTP=true -e SYFT_CACHE_DIR=/home/jenkins/caches/syft") {
            sh '/syft registry:registry:5000/petclinic:$IMAGE_TAG -o cyclonedx-json=petclinic.cdx.json'
          }
          docker.image('anchore/grype:v0.120.1-debug').inside('--entrypoint= -e GRYPE_DB_CACHE_DIR=/home/jenkins/caches/grype') {
            catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
              sh '/grype sbom:petclinic.cdx.json -o sarif --file grype.sarif --fail-on critical'
            }
          }
```
Et le bloc `post` :
```groovy
      post {
        always {
          archiveArtifacts artifacts: 'petclinic.cdx.json', allowEmptyArchive: true
          recordIssues enabledForFailure: true, tool: sarif(id: 'grype', name: 'Grype', pattern: 'grype.sarif')
        }
      }
```
Le fichier complet est [`solution/07-sbom/Jenkinsfile`](../../solution/07-sbom/Jenkinsfile).
````
