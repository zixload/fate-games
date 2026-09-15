# fate-games

[![tests](https://github.com/zixload/fate-games/actions/workflows/tests.yml/badge.svg)](https://github.com/zixload/fate-games/actions/workflows/tests.yml)

Serveur de mini-jeux sur nanos world. Premier jeu : **loup-garou**.

Le parti pris tient en une phrase : **tout se joue dans le monde, pas à l'écran**. Les cartes
sont des objets tenus en main, le vote consiste à viser quelqu'un, la nuit est un vrai
changement de lumière. L'interface se limite à une invite d'interaction et à une zone de
message transitoire pour ce qui ne peut pas être physique.

## Où ça en est

| | |
| --- | --- |
| Socle serveur | architecture modulaire, base SQLite avec migrations, comptes et personnages persistants |
| Autorité serveur | le client envoie une intention, jamais un résultat — tout est revalidé |
| Interaction | visée côté client, revalidation de distance côté serveur, journal d'audit |
| Tests | 74, exécutés hors-jeu contre des bouchons du moteur |
| Loup-garou | conception faite, logique à écrire |
| Testé avec de vrais joueurs | **pas encore** — en attente d'accès au client |

## Développement

```powershell
.\scripts\dev.ps1 start      # monte ce package sur le serveur et démarre
.\scripts\dev.ps1 console    # même chose, en console interactive
.\scripts\dev.ps1 logs -Follow
.\scripts\test.ps1           # banc de test hors-jeu, ne démarre pas le serveur
```

Plusieurs dépôts partagent la même installation de serveur (`C:\nanos-world-server`).
`dev.ps1` s'assure avant chaque démarrage que c'est **ce** package qui est monté et chargé :
lancer le script depuis un autre dépôt bascule automatiquement.

## Structure

```
Packages/fate-games/
  Server/
    Index.lua        point d'entrée, injection de dépendances
    core/            log, ordonnanceur, identifiants, config serveur
    db/              connexion, migrations
    domain/          comptes, personnages, objets interactifs
    intents/         chemin unique des actions joueur
    dev/             test d'intégration sans client
  Client/
    interaction/     visée et invite
  Shared/            données envoyées au client
tests/               banc hors-jeu, bouchons du moteur
.lua-stubs/          annotations de l'API pour l'éditeur
```

