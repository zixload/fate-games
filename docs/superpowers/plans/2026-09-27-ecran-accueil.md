# Écran d'accueil et armurier : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** remplacer l'écran d'arrivée (cartes de tenues, onglet armes) par un
écran d'accueil vivant sur la vraie carte, et déplacer les armes chez un PNJ
armurier.

**Architecture :** le joueur qui arrive reste garé caché hors carte (mécanisme
existant `Characters.OuvrirVestiaire`) pendant qu'une page WebUI d'accueil
s'affiche sur la vue de la carte ; un module pur `activite.lua` rassemble le
résumé des jeux et le fil des gains ; un module serveur `accueil.lua` gère
l'arrivée, les plans de caméra et la diffusion ; l'armurier réutilise la page
vestiaire, limitée au rayon armes.

**Tech Stack :** Lua (nanos world 1.156, scripting serveur et client), WebUI
HTML/CSS/JS, banc de test maison `lua tests/run.lua`.

**Spec :** `docs/superpowers/specs/2026-09-27-ecran-accueil-design.md`

## Global Constraints

- Tous les textes affichés sont en français.
- `Events.CallRemote` et `Events.BroadcastRemote` prennent toujours une fiabilité (`Reliability.Reliable` ou `Reliability.Unreliable`) juste après l'événement (et le joueur, côté serveur).
- `Trace`, `Player:GetCameraLocation`, `Player:GetCameraRotation`, `SetMaterialFromWebUI` sont côté client seulement (doc nanos world) ; `Player:SetCameraLocation`, `SetCameraRotation`, `TranslateCameraTo(location, time, exp?)`, `RotateCameraTo(rotation, time, exp?)` marchent des deux côtés, les deux premiers et TranslateCameraTo seulement sans personnage possédé.
- Commandes dev réservées à `dev_pour(player)`.
- Messages de commit au format du dépôt (`ACCUEIL - ...`), **aucune mention d'IA ni ligne Co-Authored-By** ; ne jamais pousser sans l'accord de l'utilisateur.
- Chaque fichier `.lua` touché passe `luac -p` ; chaque page HTML touchée passe `node --check` sur son script ; `lua tests/run.lua` reste entièrement vert.
- Plans A et B de la caméra : fournis plus tard par l'utilisateur (commandes `/accueil a|b`) ; en leur absence, un plan par défaut au-dessus du point d'apparition.

## Review Focus

- Un jeu dont le `resume()` plante : les autres jeux restent affichés (pcall) — test dans la tâche 1.
- Touche pressée deux fois, ou `accueil:jouer` reçu d'un joueur qui n'est plus sur l'accueil : une seule apparition, rien d'autre — garde dans la tâche 4, vérifié en jeu.
- Joueur qui se déconnecte pendant l'accueil : plus aucun envoi vers lui — `Player.Subscribe("Destroy")` dans la tâche 4.
- `accueil.json` absent ou illisible : plan par défaut, aucun plantage — `pcall(JSON.parse)` dans la tâche 4.
- Nouveau joueur : l'apparence tirée est toujours gratuite (donc possédée) et elle est enregistrée — test dans la tâche 2.

---

## Structure des fichiers

- Créer `Packages/fate-games/Server/domain/activite.lua` : résumé des jeux inscrits, détection de changement, fil des 10 derniers gains. Pur, sans API nanos.
- Créer `tests/suites/activite.lua` ; modifier `tests/run.lua` (liste des suites).
- Modifier `Packages/fate-games/Server/domain/boutique.lua` : `Boutique.SurGain`, apparence au hasard d'un nouveau joueur. Modifier `tests/suites/boutique.lua`.
- Modifier les trois adaptateurs : `Server/games/werewolf/adapter.lua` (`A.Resume`), `Server/games/liars_bar/adapter.lua` (`Adapter.Resume`), `Server/games/duel/adapter.lua` (`Adapter.Resume`).
- Créer `Packages/fate-games/Server/domain/accueil.lua` : arrivée, plans A/B (`accueil.json`), commandes `/accueil a|b`, `accueil:jouer`, diffusion des parties et des gains.
- Modifier `Packages/fate-games/Server/Index.lua` : branchement (arrivée, inscriptions, gains, armurier).
- Modifier `Packages/fate-games/Shared/config.lua` : bloc `accueil`, type de PNJ `armurier`.
- Créer `Packages/fate-games/Client/accueil/accueil.lua` et `accueil.html` ; modifier `Packages/fate-games/Client/Index.lua`.
- Modifier `Packages/fate-games/Client/vestiaire/vestiaire.html` et `vestiaire.lua` : mode armurerie.

---

### Task 1 : module `activite.lua` (résumé des jeux, fil des gains)

**Files :**
- Create : `Packages/fate-games/Server/domain/activite.lua`
- Create : `tests/suites/activite.lua`
- Modify : `tests/run.lua` (table `suites`)

