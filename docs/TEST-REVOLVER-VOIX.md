# Vérification revolver et voix

Mise à jour du 26/09 : le geste a été recalé dans Blender
(`scripts/blender/create_revolver_take_v3.py`) avec le vrai Nagant. Le canon
arrive à environ 1 cm de la tempe du mannequin Creative. Les doigts sont
repositionnés autour de la poignée, le poing reste fermé jusqu'au dépôt, et
l'index se replie sur le clic de tir. Ouvrir
`art/animations/seated_revolver_inspection.blend` pour parcourir le geste avec
le Nagant attaché à `RightHandProp` dans Blender. Les versions
précédentes sont gardées dans `art/animations/v1/` et `v2/`.

Les scripts et les sons OGG du package sont prêts. Les deux animations
`art/animations/seated_revolver_take.fbx` et
`art/animations/seated_revolver_fire.fbx` ont été réimportées dans l'ADK le
26/09 à 07:10. Le cook de `my-asset-pack` lancé ensuite par le joueur date de
07:19. Les commandes de reglage ci-dessous ne touchent que le Lua ; pas de
nouveau cook a lancer.

1. Redémarrer le serveur. Hors partie, saisir `/bots 0` si la chaise en face
   est occupée, puis `/posebot`. Un mannequin Creative apparaît sur la chaise
   opposée et garde la pose du revolver à la tempe sans limite de temps.
   `/posebot 2` choisit explicitement la chaise 2 ; `/posebot stop` retire le
   mannequin. La copie de l'arme utilise exactement la même attache que le jeu.
2. Saisir `/prise` pour lire les six valeurs. `/prise z -2` descend l'arme de
   2 cm ; les axes sont `x`, `y`, `z` en centimètres et `p`, `ya`, `r` en degrés.
   `/prise x y z p ya r` remplace les six valeurs. Chaque changement apparaît
   immédiatement sur le mannequin figé. Reporter les valeurs retenues dans
   `Server/games/liars_bar/data/config.lua` pour les garder après redémarrage.
   `/posebot regard 30 0` permet aussi de vérifier le mouvement de tête.
3. Retirer le mannequin, s'asseoir, puis lancer une partie avec `/bots 3`.
   Lorsqu'on est désigné : E sur son revolver, attendre le cercle rouge, puis
   clic gauche. Avant ce clic, le barillet ne doit pas avancer. La pose reste
   identique à celle du mannequin, grâce au même os `RightHandProp`.
4. Répéter jusqu'à entendre un clic à blanc et un vrai coup de feu. L'arme
   doit revenir devant sa chaise avant le tour suivant.
5. Avec deux vrais joueurs équipés d'un micro, vérifier qu'on s'entend des
   deux côtés de la table et que la voix change de côté dans un casque quand
   on tourne la caméra. Le micro se règle dans Steam ; nanos world gère la
   prise de parole dans ses paramètres audio.

Si le geste semble absent, vérifier les deux assets cuits et `DefaultSlot`
dans `ABP_Creative`. Le visuel Blender se trouve dans
`art/animations/fit_front.png` et `fit_rear.png`. Le calage exact doit encore
être validé dans le jeu après le réglage avec `/posebot`.
