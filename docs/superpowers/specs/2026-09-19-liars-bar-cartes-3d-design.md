# Liar's Bar — cartes en 3D

18-19/09/2026. Conception validée en conversation (réponses de l'auteur aux questions), écrite pendant
une session autonome. Tout est **à régler en jeu** : échelle et axes du FBX des cartes inconnus.

## Périmètre

Trois étapes, toutes **côté client**, à partir des messages que le serveur envoie déjà :

1. **Ta main** : tes cartes en éventail dans la main du clown, faces visibles pour toi seul.
2. **La table** : les poses face cachée au centre, la dernière pose retournée à la révélation.
3. **Les mains des autres** : un éventail de dos dans la main de chaque autre joueur, bots compris.

Le serveur n'ajoute que deux valeurs synchronisées : `cartes` (le clown tient ses cartes, pose
« cartes en main ») et `liars_chair` (quel personnage occupe quelle chaise, pour que chaque client
sache à qui donner des dos de cartes).

## Principes

**Rien de secret ne quitte le serveur.** Les faces de ta main viennent de `liars:deal`, envoyé à toi
seul. Les faces sur la table viennent de `liars:reveal`, public. Les dos, face cachée et mains des
autres, sont un modèle de carte **fixe** quelle que soit la vraie carte.

**Objets créés par le client.** Chaque carte est un `StaticMesh` créé par le client : il n'existe
que chez lui, et ce client en a l'autorité (doc « Authority Concepts »), donc il peut l'accrocher
(`AttachTo`) et le déplacer. `lifespan_when_detached = 0` : si le porteur disparaît, ses cartes
disparaissent avec lui.

**Une hiérarchie plutôt que des calculs de rotation.** Pivot invisible accroché à l'os de la main
(position et angle réglables), une « fente » invisible par carte disposée en éventail sur le pivot,
et la carte visible dans sa fente avec sa propre rotation réglable. Le moteur compose les rotations,
on n'en écrit aucune à la main. Hypothèse à vérifier en jeu : `SetVisibility(false)` sur le pivot ne
cache pas les objets qui y sont accrochés.

## Décisions

| Sujet | Choix |
| --- | --- |
| Où | Dans la main : os `RightHandProp` du squelette Creative, `hand_r` pour un personnage nanos (bots) |
| Pose | Animation « cartes en main » (`ANIM_Texting`, bras seuls) quand `Cartes` est vrai |
| Modèles | `<Valeur>_of_<Couleur>1` du jeu de 52, couleur tirée au hasard, stable jusqu'à la donne suivante |
| Joker | Remplacé par `Jack_of_Spades1` : le Valet ne sert pas dans ce jeu, aucune confusion |
| Dos | `Ace_of_Spades1` retourné : le dos est le même pour toutes les cartes du jeu |
| Choix | Molette pour déplacer le curseur, clic gauche pour choisir, W X C V B en raccourcis |
| Levée | La carte sous le curseur se soulève un peu, une carte choisie davantage |
| Réglage | Commande client `/fan <clé> <valeurs>`, `/fan` seul affiche tout, comme `/cam` |
| HUD | La ligne texte de la main reste tant que l'éventail n'est pas validé en jeu (`debug_text_hand`) |

## État tenu par le journal (pur, testé)

Curseur dans la main ; nombre de cartes par chaise (5 à chaque carte de table pour chaque joueur
encore en vie, moins chaque pose) ; tas du centre (liste des poses de la manche) ; dernière
révélation ; un compteur de version qui change à chaque modification, que le rendu surveille.

## Hors de cette version

La vraie carte Joker. Des faces différentes pour les dos vus de derrière (on verrait l'As de pique).
Le glissement des cartes de la main vers la table (elles apparaissent directement sur le tas).
