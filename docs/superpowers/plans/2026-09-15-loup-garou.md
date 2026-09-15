# Moteur de loup-garou — plan d'implémentation

> **Pour un exécutant agentique :** SOUS-COMPÉTENCE REQUISE — utiliser
> `superpowers:subagent-driven-development` (recommandé) ou `superpowers:executing-plans` pour
> dérouler ce plan tâche par tâche. Les étapes utilisent des cases à cocher (`- [ ]`).

**But :** implémenter la logique serveur d'une partie de loup-garou — composition, attribution
secrète des rôles, déroulement des phases, vote, victoire — entièrement testable hors-jeu.

**Architecture :** le moteur ne connaît pas nanos world. On lui donne un état et une durée écoulée,
il rend un nouvel état et une liste d'effets. Un adaptateur mince traduit ces effets en appels
moteur. Les phases vivent dans une pile, les rôles dans un registre de données.

**Pile technique :** Lua 5.4, banc de test maison (`tests/harness.lua`), aucune dépendance externe.

**Spec :** `docs/superpowers/specs/2026-09-15-loup-garou-design.md`

## Contraintes globales

- **Lua 5.4** exactement — la version de la VM du moteur nanos world.
- **Aucune globale du moteur** dans `games/werewolf/`, sauf `adapter.lua` : pas de `Events`,
  `Player`, `Timer`, `Character`, `Console`. Les modules reçoivent tout par injection.
- **Convention de module** : un module de *données* retourne directement une table ; un module de
  *comportement* retourne `function(dépendances) ... return M end`.
- **Aléatoire injecté** : jamais `math.random` directement — une fonction `rng` passée en argument,
  pour que les tests soient déterministes.
- **Tests** : une suite par module dans `tests/suites/<nom>.lua`, signature
  `return function(H, Stubs)`, enregistrée dans la liste `suites` de `tests/run.lua`.
- **Lancer les tests** : `powershell -File scripts/test.ps1` depuis la racine du dépôt, ou
  `lua tests/run.lua`. Code de sortie 1 si un test échoue.
- **Messages de commit** : jamais de mention d'un outil d'IA, jamais de `Co-Authored-By`. Règle
  stricte du projet.

---

## Structure des fichiers

| Fichier | Responsabilité |
| --- | --- |
| `Packages/fate-games/Server/games/werewolf/effects.lua` | Construire et valider les effets. Porte la garantie de confidentialité via le champ `audience`. |
| `Packages/fate-games/Server/games/werewolf/data/roles.lua` | Registre des rôles et composition selon le nombre de joueurs. Données pures. |
| `Packages/fate-games/Server/games/werewolf/match.lua` | État d'une partie : qui joue, quel rôle, qui vit. |
| `Packages/fate-games/Server/games/werewolf/voting.lua` | Enregistrement des désignations et dépouillement. |
| `Packages/fate-games/Server/games/werewolf/outcome.lua` | Conditions de victoire. |
| `Packages/fate-games/Server/games/werewolf/data/phases.lua` | Phases de base et durées par défaut. Données pures. |
| `Packages/fate-games/Server/games/werewolf/engine.lua` | La machine : pile de phases, horloge, application des règles. |
| `Packages/fate-games/Server/games/werewolf/adapter.lua` | Seul fichier qui connaît nanos world. |

Chaque module se teste seul. L'ordre des tâches suit les dépendances : `effects` ne dépend de rien,
`engine` dépend de tout le reste.

---

### Tâche 1 : le vocabulaire des effets

C'est ici que vit la garantie de confidentialité du jeu : un effet `point_at` sans audience explicite
est refusé, ce qui rend impossible d'écrire par distraction du code qui trahirait les loups.

**Fichiers :**
- Créer : `Packages/fate-games/Server/games/werewolf/effects.lua`
- Créer : `tests/suites/werewolf_effects.lua`
- Modifier : `tests/run.lua` — ajouter `"werewolf_effects"` à la liste `suites`

**Interfaces :**
- Consomme : rien.
- Produit : `Effects.assign_role(player, role)`, `Effects.reveal(viewer, target, tint)`,
  `Effects.voice_channel(player, channel)`, `Effects.mute(player, muted)`,
  `Effects.point_at(player, target, audience)`, `Effects.kill(player, cause)`,
  `Effects.announce(key, args)`, `Effects.world_light(phase)`,
  `Effects.match_ended(winner, summary)`. Chacune rend une table avec un champ `kind`.
  `Effects.validate(list) -> ok, raison`.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/suites/werewolf_effects.lua` :

```lua
return function(H, Stubs)
    local Effects = Package.Require("games/werewolf/effects.lua")

    H.describe("werewolf/effects", function()

        H.it("construit un effet d'attribution de role", function()
            local e = Effects.assign_role(7, "seer")
            H.assert_eq(e.kind, "assign_role", "genre")
            H.assert_eq(e.player, 7, "destinataire")
            H.assert_eq(e.role, "seer", "role")
        end)

        H.it("exige une audience explicite pour point_at", function()
            H.assert_error(function() Effects.point_at(1, 2) end, "audience")
        end)

        H.it("accepte les audiences connues", function()
            for _, a in ipairs({ "all", "wolves", "dead" }) do
                local e = Effects.point_at(1, 2, a)
                H.assert_eq(e.audience, a, "audience " .. a)
            end
        end)

        H.it("accepte une audience d'un seul joueur", function()
            local e = Effects.point_at(1, 2, { player = 9 })
            H.assert_eq(e.audience.player, 9, "audience nominative")
        end)

        H.it("refuse une audience inventee", function()
            H.assert_error(function() Effects.point_at(1, 2, "village") end, "audience")
        end)

        H.it("valide une liste d'effets", function()
            local ok = Effects.validate({ Effects.mute(1, true), Effects.world_light("night") })
            H.assert_true(ok, "liste valide")
        end)

        H.it("rejette une liste contenant autre chose qu'un effet", function()
            local ok, raison = Effects.validate({ { kind = "inconnu" } })
            H.assert_false(ok, "liste invalide")
            H.assert_true(raison ~= nil, "raison fournie")
        end)
    end)
end
```

Ajouter `"werewolf_effects"` à la liste `suites` de `tests/run.lua`, après `"interactables"`.

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

Lancer : `powershell -File scripts/test.ps1`
Attendu : ÉCHEC, `Package.Require : fichier introuvable -> games/werewolf/effects.lua`

- [ ] **Étape 3 : écrire l'implémentation minimale**

Créer `Packages/fate-games/Server/games/werewolf/effects.lua` :

```lua
-- Vocabulaire des effets produits par le moteur de jeu.
--
-- Le moteur ne touche jamais nanos world : il rend des effets, et l'adaptateur les
-- traduit. Ce fichier est le contrat entre les deux.
--
-- Le champ `audience` est ce qui protege le jeu. Un loup qui designe sa victime la
-- nuit tend le bras pour les autres loups uniquement. L'oublier trahirait tout le
-- monde, donc il est exige et non optionnel.

local Effects = {}

local KINDS = {
    assign_role = true, reveal = true, voice_channel = true, mute = true,
    point_at = true, kill = true, announce = true, world_light = true,
    match_ended = true,
}

local NAMED_AUDIENCES = { all = true, wolves = true, dead = true }

local function check_audience(audience)
    if type(audience) == "table" and audience.player ~= nil then return end
    if NAMED_AUDIENCES[audience] then return end
    error("audience invalide : " .. tostring(audience), 3)
end

function Effects.assign_role(player, role)
    return { kind = "assign_role", player = player, role = role }
end

function Effects.reveal(viewer, target, tint)
    return { kind = "reveal", viewer = viewer, target = target, tint = tint }
end

function Effects.voice_channel(player, channel)
    return { kind = "voice_channel", player = player, channel = channel }
end

function Effects.mute(player, muted)
    return { kind = "mute", player = player, muted = muted and true or false }
end

function Effects.point_at(player, target, audience)
    check_audience(audience)
    return { kind = "point_at", player = player, target = target, audience = audience }
end

function Effects.kill(player, cause)
    return { kind = "kill", player = player, cause = cause }
end

function Effects.announce(key, args)
    return { kind = "announce", key = key, args = args }
end

function Effects.world_light(phase)
    return { kind = "world_light", phase = phase }
end