**Interfaces :**
- Produces :
  - `Activite = Package.Require("domain/activite.lua")()`
  - `Activite.Inscrire(cle, resume)` ; `cle` ∈ `"werewolf" | "liars" | "duel"`, `resume()` rend une liste de `{ statut = "attente"|"en_cours", joueurs = n, bots = n, max = n, mise = n, detail = string|nil }`.
  - `Activite.Resume(en_ligne) -> { lignes = { { jeu, statut, joueurs, bots, max, mise, detail } }, en_ligne = n }` (`jeu` = nom affiché : « Loup-garou », « Liar's Bar », « Duel »).
  - `Activite.Changement(en_ligne) -> resume | nil` (nil si identique au dernier rendu).
  - `Activite.JeuDePartie(partie) -> { nom, dans } | nil` (préfixe `werewolf:`, `liars:`, `duel:`).
  - `Activite.AjouterGain(nom, partie, montant) -> { nom, jeu, dans, montant } | nil`.
  - `Activite.Gains() -> liste, plus récent d'abord, 10 au plus`.

- [ ] **Step 1 : écrire le test qui échoue**

`tests/suites/activite.lua` :

```lua
return function(H)
    local make = function() return Package.Require("domain/activite.lua")() end

    H.describe("domain/activite", function()

        H.it("rassemble les jeux inscrits dans l'ordre, avec leur nom affiche", function()
            local A = make()
            A.Inscrire("werewolf", function() return { { statut = "attente", joueurs = 3, bots = 2, max = 8, mise = 50 } } end)
            A.Inscrire("duel", function() return { { statut = "en_cours", joueurs = 2, max = 4, detail = "1 – 0" } } end)
            local r = A.Resume(12)
            H.assert_eq(r.en_ligne, 12, "en ligne")
            H.assert_count(r.lignes, 2, "deux lignes")
            H.assert_eq(r.lignes[1].jeu, "Loup-garou", "nom du loup-garou")
            H.assert_eq(r.lignes[1].bots, 2, "bots")
            H.assert_eq(r.lignes[2].jeu, "Duel", "nom du duel")
            H.assert_eq(r.lignes[2].bots, 0, "bots par defaut")
            H.assert_eq(r.lignes[2].mise, 0, "mise par defaut")
            H.assert_eq(r.lignes[2].detail, "1 – 0", "detail")
        end)

        H.it("un jeu qui plante n'empeche pas les autres", function()
            local A = make()
            A.Inscrire("liars", function() error("boum") end)
            A.Inscrire("duel", function() return { { statut = "attente", joueurs = 1, max = 4 } } end)
            local r = A.Resume(1)
            H.assert_count(r.lignes, 1, "le duel reste")
            H.assert_eq(r.lignes[1].jeu, "Duel", "duel")
        end)

        H.it("Changement ne rend le resume que s'il a change", function()
            local A = make()
            local n = 2
            A.Inscrire("liars", function() return { { statut = "attente", joueurs = n, max = 4 } } end)
            H.assert_true(A.Changement(5) ~= nil, "premier envoi")
            H.assert_nil(A.Changement(5), "identique")
            n = 3
            H.assert_true(A.Changement(5) ~= nil, "un joueur de plus")
            H.assert_true(A.Changement(6) ~= nil, "un joueur en ligne de plus")
        end)

        H.it("lit le jeu dans le prefixe de la partie", function()
            local A = make()
            H.assert_eq(A.JeuDePartie("werewolf:1727:3").nom, "Loup-garou", "loup-garou")
            H.assert_eq(A.JeuDePartie("liars:1727:1").dans, "au Liar's Bar", "liar's bar")
            H.assert_eq(A.JeuDePartie("duel:Est:2").dans, "en duel", "duel")
            H.assert_nil(A.JeuDePartie("autre:1"), "inconnu")
            H.assert_nil(A.JeuDePartie(nil), "nil")
        end)

        H.it("garde les 10 derniers gains, le plus recent d'abord", function()
            local A = make()
            for i = 1, 12 do A.AjouterGain("J" .. i, "liars:1:" .. i, 100 + i) end
            local g = A.Gains()
            H.assert_count(g, 10, "dix au plus")
            H.assert_eq(g[1].nom, "J12", "plus recent en tete")
            H.assert_eq(g[1].montant, 112, "montant")
            H.assert_eq(g[10].nom, "J3", "les plus vieux sortent")
        end)

        H.it("ignore les gains sans jeu connu ou sans montant", function()
            local A = make()
            H.assert_nil(A.AjouterGain("Léo", "inconnu:1", 50), "partie inconnue")
            H.assert_nil(A.AjouterGain("Léo", "duel:1", 0), "montant nul")
            H.assert_eq(A.AjouterGain(nil, "duel:1", 20).nom, "Quelqu'un", "nom par defaut")
        end)
    end)
end
```

Dans `tests/run.lua`, ajouter `"activite",` après `"boutique",` dans la table `suites`.

- [ ] **Step 2 : lancer, vérifier l'échec**

Run : `lua tests/run.lua`
Expected : échec au chargement de `domain/activite.lua` (« fichier introuvable »).

- [ ] **Step 3 : écrire le module**

`Packages/fate-games/Server/domain/activite.lua` :

```lua
-- Ce qui se passe dans les jeux, pour l'ecran d'accueil (domain/accueil.lua) :
-- le resume des salons et parties de chaque jeu inscrit, et le fil des
-- derniers gains. Pur : aucun appel au moteur, teste dans tests/suites/activite.lua.

return function()
    local Activite = {}

    -- Cle de jeu (prefixe des identifiants de partie) -> nom affiche.
    local JEUX = {
        werewolf = { nom = "Loup-garou", dans = "au loup-garou" },
        liars    = { nom = "Liar's Bar", dans = "au Liar's Bar" },
        duel     = { nom = "Duel", dans = "en duel" },
    }
    local MAX_GAINS = 10

    local inscrits = {}          -- { { cle, resume } }, dans l'ordre d'inscription
    local derniere = nil         -- signature du dernier resume rendu par Changement
    local gains = {}             -- plus recent d'abord

    -- resume() rend une liste de { statut, joueurs, bots, max, mise, detail }.
    function Activite.Inscrire(cle, resume)
        inscrits[#inscrits + 1] = { cle = cle, resume = resume }
    end

    function Activite.Resume(en_ligne)
        local lignes = {}
        for _, j in ipairs(inscrits) do
            -- Un jeu qui plante ne doit pas vider le tableau des autres.
            local ok, liste = pcall(j.resume)
            if ok and type(liste) == "table" then
                for _, l in ipairs(liste) do
                    lignes[#lignes + 1] = {
                        jeu = JEUX[j.cle] and JEUX[j.cle].nom or tostring(j.cle),
                        statut = l.statut, joueurs = l.joueurs or 0, bots = l.bots or 0,
                        max = l.max, mise = l.mise or 0, detail = l.detail,
                    }
                end
            end
        end
        return { lignes = lignes, en_ligne = en_ligne or 0 }
    end

    local function signature(r)
        local t = { tostring(r.en_ligne) }
        for _, l in ipairs(r.lignes) do
            t[#t + 1] = table.concat({ l.jeu, tostring(l.statut), l.joueurs, l.bots, tostring(l.max), l.mise,
                tostring(l.detail) }, "|")
        end
        return table.concat(t, ";")
    end

    -- Le resume s'il a change depuis le dernier rendu, sinon nil.
    function Activite.Changement(en_ligne)
        local r = Activite.Resume(en_ligne)
        local s = signature(r)
        if s == derniere then return nil end
        derniere = s
        return r
    end

    function Activite.JeuDePartie(partie)
        local cle = tostring(partie or ""):match("^(%w+):")
        return cle and JEUX[cle] or nil
    end

    function Activite.AjouterGain(nom, partie, montant)
        local jeu = Activite.JeuDePartie(partie)
        if not jeu or type(montant) ~= "number" or montant <= 0 then return nil end
        local g = { nom = nom or "Quelqu'un", jeu = jeu.nom, dans = jeu.dans, montant = montant }
        table.insert(gains, 1, g)
        while #gains > MAX_GAINS do table.remove(gains) end
        return g
    end

    function Activite.Gains()
        local copie = {}
        for i, g in ipairs(gains) do copie[i] = g end
        return copie
    end

    return Activite
end
```

- [ ] **Step 4 : lancer, vérifier que tout passe**

Run : `lua tests/run.lua`
Expected : la suite `domain/activite` passe (6 ok), 0 échec au total.

- [ ] **Step 5 : commit**

```bash
git add Packages/fate-games/Server/domain/activite.lua tests/suites/activite.lua tests/run.lua
git commit -m "ACCUEIL - activite : resume des jeux et fil des gains"
```

---

### Task 2 : boutique — abonné aux gains, apparence au hasard du nouveau joueur

**Files :**
- Modify : `Packages/fate-games/Server/domain/boutique.lua` (`lire_equipement` ~l.182-203, `Boutique.Solder` ~l.136-162)
- Modify : `tests/suites/boutique.lua` (fonction `build`, nouveaux cas)

**Interfaces :**
- Produces :
  - `Boutique.SurGain(fn)` ; `fn(partie, account, montant)` appelé pour chaque versement de raison `"gain"` réussi (pas pour les bonus de participation).
  - Après `Boutique.Charger`, `etat.nouveau == true` si le compte n'avait aucune ligne `equipement` ; `etat.perso` est alors tiré au hasard parmi les persos gratuits du catalogue (`cfg.rng(n)` si fourni, sinon `math.random(n)`).

- [ ] **Step 1 : écrire les tests qui échouent**

Dans `tests/suites/boutique.lua`, remplacer la configuration par défaut de `build` pour rendre le tirage déterministe :

```lua
        return make_boutique(Log, DB, Ids, Catalogue, {
            boutique = cfg or { bonus_accueil = 0, perso_defaut = "clown", rng = function() return 1 end },
        })
```

et ajouter, à la fin du `H.describe("domain/boutique", ...)` (avant son `end)`), les cas :

```lua
        H.it("un nouveau joueur recoit un perso gratuit tire au hasard", function()
            local c = Stubs.reset()
            local Boutique = build(c, { bonus_accueil = 0, perso_defaut = "clown", rng = function(n) return n end })
            local etat = charger(c, Boutique, 0, 0, {}, {})
            H.assert_true(etat.nouveau == true, "marque nouveau")
            H.assert_true(Catalogue.gratuit("persos", etat.perso), "perso gratuit")
            H.assert_true(etat.perso ~= "clown", "pas toujours le defaut (dernier gratuit tire)")
        end)

        H.it("un joueur deja equipe n'est pas nouveau", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            local etat = charger(c, Boutique, 0, 0, {}, { { perso = "souris", arme = Catalogue.arme_de_base } })
            H.assert_nil(etat.nouveau, "pas nouveau")
            H.assert_eq(etat.perso, "souris", "garde son perso")
        end)

        H.it("previent l'abonne des gains, pas des bonus", function()
            local c = Stubs.reset()
            local Boutique = build(c)
            deux_comptes(c, Boutique, 0, 0)
            local vus = {}
            Boutique.SurGain(function(partie, account, montant) vus[#vus + 1] = { partie, account.id, montant } end)
            Boutique.Solder("liars:9:1", { A, B }, { A }, 100, 10, nil)
            H.assert_count(vus, 1, "un seul gain")
            H.assert_eq(vus[1][1], "liars:9:1", "partie")
            H.assert_eq(vus[1][2], A.id, "compte gagnant")
            H.assert_eq(vus[1][3], 100, "montant")
        end)
```

(`A`, `B` et `deux_comptes` existent déjà plus haut dans ce fichier, utilisés par le test « solde : cagnotte aux gagnants ».)

- [ ] **Step 2 : lancer, vérifier l'échec**

Run : `lua tests/run.lua`
Expected : ÉCHEC sur « un nouveau joueur recoit un perso gratuit » (`etat.nouveau` nil) et « previent l'abonne » (`Boutique.SurGain` nil).

- [ ] **Step 3 : implémenter**

Dans `boutique.lua`, dans `lire_equipement`, remplacer :

```lua
                local row = rows and rows[1]
                if row then
                    etat.perso = row.perso
                    etat.arme  = row.arme
                end
```

par :

```lua
                local row = rows and rows[1]
                if row then
                    etat.perso = row.perso
                    etat.arme  = row.arme
                else
                    -- Premiere venue : une apparence de base des bots, gratuite
                    -- donc possedee ; l'accueil l'enregistre (Server/Index.lua).
                    -- Il la change ensuite piece par piece chez le tailleur.
                    local gratuits = {}
                    for _, a in ipairs(Catalogue.persos) do
                        if a.prix == 0 then gratuits[#gratuits + 1] = a.id end
                    end
                    if #gratuits > 0 then
                        etat.perso = gratuits[(cfg.rng or math.random)(#gratuits)]
                        etat.nouveau = true
                    end
                end
```

Toujours dans `boutique.lua`, juste avant `function Boutique.Solder`, ajouter :

```lua
    -- Abonne aux gains (ecran d'accueil, fil des derniers gains) : appele pour
    -- chaque versement de cagnotte reussi, pas pour les bonus de participation.
    local sur_gain = nil
    function Boutique.SurGain(fn)
        sur_gain = fn
    end
```

et, dans `Boutique.Solder`, remplacer :

```lua
            mouvement(v.de, compte(v.a), v.montant, v.raison, cid, function(ok)
                if ok and etats[v.a.id] then etats[v.a.id].solde = etats[v.a.id].solde + v.montant end
                suivant(i + 1)
            end)
```

par :

```lua
            mouvement(v.de, compte(v.a), v.montant, v.raison, cid, function(ok)
                if ok and etats[v.a.id] then etats[v.a.id].solde = etats[v.a.id].solde + v.montant end
                if ok and v.raison == "gain" and sur_gain then pcall(sur_gain, partie, v.a, v.montant) end
                suivant(i + 1)
            end)
```

- [ ] **Step 4 : lancer, vérifier que tout passe**

Run : `lua tests/run.lua`
Expected : tous les cas `domain/boutique` passent, dont le premier (« equipe le defaut », `clown` via `rng` = 1), 0 échec.

- [ ] **Step 5 : commit**

```bash
git add Packages/fate-games/Server/domain/boutique.lua tests/suites/boutique.lua
git commit -m "ACCUEIL - boutique : abonne aux gains, apparence au hasard du nouveau joueur"
```

---

### Task 3 : résumé de chaque jeu (`Resume`)

**Files :**
- Modify : `Packages/fate-games/Server/games/werewolf/adapter.lua` (avant `return A`, ~l.1263)
- Modify : `Packages/fate-games/Server/games/liars_bar/adapter.lua` (avant `return Adapter`)
- Modify : `Packages/fate-games/Server/games/duel/adapter.lua` (avant `return Adapter`)

**Interfaces :**
- Consumes : forme de ligne de `Activite.Inscrire` (tâche 1).
- Produces : `LoupGarou.Resume()`, `LiarsBar.Resume()`, `DuelJeu.Resume()` (noms des variables dans `Server/Index.lua`), chacune rend une liste de lignes `{ statut, joueurs, bots, max, mise, detail }`, vide si personne.

Faits utiles : au loup-garou, `salon.ordre` liste les ids assis (bots en ids négatifs), `salon.max`, `salon.mise`, l'état moteur `s` (`Engine.phase(s)` rend l'id de phase en partie, `"night_..."` ou `"day_..."`, sinon nil ; `s.nuit` compte les nuits). Au Liar's Bar, `seated` liste `{ player, chair, name, bot }`, `state` est nil hors partie, `config.max_seats` vaut 4, `salon.mise` et `mise_en_cours.mise`. Au duel, `arenes` liste les arènes, `A.d` a `phase` (`"vide"`, `"attente"`, `"decompte"`, `"combat"`, `"entre_manches"`, `"fin"`), `joueurs` (id → joueur), `mise`, `scores = { n1, n2 }` ; `bots[id]` existe pour un bot ; `Duel.Capacite(d)`.

