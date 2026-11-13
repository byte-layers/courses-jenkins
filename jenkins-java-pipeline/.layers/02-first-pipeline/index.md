---
title: "Écrire le premier Jenkinsfile : compiler et tester PetClinic"
description: "Un stage sur un agent, Maven dans un conteneur, les réglages Maven fournis par Jenkins, les résultats des tests publiés"
---

Dans ce chapitre, vous écrivez le premier `Jenkinsfile` de PetClinic. Il tient en un seul stage : il compile l'application et lance ses tests unitaires dans un conteneur Maven, sur l'un des deux agents, puis publie les résultats des tests dans Jenkins. Vous le poussez dans Gitea, et le webhook déclenche le premier build.

Comptez environ 40 minutes, dont trois à cinq minutes pour le premier build, qui télécharge l'image Maven et les dépendances du projet.
