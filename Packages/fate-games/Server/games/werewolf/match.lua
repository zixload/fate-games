-- Etat d'une partie de loup-garou : qui joue, quel role, qui vit, qui s'aime.
-- Pur ; l'aleatoire est injecte (rng(k) rend un entier de 1 a k).

return function(Roles)
    local M = {}

    local function copie(t)
        local c = {}
        for k, v in pairs(t) do c[k] = v end
        return c
    end

    -- Une composition est-elle jouable a n joueurs ? Rend ok, raison.
    function M.valider(compo, n)
        if n < Roles.MIN_JOUEURS then return false, "pas_assez_de_joueurs" end
        if n > Roles.MAX_JOUEURS then return false, "trop_de_joueurs" end
        local speciaux, loups = 0, 0
        for _, role in ipairs(Roles.speciaux) do
            local k = compo[role] or 0
            local b = Roles.bornes[role]
            if k < b[1] or k > b[2] then return false, "reglage_hors_bornes" end
            speciaux = speciaux + k
            if Roles.roles[role].loup then loups = loups + k end
        end
        if loups < 1 then return false, "aucun_loup" end
        if speciaux > n then return false, "trop_de_roles" end
        -- Des le depart autant de loups que d'autres : la partie serait jouee.
        if loups >= n - loups then return false, "trop_de_loups" end
        return true
    end

    -- Tire un role par joueur : les roles speciaux, les villageois pour le
    -- reste, melanges (Fisher-Yates). Rend { [id] = role }.
    function M.tirer(ids, compo, rng)
        local paquet = {}
        for _, role in ipairs(Roles.speciaux) do
            for _ = 1, compo[role] or 0 do paquet[#paquet + 1] = role end
        end
        while #paquet < #ids do paquet[#paquet + 1] = "villager" end
        for i = #paquet, 2, -1 do
            local j = rng(i)
            paquet[i], paquet[j] = paquet[j], paquet[i]
        end
        local roles = {}
        for i, id in ipairs(ids) do roles[id] = paquet[i] end
        return roles
    end

    function M.nouveau(ids, roles)
        local s = { ordre = copie(ids), joueurs = {}, amoureux = nil }
        for _, id in ipairs(ids) do s.joueurs[id] = { role = roles[id], vivant = true } end
        return s
    end

    function M.role(s, id) return s.joueurs[id] and s.joueurs[id].role end
    function M.vivant(s, id) return s.joueurs[id] ~= nil and s.joueurs[id].vivant end
    function M.est_loup(s, id)
        local r = M.role(s, id)
        return r ~= nil and Roles.roles[r].loup == true
    end

    -- Les vivants, dans l'ordre d'arrivee.
    function M.vivants(s)
        local out = {}
        for _, id in ipairs(s.ordre) do
            if s.joueurs[id].vivant then out[#out + 1] = id end
        end
        return out
    end

    function M.loups_vivants(s)
        local out = {}
        for _, id in ipairs(M.vivants(s)) do
            if M.est_loup(s, id) then out[#out + 1] = id end
        end
        return out
    end

    -- Le premier vivant qui tient ce role, ou nil.
    function M.porteur(s, role)
        for _, id in ipairs(M.vivants(s)) do
            if s.joueurs[id].role == role then return id end
        end
    end

    -- Rend vrai si le joueur vivait.
    function M.tuer(s, id)
        local j = s.joueurs[id]
        if not (j and j.vivant) then return false end
        j.vivant = false
        return true
    end

    function M.partenaire(s, id)
        local a = s.amoureux
        if not a then return nil end
        if a[1] == id then return a[2] end
        if a[2] == id then return a[1] end
    end

    return M
end
