---
title: "Ouvrir une pull request, la mettre à jour, la fusionner"
description: "Le sous-job PR-1, le Jenkinsfile lu dans la branche de la pull request, le statut renvoyé à Gitea, puis la fusion qui publie"
---

Une **pull request** (une *merge request* chez GitLab) est une demande de fusion d'une branche dans une autre, ouverte à la relecture. Le pipeline y joue le rôle du premier relecteur : avant qu'un humain ne lise le code, il dit si la branche compile, passe ses tests et ses contrôles.

## Ouvrir la pull request dans Gitea

Ouvrez le dépôt `spring-petclinic` dans Gitea, onglet **Pull Requests**, puis **New Pull Request**. Choisissez `main` comme branche cible (*merge into*) et `feature/welcome` comme branche source (*pull from*), puis créez la pull request avec un titre, par exemple « Change the welcome message ».

Le webhook prévient Jenkins. Dans le job `spring-petclinic`, un nouvel onglet **Pull Requests** apparaît, avec un sous-job `PR-1`, et son build démarre. Il construit le résultat de la **fusion** de la branche avec `main`, comme le demande le réglage `giteaPullRequestDiscovery { strategyId(1) }` du job : on teste ce qui existera après la fusion, et non la branche seule.

## Le build de la pull request utilise l'ancien pipeline

Ouvrez le **Console Output** du build de `PR-1`. Il compile, teste et lance les quatre contrôles, puis s'arrête sur une seule ligne `skipped` :

```
Stage "Publier le JAR" skipped due to when conditional
```

Les stages `Construire l'image` et `SBOM et scan de l'image` n'y figurent pas du tout.

⚠️ **Piège — le Jenkinsfile vient de la branche, pas de la fusion.**
- *Symptôme :* le build de la pull request suit un pipeline plus ancien que celui de `main`.
- *Cause :* la branche `feature/welcome` a été créée au chapitre sur la publication, quand le `Jenkinsfile` s'arrêtait au stage `Publier le JAR`. Le code construit est bien celui de la fusion (le journal le dit : `Merging remotes/origin/main commit … into PR head commit …`), mais le pipeline suivi est celui du `Jenkinsfile` du dernier commit de la branche. C'est ce qu'on observe avec le plugin Gitea : le `Jenkinsfile` est lu avant la fusion, dans la branche de la pull request.
- *Correctif :* mettre la branche à jour avec `main`. C'est de toute façon la bonne pratique avant une fusion : on vérifie la branche avec le code et le pipeline du moment.

Passez sur la branche, et fusionnez-y `main`. L'option `--no-edit` accepte le message de fusion proposé par Git, sans ouvrir d'éditeur :

```exec "Fusionner main dans la branche"
cd ~/byte-layers/jenkins/pipeline/petclinic && git switch feature/welcome && git merge --no-edit main
```

Poussez ensuite la branche mise à jour, pour que Gitea et Jenkins voient le commit de fusion :

```exec "Pousser la branche"
cd ~/byte-layers/jenkins/pipeline/petclinic && git push
```

Le push relance le build de `PR-1`, et lui seul : tant que la pull request est ouverte, le job ne construit plus la branche `feature/welcome` elle-même (c'est le réglage `giteaBranchDiscovery { strategyId(1) }` du premier chapitre), et son sous-job apparaît grisé. Ce nouveau build de `PR-1` suit le pipeline complet, et saute les trois stages de livraison :

```
Stage "Publier le JAR" skipped due to when conditional
Stage "Construire l'image" skipped due to when conditional
Stage "SBOM et scan de l'image" skipped due to when conditional
```

Lancez la vérification avant de fusionner la pull request, à la section suivante : une fois la pull request fusionnée, Jenkins retire son sous-job.

```verify
P=$(cat "$HOME/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password" 2>/dev/null)
J="http://localhost:28500/job/petclinic/job/PR-1"
if git -C "$HOME/byte-layers/jenkins/pipeline/petclinic" fetch -q 2>/dev/null && git -C "$HOME/byte-layers/jenkins/pipeline/petclinic" grep -q "welcome=Welcome to the byte_layers clinic" origin/main -- src/main/resources/messages/messages.properties; then
  echo "La pull request est déjà fusionnée : cette étape est faite."; exit 0
fi
R=$(curl -fsS -u "admin:$P" "$J/lastBuild/api/json?tree=result,building" 2>/dev/null) || { echo "Le sous-job PR-1 n'existe pas : ouvrez la pull request de feature/welcome vers main dans Gitea."; exit 1; }
if echo "$R" | grep -q '"building":true'; then echo "Le build de PR-1 est en cours : attendez qu'il se termine."; exit 1; fi
if ! curl -fsS -u "admin:$P" "$J/lastBuild/consoleText" 2>/dev/null | grep -q "Stage \"SBOM et scan de l'image\" skipped due to when conditional"; then
  echo "Le dernier build de PR-1 ne suit pas encore le pipeline complet : fusionnez main dans feature/welcome, puis poussez."
  exit 1
fi
echo "La pull request suit le pipeline complet, et ne livre rien."
```

## Le statut renvoyé à Gitea

Revenez sur la pull request dans Gitea. Sous le dernier commit, une coche verte et le libellé `petclinic/pipeline/pr-main` affichent le résultat du build : `This commit looks good`. Le plugin Gitea renvoie ce **statut de commit** à chaque build, en attente puis terminé. Un clic sur **Details** ouvre le build dans Jenkins.

🏢 Dans une équipe, on rend ce statut obligatoire : une règle de protection de la branche `main` (*branch protection*) interdit la fusion tant que le statut n'est pas vert. Dans Gitea, elle se règle dans **Settings › Branches**, avec l'option *Enable Status Check*.

## Fusionner, et voir main livrer

Fusionnez la pull request dans Gitea, avec le bouton **Create merge commit**. La fusion est un push sur `main` : le webhook déclenche un build de `main`, qui passe cette fois par les trois stages de livraison. Le JAR et l'image publiés contiennent le nouveau message d'accueil.

Revenez sur `main` dans votre copie, et récupérez le commit de fusion créé par Gitea :

```exec "Revenir sur main et récupérer la fusion"
cd ~/byte-layers/jenkins/pipeline/petclinic && git switch main && git pull
```

```verify
D="$HOME/byte-layers/jenkins/pipeline/petclinic"
if ! git -C "$D" grep -q "welcome=Welcome to the byte_layers clinic" origin/main -- src/main/resources/messages/messages.properties; then
  echo "La pull request n'est pas fusionnée dans main : fusionnez-la dans Gitea, puis lancez git pull."
  exit 1
fi
if [ "$(git -C "$D" branch --show-current)" != "main" ]; then
  echo "La fusion est faite, mais revenez sur main avec git switch main, puis git pull."
  exit 1
fi
echo "La pull request est fusionnée, et votre copie est à jour."
```

> 📖 [Les pull requests de Gitea](https://docs.gitea.com/usage/issues-prs/pull-request) · [La protection des branches dans Gitea](https://docs.gitea.com/usage/access-control/protected-branches)
