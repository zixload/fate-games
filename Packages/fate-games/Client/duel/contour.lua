-- Contour au sol des arenes de duel : des bandes laiton en decalques,
-- projetees de haut en bas pour epouser le terrain (dunes, marches). Decal
-- n'existe que chez le client (doc Decal) : le serveur envoie seulement la
-- forme des arenes ("duel:arenes").

return function(reglage)
    reglage = reglage or {}
    local decalques = {}

    local function effacer()
        for _, d in ipairs(decalques) do
            if d and d:IsValid() then d:Destroy() end
        end
        decalques = {}
    end

    local function monde(A, lx, ly)
        local a = math.rad(A.yaw)
        return A.x + lx * math.cos(a) - ly * math.sin(a), A.y + lx * math.sin(a) + ly * math.cos(a)
    end

    -- Points du bord, dans le repere de l'arene.
    local function bord(A)
        local pas = reglage.pas or 180
        local points = {}
        if A.forme == "cercle" then
            local n = math.max(16, math.floor(2 * math.pi * A.demi_x / pas))
            for k = 0, n do
                local ang = k / n * 2 * math.pi
                points[#points + 1] = { math.cos(ang) * A.demi_x, math.sin(ang) * A.demi_x }
            end
        else
            local coins = { { A.demi_x, A.demi_y }, { -A.demi_x, A.demi_y }, { -A.demi_x, -A.demi_y },
                { A.demi_x, -A.demi_y }, { A.demi_x, A.demi_y } }
            for k = 1, 4 do
                local a, b = coins[k], coins[k + 1]
                local n = math.max(1, math.floor(math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) / pas))
                for m = 0, n - 1 do
                    points[#points + 1] = { a[1] + (b[1] - a[1]) * m / n, a[2] + (b[2] - a[2]) * m / n }
                end
            end
            points[#points + 1] = coins[1]
        end
        return points
    end

    local function dessiner(A)
        local points = bord(A)
        local c = reglage.couleur or { r = 0.72, g = 0.52, b = 0.16 }
        for k = 1, #points - 1 do
            local a, b = points[k], points[k + 1]
            local x, y = monde(A, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
            local longueur = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
            local cap = A.yaw + math.deg(math.atan(b[2] - a[2], b[1] - a[1]))
            -- Tangage -90 : l'axe de projection du decalque pointe vers le sol.
            local d = Decal(Vector(x, y, A.z + (reglage.hauteur or 250)), Rotator(-90, cap, 0),
                reglage.materiau or "nanos-world::M_Default_Translucent_Lit_Decal",
                Vector(reglage.profondeur or 600, (reglage.largeur or 14) / 2, longueur * 0.42),
                reglage.duree or 86400)
            pcall(function() d:SetMaterialColorParameter("Tint", Color(c.r, c.g, c.b)) end)
            decalques[#decalques + 1] = d
        end
    end

    Events.SubscribeRemote("duel:arenes", function(liste)
        local ok, err = pcall(function()
            effacer()
            for _, A in ipairs(liste or {}) do dessiner(A) end
        end)
        if not ok then Console.Error("[duel] contour impossible : " .. tostring(err)) end
    end)

    Package.Subscribe("Unload", effacer)
end
