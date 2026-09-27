# PNJ Creative, flûte et chaussures

Ces fichiers s'ajoutent au pack `my-asset-pack` sans modifier les scripts Lua ni la map. Le squelette cible est `SKEL_Animations_Skeleton` du kit Creative (43 os). Les FBX et les aperçus restent dans `art/`, ignoré par Git.

## Fichiers produits

| Usage | Asset après import | Source locale | Boucle |
| --- | --- | --- | --- |
| Tailleur | `my-asset-pack::ANIM_NPC_Tailor_Idle` | `Male Standing Pose.fbx` | 4 s |
| Armurier | `my-asset-pack::ANIM_NPC_Armorer_Idle` | `Armurier Pose.fbx` | 4 s |
| Forain | `my-asset-pack::ANIM_NPC_Showman_Idle` | `Forain Pose.fbx` | 4 s |
| Musicien | `my-asset-pack::ANIM_NPC_Musician_Flute_Idle` | pose créée sur Creative | 6 s |
| Flûte | `my-asset-pack::SM_NPC_Spirit_Flute` | `zelda-spirit-flute.zip` | — |
| Chaussettes écrues | `my-asset-pack::SK_COS_Socks_Ivory` | Creative `Socks_008.obj` complété | — |
| Chaussettes anthracite | `my-asset-pack::SK_COS_Socks_Charcoal` | idem | — |
| Chaussettes à deux lignes noires | `my-asset-pack::SK_COS_Socks_BlackStripe` | idem | — |
| Geta de bois | `my-asset-pack::SK_COS_Geta_Wood` | création Blender | — |

La **main gauche du musicien reprend l'orientation et la courbure des doigts de la main droite**, avec un poignet placé sur l'autre côté des tuyaux. La flûte est inclinée autour de l'embouchure pour tomber entre les mains. Le modèle a été réduit de 600 522 polygones source à 44 486 triangles pour le jeu. Ses 9 couleurs et ses volumes sont conservés. Le mesh est exporté dans le repère local de l'os `RightHandProp` : attacher le `StaticMesh` au personnage avec la règle `SnapToTarget`, socket/bone `RightHandProp`, translation et rotation relatives à zéro. L'animation se joue en boucle (`loop=true`), sans root motion ; faire démarrer la pose et l'attachement dans la même frame. Les deux mains suivent le mouvement du buste ; la tête oscille légèrement et les genoux fléchissent peu pour une musique lente.

Les geta sont conçues avec le dessus de la semelle au niveau des pieds Creative. Quand elles sont portées, **rehausser le personnage entier de 5,8 cm** pour que les deux traverses en bois touchent le sol. Les chaussettes ne demandent pas ce décalage. Les quatre accessoires de pied sont des `SkeletalMesh` skinnés sur le même squelette et peuvent être attachés comme les autres pièces portées du kit.

Les poses de l'armurier et du forain conservent les silhouettes fournies : l'armurier appuie un bras sur le côté et le forain lève un genou. Leur mise en scène devra prévoir un comptoir ou l'espace libre approprié. Les aperçus montrent le mesh Creative neutre pour contrôler la pose, avant attribution des costumes.

Le système PNJ actuel lit `def.anim` dans `Packages/fate-games/Server/domain/pnj.lua` avec `PlayAnimation(anim, "DefaultSlot", true, 0.2, 0.2, 1.0, true)`. Pour les brancher après import : renseigner les quatre références de la table ci-dessus dans `Shared/config.lua`, respectivement sur `tailleur`, `armurier`, `forain` et `musicien`. **Le musicien est actuellement déclaré `assis` dans cette configuration** ; passer ce PNJ en position debout avant d'utiliser son animation de flûte. Ces fichiers Lua sont volontairement laissés au travail en cours de l'utilisateur.

## Régénérer hors de l'éditeur

Dans PowerShell, depuis n'importe quel dossier :

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' -b --python 'C:\Users\ingam\OneDrive\Documents\fate-games\scripts\blender\create_npc_standing_idles.py'
& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' -b --python 'C:\Users\ingam\OneDrive\Documents\fate-games\scripts\blender\create_npc_musician.py'
& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' -b --python 'C:\Users\ingam\OneDrive\Documents\fate-games\scripts\blender\create_creative_footwear.py'
& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' -b --python 'C:\Users\ingam\OneDrive\Documents\fate-games\scripts\blender\check_npc_and_footwear_exports.py'
```

Le second script extrait automatiquement `source/flute_FIN.fbx` du ZIP dans `Downloads` vers `art/cosmetics/npc/flute_source/` si nécessaire. Le ZIP et le FBX restent seulement en local. Les sorties sont dans `art/animations/npc/` et `art/cosmetics/footwear/`.

Dans la **console Python de l'ADK déjà ouvert**, importer les T-shirts et les nouvelles pièces :

```python
exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_creative_tshirt_rarities.py", encoding="utf-8").read())
exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_creative_npc_and_footwear.py", encoding="utf-8").read())
```

Attendre `TSHIRT_IMPORT_COMPLETE 4` puis `NPC_AND_FOOTWEAR_IMPORT_COMPLETE`. Contrôler visuellement les matériaux et l'attachement de la flûte dans l'ADK, faire **Save All**, puis cuire **my-asset-pack**. L'importeur vérifie le type des assets, le squelette et les durées. Il ne lance ni un autre éditeur, ni un serveur, ni le cook.

## Provenance et crédit

- Le corps, la coupe du T-shirt et la base des chaussettes proviennent de [Creative Characters FREE sur Fab](https://www.fab.com/listings/94fd60a2-5659-4fc4-af1d-a8cdd2681c2e), utilisé comme composant de jeu selon la [licence Fab](https://www.fab.com/eula). Les fichiers source Fab ne sont pas committés.
- Flûte : **« Zelda Spirit Flute » par Tom Johnson (Brigyon)**, [page Sketchfab](https://sketchfab.com/3d-models/zelda-spirit-flute-9ba664e2efe54d3298a92d6c4ba1a576), **CC Attribution**, indication de licence fournie par l'utilisateur. Modifications : réduction polygonale, remise à l'échelle, couleurs conservées, export dans le repère de la main. Créditer l'auteur, le titre, le lien, la licence et ces modifications dans les crédits distribués avec le jeu. La page Sketchfab n'a pas pu être lue automatiquement (accès 403) ; vérifier la ligne de licence sur la page avant diffusion.
- Les trois fichiers FBX de poses ont été fournis par l'utilisateur. Leur provenance/licence n'est pas inscrite dans les fichiers ; conserver la preuve d'autorisation de distribution avant diffusion publique du pack.
