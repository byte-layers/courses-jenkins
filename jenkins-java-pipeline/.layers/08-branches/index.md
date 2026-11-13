---
title: "Pull request, fusion et builds cassés exprès"
description: "Ouvrir une pull request dans Gitea et lire son build, fusionner, puis casser un test et laisser fuir un faux secret pour voir le pipeline réagir"
---

Dans ce chapitre, vous faites vivre le pipeline comme une équipe le ferait au quotidien. Vous ouvrez une pull request depuis la branche `feature/welcome`, vous lisez le statut que Jenkins renvoie à Gitea, puis vous la fusionnez. Vous cassez ensuite le build exprès, de deux façons, pour voir la différence entre un échec et un build instable.

Comptez environ 45 minutes.