- [ ] **Step 1 : loup-garou**

Dans `werewolf/adapter.lua`, juste avant la ligne `    return A` finale :

```lua
    -- Pour l'ecran d'accueil (domain/activite.lua) : le salon, en attente ou
    -- en partie. Rien si personne n'est assis.
    function A.Resume()
        local humains, nb_bots = 0, 0
        for _, id in ipairs(salon.ordre) do
            if id < 0 then nb_bots = nb_bots + 1 else humains = humains + 1 end
        end
        local phase = Engine.phase(s)
        if humains + nb_bots == 0 and not phase then return {} end
        local ligne = { statut = phase and "en_cours" or "attente", joueurs = humains, bots = nb_bots,
            max = salon.max, mise = salon.mise }
        if phase then
            ligne.detail = (phase:find("^night") and "Nuit " or "Jour ") .. tostring(s.nuit or 1)
        end
        return { ligne }
    end
```

- [ ] **Step 2 : Liar's Bar**

Dans `liars_bar/adapter.lua`, juste avant la ligne `    return Adapter` finale :

```lua
    -- Pour l'ecran d'accueil (domain/activite.lua) : la table, en attente ou
    -- en partie. Rien si personne n'est assis.
    function Adapter.Resume()
        local humains, nb_bots = 0, 0
        for _, a in ipairs(seated) do
            if a.bot then nb_bots = nb_bots + 1 else humains = humains + 1 end
        end
        if humains + nb_bots == 0 then return {} end
        return { {
            statut = state and "en_cours" or "attente", joueurs = humains, bots = nb_bots,
            max = config.max_seats, mise = (state and mise_en_cours and mise_en_cours.mise) or salon.mise,
        } }
    end
```

