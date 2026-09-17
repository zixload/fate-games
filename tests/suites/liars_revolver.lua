return function(H, Stubs)
    local config        = Package.Require("games/liars_bar/data/config.lua")
    local make_revolver = Package.Require("games/liars_bar/revolver.lua")

    local function rng_fixe(v) return function(_) return v end end

    H.describe("liars_bar/revolver", function()

        H.it("cree un barillet avec la balle a la position tiree", function()
            local R = make_revolver(config)
            local rev = R.New(rng_fixe(4))

            H.assert_eq(rev.bullet, 4, "position de la balle")
            H.assert_eq(rev.fired, 0, "aucun tir")
            H.assert_eq(rev.chambers, 6, "chambres")
        end)

        H.it("fait clic avant la balle", function()
            local R = make_revolver(config)
            local rev = R.New(rng_fixe(3))

            local fatal, chamber = R.Pull(rev)
            H.assert_false(fatal, "premier tir")
            H.assert_eq(chamber, 1, "chambre tiree")

            fatal, chamber = R.Pull(rev)
            H.assert_false(fatal, "deuxieme tir")
            H.assert_eq(chamber, 2, "chambre tiree")
        end)

        H.it("part sur la chambre de la balle", function()
            local R = make_revolver(config)
            local rev = R.New(rng_fixe(3))

            R.Pull(rev)
            R.Pull(rev)
            local fatal, chamber = R.Pull(rev)

            H.assert_true(fatal, "troisieme tir fatal")
            H.assert_eq(chamber, 3, "chambre de la balle")
        end)

        H.it("tue a coup sur au sixieme tir si la balle y est", function()
            local R = make_revolver(config)
            local rev = R.New(rng_fixe(6))

            for i = 1, 5 do
                local fatal = R.Pull(rev)
                H.assert_false(fatal, "tir " .. i .. " doit etre un clic")
            end
            H.assert_true(R.Pull(rev), "sixieme tir fatal")
        end)

        H.it("ne peut pas survivre a six tirs, quelle que soit la balle", function()
            local R = make_revolver(config)
            for position = 1, 6 do
                local rev = R.New(rng_fixe(position))
                local mort = false
                for _ = 1, 6 do
                    if R.Pull(rev) then mort = true end
                end
                H.assert_true(mort, "balle en position " .. position)
            end
        end)

        H.it("decompte les chambres restantes", function()
            local R = make_revolver(config)
            local rev = R.New(rng_fixe(6))

            H.assert_eq(R.Remaining(rev), 6, "au depart")
            R.Pull(rev)
            H.assert_eq(R.Remaining(rev), 5, "apres un tir")
            R.Pull(rev)
            H.assert_eq(R.Remaining(rev), 4, "apres deux tirs")
        end)

        H.it("refuse de tirer un barillet epuise", function()
            local R = make_revolver(config)
            local rev = R.New(rng_fixe(1))
            rev.fired = 6

            H.assert_error(function() R.Pull(rev) end, "barillet epuise")
        end)
    end)
end
