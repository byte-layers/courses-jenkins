---
title: "Casser le build exprès : un test faux, puis un faux secret"
description: "Un test qui échoue donne un build rouge, un secret détecté donne un build jaune : lire chacun, et comprendre la différence"
---

Un pipeline qui reste vert ne prouve pas grand-chose : il faut le voir refuser. Vous allez pousser deux branches de test, chacune cassée d'une façon différente, et lire ce que Jenkins en fait. Elles commencent par `try/`, pour les distinguer des vraies branches de travail.

## Un test qui échoue : le build est rouge

Créez une branche depuis `main` :

```exec "Créer la branche try/broken-test"
cd ~/byte-layers/jenkins/pipeline/petclinic && git switch -c try/broken-test main
```

Ouvrez `src/test/java/org/springframework/samples/petclinic/vet/VetTests.java`. Ce test crée un vétérinaire nommé Zaphod Beeblebrox, le sérialise, puis vérifie que la copie a le même nom. Vous allez remplacer la ligne :

```java
		assertThat(other.getLastName()).isEqualTo(vet.getLastName());
```

par cette ligne, dont l'attente est fausse puisque le vétérinaire ne s'appelle pas Prefect :

```java
		assertThat(other.getLastName()).isEqualTo("Prefect");
```

PetClinic vérifie la mise en forme de son code avant les tests, et son style indente avec des tabulations. Une ligne retapée avec des espaces ferait échouer le build sur la mise en forme, avant même le test. La commande suivante ne change donc que le texte entre parenthèses, avec `perl -pi`, qui modifie le fichier sur place :

```exec "Modifier l'attente du test"
cd ~/byte-layers/jenkins/pipeline/petclinic && perl -pi -e 's/isEqualTo\(vet\.getLastName\(\)\)/isEqualTo("Prefect")/' src/test/java/org/springframework/samples/petclinic/vet/VetTests.java
```

Contrôlez la modification avec `git diff` : une seule ligne change.

```exec "Afficher la modification"
cd ~/byte-layers/jenkins/pipeline/petclinic && git diff
```

Committez, puis poussez la branche. Comme pour `feature/welcome`, l'option `-u` relie la branche locale à celle de Gitea :

```exec "Committer et pousser la branche"
cd ~/byte-layers/jenkins/pipeline/petclinic && git commit -am "Break a test on purpose" && git push -u origin try/broken-test
```

Le build de `try/broken-test` se termine en rouge, `FAILURE`. Le journal de la branche `Compiler et tester` montre l'échec :

```
[ERROR] org.springframework.samples.petclinic.vet.VetTests.serialization -- Time elapsed: 0.016 s <<< FAILURE!
expected: "Prefect"
 but was: "Beeblebrox"
...
[ERROR] Tests run: 79, Failures: 1, Errors: 0, Skipped: 2
```

Trois choses sont à observer :

| Observation | Ce qu'elle montre |
|---|---|
| **Test Result** affiche un échec, avec le nom du test et le message `expected … but was …` | l'étape `junit` dans `post { always { … } }` a publié les résultats malgré l'échec |
| les quatre contrôles sont allés au bout, leurs rapports sont publiés | le bloc `parallel` laisse finir les autres branches, sans `failFast` |
| les stages qui suivent sont sautés, avec `skipped due to earlier failure(s)` | après un `FAILURE`, rien n'est livré, quelle que soit la branche |

```verify
P=$(cat "$HOME/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password" 2>/dev/null)
J="http://localhost:28500/job/petclinic/job/try%252Fbroken-test"
R=$(curl -fsS -u "admin:$P" "$J/lastBuild/api/json?tree=result,building" 2>/dev/null) || { echo "Le sous-job try/broken-test n'existe pas : poussez la branche."; exit 1; }
if echo "$R" | grep -q '"building":true'; then echo "Le build est en cours : attendez qu'il se termine."; exit 1; fi
if ! echo "$R" | grep -q '"result":"FAILURE"'; then echo "Le build de try/broken-test n'est pas en échec : vérifiez la modification du test, puis poussez."; exit 1; fi
F=$(curl -fsS -u "admin:$P" "$J/lastBuild/testReport/api/json?tree=failCount" 2>/dev/null | grep -o '"failCount":[0-9]*' | cut -d: -f2)
if [ "${F:-0}" -lt 1 ]; then echo "Le build échoue, mais pas sur un test : lisez son Console Output."; exit 1; fi
echo "Le test faux fait échouer le build, et Jenkins montre lequel."
```

