# Stats du joueur sur l'accueil : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** afficher sur l'écran d'accueil la carte « Tes parties » du joueur (loup-garou avec répartition des rôles, Liar's Bar, duel, argent gagné) et enregistrer les duels terminés.

**Architecture :** un module serveur `stats.lua` interroge la base (résultats du loup-garou et du Liar's Bar, nouvelle table des duels, journal de l'argent) et calcule des stats prêtes à afficher par une fonction pure testée ; l'accueil les envoie au client dans un second événement ; la page les dessine.

**Tech Stack :** Lua (nanos world), SQLite via `DB.Select` / `DB.Execute`, WebUI HTML/JS, banc `lua tests/run.lua`.

**Spec :** `docs/superpowers/specs/2026-09-27-stats-joueur-design.md`

## Global Constraints

- Textes affichés en français ; noms des rôles : Villageois, Loup, Loup blanc, Voyante, Sorcière, Chasseur, Salvateur, Cupidon.
- `Events.CallRemote(evenement, joueur, Reliability.Reliable, ...)` côté serveur ; fiabilité obligatoire.
- `DB.Select(requete, function(rows, err) ... end, args...)` et `DB.Execute(requete, function(_, err) ... end, args...)` ; une requête en erreur ne fait jamais échouer l'arrivée.
- Les parties avec bots comptent ; les bots ne sont pas écrits dans `duel_resultats`.
- Commits `STATS - ...`, sans mention d'IA ni Co-Authored-By ; pas de push sans accord.
- `luac -p` sur chaque `.lua` touché, `node --check` sur le script de chaque page touchée, `lua tests/run.lua` vert.

## Review Focus

- Base lente ou en panne à l'arrivée : l'accueil s'ouvre quand même, la carte montre des zéros ou rien — tâche 2 (source en erreur) et tâche 3.
- Joueur parti avant que ses stats arrivent : aucun envoi vers un joueur absent — garde `presents` dans la tâche 3.
- Valeurs SQLite rendues en texte ou nil (`SUM` sur zéro ligne) : `tonumber` et zéros — test dans la tâche 1.
- Rôle inconnu dans la base (rôle ajouté plus tard) : affiché avec son identifiant, pas de plantage — test dans la tâche 1.
- Duel terminé avec un bot ou un joueur parti : seuls les humains présents sont écrits — tâche 3.

---

### Task 1 : calcul des stats (`Stats.Calculer`, pur)

**Files :**
- Create : `Packages/fate-games/Server/domain/stats.lua`
- Create : `tests/suites/stats.lua`
- Modify : `tests/run.lua` (ajouter `"stats",` après `"activite",`)

**Interfaces :**
- Produces : `Stats = Package.Require("domain/stats.lua")(Log, DB)` ; `Stats.Calculer(brut) -> stats`, avec
  - `brut = { roles = { { role, n, w, s } }, liars = { n, w, p }, duel = { n, w }, argent = { total, meilleur } }` (chaque champ peut manquer ou valoir nil ; valeurs possiblement en texte) ;
  - `stats = { loup_garou = nil | { parties, victoires, taux, survies, roles = { { nom, pourcent } } }, liars = nil | { parties, victoires, taux, place }, duel = nil | { parties, victoires }, argent = { total, meilleur }, vide = bool }` ; `roles` : les 4 plus joués puis `{ nom = "autres", pourcent }` s'il en reste ; `place` arrondie à une décimale.

- [ ] **Step 1 : test qui échoue**

`tests/suites/stats.lua` :

