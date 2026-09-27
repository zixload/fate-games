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