## Un faux secret : le build est jaune

Repartez de `main`, pour une seconde branche :

```exec "Créer la branche try/leaked-token"
cd ~/byte-layers/jenkins/pipeline/petclinic && git switch -c try/leaked-token main
```

Vous allez écrire dans un fichier un faux jeton GitHub. Un jeton personnel GitHub commence par `ghp_`, suivi de 36 caractères ; `openssl rand -hex 18` en fournit 36 au hasard. Ce jeton n'ouvre rien, mais il a la forme exacte de ceux que gitleaks recherche :

```exec "Écrire un faux jeton dans deploy.env"
cd ~/byte-layers/jenkins/pipeline/petclinic && echo "GITHUB_TOKEN=ghp_$(openssl rand -hex 18)" > deploy.env
```

Ajoutez le fichier, committez et poussez :

```exec "Committer et pousser la branche"
cd ~/byte-layers/jenkins/pipeline/petclinic && git add deploy.env && git commit -m "Leak a fake token on purpose" && git push -u origin try/leaked-token
```

Le build de `try/leaked-token` se termine en jaune, `UNSTABLE`. Le journal de la branche gitleaks montre le seuil franchi :

```
[Gitleaks] -> Some quality gates have been missed: overall result is UNSTABLE
[Gitleaks]    - [Total (any severity)]: ≪Unstable≫ - (Actual value: 1, Quality gate: 1.00)
```

L'onglet **Gitleaks Warnings** donne le fichier, la ligne et la règle, `github-pat`. C'est le seuil posé au chapitre 4 qui joue : un constat de gitleaks suffit à rendre le build instable.

```verify
P=$(cat "$HOME/byte-layers/jenkins/pipeline/stack/secrets/jenkins_admin_password" 2>/dev/null)
J="http://localhost:28500/job/petclinic/job/try%252Fleaked-token"
R=$(curl -fsS -u "admin:$P" "$J/lastBuild/api/json?tree=result,building" 2>/dev/null) || { echo "Le sous-job try/leaked-token n'existe pas : poussez la branche."; exit 1; }
if echo "$R" | grep -q '"building":true'; then echo "Le build est en cours : attendez qu'il se termine."; exit 1; fi
if ! echo "$R" | grep -q '"result":"UNSTABLE"'; then echo "Le build de try/leaked-token n'est pas instable : vérifiez que deploy.env est poussé, et le seuil de gitleaks."; exit 1; fi
echo "Le faux secret rend le build instable."
```

## Rouge ou jaune : ce que chacun veut dire

Les deux builds n'ont pas le même sens, et c'est voulu :

| Cas | Statut | Pourquoi ce choix |
|---|---|---|
| un test échoue | `FAILURE`, rouge | le code ne fait pas ce qu'il doit : rien ne doit être livré, sans discussion |
| un scanner trouve quelque chose | `UNSTABLE`, jaune | un constat se lit et se juge : vrai problème, faux positif, risque accepté. Le build signale, l'équipe décide |

⚖️ Un vrai secret poussé dans Git est plus grave qu'un build jaune : il est dans l'historique, et le supprimer du fichier ne suffit pas. Il faut **révoquer** le secret, puis en émettre un nouveau. C'est pourquoi on lance aussi gitleaks avant le commit, sur le poste du développeur, avec un *hook* Git : le pipeline n'est que le dernier filet.

Revenez sur `main`. Les deux branches de test peuvent rester dans Gitea : elles ne livrent rien.

```exec "Revenir sur main"
cd ~/byte-layers/jenkins/pipeline/petclinic && git switch main
```

> 📖 [Les statuts d'un build Jenkins](https://www.jenkins.io/doc/book/pipeline/syntax/#post) · [Les hooks de gitleaks avec pre-commit](https://github.com/gitleaks/gitleaks#pre-commit)
