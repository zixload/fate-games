# Liar's Bar — HUD de suivi et bots de test : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** jouer une partie complète seul, contre des bots, en suivant chaque étape sur un HUD texte.

**Architecture:** des bots pseudo-joueurs, dont la décision est pure (`bots.lua`) et que l'adaptateur déclenche avec une garde de génération. Côté serveur, trois événements en plus : le nom à l'assise, « partie lancée », et les refus. Côté client, un journal pur (`journal.lua`) et un dessinateur (`hud.lua`). Le moteur de règles n'est pas modifié.

**Tech Stack:** Lua 5.4, nanos world 1.154 (Canvas, Input, Chat, Events, Timer), banc de test maison (`lua tests/run.lua`).

**Spec:** `docs/superpowers/specs/2026-09-18-liars-bar-hud-bots-design.md`

## Global Constraints

- Aucune mention d'IA dans les commits ni dans les fichiers : ni `Co-Authored-By`, ni « Claude ». Vérifier après chaque commit.
- Ne jamais pousser. Ne jamais lancer le serveur : l'auteur le lance lui-même.
- Commentaires de code et chaînes de log en ASCII, en français, sans accents : la console Windows les casse. Les textes du HUD, dessinés par Canvas, peuvent porter des accents. S'ils s'affichent mal en jeu, les passer en ASCII.
- Préfixe des commits : `LIARS - ...`.
- Toute API nanos utilisée est vérifiée dans `.lua-stubs/annotations.lua` ou sur docs.nanos-world.com. Toutes celles de ce plan l'ont été.
- Chemins relatifs à la racine du dépôt `fate-games`. Code du package : `Packages/fate-games/`.
- Tests : `lua tests/run.lua` depuis la racine. Les fichiers hors banc se vérifient à la syntaxe : `lua -e 'assert(loadfile("CHEMIN")) print("ok")'`.

## Structure des fichiers

| Fichier | Rôle |
| --- | --- |
| `Server/games/liars_bar/bots.lua` (nouveau) | Décision pure : qui est attendu, quel coup jouer |
| `Server/games/liars_bar/data/config.lua` | Section `bots` : délai, taux d'accusation, recul du corps |
| `Server/games/liars_bar/adapter.lua` | Pseudo-joueurs, corps, déclenchement, `SetBots`, événements HUD, refus |
| `Server/core/config.lua` | `dev.liars_bots` |
| `Server/Index.lua` | Câblage de `bots.lua`, commande de chat `/bots N` |
| `Shared/config.lua` | Section `liars_hud` : touches, lignes, plafond de pose |
| `Client/liars_bar/journal.lua` (nouveau) | État affiché, pur |
| `Client/liars_bar/hud.lua` (nouveau) | Canvas, touches, abonnements |
| `Client/Index.lua` | Câblage du HUD |
| `tests/suites/liars_bots.lua`, `tests/suites/liars_journal.lua` (nouveaux) | Tests |
| `tests/run.lua` | Enregistrement des deux suites |

---

### Task 0 : consolider l'existant

**Files:**
- Commit : `Server/games/liars_bar/adapter.lua`, `Server/games/liars_bar/data/config.lua` (les quatre places, déjà modifiées)
- Modify : `docs/superpowers/specs/2026-09-18-liars-bar-hud-bots-design.md`

- [ ] **Step 1 : commiter les quatre places**

```bash
lua tests/run.lua
git add Packages/fate-games/Server/games/liars_bar/adapter.lua Packages/fate-games/Server/games/liars_bar/data/config.lua
git commit -m "LIARS - les quatre places creees, visibles pour la calibration"
```

Attendu : `176 test(s) ok, 0 echec(s)`.

- [ ] **Step 2 : aligner la spec sur deux ajustements**

Dans la spec, section « Touches » : remplacer la ligne `Enter` par :

```markdown
* `P` : envoyer `liars_play` avec les indices choisis, puis vider la sélection. Pas `Enter`, qui
  risque de servir au chat ; le HUD ignore aussi ses touches tant que le chat est ouvert ;
```

Dans la section « Affichage », remplacer l'exemple `« Révélé : Roi, Dame → mensonge »` par
`« Révélé chez Bot 2 : Roi, Dame », « Bot 2 doit tirer »`, et ajouter après la liste des blocs :

```markdown
Le HUD ne juge pas une révélation : c'est le serveur qui désigne le tireur, et la ligne suivante le
dit.
```

Dans la section « Déclenchement », remplacer « Si l'effet `turn` ou `designated` vise un bot » par
« Si la place attendue, donnée par `Bots.Awaited(state)` (le tireur désigné, sinon le tour), est un
bot ». Le résultat est le même, mais c'est la décision pure qui répond, et non l'adaptateur.

- [ ] **Step 3 : commit**

```bash
git add docs/superpowers/specs/2026-09-18-liars-bar-hud-bots-design.md
git commit -m "SPEC - touche P pour poser, le HUD ne juge pas une revelation"
```

---

### Task 1 : la décision des bots

**Files:**
- Create : `Packages/fate-games/Server/games/liars_bar/bots.lua`
- Modify : `Packages/fate-games/Server/games/liars_bar/data/config.lua` (fin de la table)
- Create : `tests/suites/liars_bots.lua`
- Modify : `tests/run.lua` (liste `suites`)

**Interfaces:**
- Produces : `Bots.Awaited(state) -> seat|nil`, `Bots.Decide(state, seat, rng) -> act|nil`. Ici `rng(n)` rend un entier de 1 à n, et `act` vaut `{kind="shoot"|"challenge"|"play", seat, indices?}`. Config : `config.bots.delay`, `config.bots.accuse_percent`, `config.bots.body_offset`.

- [ ] **Step 1 : la section de config**

Dans `data/config.lua`, juste avant la section `layout = {` :

```lua
    -- Bots de test (voir bots.lua). Ils ne jouent que si dev.liars_bots est
    -- vrai dans Server/core/config.lua.
    bots = {
        delay          = 1.5,   -- secondes avant qu'un bot joue
        accuse_percent = 30,    -- chance d'accuser quand une pose le permet
        body_offset    = 60.0,  -- recul du corps derriere sa chaise, en cm
    },

```

- [ ] **Step 2 : le test qui échoue**

