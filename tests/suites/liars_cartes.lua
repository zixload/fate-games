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

        H.it("choisit l'image de chaque carte dans le pack", function()
            H.assert_eq(Cartes.Image("king", 3), "assets://my-asset-pack/HUD/Cartes/King_of_Hearts.jpg", "roi")
            H.assert_eq(Cartes.Image("queen", 1), "assets://my-asset-pack/HUD/Cartes/Queen_of_Clubs.jpg", "dame")
            H.assert_eq(Cartes.Image("joker", 2), "assets://my-asset-pack/HUD/Cartes/Jack_of_Spades.jpg", "joker")
            H.assert_eq(Cartes.Image(nil, 1), "assets://my-asset-pack/HUD/Cartes/Card_Back.jpg", "inconnue")
        end)

        H.it("ouvre la main a l'ecran en arc symetrique", function()
            local hud = { largeur = 100, ecart = 0.6, angle = 6, courbure = 20 }
            local milieu = Cartes.Main2D(5, 3, hud)
            H.assert_true(proche(milieu.x, 0) and proche(milieu.y, 0) and proche(milieu.angle, 0), "milieu droit")
            local g, d = Cartes.Main2D(5, 1, hud), Cartes.Main2D(5, 5, hud)
            H.assert_true(proche(g.x, -120) and proche(d.x, 120), "ecart")
            H.assert_true(proche(g.angle, -12) and proche(d.angle, 12), "angles opposes")
            H.assert_true(proche(g.y, 20) and proche(d.y, 20), "bords plus bas")
            local seule = Cartes.Main2D(1, 1, hud)
            H.assert_true(proche(seule.x, 0) and proche(seule.angle, 0), "une seule carte au centre")
        end)

        H.it("tire une couleur valide par carte", function()
            local couleurs = Cartes.Couleurs(5, function(n) return n end)
            H.assert_eq(#couleurs, 5, "nombre")
            for _, c in ipairs(couleurs) do H.assert_true(c >= 1 and c <= 4, "couleur") end
        end)

        H.it("centre la carte du milieu de l'eventail", function()
            local f = Cartes.Fente(5, 3, cfg.fan, 0)
            H.assert_true(proche(f.x, 0), "a l'origine du support")
            H.assert_true(proche(f.y, 0), "au milieu")
            H.assert_true(proche(f.yaw, 0), "droite")
        end)

        H.it("ouvre l'eventail symetriquement", function()
            local g = Cartes.Fente(5, 1, cfg.fan, 0)
            local d = Cartes.Fente(5, 5, cfg.fan, 0)
            H.assert_true(proche(g.y, -d.y), "de part et d'autre de l'axe")
            H.assert_true(proche(g.x, d.x), "a la meme distance du pivot")
            H.assert_true(proche(g.yaw, -d.yaw), "angles opposes")
            H.assert_true(g.z < d.z, "empilees dans l'ordre, le long de la face")
        end)

        H.it("souleve une carte le long de son axe", function()
            local bas  = Cartes.Fente(3, 2, cfg.fan, 0)
            local haut = Cartes.Fente(3, 2, cfg.fan, 5)
            H.assert_true(proche(haut.x - bas.x, 5), "levee, loin du pivot")
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