```lua
return function(H, Stubs)
    local function module()
        local c = Stubs.reset()
        local Log = Package.Require("core/log.lua")({ log = { min_level = "DEBUG" } })
        local DB = Package.Require("db/init.lua")(Log, { db = { connection = "db=test.db", pool_size = 1 } })
        DB.Connect()
        DB.EndStartup()
        return Package.Require("domain/stats.lua")(Log, DB), c
    end

    H.describe("domain/stats (calcul)", function()

        H.it("loup-garou : parties, victoires, taux, survies, roles en pourcentage", function()
            local S = module()
            local st = S.Calculer({ roles = {
                { role = "villager", n = 4, w = 2, s = 1 }, { role = "wolf", n = 3, w = 2, s = 2 },
                { role = "seer", n = 2, w = 1, s = 0 }, { role = "witch", n = 1, w = 0, s = 0 } } })
            local lg = st.loup_garou
            H.assert_eq(lg.parties, 10, "parties")
            H.assert_eq(lg.victoires, 5, "victoires")
            H.assert_eq(lg.taux, 50, "taux")
            H.assert_eq(lg.survies, 3, "survies")
            H.assert_eq(lg.roles[1].nom, "Villageois", "role le plus joue")
            H.assert_eq(lg.roles[1].pourcent, 40, "40 %")
            H.assert_eq(lg.roles[2].nom, "Loup", "puis loup")
            H.assert_count(lg.roles, 4, "quatre roles, pas d'autres")
            H.assert_false(st.vide, "pas vide")
        end)

        H.it("au-dela de quatre roles, le reste devient autres", function()
            local S = module()
            local st = S.Calculer({ roles = {
                { role = "villager", n = 5 }, { role = "wolf", n = 2 }, { role = "seer", n = 1 },
                { role = "witch", n = 1 }, { role = "hunter", n = 1 } } })
            local r = st.loup_garou.roles
            H.assert_count(r, 5, "quatre plus autres")
            H.assert_eq(r[5].nom, "autres", "autres")
            H.assert_eq(r[5].pourcent, 10, "10 %")
        end)

        H.it("valeurs en texte ou nil, role inconnu : pas de plantage", function()
            local S = module()
            local st = S.Calculer({ roles = { { role = "sorcier_rouge", n = "2", w = nil, s = "1" } },
                liars = { n = "3", w = "1", p = "2.3333" }, duel = { n = 0, w = nil }, argent = { total = nil } })
            H.assert_eq(st.loup_garou.parties, 2, "texte lu")
            H.assert_eq(st.loup_garou.victoires, 0, "nil -> 0")
            H.assert_eq(st.loup_garou.roles[1].nom, "sorcier_rouge", "identifiant garde")
            H.assert_eq(st.liars.parties, 3, "liars")
            H.assert_eq(st.liars.taux, 33, "taux arrondi")
            H.assert_eq(st.liars.place, 2.3, "une decimale")
            H.assert_nil(st.duel, "duel sans partie : pas de ligne")
            H.assert_eq(st.argent.total, 0, "argent nil -> 0")
        end)

        H.it("aucune partie : vide", function()
            local S = module()
            local st = S.Calculer({})
            H.assert_true(st.vide, "vide")
            H.assert_nil(st.loup_garou, "pas de loup-garou")
            H.assert_nil(st.liars, "pas de liars")
            H.assert_eq(st.argent.meilleur, 0, "argent a zero")
        end)
    end)
end
```

Dans `tests/run.lua`, ajouter `"stats",` après `"activite",`.

- [ ] **Step 2 : lancer, voir l'échec**

Run : `lua tests/run.lua`
Expected : échec « fichier introuvable -> domain/stats.lua ».

- [ ] **Step 3 : module (calcul seul ; Charger et EnregistrerDuel viennent en tâche 2)**

`Packages/fate-games/Server/domain/stats.lua` :

```lua
-- Stats du joueur pour l'ecran d'accueil (docs/superpowers/specs/2026-09-27-stats-joueur-design.md).
-- Calculer est pur (teste dans tests/suites/stats.lua) ; Charger lit la base,
-- EnregistrerDuel ecrit les duels termines. Les parties avec bots comptent.

return function(Log, DB)
    local Stats = {}

    local NOMS_ROLES = {
        villager = "Villageois", wolf = "Loup", white_wolf = "Loup blanc", seer = "Voyante",
        witch = "Sorcière", hunter = "Chasseur", guard = "Salvateur", cupid = "Cupidon",
    }
    local TOP_ROLES = 4

    local function n(v) return tonumber(v) or 0 end
    local function pourcent(part, total) return total > 0 and math.floor(part * 100 / total + 0.5) or 0 end

    function Stats.Calculer(brut)
        brut = brut or {}
        local st = { argent = { total = n(brut.argent and brut.argent.total), meilleur = n(brut.argent and brut.argent.meilleur) } }

        -- Loup-garou : une ligne par role joue.
        local roles, parties, victoires, survies = {}, 0, 0, 0
        for _, r in ipairs(brut.roles or {}) do
            local k = n(r.n)
            if k > 0 then
                roles[#roles + 1] = { id = tostring(r.role), n = k }
                parties, victoires, survies = parties + k, victoires + n(r.w), survies + n(r.s)
            end
        end
        if parties > 0 then
            table.sort(roles, function(a, b) return a.n > b.n end)
            local liste, reste = {}, 0
            for i, r in ipairs(roles) do
                if i <= TOP_ROLES then
                    liste[#liste + 1] = { nom = NOMS_ROLES[r.id] or r.id, pourcent = pourcent(r.n, parties) }
                else
                    reste = reste + r.n
                end
            end
            if reste > 0 then liste[#liste + 1] = { nom = "autres", pourcent = pourcent(reste, parties) } end
            st.loup_garou = { parties = parties, victoires = victoires, taux = pourcent(victoires, parties),
                survies = survies, roles = liste }
        end

        -- Liar's Bar : parties, victoires (placement 1), place moyenne.
        local l = brut.liars or {}
        if n(l.n) > 0 then
            st.liars = { parties = n(l.n), victoires = n(l.w), taux = pourcent(n(l.w), n(l.n)),
                place = math.floor(n(l.p) * 10 + 0.5) / 10 }
        end

        -- Duel.
        local d = brut.duel or {}
        if n(d.n) > 0 then st.duel = { parties = n(d.n), victoires = n(d.w) } end

        st.vide = not (st.loup_garou or st.liars or st.duel)
        return st
    end

    return Stats
end
```

