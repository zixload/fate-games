# Système de combat

Base commune de tous les modes PvP de fate-games (duel, FFA, équipes) et, plus tard, du combat de
Qin RP. Poings, armes blanches, lances, boucliers, arcs, armes à feu et magie obéissent aux mêmes
règles. Les animations viendront avec le temps : le moteur ne dépend d'aucune.

Décidé le 26/09/2026 : les modes PvP passent sur le personnage natif de nanos (`Character`, squelette
du mannequin), qui porte les armes natives, vise, s'accroupit, sprinte et tombe en ragdoll. Les
skins Creative seront reciblés sur ce squelette plus tard. Le loup-garou et le Liar's Bar restent
sur `CharacterSimple`.

## Principes

1. **Le serveur décide de tout.** Le client envoie des intentions (« j'attaque vers la gauche »,
   « je bloque », « je tire dans cette direction »), jamais des dégâts. Le moteur vérifie la
   cadence, la portée, l'endurance, l'angle et la ligne de tir avant d'appliquer quoi que ce soit.
2. **Équitable.** En PvP, les armes achetées sont des apparences : chacune pointe vers un
   archétype dont les chiffres sont les mêmes pour tous. Aucun hasard ne décide d'un duel : la zone
   touchée vient de la visée, pas d'un tirage.
3. **Lisible.** Chaque attaque s'annonce (temps d'armement visible), chaque défense a une réponse :
   on peut toujours parer, bloquer ou esquiver ce qu'on voit venir. Le meilleur joueur gagne.
4. **Réaliste sans être punitif.** Les zones comptent (la tête tue vite, les jambes ralentissent),
   l'armure compte selon le type de coup, l'épuisement compte. Mais un combat dure assez pour
   qu'on puisse se reprendre.
5. **Portable.** `Server/combat/` est du Lua pur, sans nanos ni fate-games : moteur, données,
   géométrie. On le copie tel quel dans Qin RP. L'adaptateur nanos est à part.

## Le combattant

| Jauge | Rôle |
| --- | --- |
| **Santé** | 100 par défaut. À 0 : mort, ou « à terre » si le mode le permet (RP). |
| **Endurance** | 100. Payée par les attaques, les blocages encaissés, l'esquive, le sprint. Remonte après un court délai sans effort. À 0 : épuisé (pas d'attaque lourde, pas d'esquive, garde fragile). |
| **Posture** | 100. Monte quand on encaisse en garde ou qu'on se fait parer ; redescend seule. Pleine : **garde brisée**, étourdi puis vulnérable. |
| **Mana** | Pour la magie, 100. Remonte lentement. |

Zones touchées et multiplicateurs de dégâts : tête ×2,0, torse ×1,0, bras ×0,75, jambes ×0,8. Un
coup aux jambes ralentit un instant, un coup à la tête étourdit si c'est un coup contondant lourd.

## Types de dégâts et armure

Chaque coup a un type : **tranchant** (épées, haches), **perforant** (lances, flèches, dagues),
**contondant** (poings, masses, bouclier), **balistique** (armes à feu), **magique** (feu, foudre,
glace), **chute**. Chaque armure réduit chaque type différemment :

| Armure | Tranchant | Perforant | Contondant | Balistique | Magique |
| --- | --- | --- | --- | --- | --- |
| aucune | 0 % | 0 % | 0 % | 0 % | 0 % |
| tissu | 10 % | 5 % | 10 % | 0 % | 15 % |
| cuir | 25 % | 15 % | 15 % | 10 % | 10 % |
| mailles | 50 % | 20 % | 15 % | 20 % | 0 % |
| plaques | 65 % | 45 % | 10 % | 35 % | 0 % |

La pénétration d'une arme retire des points de réduction (une lance perce les mailles). La masse
contourne les plaques, la magie ignore le métal : chaque armure a une faiblesse.

## Le corps à corps

Une attaque passe par trois temps : **armement** (on la voit venir, on peut feinter), **frappe**
(la fenêtre où elle touche), **récupération** (on est exposé). Deux forces : **légère** (rapide,
peu de dégâts) et **lourde** (lente, grosse posture, ne peut pas être parée par une arme légère,
brise les gardes épuisées). Trois directions : **gauche**, **droite**, **haut**, prises du dernier
mouvement de souris au moment de l'attaque.