`tests/suites/liars_bots.lua` :

```lua
return function(H, Stubs)
    local config         = Package.Require("games/liars_bar/data/config.lua")
    local make_deck      = Package.Require("games/liars_bar/data/deck.lua")
    local make_revolver  = Package.Require("games/liars_bar/revolver.lua")
    local make_challenge = Package.Require("games/liars_bar/challenge.lua")
    local make_round     = Package.Require("games/liars_bar/round.lua")
    local make_match     = Package.Require("games/liars_bar/match.lua")
    local make_effects   = Package.Require("games/liars_bar/effects.lua")
    local Appearances    = Package.Require("Shared/appearances.lua")
    local make_engine    = Package.Require("games/liars_bar/engine.lua")
    local Bots           = Package.Require("games/liars_bar/bots.lua")(config)

    local function build()
        local Deck      = make_deck(config)
        local Revolver  = make_revolver(config)
        local Challenge = make_challenge(Deck)
        local RoundM    = make_round(config, Deck)
        local MatchM    = make_match(config, Appearances, Revolver)
        return make_engine(config, Deck, Revolver, Challenge, RoundM, MatchM, make_effects())
    end

    -- Meme generateur que liars_game : reproductible et varie.
    local function rng_graine(graine)
        local etat = graine
        return function(n)
            etat = (1103515245 * etat + 12345) % 2147483648
            return (etat % n) + 1
        end
    end

    -- Rend toujours la meme valeur, plafonnee a n : 1 = le plus petit tirage,
    -- 100 = le plus grand.
    local function rng_fixe(valeur)
        return function(n) return math.min(valeur, n) end
    end

    local function etat(round, pending)
        return { round = round, pending = pending, finished = false }
    end

    H.describe("liars_bar/bots", function()
        H.it("tire quand il est designe", function()
            local act = Bots.Decide(etat({ turn = 3, hands = {} }, { seat = 2 }), 2, rng_fixe(1))
            H.assert_eq(act.kind, "shoot", "acte")
            H.assert_eq(act.seat, 2, "place")
        end)

        H.it("ne fait rien quand un autre doit tirer", function()
            local s = etat({ turn = 3, hands = { [3] = { "king" } } }, { seat = 2 })
            H.assert_nil(Bots.Decide(s, 3, rng_fixe(1)), "acte")
        end)

        H.it("ne joue pas hors de son tour", function()
            local s = etat({ turn = 1, hands = { [2] = { "king" } } })
            H.assert_nil(Bots.Decide(s, 2, rng_fixe(1)), "acte")
        end)

        H.it("n'accuse jamais sans pose precedente", function()
            -- rng_fixe(1) : un tirage d'accusation, s'il avait lieu, dirait oui
            local s = etat({ turn = 1, last = nil, hands = { [1] = { "king", "queen" } } })
            H.assert_eq(Bots.Decide(s, 1, rng_fixe(1)).kind, "play", "acte")
        end)

        H.it("n'accuse pas sa propre pose", function()
            local s = etat({ turn = 1, last = { seat = 1 }, hands = { [1] = { "king" } } })
            H.assert_eq(Bots.Decide(s, 1, rng_fixe(1)).kind, "play", "acte")
        end)

        H.it("accuse quand le tirage tombe sous le seuil", function()
            local s = etat({ turn = 1, last = { seat = 4 }, hands = { [1] = { "king" } } })
            local act = Bots.Decide(s, 1, rng_fixe(1))
            H.assert_eq(act.kind, "challenge", "acte")
            H.assert_eq(act.seat, 1, "place")
        end)

        H.it("pose des indices distincts et valides, trois au plus", function()
            local main = { "king", "queen", "ace", "joker", "king" }
            local s = etat({ turn = 1, last = { seat = 4 }, hands = { [1] = main } })
            local act = Bots.Decide(s, 1, rng_fixe(100))
            H.assert_eq(act.kind, "play", "acte")
            H.assert_eq(#act.indices, 3, "nombre")
            local vus = {}
            for _, i in ipairs(act.indices) do
                H.assert_true(i >= 1 and i <= #main, "indice dans la main")
                H.assert_nil(vus[i], "indice en double")
                vus[i] = true
            end
        end)

        H.it("ne pose jamais plus que sa main", function()
            local s = etat({ turn = 1, hands = { [1] = { "king", "ace" } } })
            H.assert_eq(#Bots.Decide(s, 1, rng_fixe(100)).indices, 2, "nombre")
        end)

        H.it("attend le tireur avant le tour", function()
            H.assert_eq(Bots.Awaited(etat({ turn = 3 }, { seat = 2 })), 2, "tireur")
            H.assert_eq(Bots.Awaited(etat({ turn = 3 })), 3, "tour")
            H.assert_nil(Bots.Awaited(nil), "hors partie")
            H.assert_nil(Bots.Awaited({ finished = true, round = { turn = 1 } }), "partie finie")
        end)

        H.it("quatre bots jouent 50 parties jusqu'au vainqueur", function()
            local Engine = build()
            for partie = 1, 50 do
                local rng = rng_graine(partie)
                local state = Engine.Start({ 1, 2, 3, 4 }, rng)
                local actes = 0
                while not state.finished do
                    local seat = Bots.Awaited(state)
                    H.assert_true(seat ~= nil, ("partie %d : personne n'est attendu"):format(partie))
                    local act = Bots.Decide(state, seat, rng)
                    H.assert_true(act ~= nil, ("partie %d : aucun coup pour la place %d"):format(partie, seat))
                    local ok, nouveau = pcall(Engine.Apply, state, act)
                    H.assert_true(ok, ("partie %d, acte %d (%s) : %s")
                        :format(partie, actes, act.kind, tostring(nouveau)))
                    state = nouveau
                    actes = actes + 1
                    H.assert_true(actes < 2000, ("partie %d sans fin"):format(partie))
                end
            end
        end)
    end)
end
```

Dans `tests/run.lua`, ajouter `"liars_bots",` après `"liars_game",` dans la liste `suites`.

- [ ] **Step 3 : vérifier l'échec**

Run : `lua tests/run.lua`
Attendu : ECHEC du chargement, avec `Package.Require : fichier introuvable -> games/liars_bar/bots.lua`.

