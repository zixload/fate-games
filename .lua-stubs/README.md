# Stubs de l'API nanos world

`annotations.lua` contient les définitions annotées de toute l'API nanos world — classes, méthodes,
signatures, documentation — au format EmmyLua.

Ce fichier n'est **jamais chargé par le serveur**. Il ne sert qu'à l'éditeur.

## À quoi ça sert

Sans lui, `Character(...)` ou `player:GetSteamID()` sont des symboles inconnus pour l'éditeur : une
faute de frappe ou un mauvais ordre d'arguments ne se voit qu'à l'exécution, dans un log. Avec lui,
l'erreur est soulignée à l'écriture, et la documentation de chaque méthode s'affiche au survol.

## Installation côté éditeur

1. Installer l'extension **Lua** de *sumneko* dans VS Code (marketplace).
2. C'est tout : [`.vscode/settings.json`](../.vscode/settings.json) pointe déjà
   `Lua.workspace.library` sur ce dossier.

## Origine et mise à jour

Généré par [`nanos-world/vscode-extension`](https://github.com/nanos-world/vscode-extension) à partir
du dépôt [`nanos-world/api`](https://github.com/nanos-world/api), et publié sur la branche
`docgen-output`.

Pour le remettre à jour :

```powershell
Invoke-WebRequest -UseBasicParsing `
  -Uri "https://raw.githubusercontent.com/nanos-world/vscode-extension/docgen-output/annotations.lua" `
  -OutFile ".lua-stubs\annotations.lua"
```

Récupéré le 13/09/2026 : 10 271 lignes.