- [ ] **Step 3 : duel**

Dans `duel/adapter.lua`, juste avant la ligne `    return Adapter` finale :

```lua
    -- Pour l'ecran d'accueil (domain/activite.lua) : une ligne par arene
    -- occupee ; en combat, le score des manches.
    function Adapter.Resume()
        local lignes = {}
        for _, A in ipairs(arenes) do
            local d = A.d
            if d and d.phase ~= "vide" then
                local humains, nb_bots = 0, 0
                for id in pairs(d.joueurs) do
                    if bots[id] then nb_bots = nb_bots + 1 else humains = humains + 1 end
                end
                local en_cours = d.phase ~= "attente"
                lignes[#lignes + 1] = {
                    statut = en_cours and "en_cours" or "attente", joueurs = humains, bots = nb_bots,
                    max = Duel.Capacite(d), mise = d.mise or 0,
                    detail = en_cours and ("%d – %d"):format(d.scores[1] or 0, d.scores[2] or 0) or nil,
                }
            end
        end
        return lignes
    end
```

- [ ] **Step 4 : vérifier**

Run : `luac -p Packages/fate-games/Server/games/werewolf/adapter.lua Packages/fate-games/Server/games/liars_bar/adapter.lua Packages/fate-games/Server/games/duel/adapter.lua && lua tests/run.lua`
Expected : aucune erreur de syntaxe ; 0 échec (les suites `werewolf`, `liars_*` chargent ces adaptateurs).

- [ ] **Step 5 : commit**

```bash
git add Packages/fate-games/Server/games/werewolf/adapter.lua Packages/fate-games/Server/games/liars_bar/adapter.lua Packages/fate-games/Server/games/duel/adapter.lua
git commit -m "ACCUEIL - resume des salons et parties de chaque jeu"
```

---

### Task 4 : serveur de l'accueil et branchement

**Files :**
- Create : `Packages/fate-games/Server/domain/accueil.lua`
- Modify : `Packages/fate-games/Server/Index.lua` (création des modules ~l.55 ; arrivée `Characters.SurArrivee` ~l.397-410 ; inscriptions et gains après la création des jeux ~l.122-140)
- Modify : `Packages/fate-games/Shared/config.lua` (nouveau bloc `accueil`)

**Interfaces :**
- Consumes : `Activite` (tâche 1), `Boutique.SurGain`, `etat.nouveau` (tâche 2), `LoupGarou.Resume`, `LiarsBar.Resume`, `DuelJeu.Resume` (tâche 3) ; existants : `Characters.OuvrirVestiaire(session, transform, look)`, `Characters.MontrerAuVestiaire(pid, visible)`, `Characters.AuVestiaire(pid)`, `Characters.Habiller(pid, look)`, `Characters.QuitterVestiaire(pid)`, `Characters.SessionByPlayer(pid)`, `Boutique.Etat(account)`, `Boutique.Equiper(account, rayon, id, cb)`.
- Produces (événements vers le client de la tâche 5) :
  - `accueil:ouvrir(d)` avec `d = { solde, plans = { a = plan, b = plan|nil }, parties = resume, gains = liste, traversee = s }`, `plan = { x, y, z, pitch, yaw, roll }`.
  - `accueil:parties(resume)`, `accueil:gain(g)`, `accueil:fermer()`, `accueil:mesurer(lettre)`.
- Consumes (événements du client) : `accueil:jouer()`, `accueil:mesure(lettre, Vector, Rotator)`.
- Produces : `Accueil.Init(look_de)`, `Accueil.Ouvrir(session, transform, etat)`, `Accueil.Gain(g)`.

- [ ] **Step 1 : configuration**

Dans `Shared/config.lua`, juste avant le bloc `-- PNJ d'ambiance` :

```lua
    -- Ecran d'accueil (Client/accueil, Server/domain/accueil.lua) : duree du
    -- travelling entre les plans A et B (s) et astuces qui tournent.
    accueil = {
        traversee = 40,
        astuces = {
            "Le tailleur te laisse essayer avant d'acheter.",
            "Maj pour courir, Espace pour sauter.",
            "Espace pour te lever d'une chaise hors partie.",
            "Au loup-garou, la nuit, seuls les loups se parlent.",
            "Au Liar's Bar, un mensonge de trop et c'est le barillet.",
            "La cagnotte d'une partie revient aux gagnants.",
            "Le crieur, le forain et le barman t'attendent sur la place.",
        },
    },
```

- [ ] **Step 2 : module `accueil.lua`**

`Packages/fate-games/Server/domain/accueil.lua` :

