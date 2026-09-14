# fate-games

Serveur de mini-jeux sur nanos world. Premier jeu : **loup-garou**.

Le parti pris tient en une phrase : **tout se joue dans le monde, pas à l'écran**. Les cartes
sont des objets tenus en main, le vote consiste à viser quelqu'un, la nuit est un vrai
changement de lumière. L'interface se limite à une invite d'interaction et à une zone de
message transitoire pour ce qui ne peut pas être physique.

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

Rechargement à chaud, dans la console du serveur :

```text
package reload all
```

Les tests exigent Lua 5.4, la même version que la VM du moteur :

```powershell
winget install --id DEVCOM.Lua --exact
```

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

## Règles héritées

Le noyau vient de `zix-medieval` et en garde les règles, qui ne sont pas négociables ici non
plus :

* le client envoie une **intention**, jamais un résultat — le serveur revalide tout ;
* aucune requête SQL bloquante une fois le serveur démarré ;
* l'état volatil s'écrit en différé, jamais à chaque changement ;
* injection de dépendances explicite, aucune globale entre modules ;
* et une règle propre aux jeux à information cachée : **le serveur ne transmet jamais à un
  client une information que ce client n'a pas le droit de connaître.** Ses propres cartes,
  oui. La table des rôles, jamais.
