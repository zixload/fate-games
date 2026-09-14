return function(H, Stubs)
    local make_intents = Package.Require("intents/init.lua")
    local make_log     = Package.Require("core/log.lua")

    -- Attention a l'ordre : la fabrique s'abonne a "zix:intent" des sa construction,
    -- donc les bouchons doivent etre remis a zero avant.
    local function new()
        local Log = make_log({ log = { min_level = "DEBUG" } })
        return make_intents(Log)
    end

    local function last_result(c)
        return c.last_sent("zix:intent_result")
    end

    H.describe("intents", function()

        H.it("refuse une intention inconnue sans planter", function()
            local c = Stubs.reset()
            new()

            c.fire_remote("zix:intent", Stubs.player(1), "inexistante", {})

            local sent = last_result(c)
            H.assert_true(sent ~= nil, "une reponse a ete envoyee")
            H.assert_eq(sent.args[1], "inexistante", "nom de l'intention")
            H.assert_false(sent.args[2], "intention refusee")
            H.assert_eq(sent.args[3], "unknown_intent", "motif du refus")
            H.assert_eq(c.count_lines("intention inconnue"), 1, "refus journalise")
        end)

        H.it("n'applique pas une intention dont la validation echoue", function()
            local c = Stubs.reset()
            local I = new()

            local applied = false
            I.Register("achat", {
                validate = function() return false, "trop_loin" end,
                apply    = function() applied = true; return true, {} end,
            })

            c.fire_remote("zix:intent", Stubs.player(1), "achat", {})

            H.assert_false(applied, "apply ne doit pas etre appele")
            local sent = last_result(c)
            H.assert_false(sent.args[2], "intention refusee")
            H.assert_eq(sent.args[3], "trop_loin", "motif du refus")
        end)

        H.it("applique, audite et repond sur le chemin nominal", function()
            local c = Stubs.reset()
            local I = new()

            local seen_payload = nil
            local seen_cid     = nil

            I.Register("achat", {
                validate = function() return true end,
                apply    = function(player, payload, cid)
                    seen_payload = payload
                    seen_cid     = cid
                    return true, { target = "objet-23", position = "0,0,0", audit = "prix=50" }
                end,
            })

            c.fire_remote("zix:intent", Stubs.player(7), "achat", { item = 23 })

            H.assert_true(seen_payload ~= nil, "payload transmis a apply")
            H.assert_eq(seen_payload.item, 23, "contenu du payload")
            H.assert_true(seen_cid ~= nil, "identifiant de correlation transmis")

            H.assert_eq(c.count_lines("action=achat"), 1, "ligne d'audit")
            H.assert_eq(c.count_lines("actor=7"), 1, "acteur audite")
            H.assert_eq(c.count_lines("target=objet-23"), 1, "cible auditee")

            local sent = last_result(c)
            H.assert_true(sent.args[2], "intention acceptee")
        end)

        H.it("capture une exception dans apply au lieu d'emporter le serveur", function()
            local c = Stubs.reset()
            local I = new()

            I.Register("casse", {
                validate = function() return true end,
                apply    = function() error("boum") end,
            })

            -- Ne doit pas remonter jusqu'a l'appelant.
            c.fire_remote("zix:intent", Stubs.player(1), "casse", {})

            H.assert_eq(c.count_lines("exception sur casse"), 1, "exception journalisee")
        end)

        H.it("signale une intention enregistree deux fois", function()
            local c = Stubs.reset()
            local I = new()

            local spec = { validate = function() return true end, apply = function() return true, {} end }
            I.Register("achat", spec)
            I.Register("achat", spec)

            H.assert_eq(c.count_lines("intention redefinie"), 1, "redefinition signalee")
        end)

        H.it("donne un identifiant de correlation different a chaque intention", function()
            local c = Stubs.reset()
            local I = new()

            local ids = {}
            I.Register("ping", {
                validate = function() return true end,
                apply    = function(_, _, cid) ids[#ids + 1] = cid; return true, {} end,
            })

            c.fire_remote("zix:intent", Stubs.player(1), "ping", {})
            c.fire_remote("zix:intent", Stubs.player(1), "ping", {})

            H.assert_eq(#ids, 2, "deux intentions traitees")
            H.assert_true(ids[1] ~= ids[2], "identifiants distincts")
        end)
    end)
end
