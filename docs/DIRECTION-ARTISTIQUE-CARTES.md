# Direction artistique : les cartes de personnage

Pour ChatGPT (génération d'images). Les cartes servent au choix du personnage
à l'arrivée : dix cartes en éventail, **aucun texte**, chaque personnage se
reconnaît à son illustration seule. Maquette : canevas « Choix du skin ».

## Le style

Des cartes à jouer anciennes, comme celles d'un tripot de Liar's Bar :
illustration à l'encre, façon gravure du XIXe siècle adoucie, avec une
couleur posée à plat par-dessus. Les personnages restent ceux du jeu :
des bonshommes ronds et un peu ridicules, tête en forme d'œuf, visage simple.
Le contraste entre un cadre sérieux et un personnage idiot est le ton voulu.

- **Palette** : papier crème `#efe6d2`, encre `#1c2123`, laiton `#c5a774`,
  un seul rouge `#e83d37` réservé aux accents (nez du clown, détails).
- **Cadrage** : buste de face, tête et épaules, centré, même taille de tête
  sur les dix cartes, fond crème uni.
- **Trait** : contour encre régulier, hachures fines pour les ombres, pas de
  dégradé numérique, pas de 3D.
- **Interdits** : texte, lettres, chiffres, signature, logo, bordure dessinée
  (le cadre est commun et fourni à part).

## Ce qu'il faut produire

1. **Dix portraits**, format 2:3 (1024 × 1536), fond crème uni.
2. **Un cadre de carte vide**, même format : filet laiton, coins ornés,
   centre transparent ou crème uni.
3. **Un dos de carte**, même format : motif symétrique encre et laiton.
4. **Trois icônes** pour l'interface, 512 × 512, fond transparent, même trait :
   une pièce de monnaie du jeu, un cadenas, une porte entrouverte avec une
   flèche (entrer).

Pour que les dix portraits se ressemblent : fais d'abord le Clown, garde-le,
puis demande chaque suivant « dans exactement le même style, le même cadrage
et la même palette que l'image précédente ». Joins si possible une capture du
personnage pris dans le jeu ou dans l'ADK, pour sa tenue exacte.

## Les prompts

Base commune, à placer devant chaque description :

> Vintage playing-card portrait, ink engraving style with fine hatching and
> flat muted color, head-and-shoulders bust facing the viewer, centered,
> plain cream paper background (#efe6d2), palette of cream, dark ink, brass
> and one accent red (#e83d37). The character is a round, goofy cartoon man
> with a smooth egg-shaped head and a simple face. No text, no letters, no
> numbers, no border, no signature.

Puis, pour chaque carte :

1. **Le Clown** : big happy grin, round red clown nose, clown costume split
   yellow and green with a jagged red ruff collar.
2. **La Souris** : wearing a mouse-head hood with two big round ears, calm
   neutral face, soft pyjama collar.
3. **Le Chapeau** : wearing a hat and round glasses, calm face, casual jacket.
4. **L'Étudiant** : short tidy hair, rectangular glasses, plain t-shirt,
   slightly shy look.
5. **Le Ronchon** : grumpy frown, thick moustache, messy hair, jacket.
6. **Le Casque** : big over-ear headphones, happy grin, short hair, t-shirt.
7. **Le Nourrisson** : a grown man with a baby's pacifier in his mouth,
   blank neutral stare, t-shirt.
8. **Le Chauve** : completely bald shiny head, angry look, small moustache,
   jacket, gloved hands visible at the bottom edge.
9. **Le Bavard** : mouth wide open mid-sentence, glasses, cheerful, jacket.
10. **Le Gantier** : angry look, glasses and moustache, raising gloved hands.

## Où les ranger

Les images vont dans le pack d'assets, comme les cartes à jouer du HUD, et
pas dans le dépôt public : `Assets/my-asset-pack/HUD/Personnages/`, en PNG,
nommées par l'identifiant de l'apparence (`clown.png`, `souris.png`,
`chapeau.png`, `etudiant.png`, `ronchon.png`, `casque.png`,
`nourrisson.png`, `chauve.png`, `bavard.png`, `gantier.png`), plus
`cadre.png`, `dos.png`, `piece.png`, `cadenas.png`, `entrer.png`.
