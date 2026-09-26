-- Regles du duel, sans rien du moteur : un etat, des fonctions qui le font
-- avancer et disent ce qui s'est passe. Le branchement au monde (zone,
-- armes, sante, argent) vit dans adapter.lua.
--
-- Phases : "vide" -> "attente" -> "decompte" -> "combat" -> "entre_manches"
-- -> "combat" ... -> "fin". Camps numerotes 1 et 2.

return function(config)
    local Duel = {}

    local function contient(liste, valeur)
        for _, v in ipairs(liste) do if v == valeur then return true end end
        return false
    end

    function Duel.Nouveau()
        return {
            phase    = "vide",
            joueurs  = {},     -- id -> { camp, pret, vivant, parti }
            ordre    = {},     -- ids dans l'ordre d'arrivee
            format   = config.formats[1],
            mise     = config.paliers[1],
            createur = nil,
            scores   = { 0, 0 },
            manche   = 0,
        }
    end

    function Duel.Capacite(d) return 2 * d.format end

    function Duel.Effectif(d) return #d.ordre end

    function Duel.Membres(d, camp)
        local ids = {}
        for _, id in ipairs(d.ordre) do
            if d.joueurs[id].camp == camp then ids[#ids + 1] = id end
        end
        return ids
    end

    local function camp_libre(d)
        local n1, n2 = #Duel.Membres(d, 1), #Duel.Membres(d, 2)
        return n2 < n1 and 2 or 1
    end

    function Duel.Entrer(d, id)
        if d.joueurs[id] then return false, "deja" end
        if d.phase ~= "vide" and d.phase ~= "attente" then return false, "en_cours" end
        if Duel.Effectif(d) >= Duel.Capacite(d) then return false, "complet" end
        if d.phase == "vide" then
            d.phase = "attente"
            d.createur = id
        end
        d.joueurs[id] = { camp = camp_libre(d), pret = false, vivant = true }
        d.ordre[#d.ordre + 1] = id
        return true
    end

    -- Format et mise : le createur seul, pendant l'attente. Changer de regles
    -- remet tout le monde en "pas pret".
    function Duel.Choisir(d, id, format, mise)
        if d.phase ~= "attente" then return false, "en_cours" end
        if id ~= d.createur then return false, "pas_createur" end
        if not contient(config.formats, format) then return false, "format" end
        if not contient(config.paliers, mise) then return false, "mise" end
        if 2 * format < Duel.Effectif(d) then return false, "trop_nombreux" end
        d.format, d.mise = format, mise
        for _, j in pairs(d.joueurs) do j.pret = false end
        return true
    end

    function Duel.Pret(d, id, pret)
        local j = d.joueurs[id]
        if not j then return false, "absent" end
        if d.phase ~= "attente" then return false, "en_cours" end
        j.pret = pret == true
        return true
    end

    function Duel.ToutPret(d)
        if d.phase ~= "attente" or Duel.Effectif(d) < Duel.Capacite(d) then return false end
        for _, id in ipairs(d.ordre) do
            if not d.joueurs[id].pret then return false end
        end
        return true
    end

    function Duel.Lancer(d)
        d.phase = "decompte"
        d.scores = { 0, 0 }
        d.manche = 0
    end

    -- Depart refuse (mise impossible) : retour a l'attente, personne pret.
    function Duel.Annuler(d)
        d.phase = "attente"
        for _, j in pairs(d.joueurs) do j.pret = false end
    end

    function Duel.DebutManche(d)
        d.phase = "combat"
        d.manche = d.manche + 1
        for _, j in pairs(d.joueurs) do j.vivant = not j.parti end
    end

    function Duel.PeutToucher(d, tireur, cible)
        if d.phase ~= "combat" then return false, "pas_en_combat" end
        local a, b = d.joueurs[tireur], d.joueurs[cible]
        if not (a and b) then return false, "hors_duel" end
        if not (a.vivant and b.vivant) then return false, "mort" end
        if a.camp == b.camp then return false, "meme_camp" end
        return true
    end

    local function camp_vivant(d, camp)
        for _, id in ipairs(Duel.Membres(d, camp)) do
            if d.joueurs[id].vivant then return true end
        end
        return false
    end

    local function camp_present(d, camp)
        for _, id in ipairs(Duel.Membres(d, camp)) do
            if not d.joueurs[id].parti then return true end
        end
        return false
    end

    local function terminer(d, gagnant)
        d.phase = "fin"
        return { fin = true, gagnant = gagnant }
    end

    -- Verifie si la manche ou le duel est joue. nil si rien ne change.
    local function bilan(d)
        for camp = 1, 2 do
            if not camp_present(d, camp) then return terminer(d, 3 - camp) end
        end
        for camp = 1, 2 do
            if not camp_vivant(d, camp) then
                local gagnant = 3 - camp
                d.scores[gagnant] = d.scores[gagnant] + 1
                if d.scores[gagnant] >= config.manches_gagnantes then
                    return terminer(d, gagnant)
                end
                d.phase = "entre_manches"
                return { manche = true, gagnant = gagnant }
            end
        end
        return nil
    end

    function Duel.Mort(d, id)
        local j = d.joueurs[id]
        if not j or d.phase ~= "combat" or not j.vivant then return nil end
        j.vivant = false
        return bilan(d)
    end

    -- Depart d'un joueur. En attente, il libere sa place (et la main passe au
    -- suivant s'il etait createur). En cours, il abandonne : sa mise reste
    -- dans la cagnotte et son camp perd s'il n'y reste plus personne.
    function Duel.Quitter(d, id)
        local j = d.joueurs[id]
        if not j then return nil end
        if d.phase == "attente" then
            d.joueurs[id] = nil
            for i, v in ipairs(d.ordre) do
                if v == id then table.remove(d.ordre, i) break end
            end
            if #d.ordre == 0 then
                local neuf = Duel.Nouveau()
                for k, v in pairs(neuf) do d[k] = v end
            elseif d.createur == id then
                d.createur = d.ordre[1]
            end
            return nil
        end
        if d.phase == "fin" then return nil end
        j.parti, j.vivant = true, false
        if d.phase == "combat" then return bilan(d) end
        -- Hors combat (decompte, entre deux manches), un depart ne marque pas
        -- de manche : seul l'abandon d'un camp entier termine le duel.
        for camp = 1, 2 do
            if not camp_present(d, camp) then return terminer(d, 3 - camp) end
        end
        return nil
    end

    return Duel
end
