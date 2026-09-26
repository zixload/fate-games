-- Designations et depouillement du loup-garou. Pur : ne sait pas ce qu'est
-- une nuit, seulement compter. Chacun peut changer d'avis jusqu'au terme.

return function()
    local V = {}

    function V.nouveau() return { choix = {} } end

    function V.designer(b, votant, cible) b.choix[votant] = cible end

    -- { [cible] = nombre de voix }
    function V.compte(b)
        local c = {}
        for _, cible in pairs(b.choix) do c[cible] = (c[cible] or 0) + 1 end
        return c
    end

    function V.votants(b)
        local n = 0
        for _ in pairs(b.choix) do n = n + 1 end
        return n
    end

    -- La cible la plus designee. Egalite : "aucun" rend nil (le village n'a
    -- pas tranche), "hasard" tire parmi les ex aequo (les loups doivent tuer).
    function V.depouiller(b, regle, rng)
        local c = V.compte(b)
        local max, tete = 0, {}
        for cible, n in pairs(c) do
            if n > max then max, tete = n, { cible } elseif n == max then tete[#tete + 1] = cible end
        end
        if max == 0 then return nil end
        if #tete == 1 then return tete[1] end
        if regle ~= "hasard" then return nil end
        table.sort(tete)
        return tete[rng(#tete)]
    end

    return V
end
