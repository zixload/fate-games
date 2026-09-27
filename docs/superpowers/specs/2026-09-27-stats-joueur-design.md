# Stats du joueur sur l'accueil

Date : 27/09/2026. Conception validée en conversation le même jour.

## But

À l'arrivée, l'écran d'accueil montre au joueur ses propres stats : parties
jouées et gagnées par jeu, répartition de ses rôles au loup-garou, argent
gagné.

Critères de réussite :

- la carte « Tes parties » s'affiche sur l'accueil, à gauche, avec les
  chiffres du joueur qui arrive ;
- les chiffres viennent de la base (parties terminées) et du journal de
  l'argent, sans rien inventer ;
- un joueur sans partie voit « Ta première partie t'attend. » ;
- les duels terminés sont désormais enregistrés.

Hors sujet : les rangs, le classement entre joueurs, les stats des autres
joueurs.

## 1. Ce que montre la carte

- **Loup-garou** : parties, victoires et taux (arrondi à l'unité), survies ;
  puis les quatre rôles les plus joués avec leur pourcentage, en petites
  barres, le reste regroupé en « autres ». Noms français : Villageois, Loup,
  Loup blanc, Voyante, Sorcière, Chasseur, Salvateur, Cupidon.
- **Liar's Bar** : parties, victoires et taux, place moyenne (une décimale).
- **Duel** : duels joués, gagnés.
- **Argent** : total gagné en cagnottes, meilleure cagnotte.
- Un jeu sans partie n'a pas de ligne. Aucune partie nulle part : « Ta
  première partie t'attend. »

## 2. D'où viennent les chiffres

Les stats sont rattachées au personnage (`character_id`, un par compte) et
au compte pour l'argent. Les parties avec bots comptent.

- Loup-garou : `werewolf_participants` (`role`, `survived`, `won`) du
  personnage.
- Liar's Bar : `liars_participants` (`placement`, 1 = vainqueur) du
  personnage.
- Duel : nouvelle table `duel_resultats` (migration 7) : `partie`,
  `character_id`, `won`, `created_at`. L'adaptateur du duel prévient un
  abonné à chaque fin de duel (`Adapter.SurFin(fn)`, liste des joueurs
  humains avec leur `character_id` et s'ils ont gagné) ; le module des stats
  écrit une ligne par joueur. Les bots ne sont pas écrits.
- Argent : `ledger`, lignes au crédit du compte (`compte:<id>`) de raison
  `gain` : somme et maximum.

## 3. Module `Server/domain/stats.lua`

- `Stats.Calculer(lignes) -> stats` : pur, testé. Reçoit les réponses brutes
  des requêtes et rend `{ loup_garou, liars, duel, argent, vide }` prêts à
  afficher (taux, pourcentages, top 4 et « autres », place moyenne).
- `Stats.Charger(character_id, account_id, callback)` : lance les requêtes
  (une par source), puis `callback(Stats.Calculer(...))`. Une requête en
  erreur donne des zéros pour sa source, jamais d'échec de l'arrivée.
- `Stats.EnregistrerDuel(partie, joueurs)` : insère les lignes du duel.

## 4. Accueil

- `Accueil.Ouvrir` charge les stats du joueur et les ajoute aux données de
  `accueil:ouvrir` (`stats`). L'accueil s'ouvre sans attendre : les stats
  partent dans un second événement `accueil:stats` dès qu'elles sont prêtes,
  pour ne pas retarder l'arrivée si la base est lente.
- La page affiche la carte « Tes parties » à gauche, dans le style sketch,
  sans chevaucher le titre, les gains ni la ligne du bas.

## 5. Tests

- `tests/suites/stats.lua` : calcul des taux, pourcentages de rôles et
  « autres », place moyenne, joueur sans partie, source en erreur.
- En jeu : la carte après quelques parties de chaque jeu, un duel terminé
  qui apparaît à la connexion suivante.
