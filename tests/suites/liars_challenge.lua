return function(H, Stubs)
    local config         = Package.Require("games/liars_bar/data/config.lua")
    local make_deck      = Package.Require("games/liars_bar/data/deck.lua")
    local make_challenge = Package.Require("games/liars_bar/challenge.lua")

    local function build()
        local Deck = make_deck(config)
        return make_challenge(Deck)
    end

    H.describe("liars_bar/challenge", function()

        H.it("condamne l'accusateur quand la pose etait vraie", function()
            local C = build()
            H.assert_eq(C.Resolve({ "king", "king" }, "king"), "accuser", "deux vrais rois")
        end)

        H.it("condamne le menteur des qu'une carte est intruse", function()
            local C = build()
            H.assert_eq(C.Resolve({ "king", "queen" }, "king"), "liar", "un roi et une dame")
        end)

        H.it("accepte le joker comme carte conforme", function()
            local C = build()
            H.assert_eq(C.Resolve({ "king", "joker" }, "king"), "accuser", "roi et joker")
            H.assert_eq(C.Resolve({ "joker", "joker" }, "ace"), "accuser", "deux jokers")
        end)

        H.it("juge une pose d'une seule carte", function()
            local C = build()
            H.assert_eq(C.Resolve({ "ace" }, "ace"),   "accuser", "un vrai as")
            H.assert_eq(C.Resolve({ "king" }, "ace"),  "liar",    "un roi annonce comme as")
        end)

        H.it("juge une pose de trois cartes", function()
            local C = build()
            H.assert_eq(C.Resolve({ "queen", "queen", "joker" }, "queen"), "accuser", "trois conformes")
            H.assert_eq(C.Resolve({ "queen", "queen", "ace" },   "queen"), "liar",    "une intruse sur trois")
        end)

        H.it("condamne le menteur meme si l'intruse est la derniere", function()
            local C = build()
            H.assert_eq(C.Resolve({ "king", "king", "ace" }, "king"), "liar", "intruse en fin de pose")
        end)

        H.it("refuse de juger une pose vide", function()
            local C = build()
            H.assert_error(function() C.Resolve({}, "king") end, "pose vide")
        end)
    end)
end