- [ ] **Step 4 : lancer, tout vert**

Run : `lua tests/run.lua`
Expected : `domain/stats (calcul)` 4 ok, 0 échec.

- [ ] **Step 5 : commit**

```bash
git add Packages/fate-games/Server/domain/stats.lua tests/suites/stats.lua tests/run.lua
git commit -m "STATS - calcul des stats du joueur"
```

---

### Task 2 : lecture en base, table des duels

**Files :**
- Modify : `Packages/fate-games/Server/domain/stats.lua` (avant `return Stats`)
- Modify : `Packages/fate-games/Server/db/migrations.lua` (migration 7, après la 6)
- Modify : `tests/suites/stats.lua` (nouveau `H.describe`)

**Interfaces :**
- Consumes : `Stats.Calculer` (tâche 1).
- Produces : `Stats.Charger(character_id, account_id, callback)` → `callback(stats)` toujours appelé ; `Stats.EnregistrerDuel(partie, joueurs)` avec `joueurs = { { character_id, won } }`. Table `duel_resultats(partie, character_id, won, created_at)`.

- [ ] **Step 1 : tests qui échouent**

Dans `tests/suites/stats.lua`, avant le dernier `end` de la fonction, ajouter :

```lua
    H.describe("domain/stats (base)", function()

        H.it("Charger lit les quatre sources et calcule", function()
            local S, c = module()
            c.answer("FROM werewolf_participants", { { role = "wolf", n = 2, w = 1, s = 1 } })
            c.answer("FROM liars_participants", { { n = 4, w = 2, p = 2 } })
            c.answer("FROM duel_resultats", { { n = 3, w = 2 } })
            c.answer("FROM ledger", { { total = 450, meilleur = 250 } })
            local st
            S.Charger(12, 7, function(r) st = r end)
            H.assert_eq(st.loup_garou.parties, 2, "loup-garou")
            H.assert_eq(st.liars.victoires, 2, "liars")
            H.assert_eq(st.duel.parties, 3, "duel")
            H.assert_eq(st.argent.meilleur, 250, "argent")
            local vu = false
            for _, s in ipairs(c.db.selected) do
                if s.query:find("FROM ledger", 1, true) then vu = s.params[1] == "compte:7" end
            end
            H.assert_true(vu, "argent lu sur compte:7")
        end)

        H.it("une base en erreur donne des stats vides, sans echec", function()
            local S, c = module()
            c.db.select_error = "base en panne"
            local st
            S.Charger(12, 7, function(r) st = r end)
            H.assert_true(st ~= nil, "callback appele")
            H.assert_true(st.vide, "vide")
        end)

        H.it("EnregistrerDuel ecrit une ligne par joueur", function()
            local S, c = module()
            S.EnregistrerDuel("duel:Est:3", { { character_id = 12, won = true }, { character_id = 13, won = false } })
            local lignes = {}
            for _, e in ipairs(c.db.executed) do
                if e.query:find("INSERT INTO duel_resultats", 1, true) then lignes[#lignes + 1] = e.params end
            end
            H.assert_count(lignes, 2, "deux lignes")
            H.assert_eq(lignes[1][1], "duel:Est:3", "partie")
            H.assert_eq(lignes[1][3], 1, "gagne = 1")
            H.assert_eq(lignes[2][3], 0, "perdu = 0")
        end)
    end)
```

