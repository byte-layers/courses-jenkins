---
title: "Construire et pousser l'image de PetClinic"
description: "Ajouter au dépôt un Dockerfile d'exécution durci, construire l'image autour du JAR testé, la marquer du commit et du numéro de build, et la pousser dans le registre"
---

Dans ce chapitre, le pipeline produit le second livrable : l'image Docker de PetClinic. Vous ajoutez au dépôt un `Dockerfile` qui ne fait que copier le JAR dans une image d'exécution durcie, vous donnez à chaque image un tag qui dit d'où elle vient, et vous la poussez dans le registre de la stack.

Comptez environ 35 minutes.