- [ ] **Step 4 : l'implémentation**

`Packages/fate-games/Server/games/liars_bar/bots.lua` :

```lua
-- Bots de test de Liar's Bar : la decision, et rien d'autre.
--
-- Pur, comme le moteur : il lit l'etat et rend un acte, sans toucher a nanos
-- world. L'adaptateur decide QUAND demander (apres chaque lot d'effets, avec
-- un delai) ; ce fichier decide QUOI jouer. Les coups sont legaux et tires au
-- hasard : un bot de test doit faire avancer la partie, pas la gagner.

return function(config)
    local Bots = {}

    -- La place dont le jeu attend un acte : le tireur designe d'abord, sinon
    -- celui dont c'est le tour.
    function Bots.Awaited(state)
        if not state or state.finished then return nil end
        if state.pending then return state.pending.seat end
        return state.round and state.round.turn or nil
    end

    function Bots.Decide(state, seat, rng)
        if not state or state.finished then return nil end

        if state.pending then
            if state.pending.seat == seat then
                return { kind = "shoot", seat = seat }
            end
            return nil
        end

        local round = state.round
        if not round or round.turn ~= seat then return nil end

        -- On n'accuse que la pose d'un autre : le moteur refuse le reste.
        local last = round.last
        local peut_accuser = last ~= nil and last.seat ~= seat
        if peut_accuser and rng(100) <= config.bots.accuse_percent then
            return { kind = "challenge", seat = seat }
        end

        local hand = round.hands[seat] or {}
        if #hand == 0 then
            -- Inatteignable en jeu normal : le tour ne va qu'a une place qui a
            -- des cartes. Garde-fou pour ne pas rendre une pose vide.
            if peut_accuser then return { kind = "challenge", seat = seat } end
            return nil
        end

        -- Tirage sans remise dans les indices de la main.
        local n = rng(math.min(config.max_play, #hand))
        local pool = {}
        for i = 1, #hand do pool[i] = i end
        local indices = {}
        for k = 1, n do
            indices[k] = table.remove(pool, rng(#pool))
        end
        table.sort(indices)

        return { kind = "play", seat = seat, indices = indices }
    end

    return Bots
end
```

- [ ] **Step 5 : vérifier que ça passe**

Run : `lua tests/run.lua`
Attendu : `186 test(s) ok, 0 echec(s)`. Si la simulation échoue, lire le message : il nomme la partie, l'acte et l'erreur du moteur. Corriger `bots.lua`, jamais le moteur.

- [ ] **Step 6 : commit**

```bash
git add Packages/fate-games/Server/games/liars_bar/bots.lua Packages/fate-games/Server/games/liars_bar/data/config.lua tests/suites/liars_bots.lua tests/run.lua
git commit -m "LIARS - decision des bots de test, eprouvee sur 50 parties"
git log -1 --format='%an%n%B' | grep -ic "claude\|anthropic\|co-authored"
```

Attendu pour la dernière commande : `0`.

---

### Task 2 : les bots dans l'adaptateur

**Files:**
- Modify : `Packages/fate-games/Server/games/liars_bar/adapter.lua`
- Modify : `Packages/fate-games/Server/core/config.lua` (section `dev`)
- Modify : `Packages/fate-games/Server/Index.lua`

**Interfaces:**
- Consumes : `Bots.Awaited`, `Bots.Decide`, `config.bots.*` (Task 1).
- Produces : `Adapter.SetBots(n) -> true, assis | false, raison`. Une entrée de `seated` porte désormais `bot`, `body` et `name`.

- [ ] **Step 1 : signature et asset**

Signature de la fabrique (ligne 11) :

```lua
return function(Log, DB, Ids, Characters, Interactables, Intents, Engine, Bots, Appearances, config, spawn)
```

Dans `ASSETS`, après `seat_marker` :

```lua
        bot_body    = "nanos-world::SK_Male",
```

Après `local devant_chaise  = {}` :

```lua

    -- Bots de test. Chaque lot d'effets incremente la generation : un
    -- minuteur de bot arme avant ne joue que si rien n'a bouge depuis.
    local bot_generation = 0
    local function bot_rng(n) return math.random(n) end
```

- [ ] **Step 2 : `send`, `character_of`, remise à zéro**

Dans `send`, juste après le bloc `if not player then ... end` :

```lua
        -- Un bot n'a pas de client : rien a lui envoyer, et ce n'est pas une anomalie.
        if player.bot then return end
```

Remplacer `character_of` :

```lua
    local function character_of(seat)
        local player = player_by_seat[seat]
        if not player then return nil end
        -- Un bot n'a pas de session : son corps est range dans son entree d'assise.
        if player.bot then
            for _, entry in ipairs(seated) do
                if entry.player == player then return entry.body end
            end
            return nil
        end
        return player:GetControlledCharacter()
    end
```

Remplacer `remettre_a_zero` :

```lua
    local function remettre_a_zero()
        for _, entry in ipairs(seated) do
            if entry.body then entry.body:Destroy() end
        end
        state, started_at = nil, nil
        player_by_seat, seat_by_player, chair_of, seated = {}, {}, {}, {}
    end
```

- [ ] **Step 3 : l'assise note `bot` et `name`**

Dans `Adapter.Seat`, remplacer la création de l'entrée :

```lua
        seated[#seated + 1] = {
            player       = player,
            chair        = chair_n,
            character_id = session and session.character_id or 0,
            name         = player:GetName(),
            bot          = player.bot or nil,
        }
```

- [ ] **Step 4 : pas de résultat en base avec des bots**

Dans `TRANSLATORS.match_ended`, remplacer la boucle qui remplit `releve.seated` :

```lua
        local avec_bots = false
        for i, entry in ipairs(seated) do
            releve.seated[i] = {
                seat         = entry.seat,
                chair        = entry.chair,
                character_id = entry.character_id,
            }
            if entry.bot then avec_bots = true end
        end
```

Remplacer ensuite le bloc `local ok, err = pcall(Adapter.PersistResult, ...)`, avec son `if not ok`, par :

```lua
        if avec_bots then
            Log.Info("liars", "partie avec bots : resultat non enregistre")
        else
            local ok, err = pcall(Adapter.PersistResult, e.winner, e.summary, releve)
            if not ok then
                Log.Error("liars", "resultat non ecrit : " .. tostring(err))
            end
        end
```

