---
title: "Produire la SBOM de l'image et y chercher les vulnérabilités"
description: "syft fait l'inventaire de l'image finale, grype y cherche les failles connues, et une vulnérabilité critique rend le build instable"
---

Dans ce chapitre, vous ajoutez le dernier stage de livraison : l'inventaire de tout ce que contient l'image poussée, au format standard d'une SBOM, puis la recherche de vulnérabilités connues dans cet inventaire. Vous apprenez à transformer l'échec d'une commande en build instable, plutôt qu'en build arrêté.

Comptez environ 40 minutes. Le premier scan télécharge la base de vulnérabilités de grype, environ 3 Go une fois décompressée.
