# Base des vêtements et cheveux Creative

Le personnage actuel est déjà modulaire. Ses pièces gardent les mêmes proportions et utilisent l'atlas `Textures_4.png` du kit **Creative Characters FREE**. Le T-shirt `T_Shirt_009` fournit une base plus régulière que le prototype construit par sélection de faces du corps : col, manches et ourlet sont de vrais éléments du maillage.

## Pièces de référence

| Pièce | Source Blender | Asset déjà présent dans l'ADK |
| --- | --- | --- |
| T-shirt | `T_Shirt_009.obj` | `my-asset-pack::SK_T_Shirt_009` |
| Cheveux | `Hairstyle_male_010.obj` | `my-asset-pack::SK_Hairstyle_male_010` |
| Visage | `Male_emotion_usual_001.obj` | `my-asset-pack::SK_Male_emotion_usual_001` |

Le script [`prepare_creative_modular_base.py`](../scripts/blender/prepare_creative_modular_base.py) charge ces trois pièces, conserve leurs UV, rétablit le lien avec l'atlas et enregistre `art/cosmetics/creative_modular_base.blend` ainsi que trois aperçus. Le T-shirt a une subdivision de niveau 2 **pour le travail dans Blender**. Cette subdivision ne modifie pas l'asset Unreal déjà installé.

Commande sur ce poste (Blender installé par Steam) :

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' -b --python 'C:\Users\ingam\OneDrive\Documents\fate-games\scripts\blender\prepare_creative_modular_base.py'
```

Pour une autre installation du kit, ajouter `-- --source-dir <dossier contenant T_Shirt_009.obj et Textures_4.png>`.

## Pour les variantes

- Partir du maillage, des proportions, des UV et de l'atlas Creative. Modifier un matériau ou créer un motif sans refaire la coupe du T-shirt.
- Pour les cheveux, conserver le volume et l'implantation des mèches de la coiffure du kit choisie comme base. Sa texture utilise le même atlas. Une autre coiffure du kit peut servir de base si sa silhouette convient mieux.
- Les fichiers OBJ du VaultCache **n'ont pas les poids de skin du squelette**. Le `.blend` produit est un fichier de conception, pas un FBX `worn` prêt à importer. Une nouvelle géométrie devra être skinnée sur `SKEL_Animations_Skeleton` et contrôlée en pose animée avant l'import. Pour une simple variation de couleur, réutiliser la pièce squelettique déjà importée et changer son matériau, sans dupliquer la géométrie.
- Ne pas publier l'atlas, les OBJ ou le `.blend` brut dans Git. `art/cosmetics/` est ignoré. Le kit provient de [Creative Characters FREE sur Fab](https://www.fab.com/listings/94fd60a2-5659-4fc4-af1d-a8cdd2681c2e) et reste soumis à sa [licence Fab](https://www.fab.com/eula) : les pièces peuvent être incorporées au jeu, mais pas redistribuées comme fichiers source autonomes.

La prochaine étape de production est **une seule pièce de base skinnée et testée en mouvement** si une coupe différente du T-shirt original est souhaitée. Les déclinaisons de couleurs et de motifs viendront ensuite.
