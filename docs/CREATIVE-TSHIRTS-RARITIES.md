# T-shirts Creative, du commun au légendaire

Le **commun** est le `my-asset-pack::SK_T_Shirt_009` du kit Creative déjà présent dans l'ADK. Le **peu commun** conserve le prototype déchiré approuvé. Les trois variantes suivantes reprennent la coupe et le squelette Creative avec une nouvelle UV pour que les motifs soient nets. Aucun vêtement ni texture sous licence n'est commité : ils restent dans `art/cosmetics/tshirts/`.

| Palier | Nom | Asset après import | Signe distinctif |
| --- | --- | --- | --- |
| Commun | T-shirt Creative | `my-asset-pack::SK_T_Shirt_009` | Coupe et atlas du kit |
| Peu commun | Effiloché | `my-asset-pack::SK_COS_TShirt_Uncommon_Frayed` | Col, poignets et ourlet déchirés |
| Rare | Éclaireur | `my-asset-pack::SK_COS_TShirt_Rare_Compass` | Toile verte, plastron et losange brodé |
| Épique | Éclipse | `my-asset-pack::SK_COS_TShirt_Epic_Eclipse` | Prune, bande claire, symbole d'éclipse, bas évasé |
| Légendaire | Soleil d'or | `my-asset-pack::SK_COS_TShirt_Legendary_Sun` | Bordeaux, soleil doré, coupe plus longue |

Fichiers : `creative_tshirt_rarities.blend`, quatre FBX, trois textures PNG de 2048 px, cinq aperçus et `manifest.json`. La géométrie des nouvelles pièces est skinnée sur les 43 os Creative. Les FBX ont été réimportés dans Blender pour vérifier les os, les poids et les UV. L'import ADK et le rendu en jeu restent à valider.

Régénérer et contrôler les FBX :

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' -b --python 'C:\Users\ingam\OneDrive\Documents\fate-games\scripts\blender\create_creative_tshirt_rarities.py'
& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' -b --python 'C:\Users\ingam\OneDrive\Documents\fate-games\scripts\blender\check_creative_tshirt_exports.py'
```

Dans la console Python de **l'ADK déjà ouvert** :

```python
exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_creative_tshirt_rarities.py", encoding="utf-8").read())
```

Attendre `TSHIRT_IMPORT_COMPLETE 4`, faire **Save All**, puis cuire `my-asset-pack`. Le script ne modifie ni les apparences Lua ni la map. Le modèle du kit utilisé comme source et ses dérivés restent soumis à la [licence Fab](https://www.fab.com/eula) : incorporation au jeu permise, distribution autonome des fichiers source interdite.