- [ ] **Step 2 : lancer, voir l'échec**

Run : `lua tests/run.lua`
Expected : ÉCHEC « attempt to call a nil value (field 'Charger') » et « (field 'EnregistrerDuel') ».

- [ ] **Step 3 : implémenter**

Dans `stats.lua`, juste avant `return Stats` :

```lua
    -- Les quatre sources, l'une apres l'autre ; une requete en erreur laisse
    -- sa source vide. callback(stats) est toujours appele.
    function Stats.Charger(character_id, account_id, callback)
        local brut = {}
        local function lire(requete, arg, cle, toutes)
            return function(suite)
                DB.Select(requete, function(rows, err)
                    if err then
                        Log.Warn("stats", cle .. " illisible : " .. tostring(err))
                    elseif rows then
                        brut[cle] = toutes and rows or rows[1]
                    end
                    suite()
                end, arg)
            end
        end
        local etapes = {
            lire([[SELECT role, COUNT(*) AS n, SUM(won) AS w, SUM(survived) AS s
                   FROM werewolf_participants WHERE character_id = :0 GROUP BY role]], character_id, "roles", true),
            lire([[SELECT COUNT(*) AS n, SUM(CASE WHEN placement = 1 THEN 1 ELSE 0 END) AS w, AVG(placement) AS p
                   FROM liars_participants WHERE character_id = :0]], character_id, "liars"),
            lire([[SELECT COUNT(*) AS n, SUM(won) AS w FROM duel_resultats WHERE character_id = :0]],
                character_id, "duel"),
            lire([[SELECT SUM(amount) AS total, MAX(amount) AS meilleur FROM ledger
                   WHERE credit_account = :0 AND reason = 'gain']], "compte:" .. tostring(account_id), "argent"),
        }
        local i = 0
        local function suivante()
            i = i + 1
            if i > #etapes then return callback(Stats.Calculer(brut)) end
            etapes[i](suivante)
        end
        suivante()
    end

    -- Un duel termine : une ligne par joueur humain present a la fin.
    function Stats.EnregistrerDuel(partie, joueurs)
        local quand = os.date("!%Y-%m-%dT%H:%M:%SZ")
        for _, j in ipairs(joueurs or {}) do
            if j.character_id and j.character_id > 0 then
                DB.Execute([[INSERT OR IGNORE INTO duel_resultats (partie, character_id, won, created_at)
                             VALUES (:0, :1, :2, :3)]],
                    function(_, err) if err then Log.Error("stats", "duel non ecrit : " .. tostring(err)) end end,
                    partie, j.character_id, j.won and 1 or 0, quand)
            end
        end
    end
```