- [ ] **Step 5 : le déclenchement**

Juste avant `function Adapter.Act(act, cid)` :

```lua
    -- Si le jeu attend un bot, on lui demande son coup apres un delai. Le
    -- coup est decide sur l'etat COURANT a l'echeance, et seulement si aucun
    -- lot d'effets n'est passe entre-temps : un minuteur perime ne joue pas.
    function Adapter.ScheduleBots()
        bot_generation = bot_generation + 1
        local seat = Bots.Awaited(state)
        local player = seat and player_by_seat[seat]
        if not (player and player.bot) then return end

        local generation = bot_generation
        Timer.SetTimeout(function()
            if generation ~= bot_generation then return end
            local act = Bots.Decide(state, seat, bot_rng)
            if not act then return end
            local ok, raison = Adapter.Act(act)
            if not ok then
                Log.Warn("liars", "coup de bot refuse : " .. tostring(raison))
            end
        end, math.floor(config.bots.delay * 1000))
    end
```

Dans `Adapter.Act`, après `Adapter.ArmShootTimeout()` sur le chemin de succès, ajouter `Adapter.ScheduleBots()`. Même chose dans `Adapter.Begin`, après son `Adapter.ArmShootTimeout()`.

- [ ] **Step 6 : `SetBots` et le corps**

Juste avant `function Adapter.Begin(player, cid)` :

```lua
    ---------------------------------------------------------------- bots de test

    -- Un bot est un pseudo-joueur : il repond a GetID et GetName comme un
    -- Player. Son identifiant est l'oppose de sa chaise, jamais celui d'un
    -- vrai joueur.
    local function nouveau_bot(chair_n)
        local id = -chair_n
        return {
            bot     = true,
            GetID   = function() return id end,
            GetName = function() return "Bot " .. chair_n end,
        }
    end

    -- Debout derriere sa chaise, dans l'axe table-chaise, tourne vers la
    -- table : assis dessus, il heurterait la chaise cuite dans la carte.
    local function corps_de_bot(chair_n)
        local loc  = config.layout.chairs[chair_n].location
        local home = config.layout.revolver_home
        local dx, dy = loc.x - home.x, loc.y - home.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1 then len = 1 end
        local recul = config.bots.body_offset
        local yaw = math.deg(math.atan(-dy, -dx))
        return Character(
            Vector(loc.x + dx / len * recul, loc.y + dy / len * recul, loc.z + 100.0),
            Rotator(0, yaw, 0),
            ASSETS.bot_body
        )
    end

    -- Fixe le nombre de bots assis : on retire ceux qui sont la, puis on en
    -- assoit n aux chaises libres, par ordre croissant. Hors partie seulement.
    function Adapter.SetBots(n)
        if state then return false, "partie_en_cours" end

        for i = #seated, 1, -1 do
            local entry = seated[i]
            if entry.bot then
                if entry.body then entry.body:Destroy() end
                player_by_seat[entry.chair] = nil
                seat_by_player[entry.player:GetID()] = nil
                table.remove(seated, i)
                send("all", "liars:unseated", entry.chair)
            end
        end

        local assis = 0
        for chair_n = 1, #config.layout.chairs do
            if assis >= n then break end
            if not player_by_seat[chair_n] and Adapter.Seat(nouveau_bot(chair_n), chair_n) then
                seated[#seated].body = corps_de_bot(chair_n)
                assis = assis + 1
            end
        end

        Log.Info("liars", ("%d bot(s) a la table"):format(assis))
        return true, assis
    end

```

- [ ] **Step 7 : le mode dev et la commande**

Dans `Server/core/config.lua`, section `dev`, après `smoke_test = false,` :

```lua
        -- Bots de test de Liar's Bar : "/bots N" dans le chat. A mettre a
        -- false sur un serveur ouvert au public.
        liars_bots = true,
```

Dans `Server/Index.lua`, après la construction de `LiarsEngine` :

```lua
local LiarsBots = Package.Require("games/liars_bar/bots.lua")(LiarsConfig)
```

puis passer `LiarsBots` à l'adaptateur, juste après `LiarsEngine` :

```lua
local LiarsBar = Package.Require("games/liars_bar/adapter.lua")(
    Log, DB, Ids, Characters, Interactables, Intents,
    LiarsEngine, LiarsBots, Appearances, LiarsConfig, ServerConfig.spawn)
```

Après `LiarsBar.Init()` :

```lua
-- Bots de test : "/bots N" dans le chat, en mode dev seulement. Retourner
-- false retient le message (doc Chat, PlayerSubmit).
if ServerConfig.dev and ServerConfig.dev.liars_bots then
    Chat.Subscribe("PlayerSubmit", function(message, player)
        local n = tostring(message):match("^/bots%s+(%d+)%s*$")
        if not n then return end

        local ok, detail = LiarsBar.SetBots(tonumber(n))
        if ok then
            Chat.SendMessage(player, ("%d bot(s) a la table"):format(detail))
        else
            Chat.SendMessage(player, "bots refuses : " .. tostring(detail))
        end
        return false
    end)
    Log.Info("liars", "bots de test actifs : /bots N dans le chat")
end
```

- [ ] **Step 8 : vérifier**

```bash
lua tests/run.lua
lua -e 'for _,f in ipairs{"Packages/fate-games/Server/games/liars_bar/adapter.lua","Packages/fate-games/Server/Index.lua","Packages/fate-games/Server/core/config.lua"} do assert(loadfile(f)) end print("syntaxe ok")'
```

Attendu : `186 test(s) ok, 0 echec(s)` et `syntaxe ok`.

- [ ] **Step 9 : commit**

```bash
git add Packages/fate-games/Server/games/liars_bar/adapter.lua Packages/fate-games/Server/core/config.lua Packages/fate-games/Server/Index.lua
git commit -m "LIARS - bots de test a la table : /bots N, corps debout, rien en base"
git log -1 --format='%an%n%B' | grep -ic "claude\|anthropic\|co-authored"
```

---

### Task 3 : les événements du HUD côté serveur

**Files:**
- Modify : `Packages/fate-games/Server/games/liars_bar/adapter.lua`

