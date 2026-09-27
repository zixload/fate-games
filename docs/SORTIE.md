# Sortir et héberger le serveur

## Mode sortie et mode dev

Le dépôt est en **mode sortie** par défaut : aucun bot, aucune commande de dev. Le mode dev
s'active serveur par serveur, dans son `Config.toml`, section `[custom_settings]` :

```toml
[custom_settings]
    dev = true
```

Le serveur relit ce réglage au démarrage (`Server.GetCustomSettings`) et l'annonce à chaque
joueur à son arrivée (`fg:dev`). Ce qu'il ouvre :

| Côté | Commandes |
| --- | --- |
| Serveur | `/bots`, `/posebot`, `/accusebot`, `/prise`, `/argent`, `/arene`, `/botduel`, `/cam`, `/vitesse`, `/saut`, `/lg bots`, `/lg passer`, `/lg brume`, `/pvp` (tout le système de combat) |
| Client | `/fan`, `/lg demo`, `/lg centre`, `/lg ciel`, `/lg nuit`, `/lg ombre`, `/lg son`, `/pvp inverser` |

Ton serveur de développement garde `dev = true` ; le serveur public ne l'a pas.

Reste accessible en mode sortie : l'Atelier (F2), réservé aux Steam ID listés dans
`Packages/atelier/Server/config.lua` (rôles `admin` et `dev`).

## Ce que les joueurs doivent avoir

nanos world, avec l'accès **Playtest** : c'est l'application Steam que les joueurs utilisent pour
rejoindre, et celle que le serveur fait tourner par défaut (doc nanos, Server Installation).

## Héberger (doc nanos : Server Installation, Server Configuration)

### Trois façons

| | P2P (comme aujourd'hui) | Ton PC en dédié | Un serveur loué (VPS) |
| --- | --- | --- | --- |
| Réglage | `dedicated_server = false` | `dedicated_server = true` + ports ouverts | `dedicated_server = true` |
| Ports | aucun | 7777 TCP/UDP et 7778 UDP ouverts sur ta box | ouverts par l'hébergeur |
| Coût | gratuit | gratuit (électricité) | environ 5 à 15 € par mois |
| Allumé | quand ton PC l'est | quand ton PC l'est | tout le temps |
| Téléchargement des assets | lent (relais Steam, ~1 Mo/s) | ton débit montant | le débit du serveur |
| Pour qui | amis, tests | amis, soirées | serveur public |

Le point qui compte le plus : `my-asset-pack` pèse environ **880 Mo** et chaque nouveau joueur le
télécharge depuis le serveur. Régler `max_file_transfer_rate` (Ko/s par joueur, jusqu'à
`max_send_rate`) selon le débit montant disponible. Publier le pack sur le Store de nanos est une
piste pour que les joueurs le récupèrent ailleurs : **à vérifier** dans la doc avant de compter
dessus.

### Installer un serveur propre (VPS ou autre machine)

1. Installer SteamCMD, puis le serveur nanos world (application `1936830`) :
   `steamcmd +force_install_dir <dossier> +login anonymous "+app_update 1936830 -beta public" validate +quit`
   Linux : Ubuntu 22.04 ou 24.04 recommandé, lancer avec `./NanosWorldServer.sh`.
   Windows : installer le Visual C++ Redistributable.
2. Copier dans le dossier du serveur :
   - `Packages/fate-games` et `Packages/atelier` ;
   - `Assets/my-asset-pack` et `Assets/stylized-egypt` (les packs cuits) ;
   - la base `fate.db` si l'on garde les comptes et l'argent (sinon elle se recrée vide).
3. Lancer une fois pour générer `Config.toml`, puis le régler (voir plus bas), et relancer.
4. Le laisser tourner : `tmux` ou un service `systemd` sous Linux, une tâche planifiée sous Windows.

### `Config.toml` du serveur public

```toml
[discover]
    name =             "Fate's Games"
    description =      "Liar's Bar, Loup-Garou et duels, sur une même place."
    language =         "fr"
    announce =         true          # visible dans la liste des serveurs
    dedicated_server = true
[general]
    max_players =      32
    password =         ""            # un mot de passe pour une bêta fermée
[game]
    map =              "my-asset-pack::MapEgypt"
    packages =         [ "fate-games", "atelier" ]
    assets =           [ "my-asset-pack", "stylized-egypt" ]
[custom_settings]
    # pas de dev = true ici
[debug]
    log_level =        1
    async_log =        true
```

Le logo de la liste des serveurs : un `Server.jpg` de 300 × 150 à côté de l'exécutable
(serveur dédié seulement).

Le serveur réécrit `Config.toml` à chaque démarrage : les commentaires et les clés inconnues
disparaissent, `[custom_settings]` reste.

## Avant d'ouvrir au public

- **Licences** des assets distribués dans le pack cuit : modèles Fab et Sketchfab (vérifier les
  conditions, créditer les CC BY), sons (`docs/CREDITS-SONS.md`, dont Mixkit et des sons d'origine
  inconnue comme `gunshot`), animations Mixamo. Une page de crédits en jeu ou sur la fiche du
  serveur.
- Un **mot de passe** pour commencer par une bêta fermée.
- La **base** : sauvegarder `fate.db` régulièrement.
- Le **système de combat** (`/pvp`) n'est pas un mode jouable : il reste en dev tant qu'aucun mode
  PvP n'existe.