Dans `Server/db/migrations.lua`, après la migration `id = 6` (avant l'accolade finale de la liste) :

```lua

    {
        id   = 7,
        name = "duel_resultats",
        statements = {
            -- Un duel termine, un joueur humain par ligne (stats de l'accueil).
            [[CREATE TABLE IF NOT EXISTS duel_resultats (
                partie       TEXT    NOT NULL,
                character_id INTEGER NOT NULL,
                won          INTEGER NOT NULL,
                created_at   TEXT    NOT NULL,
                PRIMARY KEY (partie, character_id)
            )]],
        },
    },
```

- [ ] **Step 4 : lancer, tout vert**

Run : `lua tests/run.lua`
Expected : `domain/stats (base)` 3 ok, suite `migrations` verte, 0 échec.

- [ ] **Step 5 : commit**

```bash
git add Packages/fate-games/Server/domain/stats.lua Packages/fate-games/Server/db/migrations.lua tests/suites/stats.lua
git commit -m "STATS - lecture en base et table des duels"
```

---

### Task 3 : branchement serveur (duel, accueil)

**Files :**
- Modify : `Packages/fate-games/Server/games/duel/adapter.lua` (`terminer`, et `Adapter.SurFin` avant `return Adapter`)
- Modify : `Packages/fate-games/Server/domain/accueil.lua` (paramètre `Stats`, envoi `accueil:stats`)
- Modify : `Packages/fate-games/Server/Index.lua` (création de `Stats`, `DuelJeu.SurFin`, constructeur d'`Accueil`)

**Interfaces :**
- Consumes : `Stats.Charger`, `Stats.EnregistrerDuel` (tâche 2).
- Produces : événement serveur→client `accueil:stats(stats)` ; `DuelJeu.SurFin(fn)` avec `fn(partie, joueurs)`.

- [ ] **Step 1 : duel**

Dans `duel/adapter.lua`, dans `local function terminer(A, gagnant)`, juste après la ligne `local partie = ("duel:%s:%d"):format(A.nom, A.numero)`, ajouter :

```lua
        -- Stats (domain/stats.lua) : les humains presents a la fin, gagnants ou non.
        if sur_fin then
            local joueurs = {}
            for id, j in pairs(A.d.joueurs) do
                local s = not bots[id] and not j.parti and Characters.SessionByPlayer(id)
                if s and s.character_id then
                    joueurs[#joueurs + 1] = { character_id = s.character_id, won = j.camp == gagnant }
                end
            end
            pcall(sur_fin, partie, joueurs)
        end
```

et, près du haut du module (après `local dehors = {}`, ~l.20) :

```lua
    local sur_fin = nil          -- abonne aux fins de duel (stats), Adapter.SurFin
```

puis, juste avant la ligne `    return Adapter` finale :

```lua
    function Adapter.SurFin(fn)
        sur_fin = fn
    end
```

- [ ] **Step 2 : accueil**

Dans `Server/domain/accueil.lua`, changer la signature :

```lua
return function(Log, Characters, Boutique, Activite, config, dev_pour, Stats)
```

et, à la fin de `Accueil.Ouvrir` (après l'appel `Events.CallRemote("accueil:ouvrir", ...)`), ajouter :

```lua
        -- Les stats suivent, sans retarder l'arrivee (base lente).
        if Stats and session.character_id and session.account then
            local id = session.player_id
            Stats.Charger(session.character_id, session.account.id, function(st)
                local p = presents[id]
                if p and p:IsValid() then Events.CallRemote("accueil:stats", p, Reliability.Reliable, st) end
            end)
        end
```

- [ ] **Step 3 : Index**

Dans `Server/Index.lua`, remplacer la création d'`Accueil` par :

```lua
local Stats    = Package.Require("domain/stats.lua")(Log, DB)
local Accueil  = Package.Require("domain/accueil.lua")(Log, Characters, Boutique, Activite,
    { fichier = "accueil.json", traversee = SharedConfig.accueil and SharedConfig.accueil.traversee,
      spawn = ServerConfig.spawn }, dev_pour, Stats)
```

et, juste après `Activite.Inscrire("duel", DuelJeu.Resume)`, ajouter :

```lua
DuelJeu.SurFin(Stats.EnregistrerDuel)
```

- [ ] **Step 4 : vérifier**

Run : `luac -p Packages/fate-games/Server/games/duel/adapter.lua Packages/fate-games/Server/domain/accueil.lua Packages/fate-games/Server/Index.lua && lua tests/run.lua`
Expected : aucune erreur, 0 échec.

- [ ] **Step 5 : commit**

```bash
git add Packages/fate-games/Server/games/duel/adapter.lua Packages/fate-games/Server/domain/accueil.lua Packages/fate-games/Server/Index.lua
git commit -m "STATS - duels enregistres, stats envoyees a l'accueil"
```

---

### Task 4 : carte « Tes parties » sur la page

**Files :**
- Modify : `Packages/fate-games/Client/accueil/accueil.lua`
- Modify : `Packages/fate-games/Client/accueil/accueil.html`

**Interfaces :**
- Consumes : `accueil:stats(stats)` (tâche 3), forme de `stats` (tâche 1).

- [ ] **Step 1 : pont client**

Dans `accueil.lua`, après `Events.SubscribeRemote("accueil:gain", ...)` :

```lua
    Events.SubscribeRemote("accueil:stats", function(s) vers_page("accueil:stats", s) end)
```

- [ ] **Step 2 : page**

Dans `accueil.html` :

a) dans le `<style>`, avant `</style>` :

```css
#stats { position: fixed; left: 32px; top: 110px; width: min(330px, 28vw); padding: 14px 18px 12px; display: none; }
#stats.plein { display: block; }
#stats h2 { margin: 0 0 8px; font-size: 22px; font-weight: 400; }
.jeu { margin: 8px 0 0; font-size: 16px; line-height: 1.25; }
.jeu b { font-weight: 400; color: #8a6d3b; }
.role { display: grid; grid-template-columns: 86px 1fr 38px; align-items: center; gap: 6px; font-size: 13px; margin-top: 3px; }
.barre { height: 8px; border: 2px solid var(--encre); border-radius: 5px; background: var(--papier-clair); overflow: hidden; }
.barre i { display: block; height: 100%; background: var(--laiton); }
```

b) dans le `<body>`, juste après `<div id="gains"></div>` :

```html
<div id="stats" class="sk" data-graine="61" data-rayon="12"></div>
```

c) dans le `<script>`, avant `setInterval(astuceSuivante, 6000);` :