Défenses :

- **Garde** : on tient le clic droit, orientée dans une direction. Un coup venant de cette
  direction et de face est bloqué : pas de dégâts (sauf la part qui traverse la garde), de
  l'endurance et de la posture en moins. Un bouclier bloque toutes les directions de face.
- **Parade** : poser la garde dans la bonne direction dans les 180 ms avant l'impact. Le coup est
  annulé, l'attaquant perd beaucoup de posture et reste exposé. Récompense la lecture.
- **Esquive** : un pas vif, invulnérable pendant 250 ms, coûte de l'endurance, courte récupération.
- **Feinte** : annuler son armement avant la frappe, contre de l'endurance. Punit les parades
  devinées.
- **Bousculade** : un coup d'épaule rapide qui ne blesse pas et ne se bloque pas. Il fait perdre
  de la posture et, sur une garde tenue, la fait tomber un instant (étourdi). C'est la réponse à
  qui s'enferme derrière son bouclier ; on la contre en esquivant ou en frappant pendant son
  armement.

La portée et l'angle viennent de l'arme : une lance touche loin et étroit, une hache près et
large. Le moteur trouve les cibles par la géométrie (distance, arc devant l'attaquant, hauteur) :
le serveur ne sait pas tracer de rayon dans nanos, il n'en a pas besoin pour le corps à corps.
Un coup ne touche chaque cible qu'une fois ; une arme large peut toucher plusieurs cibles.

Archétypes : poings, dague, épée courte, épée longue, hache, masse, lance, épée et bouclier,
bâton. Chacun a sa vitesse, sa portée, son arc, ses dégâts par type, son coût d'endurance et sa
posture.

## Tir

- **Armes à feu** (pistolet, revolver, fusil, fusil à pompe) : le client trace la balle (lui seul
  a `Trace`) et désigne la cible et la zone. Le serveur rejoue le tir avec les positions d'il y a
  « ping » millisecondes (compensation de latence plafonnée à 250 ms) et vérifie que le rayon passe
  bien par la capsule de la cible, que la cadence et le chargeur le permettent et que la portée est
  respectée. Dégâts réduits avec la distance. Dispersion selon le mouvement, l'accroupi, la visée.
- **Arcs** : une flèche est un projectile simulé par le serveur (vitesse, gravité, rayon). On
  bande l'arc : plus on tient, plus la flèche part vite et fort, jusqu'à un maximum ; tenir trop
  longtemps fatigue. Les murs : le client signale l'impact d'une flèche sur le décor.
- Les armes natives de nanos (`Weapon`) sont utilisées pour le rendu, les sons et le recul ; leurs
  dégâts natifs passent par l'événement `TakeDamage`, que le moteur réécrit (zone, armure,
  distance) ou annule.

## Magie

Chaque sort : coût en mana, temps d'incantation (interrompu si on se fait toucher fort),
temps de recharge, forme.

| Sort | Forme | Effet |
| --- | --- | --- |
| Trait de feu | projectile | dégâts magiques, brûlure |
| Onde de choc | cône court | repousse, casse la posture, peu de dégâts |
| Éclair | instantané, ligne | dégâts magiques élevés, courte portée, long rechargement |
| Gel | projectile | ralentit fortement |
| Soin | soi ou allié | rend de la santé sur la durée |
| Barrière | soi | absorbe des dégâts quelques secondes |
| Bond | soi | courte téléportation vers l'avant |

Contre-jeu : on voit l'incantation, on peut l'interrompre, l'esquiver, ou la bloquer (un bouclier
arrête les projectiles, une garde en réduit une partie).

## Statuts

Saignement (dégâts dans le temps, arrêté par un soin), brûlure, ralenti, étourdi (aucune action),
renversé (au sol un instant, ragdoll), vulnérable (dégâts reçus ×1,5 après une garde brisée),
barrière. Chaque statut a une durée, se renouvelle au lieu de s'empiler, et l'adaptateur le
traduit (vitesse, ragdoll, effet visuel).

## À terre (RP)

Si le mode l'active : à 0 de santé on tombe **à terre** au lieu de mourir. On rampe lentement, on
se vide de son sang pendant un temps, un allié peut nous **relever** (quelques secondes sans être
touché), un ennemi peut nous **achever**. Les modes PvP arcade le désactivent : on meurt tout de
suite.