**Interfaces:**
- Produces, vers les clients :
  - `liars:seated(chair, player_id, name)` ;
  - `liars:started({ {chair, name}, ... })` ;
  - `liars:refused(raison, contexte|nil)`, envoyé à un seul joueur.
- `Adapter.Begin` rend `false, "pas_assez_de_joueurs", { assis, minimum }`.

- [ ] **Step 1 : le nom à l'assise**

Dans `Adapter.Seat`, remplacer l'envoi :

```lua
        send("all", "liars:seated", chair_n, player:GetID(), player:GetName())
```

- [ ] **Step 2 : « partie lancée » et le contexte du refus**

Dans `Adapter.Begin`, remplacer le retour `pas_assez_de_joueurs` :

```lua
        if #seated < config.min_players then
            return false, "pas_assez_de_joueurs", { assis = #seated, minimum = config.min_players }
        end
```

Toujours dans `Begin`, juste avant le `dispatch(effects, cid)` du chemin de succès :

```lua
        -- Le moteur n'annonce pas le debut : les clients l'apprennent ici,
        -- avant la premiere carte de table.
        local annonce = {}
        for i, entry in ipairs(seated) do
            annonce[i] = { chair = entry.chair, name = entry.name }
        end
        send("all", "liars:started", annonce)
```

- [ ] **Step 3 : les refus reviennent au joueur**

Juste après la fonction `send` :

```lua
    -- Un refus par E doit revenir au joueur : le registre d'interaction ignore
    -- ce que rend on_interact, et le client recevrait "ok".
    local function refuser(player, raison, contexte)
        if player and not player.bot then
            Events.CallRemote("liars:refused", player, Reliability.Reliable, raison, contexte)
        end
    end
```

Dans `Adapter.Init`, remplacer le `on_interact` des chaises :

```lua
                on_interact = function(player, session, entry, cid)
                    local ok, raison = Adapter.Seat(player, chair_n, cid)
                    if not ok then refuser(player, raison) end
                end,
```

et celui du revolver :

```lua
            on_interact = function(player, session, entry, cid)
                if not state then
                    local ok, raison, contexte = Adapter.Begin(player, cid)
                    if not ok then refuser(player, raison, contexte) end
                    return
                end
                local seat = seat_by_player[player:GetID()]
                if not seat then
                    return refuser(player, "pas_a_table")
                end
                local ok, raison = Adapter.Act({ kind = "shoot", seat = seat }, cid)
                if not ok then refuser(player, raison) end
            end,
```

- [ ] **Step 4 : vérifier et commiter**

```bash
lua tests/run.lua
lua -e 'assert(loadfile("Packages/fate-games/Server/games/liars_bar/adapter.lua")) print("syntaxe ok")'
git add Packages/fate-games/Server/games/liars_bar/adapter.lua
git commit -m "LIARS - nom a l'assise, annonce du lancement, refus renvoyes au joueur"
git log -1 --format='%an%n%B' | grep -ic "claude\|anthropic\|co-authored"
```

---

### Task 4 : le journal du HUD

**Files:**
- Modify : `Packages/fate-games/Shared/config.lua`
- Create : `Packages/fate-games/Client/liars_bar/journal.lua`
- Create : `tests/suites/liars_journal.lua`
- Modify : `tests/run.lua`

**Interfaces:**
- Consumes : les événements de la Task 3.
- Produces : `Journal.New() -> j` et `Journal.RankName(rank)`. L'objet `j` porte les champs `my_chair`, `names`, `table_rank`, `turn`, `hand`, `lines` (`{text, kind}`, avec `kind` valant `"info"` ou `"refus"`). Ses méthodes sont `j:On(event, ...)`, `j:Toggle(i) -> bool`, `j:Selection() -> {indices}`, `j:MarkPending(indices)`, `j:IsMyTurn()`, `j:Who(chair)`. `On("seated", chair, name, is_me)` reçoit un booléen : c'est le HUD qui compare au joueur local.

- [ ] **Step 1 : la config partagée**

Dans `Shared/config.lua`, après la section `interaction = { ... },` :

```lua
    -- HUD provisoire de Liar's Bar (Client/liars_bar/). Noms de touches de la
    -- doc Input. Pas Enter pour poser : il risque de servir au chat.
    liars_hud = {
        journal_lines = 8,
        -- Miroir du plafond serveur (games/liars_bar/data/config.lua), qui
        -- seul fait foi : ici il ne sert qu'a ne pas proposer l'impossible.
        max_play = 3,
        keys = {
            select = { "One", "Two", "Three", "Four", "Five" },
            play   = "P",
            accuse = "M",
        },
    },
```

- [ ] **Step 2 : le test qui échoue**

`tests/suites/liars_journal.lua` :

