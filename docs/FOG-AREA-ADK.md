# Fog Fab dans `my-asset-pack`

Le fog importé depuis Fab se trouve dans `/Game/FogArea`. Il contient un Blueprint, ses données, matériaux, fonctions et textures. La map `FogArea/Maps/Overview` est une démonstration et ne fait pas partie du pack du jeu.

Dans **l'éditeur ADK déjà ouvert**, exécuter dans la console **Python** :

```python
exec(open(r"C:\Users\ingam\OneDrive\Documents\fate-games\scripts\unreal\import_fog_area.py", encoding="utf-8").read())
```

Le script vérifie les dépendances avant de déplacer les assets avec l'API d'Unreal vers `/Game/MyAssetPack/Imports/FogArea`. Il ne traite ni le shield ni la map du jeu. Attendre `FOG_IMPORT_COMPLETE` dans l'Output Log, puis **Save All** et cuire `my-asset-pack`. Le Blueprint doit alors se trouver à `/Game/MyAssetPack/Imports/FogArea/Blueprints/BP_FogArea` ; vérifier sa présence dans le manifeste du pack après cuisson avant de l'utiliser dans le jeu.

Les éventuels redirecteurs laissés sous `/Game/FogArea` servent à la map de démonstration. Ne pas déplacer cette map dans le pack.