```js
function stats(s) {
  const el = $("stats");
  if (!s) return;
  const lignes = [];
  if (s.vide) {
    lignes.push('<div class="jeu">Ta première partie t\'attend.</div>');
  }
  if (s.loup_garou) {
    const lg = s.loup_garou;
    lignes.push(`<div class="jeu">Loup-garou : <b>${lg.parties}</b> parties · <b>${lg.victoires}</b> victoires (${lg.taux} %) · <b>${lg.survies}</b> survies</div>`);
    for (const r of lg.roles || []) {
      lignes.push(`<div class="role"><span>${nettoyer(r.nom)}</span><span class="barre"><i style="width:${Math.max(0, Math.min(100, Number(r.pourcent) || 0))}%"></i></span><span>${nettoyer(r.pourcent)} %</span></div>`);
    }
  }
  if (s.liars) {
    const l = s.liars;
    lignes.push(`<div class="jeu">Liar's Bar : <b>${l.parties}</b> parties · <b>${l.victoires}</b> victoires (${l.taux} %) · place moyenne <b>${String(l.place).replace(".", ",")}</b></div>`);
  }
  if (s.duel) {
    lignes.push(`<div class="jeu">Duel : <b>${s.duel.parties}</b> duels · <b>${s.duel.victoires}</b> gagnés</div>`);
  }
  if (s.argent && s.argent.total > 0) {
    lignes.push(`<div class="jeu">Gagné en tout : <b>${s.argent.total}</b> · meilleure cagnotte <b>${s.argent.meilleur}</b></div>`);
  }
  el.innerHTML = `<h2>Tes parties</h2>${lignes.join("")}`;
  el.classList.add("plein");
  requestAnimationFrame(habiller);
}
```

d) dans le bloc `if (window.Events) { ... }`, ajouter :

```js
  Events.Subscribe("accueil:stats", stats);
```

e) dans le bloc de l'aperçu navigateur (`else { ... }`), à la fin :

```js
  stats({ vide: false,
    loup_garou: { parties: 10, victoires: 5, taux: 50, survies: 3, roles: [
      { nom: "Villageois", pourcent: 40 }, { nom: "Loup", pourcent: 30 }, { nom: "Voyante", pourcent: 20 }, { nom: "Sorcière", pourcent: 10 } ] },
    liars: { parties: 6, victoires: 2, taux: 33, place: 2.3 },
    duel: { parties: 3, victoires: 2 },
    argent: { total: 1850, meilleur: 400 } });
```

- [ ] **Step 3 : vérifier**

Run :
```bash
luac -p Packages/fate-games/Client/accueil/accueil.lua
python -c "import re;s=open('Packages/fate-games/Client/accueil/accueil.html',encoding='utf-8').read();open('stats_check.js','w',encoding='utf-8').write(re.findall(r'<script>(.*?)</script>',s,re.S)[-1])" && node --check stats_check.js && rm stats_check.js
```
Expected : aucune erreur. Rendu de la page dans un navigateur : carte « Tes parties » à gauche, sans chevaucher le titre ni la ligne du bas.

- [ ] **Step 4 : commit**

```bash
git add Packages/fate-games/Client/accueil/accueil.lua Packages/fate-games/Client/accueil/accueil.html
git commit -m "STATS - carte Tes parties sur l'accueil"
```

---

### Task 5 : vérification d'ensemble

- [ ] **Step 1 :** `lua tests/run.lua` vert ; `luac -p` sur tous les `.lua` modifiés depuis le début du plan.
- [ ] **Step 2 : liste en jeu (utilisateur, serveur redémarré, pas de cuisson)** : 1) la carte à la connexion (ou « Ta première partie t'attend. ») ; 2) après une partie de loup-garou, les rôles et le taux changent à la reconnexion ; 3) après un Liar's Bar, parties et place moyenne ; 4) après un duel terminé, la ligne Duel apparaît ; 5) après une cagnotte gagnée, la ligne d'argent.