```lua
return function(H, Stubs)
    local SharedConfig = Package.Require("Shared/config.lua")
    local Journal      = Package.Require("liars_bar/journal.lua")(SharedConfig.liars_hud)

    local function derniere(j) return j.lines[#j.lines] end

    -- Une table ou je suis a la chaise 1, avec Bot 2, et c'est mon tour.
    local function table_a_moi(main)
        local j = Journal.New()
        j:On("seated", 1, "zix", true)
        j:On("seated", 2, "Bot 2", false)
        j:On("started", { { chair = 1, name = "zix" }, { chair = 2, name = "Bot 2" } })
        j:On("deal", main or { "king", "queen", "ace", "joker", "king" })
        j:On("turn", 1)
        return j
    end

    H.describe("liars_bar/journal", function()
        H.it("reconnait sa chaise et nomme les joueurs", function()
            local j = Journal.New()
            j:On("seated", 1, "zix", true)
            j:On("seated", 2, "Bot 2", false)
            H.assert_eq(j.my_chair, 1, "ma chaise")
            H.assert_eq(derniere(j).text, "Bot 2 s'assoit, chaise 2", "ligne")
        end)

        H.it("annonce le lancement puis la carte de table", function()
            local j = table_a_moi()
            j:On("table_card", "queen")
            H.assert_eq(j.table_rank, "queen", "carte de table")
            H.assert_eq(derniere(j).text, "Carte de table : Dame", "ligne")
        end)

        H.it("dit quand c'est mon tour", function()
            local j = table_a_moi()
            H.assert_true(j:IsMyTurn(), "mon tour")
            H.assert_eq(derniere(j).text, "Tour : à toi !", "ligne")
        end)

        H.it("refuse la selection hors de son tour", function()
            local j = table_a_moi()
            j:On("turn", 2)
            H.assert_false(j:Toggle(1), "selection")
            H.assert_eq(derniere(j).text, "Tour : Bot 2 (chaise 2)", "ligne")
        end)

        H.it("plafonne la selection a trois cartes", function()
            local j = table_a_moi()
            H.assert_true(j:Toggle(1), "1")
            H.assert_true(j:Toggle(2), "2")
            H.assert_true(j:Toggle(3), "3")
            H.assert_false(j:Toggle(4), "4")
            H.assert_eq(table.concat(j:Selection(), ","), "1,2,3", "selection")
        end)

        H.it("refuse un indice hors de la main", function()
            local j = table_a_moi({ "king", "ace" })
            H.assert_false(j:Toggle(3), "indice 3")
        end)

        H.it("retire les cartes posees a la confirmation", function()
            local j = table_a_moi()
            j:Toggle(2)
            j:Toggle(4)
            j:MarkPending(j:Selection())
            j:On("cards_played", 1, 2)
            H.assert_eq(table.concat(j.hand, ","), "king,ace,king", "main")
            H.assert_eq(derniere(j).text, "zix (chaise 1) pose 2 carte(s)", "ligne")
        end)

        H.it("une pose refusee laisse la main intacte", function()
            local j = table_a_moi()
            j:Toggle(1)
            j:MarkPending(j:Selection())
            j:On("intent_result", "liars_play", false, { audit = "pas son tour" })
            j:On("cards_played", 1, 1)
            H.assert_eq(#j.hand, 5, "main")
            H.assert_eq(j.lines[#j.lines - 1].kind, "refus", "type de ligne")
            H.assert_eq(j.lines[#j.lines - 1].text, "Refusé : pas son tour", "texte")
        end)

        H.it("traduit un refus avec son contexte", function()
            local j = Journal.New()
            j:On("refused", "pas_assez_de_joueurs", { assis = 1, minimum = 3 })
            H.assert_eq(derniere(j).text, "Refusé : pas assez de joueurs (1/3)", "texte")
            H.assert_eq(derniere(j).kind, "refus", "type")
        end)

        H.it("un spectateur suit la table sans main", function()
            local j = Journal.New()
            j:On("seated", 1, "zix", false)
            j:On("started", { { chair = 1, name = "zix" } })
            j:On("turn", 1)
            H.assert_nil(j.my_chair, "chaise")
            H.assert_eq(#j.hand, 0, "main")
            H.assert_false(j:IsMyTurn(), "tour")
        end)

        H.it("raconte l'accusation et le tir", function()
            local j = table_a_moi()
            j:On("accuse", 2, 1)
            H.assert_eq(derniere(j).text, "Bot 2 (chaise 2) accuse zix (chaise 1)", "accusation")
            j:On("reveal", 1, { "king", "joker" })
            H.assert_eq(derniere(j).text, "Révélé chez zix (chaise 1) : Roi, Joker", "revelation")
            j:On("designated", 1)
            H.assert_eq(derniere(j).text, "Tu dois tirer : E sur le revolver", "designation")
            j:On("shoot", 1, 3, false)
            H.assert_eq(derniere(j).text, "zix (chaise 1) tire… à blanc", "tir")
        end)

        H.it("garde les dernieres lignes seulement", function()
            local j = Journal.New()
            for i = 1, 12 do j:On("refused", "code_" .. i) end
            H.assert_eq(#j.lines, 8, "nombre")
            H.assert_eq(derniere(j).text, "Refusé : code_12", "derniere")
        end)

        H.it("la fin de partie vide la main", function()
            local j = table_a_moi()
            j:On("match_ended", 2)
            H.assert_eq(#j.hand, 0, "main")
            H.assert_eq(derniere(j).text, "Victoire : Bot 2 (chaise 2)", "ligne")
        end)
    end)
end
```

Dans `tests/run.lua`, ajouter `"liars_journal",` après `"liars_bots",`.

- [ ] **Step 3 : vérifier l'échec**

Run : `lua tests/run.lua`
Attendu : échec du chargement, avec `fichier introuvable -> liars_bar/journal.lua`.

- [ ] **Step 4 : l'implémentation**

`Packages/fate-games/Client/liars_bar/journal.lua` :

