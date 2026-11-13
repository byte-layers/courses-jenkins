---
title: "Tester trois versions de Java avec une matrice"
description: "Le bloc matrix rejoue la compilation et les tests sur Java 17, 21 et 25, en parallèle, sur main et sur les pull requests"
---

Dans ce dernier chapitre de construction, vous vérifiez que PetClinic compile et passe ses tests sur trois versions de Java. Un bloc `matrix` décrit la variation une seule fois, et Jenkins en déduit les trois exécutions, qu'il lance en parallèle sur les agents.

Comptez environ 30 minutes. Le premier build télécharge deux images Maven de plus, environ 1,5 Go.