function Effects.match_ended(winner, summary)
    return { kind = "match_ended", winner = winner, summary = summary }
end

function Effects.validate(list)
    for index, effect in ipairs(list or {}) do
        if type(effect) ~= "table" or not KINDS[effect.kind] then
            return false, ("effet %d de genre inconnu : %s")
                :format(index, tostring(effect and effect.kind))
        end
    end
    return true
end

return Effects
```

- [ ] **Étape 4 : lancer les tests pour vérifier qu'ils passent**

Lancer : `powershell -File scripts/test.ps1`
Attendu : toutes les suites au vert, 7 tests de plus qu'avant.

- [ ] **Étape 5 : commit**

```bash
git add Packages/fate-games/Server/games/werewolf/effects.lua tests/suites/werewolf_effects.lua tests/run.lua
git commit -m "LOUP-GAROU - vocabulaire des effets

Le moteur rend des effets, l adaptateur les traduit. Le champ audience est
exige sur point_at : l oublier trahirait les loups la nuit."
```

---

### Tâche 2 : le registre des rôles et la composition

**Fichiers :**
- Créer : `Packages/fate-games/Server/games/werewolf/data/roles.lua`
- Créer : `tests/suites/werewolf_roles.lua`
- Modifier : `tests/run.lua` — ajouter `"werewolf_roles"`

**Interfaces :**
- Consomme : rien.
- Produit : `Roles.MIN_PLAYERS` (nombre, vaut 4), `Roles.definitions` (table indexée par id de rôle,
  chaque entrée ayant `id`, `team`, et optionnellement `night_phase = { id, duration, order }`),
  `Roles.compose(player_count) -> liste d'ids de rôles, ou nil, raison`.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/suites/werewolf_roles.lua` :

```lua
return function(H, Stubs)
    local Roles = Package.Require("games/werewolf/data/roles.lua")

    local function count(list, role_id)
        local n = 0
        for _, id in ipairs(list) do if id == role_id then n = n + 1 end end
        return n
    end

    H.describe("werewolf/roles", function()

        H.it("declare les trois roles de cette version", function()
            H.assert_true(Roles.definitions.villager ~= nil, "villageois")
            H.assert_true(Roles.definitions.wolf ~= nil, "loup")
            H.assert_true(Roles.definitions.seer ~= nil, "voyante")
        end)

        H.it("range les phases de nuit : loups avant voyante", function()
            H.assert_eq(Roles.definitions.wolf.night_phase.order, 10, "ordre des loups")
            H.assert_eq(Roles.definitions.seer.night_phase.order, 20, "ordre de la voyante")
        end)

        H.it("refuse de composer en dessous du minimum", function()
            local list, raison = Roles.compose(3)
            H.assert_nil(list, "aucune composition")
            H.assert_true(raison ~= nil, "raison fournie")
        end)

        H.it("compose une partie de quatre joueurs", function()
            local list = Roles.compose(4)
            H.assert_eq(#list, 4, "un role par joueur")
            H.assert_eq(count(list, "wolf"), 1, "un loup")
            H.assert_eq(count(list, "seer"), 1, "une voyante")
            H.assert_eq(count(list, "villager"), 2, "deux villageois")
        end)

        H.it("passe a deux loups a partir de six joueurs", function()
            H.assert_eq(count(Roles.compose(5), "wolf"), 1, "cinq joueurs")
            H.assert_eq(count(Roles.compose(6), "wolf"), 2, "six joueurs")
            H.assert_eq(count(Roles.compose(8), "wolf"), 2, "huit joueurs")
        end)

        H.it("passe a trois loups a partir de neuf joueurs", function()
            H.assert_eq(count(Roles.compose(9), "wolf"), 3, "neuf joueurs")
            H.assert_eq(count(Roles.compose(14), "wolf"), 3, "quatorze joueurs")
        end)

        H.it("rend toujours autant de roles que de joueurs", function()
            for n = Roles.MIN_PLAYERS, 20 do
                H.assert_eq(#Roles.compose(n), n, "composition a " .. n .. " joueurs")
            end
        end)

        H.it("n'a jamais plus de loups que de villageois", function()
            for n = Roles.MIN_PLAYERS, 20 do
                local list = Roles.compose(n)
                H.assert_true(count(list, "wolf") < n - count(list, "wolf"),
                    "equilibre a " .. n .. " joueurs")
            end
        end)
    end)
end
```

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

Lancer : `powershell -File scripts/test.ps1`
Attendu : ÉCHEC, fichier `games/werewolf/data/roles.lua` introuvable.

- [ ] **Étape 3 : écrire l'implémentation minimale**

Créer `Packages/fate-games/Server/games/werewolf/data/roles.lua` :

```lua
-- Registre des roles. Donnees pures : ajouter un role ne touche pas au moteur.
--
-- `order` range les phases de nuit entre elles. Un role ajoute plus tard s'insere
-- en choisissant son numero, sans toucher aux autres.

local Roles = {}

Roles.MIN_PLAYERS = 4

Roles.definitions = {
    villager = {
        id   = "villager",
        team = "village",
    },

    wolf = {
        id          = "wolf",
        team        = "wolves",
        night_phase = { id = "night_wolves", duration = 45, order = 10 },
    },

    seer = {
        id          = "seer",
        team        = "village",
        night_phase = { id = "night_seer", duration = 20, order = 20 },
    },
}

-- Nombre de loups selon la population. Au-dela, tout le reste est villageois.
local function wolf_count(player_count)
    if player_count <= 5 then return 1 end
    if player_count <= 8 then return 2 end
    return 3
end

-- Rend la liste des roles a distribuer, un par joueur. L'ordre n'a pas
-- d'importance : c'est l'appelant qui melange.
function Roles.compose(player_count)
    if type(player_count) ~= "number" or player_count < Roles.MIN_PLAYERS then
        return nil, ("il faut au moins %d joueurs"):format(Roles.MIN_PLAYERS)
    end

    local list = {}
    for _ = 1, wolf_count(player_count) do list[#list + 1] = "wolf" end
    list[#list + 1] = "seer"
    while #list < player_count do list[#list + 1] = "villager" end

    return list
end

return Roles
```

- [ ] **Étape 4 : lancer les tests pour vérifier qu'ils passent**

Lancer : `powershell -File scripts/test.ps1`
Attendu : toutes les suites au vert.

- [ ] **Étape 5 : commit**

```bash
git add Packages/fate-games/Server/games/werewolf/data/roles.lua tests/suites/werewolf_roles.lua tests/run.lua
git commit -m "LOUP-GAROU - registre des roles et composition

Les roles sont des donnees : en ajouter un ne touchera pas au moteur. Un
loup jusqu a cinq joueurs, deux jusqu a huit, trois au-dela."
```

---

### Tâche 3 : l'état d'une partie

**Fichiers :**
- Créer : `Packages/fate-games/Server/games/werewolf/match.lua`
- Créer : `tests/suites/werewolf_match.lua`
- Modifier : `tests/run.lua` — ajouter `"werewolf_match"`

**Interfaces :**
- Consomme : `Roles` (tâche 2), `Effects` (tâche 1).
- Produit : la fabrique `make_match(Roles, Effects)` qui rend un module avec
  `Match.new(player_ids, rng) -> match, effects` ou `nil, raison` ;
  `Match.role_of(match, player) -> id de rôle` ; `Match.team_of(match, player) -> "village"|"wolves"` ;
  `Match.is_alive(match, player) -> booléen` ; `Match.alive(match) -> liste d'ids triée` ;
  `Match.alive_count(match, team|nil) -> nombre` ; `Match.kill(match, player, cause) -> effets` ;
  `Match.players_with_role(match, role_id) -> liste d'ids triée`.
