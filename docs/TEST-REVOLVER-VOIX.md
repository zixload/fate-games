# Vérification revolver et voix

Mise à jour du 26/09 : le geste a été recalé dans Blender
(`scripts/blender/create_revolver_take_v3.py`) avec le vrai Nagant. Le canon
arrive à environ 1 cm de la tempe du mannequin Creative. La paume est tournée
vers la poignée, le poing reste fermé jusqu'au dépôt, et l'index se replie sur
le clic de tir. Les versions
précédentes sont gardées dans `art/animations/v1/` et `v2/`.

Les scripts et les sons OGG du package sont prêts. Les deux animations
`art/animations/seated_revolver_take.fbx` et
`art/animations/seated_revolver_fire.fbx` doivent encore être importées dans
le pack Unreal avant de lancer le jeu.

1. Dans la console Python de l'ADK, exécuter :
   `py "C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/import_revolver_segments.py"`
2. Vérifier dans `MyAssetPack/Creative_Characters_FREE/Animations` la présence
   de `ANIM_Seated_Revolver_Take` et `ANIM_Seated_Revolver_Fire`, puis cuire
   `my-asset-pack` comme d'habitude. Aucun cook n'a été lancé par Codex.
3. Redémarrer le serveur et le client, s'asseoir, puis lancer une partie avec
   `/bots 3`. Lorsqu'on est désigné : E sur son revolver, attendre le cercle
   rouge, puis clic gauche. Avant ce clic, le barillet ne doit pas avancer.
4. Pendant que l'arme est tenue à la tempe, vérifier le calage initial. La
   position dans `revolver_prise` est une mesure Blender ; si le socket importé
   diffère, affiner avec `/prise x y z tangage lacet roulis` (cm, degrés,
   relatif à `RightHandProp`) : le canon doit toucher la tempe, la poignée doit
   rester dans la main. Reporter les valeurs corrigées dans
   `games/liars_bar/data/config.lua`.
5. Répéter jusqu'à entendre un clic à blanc et un vrai coup de feu. L'arme
   doit revenir devant sa chaise avant le tour suivant.
6. Avec deux vrais joueurs équipés d'un micro, vérifier qu'on s'entend des
   deux côtés de la table et que la voix change de côté dans un casque quand
   on tourne la caméra. Le micro se règle dans Steam ; nanos world gère la
   prise de parole dans ses paramètres audio.

Si le geste semble absent, vérifier les deux assets cuits et `DefaultSlot`
dans `ABP_Creative`. Le visuel Blender se trouve dans
`art/animations/fit_front.png` et `fit_side.png`. Le calage exact doit encore
être validé dans le jeu après l'import Unreal.
