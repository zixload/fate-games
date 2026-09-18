return function(H, Stubs)
    local SharedConfig = Package.Require("Shared/config.lua")
    local cfg          = SharedConfig.liars_cards
    local Cartes       = Package.Require("liars_bar/cartes.lua")(cfg)

    local function proche(a, b) return math.abs(a - b) < 1e-6 end

    H.describe("liars_bar/cartes", function()
        H.it("choisit le modele de chaque valeur et couleur", function()
            H.assert_eq(Cartes.Mesh("king", 3), "my-asset-pack::King_of_Hearts1", "roi")
            H.assert_eq(Cartes.Mesh("queen", 1), "my-asset-pack::Queen_of_Clubs1", "dame")
            H.assert_eq(Cartes.Mesh("ace", 4), "my-asset-pack::Ace_of_Spades1", "as")
        end)

        H.it("remplace le Joker par le Valet", function()
            H.assert_eq(Cartes.Mesh("joker", 2), cfg.joker_mesh, "joker")
        end)

        H.it("montre un dos pour une valeur inconnue", function()
            H.assert_eq(Cartes.Mesh(nil, 1), cfg.back_mesh, "inconnue")
        end)

        H.it("tire une couleur valide par carte", function()
            local couleurs = Cartes.Couleurs(5, function(n) return n end)
            H.assert_eq(#couleurs, 5, "nombre")
            for _, c in ipairs(couleurs) do H.assert_true(c >= 1 and c <= 4, "couleur") end
        end)

        H.it("centre la carte du milieu de l'eventail", function()
            local f = Cartes.Fente(5, 3, cfg.fan, 0)
            H.assert_true(proche(f.x, 0), "x au centre")
            H.assert_true(proche(f.z, 0), "z au centre")
            H.assert_true(proche(f.pitch, 0), "droite")
        end)

        H.it("ouvre l'eventail symetriquement", function()
            local g = Cartes.Fente(5, 1, cfg.fan, 0)
            local d = Cartes.Fente(5, 5, cfg.fan, 0)
            H.assert_true(proche(g.x, -d.x), "x symetriques")
            H.assert_true(proche(g.z, d.z), "meme hauteur")
            H.assert_true(proche(g.pitch, -d.pitch), "angles opposes")
            H.assert_true(g.y < d.y, "les cartes se chevauchent dans l'ordre")
        end)

        H.it("souleve une carte le long de son axe", function()
            local bas  = Cartes.Fente(3, 2, cfg.fan, 0)
            local haut = Cartes.Fente(3, 2, cfg.fan, 5)
            H.assert_true(proche(haut.z - bas.z, 5), "levee")
        end)

        H.it("empile le tas du centre", function()
            local a = Cartes.Tas(1, cfg.table)
            local b = Cartes.Tas(2, cfg.table)
            H.assert_true(b.z > a.z, "chaque carte au-dessus de la precedente")
            local a2 = Cartes.Tas(1, cfg.table)
            H.assert_true(proche(a.x, a2.x) and proche(a.yaw, a2.yaw), "le meme desordre chez tous")
        end)

        H.it("aligne les cartes revelees", function()
            local g = Cartes.Revelee(3, 1, cfg.table)
            local m = Cartes.Revelee(3, 2, cfg.table)
            local d = Cartes.Revelee(3, 3, cfg.table)
            H.assert_true(proche(m.y - g.y, d.y - m.y), "ecart regulier")
            H.assert_true(proche(g.x, d.x), "sur une ligne")
        end)
    end)
end
