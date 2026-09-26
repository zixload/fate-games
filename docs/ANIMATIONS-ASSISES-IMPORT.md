# Animations assises : chute, cartes et accusation

Les clips Blender utilisent le squelette Creative déjà présent dans
`my-asset-pack` :

| Clip | Fichier source | Asset Unreal | Durée | Déclencheur |
| --- | --- | --- | --- | --- |
| Chute fatale | `art/animations/seated_revolver_fatal.fbx` | `ANIM_Seated_Revolver_Fatal` | 0,8 s | tir fatal |
| Pose de cartes | `art/animations/seated_card_play.fbx` | `ANIM_Seated_Card_Play` | 1,0 s | pose de 1, 2 ou 3 cartes |
| Accusation | `art/animations/seated_accuse_{left,center,right}.fbx` | `ANIM_Seated_Accuse_{Left,Center,Right}` | 1,37 s | pointe la chaise accusée |

La chute démarre après l'image du tir, part vers la gauche (à l'opposé du
revolver contre la tempe droite), relâche les bras et garde le bassin sur la
chaise. Sa dernière image reste affichée jusqu'à la fin de partie. Aucun
ragdoll n'est simulé. Le geste de carte avance la main gauche avec l'éventail
vers le plateau puis la ramène ; les cartes individuelles continuent d'être
animées par le rendu 3D existant.

## Import dans l'ADK

Dans la console Python de l'éditeur Unreal de l'ADK, lancer :

```text
exec(open("C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/import_seated_reactions.py", encoding="utf-8").read())
```

Le script importe les deux FBX sur `SKEL_Animations_Skeleton`, sous
`MyAssetPack/Creative_Characters_FREE/Animations`, enregistre les assets et
contrôle leur durée. Ensuite, cuire `my-asset-pack` dans l'éditeur, puis
redémarrer le serveur pour tester les références Lua. Les sources Blender
`seated_revolver_fatal.blend` et `seated_card_play.blend` permettent de corriger
les poses si le rendu du personnage habillé révèle une intersection.

Les captures `fatal_front_*.png`, `fatal_side_*.png` et
`seated_card_play_*_*.png` dans `art/animations` servent à inspecter le geste
avant l'import. La réaction doit rester visible sur les autres clients et ne
pas gêner la caméra libre du joueur éliminé.

Pour les trois variantes de l'accusation, lancer séparément dans la console
Python de l'ADK :

```text
exec(open("C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/import_seated_accuse.py", encoding="utf-8").read())
```

Le serveur choisit gauche, face ou droite selon la chaise visée. Les FBX et
les fichiers Blender éditables sont dans `art/animations`. Cuire ensuite
`my-asset-pack` dans l'éditeur avant le test en jeu.
