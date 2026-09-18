# Vision d'ensemble

Ce que fate-games doit devenir. Ce n'est ni une spec ni un plan : c'est le cap que chaque spec
doit respecter.

## Le parcours d'un joueur

On rejoint un lobby, puis on arrive sur la carte. La carte est un lieu partagé, et chaque jeu y
occupe **son propre coin** :

- **Liar's Bar** : une table et des chaises ;
- **le loup-garou** : ailleurs sur la carte, avec ses propres sièges ou emplacements de jeu.

Il n'y a ni menu de sélection ni écran de chargement entre les jeux. On marche jusqu'à celui qui
nous intéresse.

## Le même fonctionnement pour chaque jeu

1. On s'assoit à une place libre. S'asseoir, c'est s'inscrire.
2. Une fois assez de joueurs assis, n'importe lequel d'entre eux lance la partie. Aujourd'hui,
   c'est E sur le revolver. Le geste définitif, un bouton ou une interface, reste **à décider**.
3. La partie se joue sur place, à la vue de tous.

Un nouveau jeu doit reprendre ce schéma plutôt que d'en inventer un autre.

## Les spectateurs

Les gens autour peuvent **regarder les autres jouer**. Conséquence pour chaque jeu :

- l'information publique est diffusée à tous les joueurs connectés, pas seulement aux joueurs
  assis. Liar's Bar le fait déjà : les effets d'audience `"all"` partent en diffusion générale ;
- l'information secrète (une main, un rôle) ne va qu'à son propriétaire ;
- l'interface d'un spectateur est un sous-ensemble de celle d'un joueur : il voit la table, pas
  les mains.
