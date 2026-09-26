-- Designations et depouillement du loup-garou. Pur : ne sait pas ce qu'est
-- une nuit, seulement compter. Chacun peut changer d'avis jusqu'au terme.

return function()
    local V = {}

    function V.nouveau() return { choix = {} } end

    function V.designer(b, votant, cible) b.choix[votant] = cible end

    -- { [cible] = nombre de voix } ; poids : { [votant] = voix } (le maire : 2).
    function V.compte(b, poids)
        local c = {}
        for votant, cible in pairs(b.choix) do
            c[cible] = (c[cible] or 0) + ((poids and poids[votant]) or 1)
        end
        return c
    end

    function V.choix(b, votant) return b.choix[votant] end

    function V.votants(b)
        local n = 0
        for _ in pairs(b.choix) do n = n + 1 end
        return n
    end

    -- La cible la plus designee. Egalite : departage (le choix du maire), s'il
    -- est parmi les ex aequo ; sinon "aucun" rend nil (le village n'a pas
    -- tranche), "hasard" tire parmi les ex aequo (les loups doivent tuer).
    function V.depouiller(b, regle, rng, poids, departage)
        local c = V.compte(b, poids)
        local max, tete = 0, {}
        for cible, n in pairs(c) do
            if n > max then max, tete = n, { cible } elseif n == max then tete[#tete + 1] = cible end
        end
        if max == 0 then return nil end
        if #tete == 1 then return tete[1] end
        for _, cible in ipairs(tete) do
            if cible == departage then return cible end
        end
        if regle ~= "hasard" then return nil end
        table.sort(tete)
        return tete[rng(#tete)]
    end

    return V
end