```lua
-- Etat affiche par le HUD provisoire de Liar's Bar.
--
-- Pur : aucune globale nanos, donc testable hors jeu. Il recoit les
-- evenements du serveur sous leur nom court et tient ce qu'il faut dessiner.
-- Il ne juge rien du jeu : le serveur tranche, le journal raconte.

return function(config)
    local Journal = {}

    local RANGS = { king = "Roi", queen = "Dame", ace = "As", joker = "Joker" }

    local RAISONS = {
        partie_en_cours      = "une partie est en cours",
        place_occupee        = "cette place est prise",
        pas_assis            = "il faut être assis pour lancer",
        pas_assez_de_joueurs = "pas assez de joueurs",
        pas_a_table          = "tu n'es pas à la table",
        aucune_partie        = "aucune partie en cours",
        charge_invalide      = "demande invalide",
        demarrage_impossible = "la partie n'a pas pu démarrer",
    }

    function Journal.RankName(r)
        return RANGS[r] or tostring(r)
    end

    function Journal.New()
        local j = {
            my_chair   = nil,
            names      = {},
            table_rank = nil,
            turn       = nil,
            hand       = {},
            lines      = {},
        }
        local selected = {}    -- indice -> true
        local pending  = nil   -- indices envoyes, en attente de confirmation

        local function qui(chair)
            if chair == nil then return "?" end
            local nom = j.names[chair]
            if nom then return ("%s (chaise %d)"):format(nom, chair) end
            return ("chaise %d"):format(chair)
        end

        local function ligne(text, kind)
            j.lines[#j.lines + 1] = { text = text, kind = kind or "info" }
            while #j.lines > config.journal_lines do
                table.remove(j.lines, 1)
            end
        end

        local function refus(code, contexte)
            local texte = RAISONS[code] or tostring(code)
            if code == "pas_assez_de_joueurs" and type(contexte) == "table" then
                texte = ("%s (%s/%s)"):format(texte, tostring(contexte.assis), tostring(contexte.minimum))
            end
            ligne("Refusé : " .. texte, "refus")
        end

        local function hors_partie()
            j.hand, j.table_rank, j.turn = {}, nil, nil
            selected, pending = {}, nil
        end

        local H = {}

        H.seated = function(chair, name, is_me)
            j.names[chair] = name
            if is_me then j.my_chair = chair end
            ligne(("%s s'assoit, chaise %d"):format(tostring(name or "?"), chair))
        end

        H.unseated = function(chair)
            ligne(("Chaise %d libérée"):format(chair))
            j.names[chair] = nil
            if j.my_chair == chair then
                j.my_chair = nil
                hors_partie()
            end
        end

        H.started = function(list)
            hors_partie()
            ligne(("Partie lancée : %d joueurs"):format(#(list or {})))
        end

        H.deal = function(cards)
            j.hand = {}
            for i, c in ipairs(cards or {}) do j.hand[i] = c end
            selected, pending = {}, nil
            ligne(("Tu reçois %d cartes"):format(#j.hand))
        end

        H.table_card = function(r)
            j.table_rank = r
            ligne("Carte de table : " .. Journal.RankName(r))
        end

        H.turn = function(chair)
            j.turn = chair
            selected = {}
            if chair ~= nil and chair == j.my_chair then
                ligne("Tour : à toi !")
            else
                ligne("Tour : " .. qui(chair))
            end
        end

        H.cards_played = function(chair, count)
            ligne(("%s pose %d carte(s)"):format(qui(chair), count))
            if chair == j.my_chair and pending then
                table.sort(pending, function(a, b) return a > b end)
                for _, i in ipairs(pending) do table.remove(j.hand, i) end
                pending = nil
            end
        end

        H.accuse = function(accuser, target)
            ligne(("%s accuse %s"):format(qui(accuser), qui(target)))
        end

        H.reveal = function(chair, cards)
            local noms = {}
            for i, c in ipairs(cards or {}) do noms[i] = Journal.RankName(c) end
            ligne(("Révélé chez %s : %s"):format(qui(chair), table.concat(noms, ", ")))
        end

        H.designated = function(chair)
            if chair ~= nil and chair == j.my_chair then
                ligne("Tu dois tirer : E sur le revolver")
            else
                ligne(qui(chair) .. " doit tirer")
            end
        end

        H.shoot = function(chair, chamber, fatal)
            ligne(("%s tire… %s"):format(qui(chair), fatal and "BANG" or "à blanc"))
        end

        H.eliminated = function(chair)
            ligne(qui(chair) .. " est éliminé")
        end

        H.round_ended = function()
            j.turn = nil
            selected = {}
            ligne("Fin de manche")
        end

        H.match_ended = function(winner)
            hors_partie()
            if winner then
                ligne("Victoire : " .. qui(winner))
            else
                ligne("Partie terminée sans vainqueur")
            end
        end

        H.refused = function(code, contexte)
            refus(code, contexte)
        end

        H.intent_result = function(name, ok, detail)
            if name ~= "liars_play" and name ~= "liars_challenge" then return end
            if ok then return end
            if name == "liars_play" then pending = nil end
            refus(type(detail) == "table" and detail.audit or detail)
        end

        function j:On(event, ...)
            local handler = H[event]
            if handler then handler(...) end
        end

        function j:IsMyTurn()
            return j.my_chair ~= nil and j.turn == j.my_chair
        end

        function j:Who(chair)
            return qui(chair)
        end

        function j:Selection()
            local out = {}
            for i in pairs(selected) do out[#out + 1] = i end
            table.sort(out)
            return out
        end

        function j:IsSelected(i)
            return selected[i] == true
        end

        -- Choisir ou retirer une carte. Refuse hors de son tour, hors de la
        -- main et au-dela du plafond : rend vrai si la selection a change.
        function j:Toggle(i)
            if not j:IsMyTurn() then return false end
            if i < 1 or i > #j.hand then return false end
            if selected[i] then
                selected[i] = nil
                return true
            end
            if #j:Selection() >= config.max_play then return false end
            selected[i] = true
            return true
        end

        -- La pose part vers le serveur : la main n'est retouchee qu'a sa
        -- confirmation, par cards_played pour ma chaise.
        function j:MarkPending(indices)
            pending = indices
            selected = {}
        end

        return j
    end

    return Journal
end
```

- [ ] **Step 5 : vérifier que ça passe**

Run : `lua tests/run.lua`
Attendu : `199 test(s) ok, 0 echec(s)`.

- [ ] **Step 6 : commit**

```bash
git add Packages/fate-games/Shared/config.lua Packages/fate-games/Client/liars_bar/journal.lua tests/suites/liars_journal.lua tests/run.lua
git commit -m "LIARS - journal du HUD : etat affiche, selection, refus traduits"
git log -1 --format='%an%n%B' | grep -ic "claude\|anthropic\|co-authored"
```

---

### Task 5 : le HUD dessiné

**Files:**
- Create : `Packages/fate-games/Client/liars_bar/hud.lua`
- Modify : `Packages/fate-games/Client/Index.lua`

**Interfaces:**
- Consumes : `Journal` (Task 4), `send_intent(name, payload)` défini dans `Client/Index.lua`, config `liars_hud`.

- [ ] **Step 1 : l'implémentation**

`Packages/fate-games/Client/liars_bar/hud.lua` :

