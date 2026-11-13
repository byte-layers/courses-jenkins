---
title: "Lancer quatre contrôles de sécurité en parallèle"
description: "semgrep, osv-scanner, kics et gitleaks dans un bloc parallel réparti sur les deux agents, leurs rapports SARIF dans Jenkins, puis les contrôles déplacés pour tourner pendant la compilation"
---

Dans ce chapitre, vous ajoutez au pipeline quatre contrôles automatiques : l'analyse du code, celle des dépendances, celle des fichiers de configuration, et la recherche de secrets. Ils tournent en même temps, répartis sur les deux agents, et Jenkins affiche leurs résultats. Dans un second temps, vous les déplacez pour qu'ils tournent pendant la compilation, et vous mesurez le temps gagné.

Comptez environ 1 heure. Le premier build télécharge les images des quatre scanners, environ 2,5 Go, dont 1,6 Go pour semgrep.