- `rng(n)` est une fonction rendant un entier entre 1 et n.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/suites/werewolf_match.lua` :

```lua
return function(H, Stubs)
    local make_match = Package.Require("games/werewolf/match.lua")
    local Roles      = Package.Require("games/werewolf/data/roles.lua")
    local Effects    = Package.Require("games/werewolf/effects.lua")

    local Match = make_match(Roles, Effects)

    -- Tirage previsible : rend toujours le premier element.
    local function first() return 1 end

    local function new4()
        return Match.new({ 1, 2, 3, 4 }, first)
    end

    H.describe("werewolf/match", function()

        H.it("refuse de demarrer sous le minimum", function()
            local match, raison = Match.new({ 1, 2, 3 }, first)
            H.assert_nil(match, "aucune partie")
            H.assert_true(raison ~= nil, "raison fournie")
        end)

        H.it("attribue un role a chaque joueur", function()
            local match = new4()
            for _, id in ipairs({ 1, 2, 3, 4 }) do
                H.assert_true(Match.role_of(match, id) ~= nil, "role du joueur " .. id)
            end
        end)

        H.it("distribue exactement la composition prevue", function()
            local match = new4()
            local wolves = Match.players_with_role(match, "wolf")
            local seers  = Match.players_with_role(match, "seer")
            H.assert_eq(#wolves, 1, "un loup")
            H.assert_eq(#seers, 1, "une voyante")
        end)

        H.it("annonce son role a chaque joueur, et a lui seul", function()
            local match, effects = new4()
            local seen = {}
            for _, e in ipairs(effects) do
                if e.kind == "assign_role" then
                    H.assert_nil(seen[e.player], "un seul envoi par joueur")
                    seen[e.player] = e.role
                    H.assert_eq(e.role, Match.role_of(match, e.player), "role coherent")
                end
            end
            H.assert_count(seen, 4, "quatre envois")
        end)

        H.it("commence avec tout le monde vivant", function()
            local match = new4()
            H.assert_eq(Match.alive_count(match), 4, "quatre vivants")
            H.assert_true(Match.is_alive(match, 1), "joueur 1 vivant")
        end)

        H.it("compte les vivants par camp", function()
            local match = new4()
            H.assert_eq(Match.alive_count(match, "wolves"), 1, "un loup vivant")
            H.assert_eq(Match.alive_count(match, "village"), 3, "trois villageois vivants")
        end)

        H.it("tue un joueur et rend l'effet correspondant", function()
            local match = new4()
            local effects = Match.kill(match, 2, "wolves")
            H.assert_false(Match.is_alive(match, 2), "joueur 2 mort")
            H.assert_eq(Match.alive_count(match), 3, "trois vivants")
            H.assert_eq(effects[1].kind, "kill", "effet de mort")
            H.assert_eq(effects[1].player, 2, "bon joueur")
            H.assert_eq(effects[1].cause, "wolves", "cause transmise")
        end)

        H.it("ignore une seconde mort du meme joueur", function()
            local match = new4()
            Match.kill(match, 2, "wolves")
            local effects = Match.kill(match, 2, "village")
            H.assert_eq(#effects, 0, "aucun effet")
            H.assert_eq(Match.alive_count(match), 3, "toujours trois vivants")
        end)

        H.it("rend la liste des vivants triee", function()
            local match = new4()
            Match.kill(match, 2, "wolves")
            local alive = Match.alive(match)
            H.assert_eq(#alive, 3, "trois vivants")
            H.assert_eq(alive[1], 1, "premier")
            H.assert_eq(alive[2], 3, "deuxieme")
            H.assert_eq(alive[3], 4, "troisieme")
        end)
    end)
end
```

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

Lancer : `powershell -File scripts/test.ps1`
Attendu : ÉCHEC, fichier `games/werewolf/match.lua` introuvable.

- [ ] **Étape 3 : écrire l'implémentation minimale**

Créer `Packages/fate-games/Server/games/werewolf/match.lua` :

```lua
-- Etat d'une partie : qui joue, quel role, qui vit encore.
--
-- Lua pur : ce module ne sait pas qu'il tourne dans un jeu. L'aleatoire est
-- injecte pour que les tests soient deterministes.

return function(Roles, Effects)
    local Match = {}

    -- Melange par Fisher-Yates, avec le tirage fourni.
    local function shuffle(list, rng)
        for i = #list, 2, -1 do
            local j = rng(i)
            list[i], list[j] = list[j], list[i]
        end
        return list
    end

    function Match.new(player_ids, rng)
        local composition, raison = Roles.compose(#player_ids)
        if not composition then return nil, raison end

        shuffle(composition, rng)

        local match = { players = {}, order = {}, day = 0 }
        local effects = {}

        for index, id in ipairs(player_ids) do
            local role = composition[index]
            match.players[id] = { role = role, alive = true }
            match.order[#match.order + 1] = id
            -- Chaque joueur apprend son role, et lui seul.
            effects[#effects + 1] = Effects.assign_role(id, role)
        end

        table.sort(match.order)
        return match, effects
    end

    function Match.role_of(match, player)
        local entry = match.players[player]
        return entry and entry.role
    end

    function Match.team_of(match, player)
        local role = Match.role_of(match, player)
        local definition = role and Roles.definitions[role]
        return definition and definition.team
    end

    function Match.is_alive(match, player)
        local entry = match.players[player]
        return entry ~= nil and entry.alive
    end

    function Match.alive(match)
        local list = {}
        for _, id in ipairs(match.order) do
            if Match.is_alive(match, id) then list[#list + 1] = id end
        end
        return list
    end

    function Match.alive_count(match, team)
        local n = 0
        for _, id in ipairs(match.order) do
            if Match.is_alive(match, id) then
                if team == nil or Match.team_of(match, id) == team then n = n + 1 end
            end
        end
        return n
    end

    function Match.players_with_role(match, role_id)
        local list = {}
        for _, id in ipairs(match.order) do
            if Match.role_of(match, id) == role_id then list[#list + 1] = id end
        end
        return list
    end

    -- Tuer un mort ne produit rien : le moteur peut appeler sans verifier.
    function Match.kill(match, player, cause)
        if not Match.is_alive(match, player) then return {} end
        match.players[player].alive = false
        return { Effects.kill(player, cause) }
    end

    return Match
end
```

- [ ] **Étape 4 : lancer les tests pour vérifier qu'ils passent**

Lancer : `powershell -File scripts/test.ps1`
Attendu : toutes les suites au vert.

- [ ] **Étape 5 : commit**

```bash
git add Packages/fate-games/Server/games/werewolf/match.lua tests/suites/werewolf_match.lua tests/run.lua
git commit -m "LOUP-GAROU - etat d une partie

Composition melangee par Fisher-Yates avec un tirage injecte, donc des
tests deterministes. Chaque joueur recoit son role et lui seul."
```

---

### Tâche 4 : le vote

Les deux règles d'égalité sont différentes et c'est délibéré : au village une égalité ne tue
personne, chez les loups elle est tranchée au hasard pour qu'une nuit ne soit jamais vide.

**Fichiers :**
- Créer : `Packages/fate-games/Server/games/werewolf/voting.lua`
- Créer : `tests/suites/werewolf_voting.lua`
- Modifier : `tests/run.lua` — ajouter `"werewolf_voting"`

**Interfaces :**
- Consomme : rien.
- Produit : la fabrique `make_voting()` rendant `Voting.new() -> ballot` ;
  `Voting.designate(ballot, voter, target)` — remplace la désignation précédente du même votant ;
  `Voting.clear(ballot, voter)` ; `Voting.tally(ballot) -> table cible -> nombre` ;
  `Voting.village_result(ballot) -> cible ou nil` — `nil` en cas d'égalité ou d'absence de vote ;
  `Voting.wolves_result(ballot, rng) -> cible ou nil` — tirage au sort entre ex æquo.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/suites/werewolf_voting.lua` :

```lua
return function(H, Stubs)
    local make_voting = Package.Require("games/werewolf/voting.lua")
    local Voting = make_voting()

    local function first() return 1 end

    H.describe("werewolf/voting", function()

        H.it("enregistre une designation", function()
            local b = Voting.new()
            Voting.designate(b, 1, 2)
            H.assert_eq(Voting.tally(b)[2], 1, "une voix pour 2")
        end)

        H.it("remplace la designation precedente du meme votant", function()
            local b = Voting.new()
            Voting.designate(b, 1, 2)
            Voting.designate(b, 1, 3)
            local counts = Voting.tally(b)
            H.assert_nil(counts[2], "plus de voix pour 2")
            H.assert_eq(counts[3], 1, "une voix pour 3")
        end)

        H.it("permet de retirer sa designation", function()
            local b = Voting.new()
            Voting.designate(b, 1, 2)
            Voting.clear(b, 1)
            H.assert_count(Voting.tally(b), 0, "aucune voix")
        end)

        H.it("elit la majorite au village", function()
            local b = Voting.new()
            Voting.designate(b, 1, 4)
            Voting.designate(b, 2, 4)
            Voting.designate(b, 3, 5)
            H.assert_eq(Voting.village_result(b), 4, "cible elue")
        end)

        H.it("ne tue personne en cas d'egalite au village", function()
            local b = Voting.new()
            Voting.designate(b, 1, 4)
            Voting.designate(b, 2, 5)
            H.assert_nil(Voting.village_result(b), "aucune elimination")
        end)

        H.it("ne tue personne si personne n'a vote", function()
            H.assert_nil(Voting.village_result(Voting.new()), "aucune elimination")
        end)

        H.it("tranche l'egalite au hasard chez les loups", function()
            local b = Voting.new()
            Voting.designate(b, 1, 4)
            Voting.designate(b, 2, 5)
            local cible = Voting.wolves_result(b, first)
            H.assert_true(cible == 4 or cible == 5, "une des deux cibles")
        end)

        H.it("suit la majorite chez les loups quand il y en a une", function()
            local b = Voting.new()
            Voting.designate(b, 1, 4)
            Voting.designate(b, 2, 4)
            Voting.designate(b, 3, 5)
            H.assert_eq(Voting.wolves_result(b, first), 4, "majorite respectee")
        end)

        H.it("rend nil chez les loups si aucun n'a vote", function()
            H.assert_nil(Voting.wolves_result(Voting.new(), first), "aucune victime")
        end)
    end)
end
```

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

Lancer : `powershell -File scripts/test.ps1`
Attendu : ÉCHEC, fichier `games/werewolf/voting.lua` introuvable.

- [ ] **Étape 3 : écrire l'implémentation minimale**

Créer `Packages/fate-games/Server/games/werewolf/voting.lua` :

```lua
-- Enregistrement des designations et depouillement.
--
-- Ce module ne sait pas ce qu'est une nuit ni un loup. Il compte des voix.

return function()
    local Voting = {}

    function Voting.new()
        return { by_voter = {} }
    end

    function Voting.designate(ballot, voter, target)
        ballot.by_voter[voter] = target
    end

    function Voting.clear(ballot, voter)
        ballot.by_voter[voter] = nil
    end

    function Voting.tally(ballot)
        local counts = {}
        for _, target in pairs(ballot.by_voter) do
            counts[target] = (counts[target] or 0) + 1
        end
        return counts
    end

    -- Rend la liste des cibles a egalite au sommet, triee.
    local function leaders(ballot)
        local counts = Voting.tally(ballot)
        local best, list = 0, {}

        for target, n in pairs(counts) do
            if n > best then best, list = n, { target }
            elseif n == best then list[#list + 1] = target end
        end

        table.sort(list)
        return list, best
    end

    -- Au village, une egalite ne tue personne : le village n'a pas tranche.
    function Voting.village_result(ballot)
        local list = leaders(ballot)
        if #list ~= 1 then return nil end
        return list[1]
    end

    -- Chez les loups, une nuit sans victime bloquerait la partie : on tranche.
    function Voting.wolves_result(ballot, rng)
        local list = leaders(ballot)
        if #list == 0 then return nil end
        if #list == 1 then return list[1] end
        return list[rng(#list)]
    end

    return Voting
end
```

- [ ] **Étape 4 : lancer les tests pour vérifier qu'ils passent**

Lancer : `powershell -File scripts/test.ps1`
Attendu : toutes les suites au vert.

- [ ] **Étape 5 : commit**

```bash
git add Packages/fate-games/Server/games/werewolf/voting.lua tests/suites/werewolf_voting.lua tests/run.lua
git commit -m "LOUP-GAROU - vote et depouillement

Deux regles d egalite differentes et delibrees : au village une egalite ne
tue personne, chez les loups elle est tranchee au hasard pour qu une nuit
ne soit jamais vide."
```

---

### Tâche 5 : les conditions de victoire

**Fichiers :**
- Créer : `Packages/fate-games/Server/games/werewolf/outcome.lua`
- Créer : `tests/suites/werewolf_outcome.lua`
- Modifier : `tests/run.lua` — ajouter `"werewolf_outcome"`

**Interfaces :**
- Consomme : `Match` (tâche 3), `Roles` (tâche 2, pour `MIN_PLAYERS`).
- Produit : la fabrique `make_outcome(Match, Roles)` rendant
  `Outcome.check(match) -> nil | "village" | "wolves" | "aborted"`.
  `nil` signifie que la partie continue. `"aborted"` quand il reste moins de
  `Roles.MIN_PLAYERS` vivants.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/suites/werewolf_outcome.lua` :

```lua
return function(H, Stubs)
    local make_outcome = Package.Require("games/werewolf/outcome.lua")
    local make_match   = Package.Require("games/werewolf/match.lua")
    local Roles        = Package.Require("games/werewolf/data/roles.lua")
    local Effects      = Package.Require("games/werewolf/effects.lua")

    local Match   = make_match(Roles, Effects)
    local Outcome = make_outcome(Match, Roles)

    -- Construit une partie factice avec des roles imposes, pour maitriser les cas.
    local function fake(roles_by_player)
        local match = { players = {}, order = {}, day = 0 }
        for id, role in pairs(roles_by_player) do
            match.players[id] = { role = role, alive = true }
            match.order[#match.order + 1] = id
        end
        table.sort(match.order)
        return match
    end

    H.describe("werewolf/outcome", function()

        H.it("laisse la partie continuer quand les deux camps tiennent", function()
            local m = fake({ [1]="wolf", [2]="villager", [3]="villager", [4]="seer" })
            H.assert_nil(Outcome.check(m), "partie en cours")
        end)

        H.it("donne la victoire au village quand il ne reste aucun loup", function()
            local m = fake({ [1]="wolf", [2]="villager", [3]="villager", [4]="seer" })
            Match.kill(m, 1, "village")
            H.assert_eq(Outcome.check(m), "village", "village vainqueur")
        end)

        H.it("donne la victoire aux loups a egalite numerique", function()
            local m = fake({ [1]="wolf", [2]="wolf", [3]="villager", [4]="villager" })
            Match.kill(m, 3, "wolves")
            Match.kill(m, 4, "wolves")
            H.assert_eq(Outcome.check(m), "wolves", "loups vainqueurs")
        end)

        H.it("ne donne pas la victoire aux loups tant qu'ils sont minoritaires", function()
            local m = fake({ [1]="wolf", [2]="villager", [3]="villager", [4]="seer" })
            Match.kill(m, 2, "wolves")
            H.assert_nil(Outcome.check(m), "partie en cours")
        end)

        H.it("abandonne la partie quand il reste trop peu de monde", function()
            local m = fake({ [1]="wolf", [2]="villager", [3]="villager", [4]="seer",
                             [5]="villager", [6]="villager" })
            Match.kill(m, 3, "left")
            Match.kill(m, 4, "left")
            Match.kill(m, 5, "left")
            H.assert_eq(Outcome.check(m), "aborted", "partie abandonnee")
        end)
    end)
end
```

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

Lancer : `powershell -File scripts/test.ps1`
Attendu : ÉCHEC, fichier `games/werewolf/outcome.lua` introuvable.

- [ ] **Étape 3 : écrire l'implémentation minimale**

Créer `Packages/fate-games/Server/games/werewolf/outcome.lua` :

```lua
-- Conditions de victoire. Verifiees apres chaque resolution de mort, jamais
-- ailleurs.

return function(Match, Roles)
    local Outcome = {}

    -- Rend nil si la partie continue, sinon "village", "wolves" ou "aborted".
    function Outcome.check(match)
        local wolves  = Match.alive_count(match, "wolves")
        local village = Match.alive_count(match, "village")

        if wolves == 0 then return "village" end

        -- A egalite numerique, les loups ne peuvent plus perdre un vote : la
        -- partie est decidee, la prolonger ne serait que du temps perdu.
        if wolves >= village then return "wolves" end

        if wolves + village < Roles.MIN_PLAYERS then return "aborted" end

        return nil
    end

    return Outcome
end
```

- [ ] **Étape 4 : lancer les tests pour vérifier qu'ils passent**

Lancer : `powershell -File scripts/test.ps1`
Attendu : toutes les suites au vert.

- [ ] **Étape 5 : commit**

```bash
git add Packages/fate-games/Server/games/werewolf/outcome.lua tests/suites/werewolf_outcome.lua tests/run.lua
git commit -m "LOUP-GAROU - conditions de victoire

Les loups gagnent des l egalite numerique : a ce moment ils ne peuvent plus
perdre un vote. Une partie tombee sous le minimum de joueurs s arrete sans
vainqueur."
```

---

### Tâche 6 : les phases et la machine

C'est la tâche la plus grosse. La pile de phases est ce qui rendra le chasseur possible plus tard.

**Fichiers :**
- Créer : `Packages/fate-games/Server/games/werewolf/data/phases.lua`
- Créer : `Packages/fate-games/Server/games/werewolf/engine.lua`
- Créer : `tests/suites/werewolf_engine.lua`
- Modifier : `tests/run.lua` — ajouter `"werewolf_engine"`

**Interfaces :**
- Consomme : `Roles`, `Match`, `Voting`, `Outcome`, `Effects`.
- Produit : `Phases.DEFAULT_DURATIONS` (table id de phase -> secondes) ;
  la fabrique `make_engine(Roles, Phases, Match, Voting, Outcome, Effects)` rendant
  `Engine.new() -> state` (état en attente) ;
  `Engine.ring_bell(state, player_ids, rng) -> effets, raison` ;
  `Engine.designate(state, actor, target) -> effets` ;
  `Engine.advance(state, dt) -> effets` ;
  `Engine.player_left(state, player) -> effets` ;
  `Engine.current_phase(state) -> id de phase ou nil`.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/suites/werewolf_engine.lua` :

```lua
return function(H, Stubs)
    local make_engine  = Package.Require("games/werewolf/engine.lua")
    local Phases       = Package.Require("games/werewolf/data/phases.lua")
    local make_match   = Package.Require("games/werewolf/match.lua")
    local make_voting  = Package.Require("games/werewolf/voting.lua")
    local make_outcome = Package.Require("games/werewolf/outcome.lua")
    local Roles        = Package.Require("games/werewolf/data/roles.lua")
    local Effects      = Package.Require("games/werewolf/effects.lua")

    local Match   = make_match(Roles, Effects)
    local Voting  = make_voting()
    local Outcome = make_outcome(Match, Roles)
    local Engine  = make_engine(Roles, Phases, Match, Voting, Outcome, Effects)

    local function first() return 1 end

    local function started()
        local state = Engine.new()
        Engine.ring_bell(state, { 1, 2, 3, 4 }, first)
        return state
    end

    local function kinds(effects)
        local set = {}
        for _, e in ipairs(effects) do set[e.kind] = true end
        return set
    end

    H.describe("werewolf/engine", function()

        H.it("refuse de demarrer sous le minimum", function()
            local state = Engine.new()
            local effects, raison = Engine.ring_bell(state, { 1, 2, 3 }, first)
            H.assert_nil(effects, "aucun effet")
            H.assert_true(raison ~= nil, "raison fournie")
            H.assert_nil(Engine.current_phase(state), "toujours en attente")
        end)

        H.it("demarre sur la nuit des loups", function()
            local state = started()
            H.assert_eq(Engine.current_phase(state), "night_wolves", "premiere phase")
        end)

        H.it("annonce les roles au demarrage", function()
            local state = Engine.new()
            local effects = Engine.ring_bell(state, { 1, 2, 3, 4 }, first)
            H.assert_true(kinds(effects).assign_role, "roles attribues")
            H.assert_true(kinds(effects).world_light, "lumiere de nuit")
        end)

        H.it("enchaine les phases quand le temps passe", function()
            local state = started()
            Engine.advance(state, Phases.DEFAULT_DURATIONS.night_wolves)
            H.assert_eq(Engine.current_phase(state), "night_seer", "voyante ensuite")
        end)

        H.it("ne fait rien tant que la duree n'est pas ecoulee", function()
            local state = started()
            Engine.advance(state, 1)
            H.assert_eq(Engine.current_phase(state), "night_wolves", "toujours les loups")
        end)

        H.it("fait tendre le bras d'un loup pour les loups seulement", function()
            local state = started()
            local wolf = Match.players_with_role(state.match, "wolf")[1]
            local target = Match.players_with_role(state.match, "villager")[1]

            local effects = Engine.designate(state, wolf, target)

            local pointed = nil
            for _, e in ipairs(effects) do
                if e.kind == "point_at" then pointed = e end
            end
            H.assert_true(pointed ~= nil, "bras tendu")
            H.assert_eq(pointed.audience, "wolves", "vu des loups seulement")
        end)

        H.it("refuse une designation venue d'un joueur sans role dans la phase", function()
            local state = started()
            local villager = Match.players_with_role(state.match, "villager")[1]
            local effects = Engine.designate(state, villager, 1)
            H.assert_eq(#effects, 0, "aucun effet")
        end)

        H.it("revele la couleur d'une cible a la voyante seule", function()
            local state = started()
            Engine.advance(state, Phases.DEFAULT_DURATIONS.night_wolves)

            local seer = Match.players_with_role(state.match, "seer")[1]
            local wolf = Match.players_with_role(state.match, "wolf")[1]
            local effects = Engine.designate(state, seer, wolf)

            local revealed = nil
            for _, e in ipairs(effects) do
                if e.kind == "reveal" then revealed = e end
            end
            H.assert_true(revealed ~= nil, "revelation emise")
            H.assert_eq(revealed.viewer, seer, "vue par la voyante")
            H.assert_eq(revealed.target, wolf, "sur la bonne cible")
            H.assert_eq(revealed.tint, "wolf", "teinte de loup")
        end)

        H.it("tue la victime des loups a l'aube", function()
            local state = started()
            local wolf   = Match.players_with_role(state.match, "wolf")[1]
            local target = Match.players_with_role(state.match, "villager")[1]
            Engine.designate(state, wolf, target)

            Engine.advance(state, Phases.DEFAULT_DURATIONS.night_wolves)
            Engine.advance(state, Phases.DEFAULT_DURATIONS.night_seer)

            H.assert_false(Match.is_alive(state.match, target), "victime morte")
        end)

        H.it("traite un depart comme une mort", function()
            local state = started()
            Engine.player_left(state, 2)
            H.assert_false(Match.is_alive(state.match, 2), "joueur 2 mort")
        end)

        H.it("joue une partie entiere jusqu'a une victoire", function()
            local state = Engine.new()
            Engine.ring_bell(state, { 1, 2, 3, 4, 5, 6 }, first)

            -- Le premier vivant du camp adverse, ou nil s'il n'y en a plus.
            local function first_enemy_of(team)
                for _, id in ipairs(Match.alive(state.match)) do
                    if Match.team_of(state.match, id) ~= team then return id end
                end
                return nil
            end

            -- Sans acteurs, personne ne meurt et la partie tournerait sans fin :
            -- on fait donc agir tout le monde a chaque phase qui le permet.
            local function act()
                local phase = Engine.current_phase(state)
                if phase == "night_wolves" then
                    local victim = first_enemy_of("wolves")
                    if victim then
                        for _, id in ipairs(Match.alive(state.match)) do
                            if Match.team_of(state.match, id) == "wolves" then
                                Engine.designate(state, id, victim)
                            end
                        end
                    end
                elseif phase == "vote" then
                    local condemned = first_enemy_of("village")
                    if condemned then
                        for _, id in ipairs(Match.alive(state.match)) do
                            Engine.designate(state, id, condemned)
                        end
                    end
                end
            end

            local ended = nil
            for _ = 1, 500 do
                act()
                local effects = Engine.advance(state, 10)
                for _, e in ipairs(effects) do
                    if e.kind == "match_ended" then ended = e end
                end
                if ended then break end
            end

            H.assert_true(ended ~= nil, "la partie se termine")
            H.assert_true(ended.winner == "village" or ended.winner == "wolves"
                or ended.winner == "aborted", "vainqueur connu : " .. tostring(ended.winner))
        end)
    end)
end
```

- [ ] **Étape 2 : lancer le test pour vérifier qu'il échoue**

Lancer : `powershell -File scripts/test.ps1`
Attendu : ÉCHEC, fichier `games/werewolf/data/phases.lua` introuvable.

- [ ] **Étape 3 : écrire les données de phases**

Créer `Packages/fate-games/Server/games/werewolf/data/phases.lua` :

```lua
-- Phases de base et durees par defaut, en secondes.
--
-- Les phases de nuit propres a un role sont declarees dans le registre des roles,
-- pas ici : ajouter un role ne doit pas obliger a toucher ce fichier.

local Phases = {}

Phases.DEFAULT_DURATIONS = {
    night_wolves = 45,
    night_seer   = 20,
    dawn         = 10,
    debate       = 180,
    vote         = 45,
    execution    = 10,
}

-- Les phases de jour, dans l'ordre, apres la resolution de l'aube.
Phases.DAY_SEQUENCE = { "debate", "vote", "execution" }

return Phases
```

- [ ] **Étape 4 : écrire la machine**

Créer `Packages/fate-games/Server/games/werewolf/engine.lua` :

```lua
-- La machine. Fait avancer le temps, applique les regles, produit des effets.
--
-- Lua pur : aucune globale du moteur. On lui donne un etat et une duree ecoulee,
-- il rend des effets.
--
-- Les phases vivent dans une PILE et non dans une sequence plate. C'est ce qui
-- rendra le chasseur possible plus tard : sa mort empilera une phase de tir depuis
-- n'importe quelle resolution, puis la partie reprendra ou elle en etait.

return function(Roles, Phases, Match, Voting, Outcome, Effects)
    local Engine = {}

    ----------------------------------------------------------------------------
    -- Pile de phases
    ----------------------------------------------------------------------------

    local function push(state, id)
        state.stack[#state.stack + 1] = {
            id        = id,
            remaining = Phases.DEFAULT_DURATIONS[id],
            ballot    = Voting.new(),
        }
    end

    local function top(state)
        return state.stack[#state.stack]
    end

    local function pop(state)
        state.stack[#state.stack] = nil
    end

    function Engine.current_phase(state)
        local phase = top(state)
        return phase and phase.id
    end

    ----------------------------------------------------------------------------
    -- Sequence
    ----------------------------------------------------------------------------

    -- Les phases de nuit viennent du registre des roles, rangees par `order`.
    local function night_sequence()
        local list = {}
        for _, definition in pairs(Roles.definitions) do
            if definition.night_phase then list[#list + 1] = definition.night_phase end
        end
        table.sort(list, function(a, b) return a.order < b.order end)

        local ids = {}
        for _, night in ipairs(list) do ids[#ids + 1] = night.id end
        return ids
    end

    local SEQUENCE = nil

    local function full_sequence()
        if SEQUENCE then return SEQUENCE end
        SEQUENCE = {}
        for _, id in ipairs(night_sequence()) do SEQUENCE[#SEQUENCE + 1] = id end
        SEQUENCE[#SEQUENCE + 1] = "dawn"
        for _, id in ipairs(Phases.DAY_SEQUENCE) do SEQUENCE[#SEQUENCE + 1] = id end
        return SEQUENCE
    end

    local function next_phase_id(current)
        local sequence = full_sequence()
        for index, id in ipairs(sequence) do
            if id == current then return sequence[index + 1] or sequence[1] end
        end
        return sequence[1]
    end

    ----------------------------------------------------------------------------
    -- Etat
    ----------------------------------------------------------------------------

    function Engine.new()
        return { match = nil, stack = {}, finished = false, rng = nil }
    end

    local function append(into, from)
        for _, e in ipairs(from or {}) do into[#into + 1] = e end
        return into
    end

    local function enter(state, id)
        push(state, id)
        local effects = {}

        if id == "night_wolves" then
            append(effects, { Effects.world_light("night") })
            for _, player in ipairs(Match.alive(state.match)) do
                local channel = Match.team_of(state.match, player) == "wolves"
                    and "wolves" or "village"
                append(effects, { Effects.voice_channel(player, channel) })
                append(effects, { Effects.mute(player, channel ~= "wolves") })
            end
        elseif id == "dawn" then
            append(effects, { Effects.world_light("day") })
        elseif id == "debate" then
            for _, player in ipairs(Match.alive(state.match)) do
                append(effects, { Effects.voice_channel(player, "village") })
                append(effects, { Effects.mute(player, false) })
            end
        end

        append(effects, { Effects.announce("phase_started", { phase = id }) })
        return effects
    end

    ----------------------------------------------------------------------------
    -- Demarrage
    ----------------------------------------------------------------------------

    function Engine.ring_bell(state, player_ids, rng)
        if state.match then return nil, "partie_en_cours" end

        local match, effects = Match.new(player_ids, rng)
        if not match then return nil, effects end

        state.match = match
        state.rng   = rng

        append(effects, enter(state, "night_wolves"))
        return effects
    end

    ----------------------------------------------------------------------------
    -- Fin de partie
    ----------------------------------------------------------------------------

    local function finish(state, winner)
        state.finished = true
        state.stack = {}

        local summary = {}
        for _, id in ipairs(state.match.order) do
            summary[#summary + 1] = {
                player = id,
                role   = Match.role_of(state.match, id),
                alive  = Match.is_alive(state.match, id),
            }
        end

        return { Effects.match_ended(winner, summary) }
    end

    -- Verifie la victoire apres chaque resolution de mort, jamais ailleurs.
    local function check_end(state, effects)
        local winner = Outcome.check(state.match)
        if winner then append(effects, finish(state, winner)) end
        return winner ~= nil
    end

    ----------------------------------------------------------------------------
    -- Resolution d'une phase
    ----------------------------------------------------------------------------

    local function resolve(state, phase)
        local effects = {}

        if phase.id == "night_wolves" then
            state.pending_victim = Voting.wolves_result(phase.ballot, state.rng)

        elseif phase.id == "dawn" then
            local victim = state.pending_victim
            state.pending_victim = nil
            if victim then
                append(effects, Match.kill(state.match, victim, "wolves"))
                append(effects, { Effects.announce("killed_by_wolves", { player = victim }) })
            else
                append(effects, { Effects.announce("nobody_died", {}) })
            end

        elseif phase.id == "execution" then
            local condemned = state.pending_condemned
            state.pending_condemned = nil
            if condemned then
                append(effects, Match.kill(state.match, condemned, "village"))
                append(effects, { Effects.announce("executed", { player = condemned }) })
            else
                append(effects, { Effects.announce("no_execution", {}) })
            end

        elseif phase.id == "vote" then
            state.pending_condemned = Voting.village_result(phase.ballot)
        end

        return effects
    end

    ----------------------------------------------------------------------------
    -- Avancement du temps
    ----------------------------------------------------------------------------

    function Engine.advance(state, dt)
        local effects = {}
        if state.finished or not state.match then return effects end

        local phase = top(state)
        if not phase then return effects end

        if phase.remaining == nil then return effects end

        phase.remaining = phase.remaining - dt
        if phase.remaining > 0 then return effects end

        local id = phase.id
        append(effects, resolve(state, phase))
        pop(state)

        -- Une mort a pu survenir : la victoire se verifie ici.
        if check_end(state, effects) then return effects end

        -- Si la resolution a empile une interruption, on la laisse jouer.
        if top(state) then return effects end

        append(effects, enter(state, next_phase_id(id)))
        return effects
    end

    ----------------------------------------------------------------------------
    -- Actes des joueurs
    ----------------------------------------------------------------------------

    -- Qui a le droit d'agir dans la phase courante, et pour quelle audience.
    local function actor_scope(state, phase_id, actor)
        if not Match.is_alive(state.match, actor) then return nil end

        if phase_id == "night_wolves" then
            if Match.team_of(state.match, actor) == "wolves" then return "wolves" end
            return nil
        end

        if phase_id == "night_seer" then
            if Match.role_of(state.match, actor) == "seer" then return { player = actor } end
            return nil
        end

        if phase_id == "vote" then return "all" end

        return nil
    end

    function Engine.designate(state, actor, target)
        local effects = {}
        if state.finished or not state.match then return effects end

        local phase = top(state)
        if not phase then return effects end

        local audience = actor_scope(state, phase.id, actor)
        if not audience then return effects end
        if not Match.is_alive(state.match, target) then return effects end

        if phase.id == "night_seer" then
            -- La voyante voit une couleur, et elle seule.
            local tint = Match.team_of(state.match, target) == "wolves" and "wolf" or "villager"
            append(effects, { Effects.reveal(actor, target, tint) })
            return effects
        end

        Voting.designate(phase.ballot, actor, target)
        append(effects, { Effects.point_at(actor, target, audience) })
        return effects
    end

    function Engine.player_left(state, player)
        local effects = {}
        if state.finished or not state.match then return effects end
        if not Match.is_alive(state.match, player) then return effects end

        append(effects, Match.kill(state.match, player, "left"))
        check_end(state, effects)
        return effects
    end

    return Engine
end
```

- [ ] **Étape 5 : lancer les tests pour vérifier qu'ils passent**

Lancer : `powershell -File scripts/test.ps1`
Attendu : toutes les suites au vert.

- [ ] **Étape 6 : commit**

```bash
git add Packages/fate-games/Server/games/werewolf/data/phases.lua Packages/fate-games/Server/games/werewolf/engine.lua tests/suites/werewolf_engine.lua tests/run.lua
git commit -m "LOUP-GAROU - phases et machine a etats

Pile de phases plutot que sequence plate : une resolution peut empiler une
interruption, ce qui rendra le chasseur possible sans reecriture. Les
phases de nuit viennent du registre des roles, rangees par ordre."
```

---

### Tâche 7 : le test de confidentialité

Ce n'est pas un test de logique mais de sécurité, et c'est la seule faille qui ruinerait le jeu.

**Fichiers :**
- Créer : `tests/suites/werewolf_secrecy.lua`
- Modifier : `tests/run.lua` — ajouter `"werewolf_secrecy"`

**Interfaces :**
- Consomme : `Engine`, `Match`, tout ce qui précède.
- Produit : rien. C'est un filet.

- [ ] **Étape 1 : écrire le test**

Créer `tests/suites/werewolf_secrecy.lua` :

```lua
return function(H, Stubs)
    local make_engine  = Package.Require("games/werewolf/engine.lua")
    local Phases       = Package.Require("games/werewolf/data/phases.lua")
    local make_match   = Package.Require("games/werewolf/match.lua")
    local make_voting  = Package.Require("games/werewolf/voting.lua")
    local make_outcome = Package.Require("games/werewolf/outcome.lua")
    local Roles        = Package.Require("games/werewolf/data/roles.lua")
    local Effects      = Package.Require("games/werewolf/effects.lua")

    local Match   = make_match(Roles, Effects)
    local Voting  = make_voting()
    local Outcome = make_outcome(Match, Roles)
    local Engine  = make_engine(Roles, Phases, Match, Voting, Outcome, Effects)

    local function first() return 1 end

    H.describe("werewolf/confidentialite", function()

        H.it("n'annonce jamais un role a quelqu'un d'autre qu'a son porteur", function()
            local state = Engine.new()
            local effects = Engine.ring_bell(state, { 1, 2, 3, 4, 5, 6 }, first)

            for _, e in ipairs(effects) do
                if e.kind == "assign_role" then
                    H.assert_eq(e.role, Match.role_of(state.match, e.player),
                        "le role annonce est celui du destinataire")
                end
            end
        end)

        H.it("ne montre jamais le bras d'un loup au village pendant la nuit", function()
            local state = Engine.new()
            Engine.ring_bell(state, { 1, 2, 3, 4, 5, 6 }, first)

            local wolf   = Match.players_with_role(state.match, "wolf")[1]
            local target = Match.players_with_role(state.match, "villager")[1]
            local effects = Engine.designate(state, wolf, target)

            for _, e in ipairs(effects) do
                if e.kind == "point_at" then
                    H.assert_eq(e.audience, "wolves", "audience restreinte aux loups")
                end
            end
        end)

        H.it("ne revele une vision qu'a la voyante", function()
            local state = Engine.new()
            Engine.ring_bell(state, { 1, 2, 3, 4, 5, 6 }, first)
            Engine.advance(state, Phases.DEFAULT_DURATIONS.night_wolves)

            local seer   = Match.players_with_role(state.match, "seer")[1]
            local target = Match.players_with_role(state.match, "wolf")[1]
            local effects = Engine.designate(state, seer, target)

            for _, e in ipairs(effects) do
                if e.kind == "reveal" then
                    H.assert_eq(e.viewer, seer, "vue par la voyante seule")
                end
            end
        end)

        H.it("ne laisse fuiter aucun role dans une annonce", function()
            local state = Engine.new()
            local effects = Engine.ring_bell(state, { 1, 2, 3, 4, 5, 6 }, first)

            for _, e in ipairs(effects) do
                if e.kind == "announce" then
                    for key, value in pairs(e.args or {}) do
                        H.assert_true(value ~= "wolf" and value ~= "seer",
                            "aucun role dans l'annonce (" .. tostring(key) .. ")")
                    end
                end
            end
        end)
    end)
end
```

- [ ] **Étape 2 : lancer les tests**

Lancer : `powershell -File scripts/test.ps1`
Attendu : toutes les suites au vert. Si un test échoue, c'est une vraie fuite — corriger le moteur,
pas le test.

- [ ] **Étape 3 : commit**

```bash
git add tests/suites/werewolf_secrecy.lua tests/run.lua
git commit -m "LOUP-GAROU - filet de confidentialite

Verifie qu aucun effet ne transmet le role d un joueur a quelqu un qui n y
a pas droit. C est la seule faille qui ruinerait le jeu, elle doit echouer
au banc plutot qu en partie."
```

---

### Tâche 8 : l'adaptateur et le branchement

L'adaptateur ne décide rien. Il traduit. Il n'est pas testable sans client, donc on le garde mince.

**Fichiers :**
- Créer : `Packages/fate-games/Server/games/werewolf/adapter.lua`
- Modifier : `Packages/fate-games/Server/Index.lua`
- Modifier : `Packages/fate-games/Server/core/config.lua` — ajouter la section `werewolf`

**Interfaces :**
- Consomme : `Engine`, `Log`, `Scheduler`, `Intents`, `Interactables`, `Characters`.
- Produit : la fabrique `make_adapter(Log, Scheduler, Intents, Interactables, Characters, Engine, config)`
  rendant `Adapter.Start()`.

- [ ] **Étape 1 : écrire l'adaptateur**

Créer `Packages/fate-games/Server/games/werewolf/adapter.lua` :

```lua
-- Seul fichier de la partie loup-garou qui connait nanos world.
--
-- Il ne decide rien : il recoit des intentions deja validees par le pipeline, les
-- passe au moteur, et execute les effets que le moteur rend. Toute decision reste
-- dans le moteur, qui lui est testable.

return function(Log, Scheduler, Intents, Interactables, Characters, Engine, config)
    local Adapter = {}

    local state = Engine.new()

    local function rng(n)
        return math.random(n)
    end

    ----------------------------------------------------------------------------
    -- Effets -> moteur de jeu
    ----------------------------------------------------------------------------

    local function apply(effects)
        for _, e in ipairs(effects or {}) do
            if e.kind == "assign_role" then
                -- Au seul destinataire. Jamais une diffusion.
                local session = Characters.SessionByPlayer(e.player)
                if session and session.player then
                    Events.CallRemote("zix:role", session.player, Reliability.Reliable, e.role)
                end

            elseif e.kind == "mute" then
                local session = Characters.SessionByPlayer(e.player)
                if session and session.player then session.player:SetVOIPMuted(e.muted) end

            elseif e.kind == "kill" then
                local session = Characters.SessionByPlayer(e.player)
                if session and session.player then session.player:UnPossess() end

            elseif e.kind == "match_ended" then
                Log.Info("werewolf", "partie terminee : " .. tostring(e.winner))
            end

            -- Les autres effets attendent la carte et les animations.
            Log.Debug("werewolf", "effet " .. tostring(e.kind))
        end
    end

    ----------------------------------------------------------------------------
    -- Intentions -> moteur de jeu
    ----------------------------------------------------------------------------

    function Adapter.Start()
        Intents.Register("designate", {
            validate = function(player, payload)
                if type(payload) ~= "table" or not tonumber(payload.target) then
                    return false, "cible_invalide"
                end
                return true
            end,
            apply = function(player, payload)
                apply(Engine.designate(state, player:GetID(), tonumber(payload.target)))
                return true, { target = tostring(payload.target), audit = "designate" }
            end,
        })

        -- L'horloge du jeu : une seconde de jeu par tour de roue.
        Scheduler.Add("werewolf:clock", function()
            apply(Engine.advance(state, 1))
        end)

        Log.Info("werewolf", "adaptateur pret")
    end

    -- Appele par la cloche du village.
    function Adapter.RingBell()
        local players = Characters.OnlinePlayerIds()
        local effects, raison = Engine.ring_bell(state, players, rng)
        if not effects then
            Log.Info("werewolf", "cloche refusee : " .. tostring(raison))
            return false, raison
        end

        apply(effects)
        return true
    end

    return Adapter
end
```

- [ ] **Étape 2 : ajouter `OnlinePlayerIds` au module des personnages**

Dans `Packages/fate-games/Server/domain/characters.lua`, à côté de `CountOnline`, ajouter :

```lua
    function Characters.OnlinePlayerIds()
        local list = {}
        for player_id in pairs(sessions) do list[#list + 1] = player_id end
        table.sort(list)
        return list
    end
```

- [ ] **Étape 3 : brancher dans Index.lua**

Dans `Packages/fate-games/Server/Index.lua`, après la ligne qui crée `Interactables`, ajouter :

```lua
local Roles   = Package.Require("games/werewolf/data/roles.lua")
local Phases  = Package.Require("games/werewolf/data/phases.lua")
local Effects = Package.Require("games/werewolf/effects.lua")
local Match   = Package.Require("games/werewolf/match.lua")(Roles, Effects)
local Voting  = Package.Require("games/werewolf/voting.lua")()
local Outcome = Package.Require("games/werewolf/outcome.lua")(Match, Roles)
local Engine  = Package.Require("games/werewolf/engine.lua")(Roles, Phases, Match, Voting, Outcome, Effects)

local Werewolf = Package.Require("games/werewolf/adapter.lua")(
    Log, Scheduler, Intents, Interactables, Characters, Engine, ServerConfig)
Werewolf.Start()
```

Puis remplacer l'objet de démonstration — le bloc `do ... end` qui crée la table en bois — par la
cloche :

```lua
do
    local bell = Prop(
        Vector(ServerConfig.spawn.x, ServerConfig.spawn.y, ServerConfig.spawn.z),
        Rotator(0, 0, 0),
        "nanos-world::SM_WoodenTable"
    )

    Interactables.Register(bell, {
        label = "Sonner la cloche",
        on_interact = function()
            Werewolf.RingBell()
        end,
    })
end
```

- [ ] **Étape 4 : vérifier que le serveur démarre**

Lancer : `powershell -File scripts/dev.ps1 restart`
Attendu : `Server started!`, et dans les logs `[INFO][werewolf] adaptateur pret` ainsi que
`[DEBUG][interactables] enregistre 1 (Sonner la cloche)`.

- [ ] **Étape 5 : lancer les tests une dernière fois**

Lancer : `powershell -File scripts/test.ps1`
Attendu : toutes les suites au vert.

- [ ] **Étape 6 : commit**

```bash
git add Packages/fate-games/Server/games/werewolf/adapter.lua Packages/fate-games/Server/Index.lua Packages/fate-games/Server/domain/characters.lua
git commit -m "LOUP-GAROU - adaptateur et branchement

L adaptateur ne decide rien : il passe les intentions au moteur et execute
les effets rendus. La cloche du village remplace l objet de demonstration.

Beaucoup d effets n ont pas encore de traduction : ils attendent la carte,
les animations et les canaux vocaux. Ils sont journalises en attendant."
```

---

### Tâche 9 : l'écriture du résultat en base

La spec l'exige : l'état d'une partie en cours est volatil, mais son **résultat** est une donnée
transactionnelle, écrite immédiatement.

**Fichiers :**
- Modifier : `Packages/fate-games/Server/db/migrations.lua` — ajouter la migration 3
- Modifier : `Packages/fate-games/Server/Index.lua` — amorcer le compteur `matches`
- Modifier : `Packages/fate-games/Server/games/werewolf/adapter.lua` — écrire sur `match_ended`

**Interfaces :**
- Consomme : `DB`, `Ids`, l'effet `match_ended` produit par le moteur.
- Produit : deux tables, `matches` et `match_players`.

- [ ] **Étape 1 : ajouter la migration**

Dans `Packages/fate-games/Server/db/migrations.lua`, ajouter après la migration 2 :

```lua
    {
        id   = 3,
        name = "historique_des_parties",
        statements = {
            [[CREATE TABLE IF NOT EXISTS matches (
                id         INTEGER PRIMARY KEY,
                game       TEXT NOT NULL,
                winner     TEXT NOT NULL,
                ended_at   TEXT NOT NULL
            )]],

            [[CREATE TABLE IF NOT EXISTS match_players (
                match_id  INTEGER NOT NULL,
                player_id INTEGER NOT NULL,
                role      TEXT NOT NULL,
                survived  INTEGER NOT NULL
            )]],

            [[CREATE INDEX IF NOT EXISTS idx_match_players_match
                ON match_players (match_id)]],
        },
    },
```

- [ ] **Étape 2 : lancer les tests**

Lancer : `powershell -File scripts/test.ps1`
Attendu : au vert. La suite `db/migrations` calcule le nombre d'instructions attendu à partir de la
liste elle-même, donc elle s'adapte sans modification.

- [ ] **Étape 3 : amorcer le compteur d'identifiants**

Dans `Packages/fate-games/Server/Index.lua`, remplacer :

```lua
if not Ids.Seed({ "accounts", "characters", "ledger" }) then
```

par :

```lua
if not Ids.Seed({ "accounts", "characters", "ledger", "matches" }) then
```

- [ ] **Étape 4 : écrire le résultat depuis l'adaptateur**

Dans `Packages/fate-games/Server/games/werewolf/adapter.lua`, changer la signature de la fabrique
pour recevoir `DB` et `Ids` :

```lua
return function(Log, Scheduler, Intents, Interactables, Characters, Engine, DB, Ids, config)
```

Puis remplacer la branche `match_ended` de la fonction `apply` par :

```lua
            elseif e.kind == "match_ended" then
                Log.Info("werewolf", "partie terminee : " .. tostring(e.winner))

                -- Donnee transactionnelle : ecrite tout de suite, pas en differe.
                local match_id = Ids.Next("matches")
                local now = os.date("!%Y-%m-%dT%H:%M:%SZ")

                DB.Execute(
                    "INSERT INTO matches (id, game, winner, ended_at) VALUES (:0, :1, :2, :3)",
                    nil, match_id, "werewolf", e.winner, now)

                for _, line in ipairs(e.summary or {}) do
                    DB.Execute(
                        [[INSERT INTO match_players (match_id, player_id, role, survived)
                          VALUES (:0, :1, :2, :3)]],
                        nil, match_id, line.player, line.role, line.alive and 1 or 0)
                end
```

Et dans `Index.lua`, passer les deux nouvelles dépendances :

```lua
local Werewolf = Package.Require("games/werewolf/adapter.lua")(
    Log, Scheduler, Intents, Interactables, Characters, Engine, DB, Ids, ServerConfig)
```

- [ ] **Étape 5 : vérifier sur le serveur**

Lancer : `powershell -File scripts/dev.ps1 restart`
Attendu : dans les logs, `migration 3 appliquee : historique_des_parties`, puis
`[DEBUG][ids] matches amorce a 0`.

- [ ] **Étape 6 : commit**

```bash
git add Packages/fate-games/Server/db/migrations.lua Packages/fate-games/Server/Index.lua Packages/fate-games/Server/games/werewolf/adapter.lua
git commit -m "LOUP-GAROU - historique des parties

L etat d une partie en cours reste volatil, mais son resultat est une
donnee transactionnelle : ecrit immediatement a la fin, avec le role et le
sort de chaque joueur."
```

---

## Ce que ce plan ne fait pas

**Les effets sans traduction.** `reveal`, `point_at`, `world_light`, `voice_channel` par canal et
`announce` sont produits par le moteur mais seulement journalisés par l'adaptateur. Ils exigent la
carte, les animations et un client pour être vérifiés. Le moteur, lui, est complet et testé.

**Le gardien, la sorcière et le chasseur.** Chacun sera une entrée du registre des rôles plus un
résolveur. La pile de phases et le champ `audience` sont déjà là pour eux.