```lua
-- HUD provisoire de Liar's Bar : dessine le journal et ecoute les touches.
--
-- Le seul fichier du HUD qui touche au moteur. Tout ce qui se decide sur
-- l'affichage est dans journal.lua, teste hors jeu ; ici on branche et on
-- dessine. Il disparaitra avec l'eventail 3D.

return function(config, Journal, send_intent)
    local journal = Journal.New()
    local chat_ouvert = false

    -- Evenements relayes tels quels, sous leur nom court.
    local EVENTS = {
        "unseated", "started", "deal", "table_card", "turn", "cards_played",
        "accuse", "reveal", "designated", "shoot", "eliminated",
        "round_ended", "match_ended", "refused",
    }
    for _, name in ipairs(EVENTS) do
        Events.SubscribeRemote("liars:" .. name, function(...)
            journal:On(name, ...)
        end)
    end

    -- "seated" porte l'identifiant du joueur : on le compare au joueur local
    -- ici, pour que journal.lua reste sans globale.
    Events.SubscribeRemote("liars:seated", function(chair, player_id, name)
        local me = Client.GetLocalPlayer()
        journal:On("seated", chair, name, me ~= nil and me:GetID() == player_id)
    end)

    Events.SubscribeRemote("zix:intent_result", function(name, ok, detail)
        journal:On("intent_result", name, ok, detail)
    end)

    -- Taper "/bots 3" ne doit pas poser de cartes.
    Chat.Subscribe("Open", function() chat_ouvert = true end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    Input.Subscribe("KeyPress", function(key_name)
        if chat_ouvert then return end
        local keys = config.keys

        for i, k in ipairs(keys.select) do
            if key_name == k then
                journal:Toggle(i)
                return
            end
        end

        if key_name == keys.play then
            local indices = journal:Selection()
            if #indices > 0 and journal:IsMyTurn() then
                journal:MarkPending(indices)
                send_intent("liars_play", { indices = indices })
            end
        elseif key_name == keys.accuse then
            if journal:IsMyTurn() then
                send_intent("liars_challenge", {})
            end
        end
    end)

    ---------------------------------------------------------------- dessin

    local FOND  = Color(0.02, 0.02, 0.02, 0.75)
    local ROUGE = Color(1.0, 0.4, 0.4, 1.0)
    local JAUNE = Color(1.0, 0.85, 0.3, 1.0)

    local function texte(c, s, x, y, taille, couleur, centre)
        c:DrawText(s, Vector2D(x, y), FontType.Roboto, taille, couleur,
            0, centre or false, false, Color.BLACK, Vector2D(1, 1), true, Color.BLACK)
    end

    local canvas = Canvas(true, Color.TRANSPARENT, -1, true, true)

    canvas:Subscribe("Update", function(self, width, height)
        -- Rien a montrer tant que la table n'a rien dit.
        if #journal.lines == 0 then return end

        -- L'etat, en haut a gauche.
        local etat = { journal.my_chair and ("Ta chaise : %d"):format(journal.my_chair) or "Spectateur" }
        if journal.table_rank then
            etat[#etat + 1] = "Carte de table : " .. Journal.RankName(journal.table_rank)
        end
        if journal:IsMyTurn() then
            etat[#etat + 1] = "À toi !"
        elseif journal.turn then
            etat[#etat + 1] = "Tour : " .. journal:Who(journal.turn)
        end
        texte(self, table.concat(etat, "   |   "), 20, 20, 20,
            journal:IsMyTurn() and JAUNE or Color.WHITE)

        -- Le journal, sous l'etat.
        local hauteur_ligne = 24
        local n = #journal.lines
        self:DrawRect("", Vector2D(12, 52), Vector2D(560, n * hauteur_ligne + 16),
            FOND, BlendMode.AlphaBlend)
        for i, l in ipairs(journal.lines) do
            texte(self, l.text, 20, 52 + (i - 1) * hauteur_ligne + 8, 17,
                l.kind == "refus" and ROUGE or Color.WHITE)
        end

        -- Ma main, en bas, seulement si j'en ai une.
        if #journal.hand > 0 then
            local cartes = {}
            for i, c in ipairs(journal.hand) do
                local nom = ("[%d] %s"):format(i, Journal.RankName(c))
                cartes[i] = journal:IsSelected(i) and ("> " .. nom .. " <") or nom
            end
            texte(self, table.concat(cartes, "    "), width / 2, height - 110, 24, Color.WHITE, true)
            if journal:IsMyTurn() then
                texte(self, "1-5 choisir   ·   P poser   ·   M accuser", width / 2, height - 76, 16, JAUNE, true)
            end
        end
    end)

    return journal
end
```

- [ ] **Step 2 : le câblage**

Dans `Client/Index.lua`, juste après `Interaction.Start()` :

```lua

-- HUD provisoire de Liar's Bar : le journal et la main, au clavier.
local LiarsJournal = Package.Require("liars_bar/journal.lua")(SharedConfig.liars_hud)
Package.Require("liars_bar/hud.lua")(SharedConfig.liars_hud, LiarsJournal, send_intent)
```

- [ ] **Step 3 : vérifier**

```bash
lua tests/run.lua
lua -e 'for _,f in ipairs{"Packages/fate-games/Client/liars_bar/hud.lua","Packages/fate-games/Client/Index.lua"} do assert(loadfile(f)) end print("syntaxe ok")'
```

Attendu : `199 test(s) ok, 0 echec(s)` et `syntaxe ok`.

- [ ] **Step 4 : commit**

```bash
git add Packages/fate-games/Client/liars_bar/hud.lua Packages/fate-games/Client/Index.lua
git commit -m "LIARS - HUD provisoire : etat, journal et main au clavier"
git log -1 --format='%an%n%B' | grep -ic "claude\|anthropic\|co-authored"
```

---

### Task 6 : la vérification en jeu (par l'auteur)

Rien à coder. L'auteur relance avec `.\scripts\dev.ps1 restart`, pendant que je lis `C:\nanos-world-server\.dev\server.log`.

- [ ] Les quatre cubes gris recouvrent leur chaise.
- [ ] Seul, E sur le revolver : ligne rouge « Refusé : pas assez de joueurs (1/3) ».
- [ ] `/bots 3` dans le chat : la commande n'apparaît pas dans le chat, trois corps se tiennent derrière les chaises libres, et le journal affiche « Bot N s'assoit ».
- [ ] S'asseoir à la chaise restante, puis E sur le revolver : « Partie lancée : 4 joueurs », la carte de table, et ta main en bas.
- [ ] À ton tour : 1 à 5 pour choisir, P pour poser, M pour accuser. Les bots jouent seuls.
- [ ] Désigné : E sur le revolver pour tirer.
- [ ] La partie va jusqu'à « Victoire », et le journal serveur dit `partie avec bots : resultat non enregistre`.

Une fois tout vérifié : `debug_visible = false` dans `data/config.lua`, puis :

```bash
git commit -am "LIARS - reperes des places invisibles apres calibration"
```