```lua
-- Ecran d'accueil : a la connexion, le personnage attend cache hors carte
-- (Characters.OuvrirVestiaire) pendant que le client montre la carte, le titre
-- et l'activite (Client/accueil). Une touche : accueil:jouer, il apparait.
--
-- Plans A et B de la camera dans accueil.json, a la racine du serveur (doc
-- File), poses en jeu par /accueil a et /accueil b (mode dev) : la camera du
-- developpeur, que seul son client connait (accueil:mesurer).

return function(Log, Characters, Boutique, Activite, config, dev_pour)
    local Accueil = {}
    local FICHIER = config.fichier or "accueil.json"
    local plans = {}        -- { a = plan, b = plan }, plan = { x, y, z, pitch, yaw, roll }
    local presents = {}     -- player_id -> Player, sur l'accueil
    local look_de = nil     -- fonction(etat) -> tenue resolue (Server/Index.lua)

    local function lire()
        if not File.Exists(FICHIER) then return {} end
        local f = File(FICHIER)
        local texte = f:Read(0)
        f:Close()
        local ok, t = pcall(JSON.parse, texte)
        return (ok and type(t) == "table") and t or {}
    end

    local function ecrire()
        local f = File(FICHIER, true)
        f:Write(JSON.stringify(plans))
        f:Close()
    end

    -- Sans plan pose : au-dessus du point d'apparition, un peu en retrait.
    local function plan_defaut()
        local s = config.spawn
        return { x = s.x, y = s.y - 900, z = s.z + 450, pitch = -18, yaw = 90, roll = 0 }
    end

    local function en_ligne()
        local n = 0
        for _ in pairs(Player.GetPairs()) do n = n + 1 end
        return n
    end

    local function a_tous(evenement, donnee)
        for id, p in pairs(presents) do
            if p:IsValid() then
                Events.CallRemote(evenement, p, Reliability.Reliable, donnee)
            else
                presents[id] = nil
            end
        end
    end

    function Accueil.Ouvrir(session, transform, etat)
        Characters.OuvrirVestiaire(session, transform, look_de(etat))
        Characters.MontrerAuVestiaire(session.player_id, false)
        presents[session.player_id] = session.player
        Events.CallRemote("accueil:ouvrir", session.player, Reliability.Reliable, {
            solde = etat.solde,
            plans = { a = plans.a or plan_defaut(), b = plans.b },
            parties = Activite.Resume(en_ligne()),
            gains = Activite.Gains(),
            traversee = config.traversee or 40,
        })
    end

    function Accueil.Gain(g)
        a_tous("accueil:gain", g)
    end

    function Accueil.Init(fonction_look)
        look_de = fonction_look
        plans = lire()

        -- Une touche : il apparait (une seule fois, et seulement depuis l'accueil).
        Events.SubscribeRemote("accueil:jouer", function(player)
            local id = player:GetID()
            if not presents[id] then return end
            presents[id] = nil
            if not Characters.AuVestiaire(id) then return end
            local session = Characters.SessionByPlayer(id)
            local etat = session and session.account and Boutique.Etat(session.account)
            if etat then Characters.Habiller(id, look_de(etat)) end
            Characters.QuitterVestiaire(id)
            Events.CallRemote("accueil:fermer", player, Reliability.Reliable)
        end)

        -- /accueil a|b : le client du developpeur renvoie sa camera.
        Chat.Subscribe("PlayerSubmit", function(message, player)
            local lettre = tostring(message):match("^/accueil%s+([abAB])%s*$")
            if not lettre then return end
            if not dev_pour(player) then return end
            Events.CallRemote("accueil:mesurer", player, Reliability.Reliable, lettre:lower())
            return false
        end)
        Events.SubscribeRemote("accueil:mesure", function(player, lettre, l, r)
            if not dev_pour(player) or (lettre ~= "a" and lettre ~= "b") then return end
            if not (l and r and l.X and r.Yaw) then return end
            plans[lettre] = { x = l.X, y = l.Y, z = l.Z, pitch = r.Pitch, yaw = r.Yaw, roll = r.Roll }
            ecrire()
            Chat.SendMessage(player, ("Plan %s de l'accueil enregistre."):format(lettre:upper()))
        end)

        -- Toutes les 2 s : le resume des jeux, envoye seulement s'il a change.
        Timer.SetInterval(function()
            if not next(presents) then return end
            local r = Activite.Changement(en_ligne())
            if r then a_tous("accueil:parties", r) end
        end, 2000)

        Player.Subscribe("Destroy", function(player) presents[player:GetID()] = nil end)
        Log.Info("accueil", "pret" .. (plans.a and " (plan A pose)" or " (plan par defaut)"))
    end

    return Accueil
end
```

Vérifier dans `Server/domain/pnj.lua` comment ses commandes `/pnj` s'abonnent au chat et utiliser **exactement la même API** que lui (`Chat.Subscribe("PlayerSubmit", ...)` ou l'équivalent qu'il emploie) ; si c'est différent de ci-dessus, adapter l'abonnement de `/accueil`.

- [ ] **Step 3 : branchement dans `Server/Index.lua`**

a) Après `local Pnj = ...` (~l.55), créer les deux modules :

```lua
-- Ecran d'accueil : activite des jeux (resume, gains) et arrivee des joueurs.
local Activite = Package.Require("domain/activite.lua")()
local Accueil  = Package.Require("domain/accueil.lua")(Log, Characters, Boutique, Activite,
    { fichier = "accueil.json", traversee = SharedConfig.accueil and SharedConfig.accueil.traversee,
      spawn = ServerConfig.spawn }, dev_pour)
```

(si `Boutique` est créé plus bas dans le fichier, placer ces lignes juste après sa création.)

b) Après la création des trois jeux (`DuelJeu.Init()` ~l.121 et `LoupGarou` ~l.122), inscrire les jeux et brancher les gains :

```lua
Activite.Inscrire("werewolf", LoupGarou.Resume)
Activite.Inscrire("liars", LiarsBar.Resume)
Activite.Inscrire("duel", DuelJeu.Resume)

-- Le nom du joueur qui tient ce compte, s'il est en ligne.
local function nom_du_compte(account)
    for _, p in pairs(Player.GetPairs()) do
        local s = p:IsValid() and Characters.SessionByPlayer(p:GetID())
        if s and s.account and s.account.id == account.id then return p:GetName() end
    end
end
Boutique.SurGain(function(partie, account, montant)
    local g = Activite.AjouterGain(nom_du_compte(account), partie, montant)
    if g then Accueil.Gain(g) end
end)
```

c) Remplacer tout le corps de `Characters.SurArrivee(function(session, transform) ... end)` par :

```lua
    Characters.SurArrivee(function(session, transform)
        Boutique.Charger(session.account, function(etat)
            if not Characters.SessionByPlayer(session.player_id) then return end
            -- Base en panne : on entre quand meme, avec la tenue par defaut.
            if not etat then
                return Characters.Apparaitre(session, transform, ServerConfig.boutique.perso_defaut)
            end
            -- Premiere venue : l'apparence tiree au hasard est gardee.
            if etat.nouveau then
                etat.nouveau = nil
                Boutique.Equiper(session.account, "persos", etat.perso, function() end)
            end
            if not (ServerConfig.vestiaire and ServerConfig.vestiaire.enabled) then
                return Characters.Apparaitre(session, transform, look_de(etat))
            end
            Accueil.Ouvrir(session, transform, etat)
        end)
    end)
    Accueil.Init(look_de)
```

(`Accueil.Init(look_de)` juste après, dans le même bloc que `look_de`, qui est défini juste au-dessus.)

- [ ] **Step 4 : vérifier**

Run : `luac -p Packages/fate-games/Server/domain/accueil.lua Packages/fate-games/Server/Index.lua Packages/fate-games/Shared/config.lua && lua tests/run.lua`
Expected : aucune erreur ; 0 échec.

- [ ] **Step 5 : commit**

```bash
git add Packages/fate-games/Server/domain/accueil.lua Packages/fate-games/Server/Index.lua Packages/fate-games/Shared/config.lua
git commit -m "ACCUEIL - serveur : arrivee sur l'accueil, plans A/B, parties et gains diffuses"
```

---

### Task 5 : client de l'accueil (page et caméra)

**Files :**
- Create : `Packages/fate-games/Client/accueil/accueil.lua`
- Create : `Packages/fate-games/Client/accueil/accueil.html`
- Modify : `Packages/fate-games/Client/Index.lua` (à côté du chargement du tailleur, ~l.48-50)

**Interfaces :**
- Consumes : événements de la tâche 4 (`accueil:ouvrir`, `accueil:parties`, `accueil:gain`, `accueil:fermer`, `accueil:mesurer`) ; `SharedConfig.accueil.astuces`.
- Produces : `accueil:jouer`, `accueil:mesure(lettre, Vector, Rotator)` vers le serveur ; événements de page `accueil:ouvrir(d, astuces)`, `accueil:parties(r)`, `accueil:gain(g)` ; la page appelle `pret` une fois chargée.

- [ ] **Step 1 : script client**

`Packages/fate-games/Client/accueil/accueil.lua` :

