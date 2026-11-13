---
title: "Répartir le travail sur deux agents avec stash"
description: "Un agent par stage, un seul checkout, et stash pour faire voyager le code et le JAR d'un agent à l'autre"
---

Dans ce chapitre, vous découpez le pipeline en trois stages qui peuvent tourner sur des agents différents. Vous récupérez le code une seule fois, vous le passez au stage de compilation avec `stash`, et vous faites voyager le JAR jusqu'à `agent2`. C'est la base des chapitres suivants, où plusieurs stages tourneront en même temps sur les deux agents.

Comptez environ 30 minutes.
