# Écran d'accueil et armurier

Date : 27/09/2026. Conception validée en conversation le même jour.

## But

Remplacer l'écran d'arrivée actuel (cartes de tenues, onglet armes) par un
écran d'accueil vivant. Les tenues se prennent désormais chez le tailleur ; les
armes partent chez un nouveau PNJ, l'armurier.

Critères de réussite :

- à la connexion, le joueur voit la vraie carte (coin Liar's Bar et
  loup-garou) derrière un écran titre, avec son argent ;
- n'importe quelle touche ou un clic le fait apparaître dans le monde, à sa
  dernière position (le point d'apparition pour une première visite), dans sa
  tenue du tailleur ;
- l'écran montre les parties en cours et les salons en attente, les derniers
  gains et des astuces qui tournent, et la caméra glisse lentement ;
- E sur l'armurier ouvre la page armes existante, et on revient où l'on était
  en la fermant.

Hors sujet : le tableau 3D du crieur (mis de côté), les animations et voix des
PNJ.

## 1. Arrivée

Le mécanisme d'attente du vestiaire reste : le personnage est garé caché hors
carte (`Characters.OuvrirVestiaire`, socle invisible), non possédé, et le
serveur ouvre l'accueil au lieu du vestiaire. Le personnage est invisible
pendant tout l'accueil.

- Serveur, à l'arrivée (`Characters.SurArrivee`) : `accueil:ouvrir` au client
  avec le solde, le plan de caméra, le résumé des parties, les derniers gains.
  Base en panne : on apparaît directement, comme aujourd'hui.
- Client : touche (`Input` `KeyDown`) ou clic (`MouseDown`), bloqués pendant
  l'accueil → `accueil:jouer`. Une seule fois : l'écran se ferme aussitôt.
- Serveur, `accueil:jouer` : habille avec la tenue (`look_de(etat)`), puis
  `Characters.QuitterVestiaire` (dernière position ou point d'apparition).
- Un joueur qui ne touche à rien reste sur l'accueil ; aucune limite de temps.
- Nouveau joueur (aucune apparence enregistrée) : il reçoit au hasard une
  des apparences de base des bots (`Apparences.Aleatoire`), enregistrée comme
  son apparence (`equipement`, rayon `persos`) pour qu'il la retrouve à chaque
  connexion. Il la change ensuite pièce par pièce chez le tailleur.

## 2. Caméra vivante

- Deux plans A et B (position et rotation de caméra) dans `accueil.json`, à
  la racine du serveur (comme `pnj.json`, doc File).
- Commandes dev `/accueil a` et `/accueil b` : le serveur demande au client
  du développeur sa caméra (`accueil:mesurer`, `Player:GetCameraLocation` et
  `GetCameraRotation` n'existent que côté client), le client répond, le
  serveur enregistre.
- Client : `TranslateCameraTo` et `RotateCameraTo` de A vers B puis de B vers
  A, en boucle, sur `accueil.traversee` secondes (40 par défaut, dans
  `Shared/config.lua`). Avec un seul plan ou aucun : plan fixe (A, sinon un
  plan par défaut au-dessus du point d'apparition).

## 3. Bandeaux vivants

### Parties

- Nouveau module serveur `Server/domain/activite.lua`. Chaque jeu s'y
  inscrit : `Activite.Inscrire(nom_du_jeu, resume)`, où `resume()` rend une
  liste de lignes `{ statut = "attente" | "en_cours", joueurs, bots, max, mise,
  detail }` (`detail` : « Nuit 2 », « Manche 3 », « 1 – 0 », facultatif).
- Inscrits : loup-garou (le salon), Liar's Bar (la table), duel (une ligne par
  arène qui n'est pas vide). Le PvP de test n'est pas inscrit.
- Toutes les 2 s, le module refait le résumé ; s'il a changé, il l'envoie aux
  joueurs sur l'accueil (`accueil:parties`). Il ajoute le nombre de joueurs en
  ligne.
- Affichage : une ligne discrète, par exemple « Loup-garou : 5/8 attendent ·
  Liar's Bar en cours · 12 joueurs en ligne ». Rien en cours : « Personne ne
  joue encore : assieds-toi à une table pour lancer une partie. »

### Derniers gains

- `Boutique.Solder` prévient, pour chaque versement de raison `gain`, un
  abonné (`Boutique.SurGain(fn)`, appelé avec la partie, le compte, le
  montant). Le jeu se lit dans le préfixe de la partie (`werewolf:`,
  `liars:`, `duel:`).
- `activite.lua` garde les 10 derniers gains (nom du joueur, jeu, montant) et
  pousse chaque nouveau gain aux joueurs sur l'accueil (`accueil:gain`).
- Affichage : des bandeaux qui glissent, « Léo a gagné 250 au Liar's Bar ».
  Les bonus de participation ne comptent pas.

### Astuces

- Liste `accueil.astuces` dans `Shared/config.lua` ; une phrase toutes les
  6 s, dans un ordre mélangé.

## 4. Page d'accueil

`Client/accueil/accueil.lua` et `accueil.html`, dans le style sketch des
autres écrans (papier, trait tremblé, police Lilita One, `../ui/esquisse.js`) :

- en haut à droite, le solde avec la pile de pièces ;
- au centre, le titre « Fate's Games » et, dessous, « Appuie sur n'importe
  quelle touche pour jouer », qui pulse doucement (`prefers-reduced-motion`
  respecté) ;
- en bas, la ligne des parties et l'astuce du moment ;
- à droite, le fil des gains.

La page ne prend pas le focus : les touches sont lues par le script Lua.

## 5. Armurier

- Nouveau type de PNJ `armurier` dans `SharedConfig.pnj.types`, interaction
  E, action `armurerie`.
- `PnjActions.armurerie` : `Characters.RetournerVestiaire` (garde la position
  quittée), puis ouvre la page vestiaire existante limitée au rayon armes
  (achat, équipement, vitrine 3D inchangés). Fermer la page :
  `Characters.QuitterVestiaire`, retour à la position quittée.

## 6. Ce qui disparaît

- Les cartes de tenues à l'arrivée et le rayon « persos » de la page
  vestiaire. Les données (`possessions`, `equipement`) ne sont pas touchées.

## 7. Tests

- `tests/suites/activite.lua` : inscription de faux jeux, résumé attendu,
  envoi seulement quand le résumé change, fil limité à 10 gains, gains
  construits depuis les préfixes de partie, bonus de participation ignorés.
- En jeu : l'accueil à la connexion, la touche, la caméra A/B, les bandeaux
  pendant une vraie partie, l'armurier.
