---
title: "Publier le JAR dans Reposilite, depuis main seulement"
description: "Publier le JAR testé sans le recompiler, donner à Jenkins le droit d'écrire dans Reposilite par JCasC, et réserver la publication à la branche main avec when"
---

Dans ce chapitre, le pipeline commence à livrer : il dépose le JAR dans le dépôt Maven de Reposilite. Vous écrivez le stage de publication, vous constatez que Reposilite le refuse, et vous donnez à Jenkins son jeton par la configuration JCasC. Vous réservez enfin la publication à la branche `main`, et vous le vérifiez avec une première branche de travail.

Comptez environ 45 minutes.
