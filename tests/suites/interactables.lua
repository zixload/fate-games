return function(H, Stubs)
    local make_interactables = Package.Require("domain/interactables.lua")
    local make_intents       = Package.Require("intents/init.lua")
    local make_log           = Package.Require("core/log.lua")

    -- Faux module de personnages : seul SessionByPlayer est utilise ici.
    local function fake_characters(session)
        return {
            SessionByPlayer = function() return session end,
        }
    end

    -- Session avec un personnage place a l'origine.
    local function session_at(x, y, z)
        return {
            character = {
                GetLocation = function() return { X = x, Y = y, Z = z } end,
            },
        }
    end

    local function build(c, session)
        local Log     = make_log({ log = { min_level = "DEBUG" } })
        local Intents = make_intents(Log)
        local I       = make_interactables(Log, Intents, fake_characters(session), {
            interaction = { max_distance = 250 },
        })
        return I, Intents
    end

    local function fire_interact(c, player, target)
        c.fire_remote("zix:intent", player, "interact", { target = target })
    end

    local function last_result(c)
        return c.last_sent("zix:intent_result")
    end

    H.describe("domain/interactables", function()

        H.it("enregistre un acteur et previent les clients", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            local id = I.Register(Stubs.actor(31, 100, 0, 0), {
                label = "Examiner",
                on_interact = function() end,
            })

            H.assert_eq(id, 31, "identifiant rendu")
            H.assert_eq(I.Count(), 1, "une entree au registre")
            H.assert_eq(#c.events.broadcast, 1, "une diffusion")
            H.assert_eq(c.events.broadcast[1].name, "zix:interactable_added", "evenement diffuse")
            H.assert_eq(c.events.broadcast[1].args[1].label, "Examiner", "libelle transmis")
        end)

        H.it("refuse un enregistrement sans on_interact", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            H.assert_error(function()
                I.Register(Stubs.actor(1, 0, 0, 0), { label = "Vide" })
            end, "on_interact est requis")
        end)

        H.it("declenche l'action quand le joueur est a portee", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            local touched = false
            I.Register(Stubs.actor(31, 100, 0, 0), {
                label = "Examiner",
                on_interact = function() touched = true end,
            })

            fire_interact(c, Stubs.player(1), 31)

            H.assert_true(touched, "on_interact appele")
            H.assert_true(last_result(c).args[2], "intention acceptee")
            H.assert_eq(c.count_lines("action=interact"), 1, "ligne d'audit")
        end)

        H.it("refuse au-dela de la portee, meme si le client insiste", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            local touched = false
            I.Register(Stubs.actor(31, 5000, 0, 0), {
                label = "Examiner",
                on_interact = function() touched = true end,
            })

            fire_interact(c, Stubs.player(1), 31)

            H.assert_false(touched, "on_interact ne doit pas etre appele")
            local sent = last_result(c)
            H.assert_false(sent.args[2], "intention refusee")
            H.assert_eq(sent.args[3], "trop_loin", "motif du refus")
        end)

        H.it("respecte une portee propre a l'objet", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            local touched = false
            I.Register(Stubs.actor(31, 900, 0, 0), {
                label = "Crier dessus",
                max_distance = 1000,
                on_interact = function() touched = true end,
            })

            fire_interact(c, Stubs.player(1), 31)

            H.assert_true(touched, "portee elargie respectee")
        end)

        H.it("refuse une cible inconnue", function()
            local c = Stubs.reset()
            build(c, session_at(0, 0, 0))

            fire_interact(c, Stubs.player(1), 999)

            H.assert_eq(last_result(c).args[3], "cible_inconnue", "motif du refus")
        end)

        H.it("refuse un joueur qui n'est pas en jeu", function()
            local c = Stubs.reset()
            local I = build(c, nil)

            I.Register(Stubs.actor(31, 0, 0, 0), {
                label = "Examiner",
                on_interact = function() end,
            })

            fire_interact(c, Stubs.player(1), 31)

            H.assert_eq(last_result(c).args[3], "pas_en_jeu", "motif du refus")
        end)

        H.it("honore une validation propre a l'objet", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            local touched = false
            I.Register(Stubs.actor(31, 0, 0, 0), {
                label = "Porte verrouillee",
                validate = function() return false, "verrouille" end,
                on_interact = function() touched = true end,
            })

            fire_interact(c, Stubs.player(1), 31)

            H.assert_false(touched, "action bloquee par la validation")
            H.assert_eq(last_result(c).args[3], "verrouille", "motif remonte")
        end)

        H.it("survit a une action qui plante", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            I.Register(Stubs.actor(31, 0, 0, 0), {
                label = "Piege",
                on_interact = function() error("boum") end,
            })

            fire_interact(c, Stubs.player(1), 31)

            H.assert_eq(c.count_lines("on_interact en echec"), 1, "echec journalise")
            H.assert_false(last_result(c).args[2], "intention rapportee comme echouee")
        end)

        H.it("retire du registre et previent les clients", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            I.Register(Stubs.actor(31, 0, 0, 0), { on_interact = function() end })
            H.assert_true(I.Unregister(31), "retrait effectif")
            H.assert_eq(I.Count(), 0, "registre vide")
            H.assert_eq(I.Get(31), nil, "entree disparue")

            local removal = c.events.broadcast[#c.events.broadcast]
            H.assert_eq(removal.name, "zix:interactable_removed", "diffusion du retrait")
            H.assert_eq(removal.args[1], 31, "identifiant diffuse")

            fire_interact(c, Stubs.player(1), 31)
            H.assert_eq(last_result(c).args[3], "cible_inconnue", "plus interactif")
        end)

        H.it("ignore le retrait d'une entree inexistante", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            H.assert_false(I.Unregister(999), "retrait sans effet")
        end)

        H.it("envoie l'etat complet a un joueur qui arrive", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            I.Register(Stubs.actor(1, 0, 0, 0), { label = "A", on_interact = function() end })
            I.Register(Stubs.actor(2, 0, 0, 0), { label = "B", on_interact = function() end })

            I.SendSnapshotTo(Stubs.player(9))

            local sent = c.last_sent("zix:interactables_full")
            H.assert_true(sent ~= nil, "instantane envoye")
            H.assert_eq(#sent.args[1], 2, "deux entrees transmises")
        end)

        H.it("ne transmet pas les fonctions au client", function()
            local c = Stubs.reset()
            local I = build(c, session_at(0, 0, 0))

            I.Register(Stubs.actor(1, 0, 0, 0), {
                label = "A",
                validate = function() return true end,
                on_interact = function() end,
            })

            -- La copie envoyee au client ne doit porter que de l'affichage.
            local entry = I.Snapshot()[1]
            H.assert_nil(entry.on_interact, "pas de fonction dans l'instantane")
            H.assert_nil(entry.validate, "pas de validation dans l'instantane")
            H.assert_nil(entry.actor, "pas de reference d'acteur dans l'instantane")
        end)
    end)
end