```lua
-- Ecran d'accueil (Server/domain/accueil.lua) : la page par-dessus la vue de
-- la carte, la camera qui glisse de A a B en boucle, n'importe quelle touche
-- ou un clic pour jouer. La page ne prend pas le focus : les touches sont
-- lues ici (Input KeyDown / MouseDown), bloquees tant que l'accueil est ouvert.

return function(config)
    config = config or {}
    local page = WebUI("accueil", "file://accueil/accueil.html", WidgetVisibility.Hidden)
    local ouvert, parti = false, false
    local minuteur = nil
    local pret, attente = false, {}

    local function vers_page(evenement, ...)
        if pret then page:CallEvent(evenement, ...) else attente[#attente + 1] = { evenement, { ... } } end
    end
    page:Subscribe("pret", function()
        pret = true
        for _, a in ipairs(attente) do page:CallEvent(a[1], table.unpack(a[2])) end
        attente = {}
    end)

    local function lieu(p) return Vector(p.x, p.y, p.z) end
    local function angle(p) return Rotator(p.pitch or 0, p.yaw or 0, p.roll or 0) end

    -- A, puis de A vers B et retour, sur `duree` secondes chaque trajet.
    local function travelling(a, b, duree)
        local moi = Client.GetLocalPlayer()
        moi:SetCameraLocation(lieu(a))
        moi:SetCameraRotation(angle(a))
        if not b then return end
        local cible, autre = b, a
        local function trajet()
            local j = Client.GetLocalPlayer()
            j:TranslateCameraTo(lieu(cible), duree)
            j:RotateCameraTo(angle(cible), duree)
            cible, autre = autre, cible
        end
        trajet()
        minuteur = Timer.SetInterval(trajet, math.floor(duree * 1000))
    end

    local function fermer()
        if minuteur then Timer.ClearInterval(minuteur); minuteur = nil end
        if not ouvert then return end
        ouvert = false
        page:SetVisibility(WidgetVisibility.Hidden)
    end

    local function jouer()
        if not ouvert or parti then return end
        parti = true
        Events.CallRemote("accueil:jouer", Reliability.Reliable)
        fermer()
    end

    Events.SubscribeRemote("accueil:ouvrir", function(d)
        ouvert, parti = true, false
        page:SetVisibility(WidgetVisibility.Visible)
        page:BringToFront()
        vers_page("accueil:ouvrir", d, config.astuces or {})
        if d and d.plans and d.plans.a then travelling(d.plans.a, d.plans.b, d.traversee or 40) end
    end)
    Events.SubscribeRemote("accueil:parties", function(r) vers_page("accueil:parties", r) end)
    Events.SubscribeRemote("accueil:gain", function(g) vers_page("accueil:gain", g) end)
    Events.SubscribeRemote("accueil:fermer", fermer)

    -- /accueil a|b (dev) : le serveur demande la camera, on la lui renvoie.
    Events.SubscribeRemote("accueil:mesurer", function(lettre)
        local moi = Client.GetLocalPlayer()
        Events.CallRemote("accueil:mesure", Reliability.Reliable, lettre, moi:GetCameraLocation(), moi:GetCameraRotation())
    end)

    Input.Subscribe("KeyDown", function()
        if ouvert then jouer(); return false end
    end)
    Input.Subscribe("MouseDown", function()
        if ouvert then jouer(); return false end
    end)
end
```

- [ ] **Step 2 : page**

`Packages/fate-games/Client/accueil/accueil.html` :

