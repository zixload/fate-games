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

    return Stats
end
