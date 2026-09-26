-- Salon de Liar's Bar : l'attente entre le moment ou l'on s'assoit et le
-- lancement, comme celle du duel. Chacun se dit pret, le premier humain
-- arrive choisit la mise ; quand tous les assis sont prets (et assez
-- nombreux), la partie part.
--
-- Pur : aucune globale nanos. Les places ne sont pas gardees ici : elles se
-- lisent a chaque appel dans la liste des assis de l'adaptateur,
-- { { chair, nom, bot } } dans l'ordre d'arrivee. Le salon ne tient que ce
-- qui n'y est pas : qui est pret, la mise, qui la choisit.

return function(config)
    local Salon = {}

    local function contient(liste, v)
        for _, x in ipairs(liste) do if x == v then return true end end
        return false
    end

    local function place(assis, chair)
        for _, a in ipairs(assis) do
            if a.chair == chair then return a end
        end
    end

    function Salon.New()
        return { pret = {}, mise = config.paliers[1], createur = nil }
    end

    -- Remet le salon d'accord avec les assis : oublie les partis, les bots
    -- sont toujours prets, et le createur parti passe la main au plus ancien
    -- humain. Sans humain, la mise revient au premier palier.
    function Salon.Accorder(s, assis)
        for chair in pairs(s.pret) do
            if not place(assis, chair) then s.pret[chair] = nil end
        end
        for _, a in ipairs(assis) do
            if a.bot then s.pret[a.chair] = true end
        end
        local c = s.createur and place(assis, s.createur)
        if not (c and not c.bot) then
            s.createur = nil
            for _, a in ipairs(assis) do
                if not a.bot then s.createur = a.chair break end
            end
        end
        if not s.createur then s.mise = config.paliers[1] end
    end

    function Salon.Pret(s, assis, chair, oui)
        local a = place(assis, chair)
        if not a then return false, "pas_a_table" end
        if a.bot then return false, "bot" end
        s.pret[chair] = oui == true or nil
        return true
    end

    -- Seul le createur choisit, parmi les paliers. Changer la mise remet les
    -- humains en "pas pret" : ils doivent accepter la nouvelle.
    function Salon.ChoisirMise(s, assis, chair, mise)
        if chair ~= s.createur then return false, "pas_createur" end
        if not contient(config.paliers, mise) then return false, "mise" end
        s.mise = mise
        for _, a in ipairs(assis) do
            if not a.bot then s.pret[a.chair] = nil end
        end
        return true
    end

    function Salon.AvecBots(assis)
        for _, a in ipairs(assis) do
            if a.bot then return true end
        end
        return false
    end

    -- Assez de monde, au moins un humain, et tous prets.
    function Salon.ToutPret(s, assis)
        if #assis < config.min_players then return false end
        local humain = false
        for _, a in ipairs(assis) do
            if not s.pret[a.chair] then return false end
            if not a.bot then humain = true end
        end
        return humain
    end

    -- Ce qu'affiche le panneau : une ligne par chaise, dans l'ordre des chaises.
    function Salon.Vue(s, assis)
        local places = {}
        for chair = 1, config.max_seats do
            local a = place(assis, chair)
            places[chair] = a and { chair = chair, nom = a.nom, bot = a.bot or false,
                pret = s.pret[chair] == true } or { chair = chair, vide = true }
        end
        return {
            mise = Salon.AvecBots(assis) and 0 or s.mise,
            paliers = config.paliers,
            createur = s.createur,
            minimum = config.min_players,
            avec_bots = Salon.AvecBots(assis),
            places = places,
        }
    end

    return Salon
end