```html
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>Accueil</title>
<style>
@font-face { font-family: "Lilita One"; src: url("../vestiaire/fonts/LilitaOne-Regular.ttf") format("truetype"); }
:root { --encre: #1c2123; --papier: #efe6d2; --papier-clair: #f6eedb; --laiton: #d9b56a; --ombre: #070a0b; }
* { box-sizing: border-box; }
html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent;
    font-family: "Lilita One", sans-serif; color: var(--encre); user-select: none; cursor: default; }
body.apercu-navigateur { background: linear-gradient(160deg, #2b3450, #6a5a48 60%, #3a2c22); }
/* Assombrit les bords pour lire le texte par-dessus la carte. */
#voile { position: fixed; inset: 0; pointer-events: none;
    background: radial-gradient(ellipse at 50% 42%, transparent 35%, rgba(7, 10, 11, .55) 100%); }

.sk { position: relative; isolation: isolate; }
.sk-svg { position: absolute; z-index: -1; overflow: visible; pointer-events: none; }
.sk-svg .ombre { fill: var(--ombre); }
.sk-svg .fond { fill: var(--fond, var(--papier)); }
.sk-svg .trait { fill: none; stroke: var(--bord, var(--encre)); stroke-width: var(--epais, 3.5px); stroke-linejoin: round; }
.sk-svg .trait2 { fill: none; stroke: var(--bord, var(--encre)); stroke-width: 1.5px; opacity: .4; }

#solde { position: fixed; top: 28px; right: 32px; display: flex; align-items: center; gap: 8px;
    padding: 8px 18px 8px 12px; font-size: 30px; }
#titre { position: fixed; left: 50%; top: 30%; transform: translate(-50%, -50%) rotate(-2.5deg);
    text-align: center; }
#titre h1 { margin: 0; font-size: clamp(64px, 9vw, 150px); font-weight: 400; line-height: .9; color: var(--papier-clair);
    -webkit-text-stroke: 5px var(--encre); paint-order: stroke fill;
    text-shadow: 7px 8px 0 var(--ombre); }
#jouer { display: inline-block; margin-top: 26px; padding: 10px 22px 8px; font-size: 26px;
    transform: rotate(1.5deg); animation: respire 1.8s ease-in-out infinite; }
@keyframes respire { 50% { opacity: .55; transform: rotate(1.5deg) scale(.97); } }
@media (prefers-reduced-motion: reduce) { #jouer { animation: none; } .gain { animation: none !important; } }

#bas { position: fixed; left: 32px; right: 32px; bottom: 28px; display: flex; flex-direction: column;
    align-items: flex-start; gap: 10px; }
#parties { padding: 8px 16px 7px; font-size: 20px; max-width: 70vw; }
#astuce { display: flex; align-items: center; gap: 8px; color: var(--papier-clair); font-size: 18px;
    text-shadow: 2px 2px 0 var(--ombre); transition: opacity .4s; }
#astuce.cache { opacity: 0; }

#gains { position: fixed; right: 32px; top: 110px; display: flex; flex-direction: column; align-items: flex-end;
    gap: 10px; width: min(360px, 32vw); }
.gain { padding: 7px 14px 6px; font-size: 17px; animation: glisse .5s ease-out; }
.gain b { color: #8a6d3b; font-weight: 400; }
@keyframes glisse { from { opacity: 0; transform: translateX(40px); } }
</style>
</head>
<body>
<div id="voile"></div>
<svg width="0" height="0" style="position:absolute">
  <symbol id="pile" viewBox="0 0 48 48">
    <circle cx="18.5" cy="25.5" r="13.5" fill="#8a6d3b" stroke="#1c2123" stroke-width="2.6"/>
    <circle cx="16" cy="24" r="13.5" fill="#e3c173" stroke="#1c2123" stroke-width="2.8"/>
    <path d="M16 17.2l2 4.4 4.7.4-3.6 3.1 1.1 4.6-4.2-2.5-4.2 2.5 1.1-4.6-3.6-3.1 4.7-.4z" fill="#a8843f" stroke="#1c2123" stroke-width="1.6" stroke-linejoin="round"/>
  </symbol>
  <symbol id="ampoule" viewBox="0 0 24 24"><path d="M9 18h6M10 21h4M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2.1h5c0-.9.4-1.6 1-2.1A6 6 0 0 0 12 3z" fill="#f6eedb" stroke="#1c2123" stroke-width="1.8" stroke-linejoin="round"/></symbol>
</svg>

<div id="solde" class="sk" data-graine="11" data-rayon="999"><svg width="34" height="34"><use href="#pile"/></svg><span id="montant">0</span></div>
<div id="titre">
  <h1>Fate's Games</h1>
  <div id="jouer" class="sk" data-graine="5" data-rayon="14">Appuie sur n'importe quelle touche pour jouer</div>
</div>
<div id="gains"></div>
<div id="bas">
  <div id="parties" class="sk" data-graine="21" data-rayon="12"></div>
  <div id="astuce"><svg width="22" height="22"><use href="#ampoule"/></svg><span id="astuce-texte"></span></div>
</div>

<script src="../ui/esquisse.js"></script>
<script>
"use strict";
const $ = (id) => document.getElementById(id);
const nettoyer = (s) => String(s == null ? "" : s).replace(/[<>&"]/g, "");
let astuces = [], rang = 0;

function texteParties(r) {
  const lignes = (r && r.lignes) || [];
  const bouts = lignes.map((l) => {
    const n = (l.joueurs || 0) + (l.bots || 0);
    if (l.statut === "attente") return `${l.jeu} : ${n}/${l.max} attendent`;
    return `${l.jeu} en cours${l.detail ? ` (${l.detail})` : ""}`;
  });
  const enLigne = r && r.en_ligne ? `${r.en_ligne} joueur${r.en_ligne > 1 ? "s" : ""} en ligne` : "";
  if (!bouts.length) return `Personne ne joue encore : assieds-toi à une table pour lancer une partie.${enLigne ? " · " + enLigne : ""}`;
  return [...bouts, enLigne].filter(Boolean).join(" · ");
}

function parties(r) { $("parties").textContent = texteParties(r); requestAnimationFrame(habiller); }

function gain(g, anime) {
  const d = document.createElement("div");
  d.className = "gain sk";
  d.dataset.graine = String(30 + Math.floor(Math.random() * 60));
  d.dataset.rayon = "10";
  if (!anime) d.style.animation = "none";
  d.innerHTML = `${nettoyer(g.nom)} a gagné <b>${nettoyer(g.montant)}</b> ${nettoyer(g.dans)}`;
  $("gains").prepend(d);
  while ($("gains").children.length > 4) $("gains").lastElementChild.remove();
  requestAnimationFrame(habiller);
}

function astuceSuivante() {
  if (!astuces.length) return;
  $("astuce").classList.add("cache");
  setTimeout(() => {
    $("astuce-texte").textContent = astuces[rang++ % astuces.length];
    $("astuce").classList.remove("cache");
  }, 400);
}

function ouvrir(d, liste) {
  $("montant").textContent = (d && d.solde) || 0;
  parties(d && d.parties);
  $("gains").innerHTML = "";
  ((d && d.gains) || []).slice(0, 4).reverse().forEach((g) => gain(g, false));
  astuces = (liste || []).slice().sort(() => Math.random() - 0.5);
  rang = 0;
  astuceSuivante();
  requestAnimationFrame(habiller);
}

setInterval(astuceSuivante, 6000);
new ResizeObserver(() => requestAnimationFrame(habiller)).observe(document.body);

if (window.Events) {
  Events.Subscribe("accueil:ouvrir", ouvrir);
  Events.Subscribe("accueil:parties", parties);
  Events.Subscribe("accueil:gain", (g) => gain(g, true));
  Events.Call("pret");
} else {
  // Ouverte dans un navigateur : donnees d'exemple pour regler la page.
  document.body.classList.add("apercu-navigateur");
  ouvrir({ solde: 1250,
    parties: { en_ligne: 12, lignes: [
      { jeu: "Loup-garou", statut: "attente", joueurs: 3, bots: 2, max: 8 },
      { jeu: "Liar's Bar", statut: "en_cours" },
      { jeu: "Duel", statut: "en_cours", detail: "1 – 0" } ] },
    gains: [ { nom: "Léo", montant: 250, dans: "au Liar's Bar" }, { nom: "Sam", montant: 120, dans: "au loup-garou" } ] },
    ["Le tailleur te laisse essayer avant d'acheter.", "Maj pour courir, Espace pour sauter."]);
  setTimeout(() => gain({ nom: "Inès", montant: 400, dans: "en duel" }, true), 2500);
}
</script>
</body>
</html>
```

(`habiller()` vient de `../ui/esquisse.js`, comme dans `Client/tailleur/tailleur.html`.)

- [ ] **Step 3 : charger le script client**

Dans `Packages/fate-games/Client/Index.lua`, juste avant le bloc du tailleur (`-- Boutique du tailleur ...`) :

```lua
-- Ecran d'accueil : titre, activite des jeux, n'importe quelle touche pour jouer.
local ok_accueil, err_accueil = pcall(function() Package.Require("accueil/accueil.lua")(SharedConfig.accueil) end)
if not ok_accueil then Console.Error("[accueil] chargement impossible : " .. tostring(err_accueil)) end
```

- [ ] **Step 4 : vérifier**

Run :
```bash
luac -p Packages/fate-games/Client/accueil/accueil.lua Packages/fate-games/Client/Index.lua
python -c "import re;s=open('Packages/fate-games/Client/accueil/accueil.html',encoding='utf-8').read();open('accueil_check.js','w',encoding='utf-8').write(re.findall(r'<script>(.*?)</script>',s,re.S)[-1])" && node --check accueil_check.js && rm accueil_check.js
```
Expected : aucune erreur. Ouvrir `accueil.html` dans un navigateur : titre au centre, solde en haut à droite, trois parties en bas, deux gains puis un troisième qui glisse, une astuce qui change toutes les 6 s.

- [ ] **Step 5 : commit**

```bash
git add Packages/fate-games/Client/accueil/accueil.lua Packages/fate-games/Client/accueil/accueil.html Packages/fate-games/Client/Index.lua
git commit -m "ACCUEIL - client : page d'accueil, travelling A/B, une touche pour jouer"
```

---

### Task 6 : armurier (page armes existante)

**Files :**
- Modify : `Packages/fate-games/Shared/config.lua` (`pnj.types`)
- Modify : `Packages/fate-games/Server/Index.lua` (à côté de `PnjActions.vestiaire`)
- Modify : `Packages/fate-games/Client/vestiaire/vestiaire.html` (CSS, bouton `#sortir`, `recevoir`, `vestiaire:ouvrir`, touches)
- Modify : `Packages/fate-games/Client/vestiaire/vestiaire.lua` (`page:Subscribe("sortir")`)

**Interfaces :**
- Consumes : existants `Characters.RetournerVestiaire(pid, look)`, `Characters.QuitterVestiaire(pid)`, `Boutique.Vue(etat)`, `look_de`, `chez_tailleur`, événements `vestiaire:ouvrir(vue)` / `vestiaire:fermer()`.
- Produces : type de PNJ `armurier` (action `armurerie`) ; `vue.mode = "armurerie"` dans la vue envoyée ; événement client→serveur `armurerie:sortir()`.

