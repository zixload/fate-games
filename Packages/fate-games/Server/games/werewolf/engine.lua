-- La machine du loup-garou (spec, "La pile de phases" et "Deroulement").
--
-- Ne connait pas nanos world : on lui donne un etat et une duree ecoulee, une
-- designation ou un depart ; elle rend une liste d'effets (effects.lua), que
-- l'adaptateur traduit. Pur, aleatoire injecte (rng(k) : entier de 1 a k).
--
-- Deroulement : une file de phases pour la nuit en cours (les roles de la
-- composition, dans l'ordre de data/phases.lua), puis le jour ; une pile par
-- dessus pour ce qui interrompt (le tir du chasseur, empile a sa mort).
--
--   Engine.nouveau(reglages)                 etat en attente
--   Engine.demarrer(s, ids, compo, rng)      effets | nil, raison
--   Engine.designer(s, acteur, cible)        effets | nil, raison
--   Engine.avancer(s, dt)                    effets
--   Engine.depart(s, joueur)                 effets
--   Engine.phase(s)                          id de la phase en cours, ou nil

return function(Roles, Phases, Match, Voting, Outcome, Effects)
    local Engine = {}

    function Engine.nouveau(reglages)
        reglages = reglages or {}
        local durees = {}
        for id, d in pairs(Phases.durees) do durees[id] = d end
        if reglages.debat then durees.day_debate = reglages.debat end
        return { statut = "attente", durees = durees }
    end

    function Engine.phase(s) return s.statut == "partie" and s.phase or nil end

    ---------------------------------------------------------------- morts et victoire

    local function verifier(s, fx)
        local gagnant = Outcome.verdict(s.match)
        if not gagnant then return false end
        s.statut = "finie"
        local roles = {}
        for id, j in pairs(s.match.joueurs) do roles[id] = j.role end
        fx[#fx + 1] = Effects.match_ended(gagnant, { roles = roles, nuits = s.nuit })
        return true
    end

    -- Tue un joueur et ce qui suit sa mort : son amoureux meurt de chagrin, le
    -- chasseur empile son tir.
    local function tuer(s, id, cause, fx)
        if not Match.tuer(s.match, id) then return end
        fx[#fx + 1] = Effects.kill(id, cause)
        fx[#fx + 1] = Effects.voice_channel(id, "dead")
        local r = Roles.roles[Match.role(s.match, id)]
        if r.on_death then
            s.pile[#s.pile + 1] = r.on_death
            s.tireurs[#s.tireurs + 1] = id
        end
        -- Le maire mort designe son successeur.
        if s.maire == id then
            s.maire, s.ancien_maire = nil, id
            s.pile[#s.pile + 1] = "mayor_succession"
        end
        local p = Match.partenaire(s.match, id)
        if p and Match.vivant(s.match, p) then tuer(s, p, "chagrin", fx) end
    end

    ---------------------------------------------------------------- phases

    local entrer, suivante

    local function commencer_nuit(s, fx)
        s.nuit = s.nuit + 1
        s.file = {}
        for _, p in ipairs(Phases.nuit) do
            local present = (s.compo[p.role] or 0) > 0
            if present and not (p.premiere_seulement and s.nuit > 1)
                and not (p.une_sur and s.nuit % p.une_sur ~= 0) then
                s.file[#s.file + 1] = p.id
            end
        end
        for _, id in ipairs(Phases.jour) do
            -- L'election du maire, avant le debat du jour prevu.
            if id == "day_debate" and not s.maire and not s.maire_elu
                and Phases.maire and s.nuit >= Phases.maire.jour then
                s.file[#s.file + 1] = "day_mayor"
            end
            s.file[#s.file + 1] = id
        end
        s.victime_loups, s.victime_blanc, s.protege = nil, nil, nil
        fx[#fx + 1] = Effects.world_light("night")
        for _, id in ipairs(Match.vivants(s.match)) do
            fx[#fx + 1] = Effects.voice_channel(id, Match.est_loup(s.match, id) and "wolves" or "sleep")
        end
    end

    -- A l'aube : la victime des loups meurt, sauf si le gardien la protege ;
    -- celle du loup blanc aussi.
    local function resoudre_nuit(s, fx)
        local morts = {}
        if s.victime_loups and s.victime_loups ~= s.protege then morts[#morts + 1] = s.victime_loups end
        if s.victime_blanc and s.victime_blanc ~= s.victime_loups then morts[#morts + 1] = s.victime_blanc end
        local avant = #fx
        for _, id in ipairs(morts) do tuer(s, id, "nuit", fx) end
        local tues = {}
        for i = avant + 1, #fx do
            if fx[i].kind == "kill" then tues[#tues + 1] = fx[i].player end
        end
        fx[#fx + 1] = Effects.world_light("day")
        fx[#fx + 1] = Effects.announce(#tues > 0 and "aube_morts" or "aube_personne", { morts = tues })
        for _, id in ipairs(Match.vivants(s.match)) do fx[#fx + 1] = Effects.voice_channel(id, "village") end
    end

    entrer = function(s, id, fx)
        s.phase, s.reste = id, s.durees[id] or 10
        s.bulletin = Voting.nouveau()
        s.lies = {}
        fx[#fx + 1] = Effects.phase(id, s.reste)
        if id == "dawn" then
            resoudre_nuit(s, fx)
            verifier(s, fx)
        elseif id == "execution" then
            if s.condamne then
                local c = s.condamne
                s.condamne = nil
                tuer(s, c, "vote", fx)
                fx[#fx + 1] = Effects.announce("execution", { joueur = c, role = Match.role(s.match, c) })
            else
                fx[#fx + 1] = Effects.announce("egalite", {})
            end
            verifier(s, fx)
        elseif id == "hunter_shot" then
            s.tireur = table.remove(s.tireurs, 1)
        end
    end

    suivante = function(s, fx)
        if s.statut ~= "partie" then return end
        local id = table.remove(s.pile)
        if not id then
            id = table.remove(s.file, 1)
            if not id then
                commencer_nuit(s, fx)
                id = table.remove(s.file, 1)
            end
        end
        entrer(s, id, fx)
    end

    -- Fin d'une phase : ce qu'elle a decide, puis la suivante.
    local function terminer(s, fx)
        local id = s.phase
        if id == "night_wolves" then
            local v = Voting.depouiller(s.bulletin, "hasard", s.rng)
            if not v then
                -- Personne n'a vote : une nuit sans victime bloquerait la partie.
                local proies = {}
                for _, j in ipairs(Match.vivants(s.match)) do
                    if not Match.est_loup(s.match, j) then proies[#proies + 1] = j end
                end
                if #proies > 0 then v = proies[s.rng(#proies)] end
            end
            s.victime_loups = v
        elseif id == "night_guard" then
            s.protege_avant = s.protege
        elseif id == "day_vote" then
            local poids = s.maire and { [s.maire] = 2 } or nil
            s.condamne = Voting.depouiller(s.bulletin, "aucun", s.rng, poids,
                s.maire and Voting.choix(s.bulletin, s.maire))
        elseif id == "day_mayor" then
            -- Il faut un maire : egalite tiree au sort, et sans vote, au hasard.
            local elu = Voting.depouiller(s.bulletin, "hasard", s.rng)
            local vivants = Match.vivants(s.match)
            if not elu and #vivants > 0 then elu = vivants[s.rng(#vivants)] end
            if elu then
                s.maire, s.maire_elu = elu, true
                fx[#fx + 1] = Effects.mayor(elu)
                fx[#fx + 1] = Effects.announce("maire", { joueur = elu })
            end
        elseif id == "mayor_succession" then
            if not s.maire then
                local vivants = Match.vivants(s.match)
                if #vivants > 0 then
                    s.maire = vivants[s.rng(#vivants)]
                    fx[#fx + 1] = Effects.mayor(s.maire)
                    fx[#fx + 1] = Effects.announce("successeur", { joueur = s.maire })
                end
            end
            s.ancien_maire = nil
        elseif id == "hunter_shot" then
            s.tireur = nil
        end
        suivante(s, fx)
    end

    ---------------------------------------------------------------- entrees

    function Engine.demarrer(s, ids, compo, rng)
        if s.statut == "partie" then return nil, "partie_en_cours" end
        compo = compo or Roles.par_defaut(#ids)
        local ok, raison = Match.valider(compo, #ids)
        if not ok then return nil, raison end

        s.statut, s.rng, s.compo, s.nuit = "partie", rng, compo, 0
        s.file, s.pile, s.tireurs = {}, {}, {}
        s.match = Match.nouveau(ids, Match.tirer(ids, compo, rng))

        local fx = {}
        local loups = Match.loups_vivants(s.match)
        for _, id in ipairs(ids) do
            local allies = {}
            if Match.est_loup(s.match, id) then
                for _, l in ipairs(loups) do
                    if l ~= id then allies[#allies + 1] = l end
                end
            end
            fx[#fx + 1] = Effects.assign_role(id, Match.role(s.match, id), allies)
        end
        commencer_nuit(s, fx)
        suivante(s, fx)
        return fx
    end

    function Engine.avancer(s, dt)
        local fx = {}
        if s.statut ~= "partie" then return fx end
        s.reste = s.reste - dt
        local garde = 0
        while s.statut == "partie" and s.reste <= 0 and garde < 32 do
            local deborde = s.reste
            terminer(s, fx)
            if s.statut == "partie" then s.reste = s.reste + deborde end
            garde = garde + 1
        end
        return fx
    end

    -- Une designation, selon la phase : vote, cible des loups, protection,
    -- vision, lien ou tir. Rend les effets, ou nil et la raison du refus.
    function Engine.designer(s, acteur, cible)
        if s.statut ~= "partie" then return nil, "aucune_partie" end
        local m, id = s.match, s.phase
        local role = Match.role(m, acteur)
        if not role then return nil, "pas_joueur" end
        if not Match.vivant(m, cible) then return nil, "cible_invalide" end
        local tir = id == "hunter_shot" and acteur == s.tireur
        local succession = id == "mayor_succession" and acteur == s.ancien_maire
        if not (tir or succession) and not Match.vivant(m, acteur) then return nil, "mort" end

        local fx = {}
        if id == "night_wolves" then
            if not Match.est_loup(m, acteur) or Match.est_loup(m, cible) then return nil, "interdit" end
            Voting.designer(s.bulletin, acteur, cible)
            fx[#fx + 1] = Effects.votes(Voting.compte(s.bulletin), "wolves")
            fx[#fx + 1] = Effects.point_at(acteur, cible, "wolves")
            if Voting.votants(s.bulletin) >= #Match.loups_vivants(m) then terminer(s, fx) end
        elseif id == "night_guard" then
            if role ~= "guard" or cible == s.protege_avant then return nil, "interdit" end
            s.protege = cible
            terminer(s, fx)
        elseif id == "night_white_wolf" then
            if role ~= "white_wolf" or cible == acteur or not Match.est_loup(m, cible) then return nil, "interdit" end
            s.victime_blanc = cible
            terminer(s, fx)
        elseif id == "night_seer" then
            if role ~= "seer" or cible == acteur then return nil, "interdit" end
            fx[#fx + 1] = Effects.reveal(acteur, cible, Match.role(m, cible))
            terminer(s, fx)
        elseif id == "night_cupid" then
            if role ~= "cupid" then return nil, "interdit" end
            for _, deja in ipairs(s.lies) do
                if deja == cible then return nil, "deja_choisi" end
            end
            s.lies[#s.lies + 1] = cible
            if #s.lies == 2 then
                local a, b = s.lies[1], s.lies[2]
                m.amoureux = { a, b }
                fx[#fx + 1] = Effects.lovers(a, b)
                fx[#fx + 1] = Effects.lovers(b, a)
                terminer(s, fx)
            end
        elseif id == "day_vote" then
            if cible == acteur then return nil, "interdit" end
            Voting.designer(s.bulletin, acteur, cible)
            fx[#fx + 1] = Effects.votes(Voting.compte(s.bulletin, s.maire and { [s.maire] = 2 } or nil), "all")
            fx[#fx + 1] = Effects.point_at(acteur, cible, "all")
        elseif id == "day_mayor" then
            Voting.designer(s.bulletin, acteur, cible)
            fx[#fx + 1] = Effects.votes(Voting.compte(s.bulletin), "all")
            fx[#fx + 1] = Effects.point_at(acteur, cible, "all")
        elseif succession then
            if cible == acteur then return nil, "interdit" end
            s.maire = cible
            fx[#fx + 1] = Effects.mayor(cible)
            fx[#fx + 1] = Effects.announce("successeur", { joueur = cible })
            terminer(s, fx)
        elseif tir then
            if cible == acteur then return nil, "interdit" end
            tuer(s, cible, "chasseur", fx)
            fx[#fx + 1] = Effects.announce("chasseur", { tireur = acteur, joueur = cible })
            if not verifier(s, fx) then terminer(s, fx) end
        else
            return nil, "hors_phase"
        end
        return fx
    end

    -- Un joueur quitte la partie : il est traite comme mort. Sous le minimum
    -- de joueurs, la partie s'arrete sans vainqueur (spec, "Pannes").
    function Engine.depart(s, joueur)
        local fx = {}
        if s.statut ~= "partie" or not Match.vivant(s.match, joueur) then return fx end
        tuer(s, joueur, "depart", fx)
        fx[#fx + 1] = Effects.announce("depart", { joueur = joueur })
        if verifier(s, fx) then return fx end
        if #Match.vivants(s.match) < Roles.MIN_JOUEURS then
            s.statut = "finie"
            fx[#fx + 1] = Effects.match_ended("none", { raison = "trop_peu" })
        end
        return fx
    end

    return Engine
end
