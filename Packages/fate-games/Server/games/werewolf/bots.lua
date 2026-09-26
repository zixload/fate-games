-- Bots de test du loup-garou : qui peut agir dans une phase, et quelle cible
-- il choisit. Pur (aleatoire injecte) : sert aux bots en jeu (adapter.lua) et
-- aux parties simulees des tests.
--
-- Pas un vrai joueur, juste assez pour que les parties avancent et se
-- terminent : les loups suivent la cible deja choisie par un autre loup, la
-- voyante retient ce qu'elle a vu et vote contre un loup demasque, au vote le
-- village suit souvent le plus designe. Un bot lit l'etat du moteur : il
-- triche, ce n'est pas grave, il ne sert qu'aux tests.

return function(Match)
    local B = {}

    local QUI = {
        night_cupid = { cupid = true }, night_guard = { guard = true },
        night_wolves = { wolf = true, white_wolf = true }, night_white_wolf = { white_wolf = true },
        night_seer = { seer = true }, night_witch = { witch = true },
        hunter_shot = "tireur", mayor_succession = "maire",
        day_mayor = "tous", day_vote = "tous", day_debate = "tous",
    }

    -- Peut-il designer dans la phase en cours ? Combien de fois (Cupidon : 2).
    function B.coups(s, id)
        local m, phase = s.match, s.phase
        local qui = QUI[phase or ""]
        if not (m and qui) then return 0 end
        if qui == "tireur" then return s.tireur == id and 1 or 0 end
        if qui == "maire" then return s.ancien_maire == id and 1 or 0 end
        if not Match.vivant(m, id) then return 0 end
        if qui == "tous" then return 1 end
        if not qui[Match.role(m, id)] then return 0 end
        return phase == "night_cupid" and 2 or 1
    end

    local function au_hasard(liste, rng)
        if #liste == 0 then return nil end
        return liste[rng(#liste)]
    end

    -- La cible la plus designee du bulletin en cours (le jour : le vote du
    -- village, ouvert des le debat), si elle convient.
    local function en_tete(s, filtre)
        local b = (s.phase == "day_vote" or s.phase == "day_debate") and s.vote_jour or s.bulletin
        local c = {}
        for _, cible in pairs(b and b.choix or {}) do c[cible] = (c[cible] or 0) + 1 end
        local meilleure, max = nil, 0
        for cible, n in pairs(c) do
            if n > max and filtre(cible) then meilleure, max = cible, n end
        end
        return meilleure
    end

    -- memoire : une table par bot, gardee d'un appel a l'autre ({ vus = {} }).
    function B.choisir(s, id, rng, memoire)
        local m, phase = s.match, s.phase
        memoire.vus = memoire.vus or {}
        local vivants = Match.vivants(m)
        local function autres(filtre)
            local out = {}
            for _, v in ipairs(vivants) do
                if v ~= id and (not filtre or filtre(v)) then out[#out + 1] = v end
            end
            return out
        end
        local loup = function(v) return Match.est_loup(m, v) end
        local pas_loup = function(v) return not Match.est_loup(m, v) end

        if phase == "night_wolves" then
            return en_tete(s, pas_loup) or au_hasard(autres(pas_loup), rng)
        elseif phase == "night_white_wolf" then
            return au_hasard(autres(loup), rng)
        elseif phase == "night_guard" then
            local out = {}
            for _, v in ipairs(vivants) do if v ~= s.protege_avant then out[#out + 1] = v end end
            return au_hasard(out, rng)
        elseif phase == "night_seer" then
            local cible = au_hasard(autres(function(v) return memoire.vus[v] == nil end), rng)
                or au_hasard(autres(), rng)
            if cible then memoire.vus[cible] = Match.role(m, cible) end
            return cible
        elseif phase == "night_witch" then
            -- Sauve une fois sur deux, empoisonne parfois, sinon passe.
            if s.potion_vie and s.victime_loups and rng(2) == 1 then return s.victime_loups end
            if s.potion_mort and rng(3) == 1 then
                return au_hasard(autres(function(v) return v ~= s.victime_loups end), rng)
            end
            return nil
        elseif phase == "night_cupid" then
            local deja = {}
            for _, v in ipairs(s.lies or {}) do deja[v] = true end
            local out = {}
            for _, v in ipairs(vivants) do if not deja[v] then out[#out + 1] = v end end
            return au_hasard(out, rng)
        elseif phase == "day_vote" or phase == "day_debate" or phase == "day_mayor" then
            -- La voyante denonce un loup qu'elle a vu.
            for v, role in pairs(memoire.vus) do
                if Match.vivant(m, v) and (role == "wolf" or role == "white_wolf") and phase ~= "day_mayor" then return v end
            end
            -- Un loup ne vote pas contre les siens.
            local filtre = Match.est_loup(m, id) and pas_loup or function(v) return v ~= id end
            if rng(2) == 1 then
                local tete = en_tete(s, function(v) return v ~= id and filtre(v) end)
                if tete then return tete end
            end
            return au_hasard(autres(filtre), rng)
        else
            return au_hasard(autres(), rng)
        end
    end

    return B
end