- [ ] **Step 1 : type de PNJ**

Dans `Shared/config.lua`, dans `pnj.types`, après la ligne du `barman` :

```lua
            -- E sur l'armurier : le rayon des armes (achat, equipement, vitrine).
            armurier = { nom = "L'armurier", look = "casque", phrases = {},
                interaction = { label = "Armurerie", kind = "pickup", action = "armurerie" } },
```

- [ ] **Step 2 : serveur**

Dans `Server/Index.lua`, juste après la fonction `PnjActions.vestiaire = function(player, pnj) ... end` :

```lua
    -- Armurerie : E sur l'armurier. Le personnage remonte au vestiaire (sa
    -- position est gardee), la page s'ouvre sur le seul rayon des armes ;
    -- Sortir le redescend ou il etait (armurerie:sortir).
    PnjActions.armurerie = function(player)
        local session = Characters.SessionByPlayer(player:GetID())
        if not (session and session.account and session.character) then return end
        if session.assis or Characters.AuVestiaire(player:GetID()) or chez_tailleur[player:GetID()] then return end
        Boutique.Charger(session.account, function(etat)
            if not etat or not player:IsValid() then return end
            local ok, raison = Characters.RetournerVestiaire(player:GetID(), look_de(etat))
            if not ok then return Log.Debug("armurerie", "refus : " .. tostring(raison)) end
            local vue = Boutique.Vue(etat)
            vue.mode = "armurerie"
            Events.CallRemote("vestiaire:ouvrir", player, Reliability.Reliable, vue)
        end)
    end

    Events.SubscribeRemote("armurerie:sortir", function(player)
        if not Characters.AuVestiaire(player:GetID()) then return end
        Characters.QuitterVestiaire(player:GetID())
        Events.CallRemote("vestiaire:fermer", player, Reliability.Reliable)
    end)
```

(`PnjActions.vestiaire` est défini plus bas que `chez_tailleur` ; si `chez_tailleur` n'est pas visible à cet endroit, placer ce bloc juste après `Player.Subscribe("Destroy", ...)` du tailleur.)

- [ ] **Step 3 : page vestiaire en mode armurerie**

Dans `Client/vestiaire/vestiaire.html` :

a) dans le `<style>`, ajouter :

```css
/* Armurerie (E sur l'armurier) : seul le rayon des armes, et un bouton Sortir. */
body.armurerie #rayon-persos, body.armurerie #rayon-armes { display: none; }
#sortir { display: none; position: fixed; top: 28px; left: 32px; font-size: 22px; padding: 8px 16px; }
body.armurerie #sortir { display: block; }
```

b) juste avant `<script src="../ui/esquisse.js"></script>`, ajouter le bouton :

```html
<button id="sortir" class="sk" data-graine="53" data-rayon="999">Sortir</button>
```

c) remplacer la fonction `recevoir` par :

```js
let mode = null;
function recevoir(nouvelle, refus) {
  const premiere = vue === null;
  vue = nouvelle;
  // La vue d'ouverture dit le mode ; les suivantes (apres un achat) ne le
  // redisent pas : on le garde jusqu'a la prochaine ouverture.
  if (nouvelle.mode) mode = nouvelle.mode;
  document.body.classList.toggle("armurerie", mode === "armurerie");
  if (mode === "armurerie" && rayon !== "armes") changerRayon("armes");
  if (premiere) {
    // On ouvre sur la tenue portee et l'arme equipee.
    sel.persos = Math.max(0, vue.persos.findIndex((a) => a.id === vue.perso));
    sel.armes = Math.max(0, vue.armes.findIndex((a) => a.id === vue.arme));
  }
  dessiner();
  if (refus) secouer();
}
```

d) dans `Events.Subscribe("vestiaire:ouvrir", () => { ... })`, ajouter en première ligne du corps :

```js
    mode = null;
```

e) dans l'écouteur `keydown`, remplacer la ligne de la touche Tab par :

```js
  else if (k === "tab") { e.preventDefault(); if (mode !== "armurerie") changerRayon(rayon === "persos" ? "armes" : "persos"); }
  else if (k === "escape" && mode === "armurerie") envoyer("sortir");
```

f) après `$("action").addEventListener("click", agir);`, ajouter :

```js
$("sortir").addEventListener("click", () => envoyer("sortir"));
```

(`envoyer` est la fonction de la page qui appelle `Events.Call` ; vérifier son nom dans la page et utiliser le même que pour `"acheter"`.)

- [ ] **Step 4 : pont client**

Dans `Client/vestiaire/vestiaire.lua`, après `page:Subscribe("entrer", ...)` :

```lua
    -- Armurerie : Sortir redescend le personnage ou il etait.
    page:Subscribe("sortir", function()
        Events.CallRemote("armurerie:sortir", Reliability.Reliable)
    end)
```

- [ ] **Step 5 : vérifier**

Run :
```bash
luac -p Packages/fate-games/Server/Index.lua Packages/fate-games/Shared/config.lua Packages/fate-games/Client/vestiaire/vestiaire.lua && lua tests/run.lua
python -c "import re;s=open('Packages/fate-games/Client/vestiaire/vestiaire.html',encoding='utf-8').read();open('vest_check.js','w',encoding='utf-8').write(re.findall(r'<script>(.*?)</script>',s,re.S)[-1])" && node --check vest_check.js && rm vest_check.js
```
Expected : aucune erreur ; 0 échec.

- [ ] **Step 6 : commit**

```bash
git add Packages/fate-games/Shared/config.lua Packages/fate-games/Server/Index.lua Packages/fate-games/Client/vestiaire/vestiaire.html Packages/fate-games/Client/vestiaire/vestiaire.lua
git commit -m "ACCUEIL - armurier : E ouvre le rayon des armes, Sortir ramene ou l'on etait"
```

---

### Task 7 : vérification d'ensemble

**Files :** aucun nouveau.

- [ ] **Step 1 : banc de test et syntaxe**

Run :
```bash
lua tests/run.lua
for f in $(git diff --name-only HEAD~6 -- '*.lua'); do luac -p "$f" || echo "ECHEC $f"; done
```
Expected : 0 échec ; aucune ligne `ECHEC`.

- [ ] **Step 2 : liste de vérification en jeu (à faire par l'utilisateur, serveur redémarré, pas de cuisson)**

1. Connexion : l'accueil s'affiche sur la carte, argent en haut à droite, astuce qui change, pas de personnage visible.
2. `/accueil a` puis `/accueil b` (dev, à deux endroits) : message « Plan A/B de l'accueil enregistre » ; à la reconnexion, la caméra glisse de A à B et revient.
3. Une touche ou un clic : le personnage apparaît à la dernière position, dans sa tenue du tailleur ; une seconde touche ne fait rien de plus.
4. Nouveau compte : une apparence de base au hasard, la même à la reconnexion.
5. Salon de loup-garou ou table de Liar's Bar occupés : la ligne des parties change en moins de 3 s sur l'accueil d'un autre joueur ; une fin de partie avec mise ajoute un bandeau de gain.
6. `/pnj poser armurier`, E : rayon des armes seul, achat et équipement ; Sortir (ou Échap) ramène où l'on était.

- [ ] **Step 3 : commit éventuel des corrections**, puis signaler l'état à l'utilisateur (pas de push sans son accord).