## Équilibre

`lua scripts/combat/equilibrage.lua` fait s'affronter des bots (100 combats par affiche). Repères
au 27/09/2026 : à armes égales le bot difficile bat le facile 92 fois sur 100, l'épée courte en
miroir fait 56–44, le bouclier bat l'épée longue 65–35, la hache bat la lance 70–30, la dague
reste l'arme la plus exigeante (20 % contre la masse). Les armements sont de 0,35 à 0,55 s pour
une légère : assez pour lire le coup et le bloquer.

En terrain ouvert, les armes à feu et l'arc battent toujours une arme de corps à corps : les modes
regroupent donc les classes d'armes (arène de corps à corps, mode armes à feu, mode libre assumé).

## Équité et triche

- Aucune valeur de dégâts ne vient du client ; les intentions trop rapprochées sont ignorées.
- La cadence, la portée, l'angle et l'état (étourdi, épuisé, mort) sont vérifiés au serveur.
- Compensation de latence bornée, pour qu'un gros ping ne tire pas dans le passé.
- Hasard : aucun sur les dégâts. Le seul hasard (dispersion d'un fusil à pompe) vient d'un
  générateur donné par le mode, reproductible.

## Architecture

```
Server/combat/            Lua pur, portable (Qin RP)
  regles.lua              zones, types, armures, constantes
  armes.lua               archétypes de corps à corps et de tir
  sorts.lua               sorts
  geometrie.lua           vecteurs, arcs, rayon contre capsule
  moteur.lua              combattants, intentions, résolution, avancée du temps -> effets
Server/games/pvp/         adaptateur nanos : Character, Weapon, entrées, effets -> jeu
Client/pvp/               entrées (souris, touches), HUD (jauges, direction de garde)
```

Le moteur suit le même contrat que celui du loup-garou : un état, des fonctions qui le font
avancer et rendent une liste d'effets (`degats`, `bloque`, `pare`, `esquive`, `statut`, `mort`,
`a_terre`, `projectile`...), et l'adaptateur les traduit. Tout est testé hors du jeu.

## Essayer (mode dev)

Le système tourne en parallèle du duel, qu'il ne touche pas. Serveur redémarré, dans le chat :

| Commande | Effet |
| --- | --- |
| `/pvp` | entrer (personnage natif, épée longue) ou sortir (on retrouve son personnage) |
| `/pvp arme <id>` | poings, dague, epee_courte, epee_longue, hache, masse, lance, epee_bouclier, baton, pistolet, revolver, fusil, fusil_pompe, fusil_precision, arc, arbalete |
| `/pvp armure <id>` | aucune, tissu, cuir, mailles, plaques |
| `/pvp bot [arme] [niveau]` | un bot devant soi (facile, normal, difficile) |
| `/pvp bots` | retirer les bots |
| `/pvp aterre` | à terre au lieu de mourir (RP) |
| `/pvp soin` | se remettre à neuf |
| `/pvp inverser` | inverser le geste vertical de garde |

Commandes en combat :

| Touche | Corps à corps | Arc | Armes à feu |
| --- | --- | --- | --- |
| clic gauche | attaque légère | tenir pour bander, relâcher | tir (natif) |
| clic molette ou F | attaque lourde | | |
| clic droit tenu | garde ; la souris choisit le côté, la caméra suit l'ennemi | | visée (native) |
| Q | feinte pendant l'armement | | |
| V | bousculade (traverse la garde, sans dégâts) | | |
| Alt gauche | esquive (direction : touches tenues) | esquive | esquive |
| & é " ' ( - è (AZERTY) ou 1 à 7 (QWERTY) | sorts : trait de feu, onde de choc, éclair, gel, soin, barrière, bond | | |
| G | relever un allié à terre, achever un ennemi à terre | | |

Au-dessus d'un ennemi qui arme un coup : le côté où mettre sa garde (`<<`, `>>`, `^`), jaune
pour une légère, rouge pour une lourde, avec une barre qui se vide jusqu'à l'impact. Sa garde
tenue s'affiche en gris.

Ce qui reste provisoire : les animations (celles du pack par défaut), les modèles d'épées et de
bouclier (pied-de-biche, batte), l'arc sans modèle. Le moteur n'en dépend pas.
