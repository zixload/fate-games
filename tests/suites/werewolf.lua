return function(H)
    local Roles   = Package.Require("games/werewolf/data/roles.lua")
    local Phases  = Package.Require("games/werewolf/data/phases.lua")
    local Effects = Package.Require("games/werewolf/effects.lua")()
    local Match   = Package.Require("games/werewolf/match.lua")(Roles)
    local Voting  = Package.Require("games/werewolf/voting.lua")()
    local Outcome = Package.Require("games/werewolf/outcome.lua")(Match, Roles)
    local Engine  = Package.Require("games/werewolf/engine.lua")(Roles, Phases, Match, Voting, Outcome, Effects)

    local function premier(_) return 1 end
    local function ids(n)
        local t = {}
        for i = 1, n do t[i] = i end
        return t
    end
    local function compo(t)
        local c = { wolf = 1, white_wolf = 0, seer = 0, hunter = 0, guard = 0, cupid = 0 }
        for k, v in pairs(t or {}) do c[k] = v end
        return c
    end
    local function partie(n, c)
        local s = Engine.nouveau()
        local fx = Engine.demarrer(s, ids(n), compo(c), premier)
        return s, fx
    end
    -- Avance seconde par seconde jusqu'a la phase voulue ; rend les effets vus.
    local function jusqua(s, phase, max)
        local vus = {}
        for _ = 1, max or 600 do
            if Engine.phase(s) == phase then return vus end
            for _, e in ipairs(Engine.avancer(s, 1)) do vus[#vus + 1] = e end
        end
        error("phase jamais atteinte : " .. phase)
    end
    local function porteur(s, role)
        for id, j in pairs(s.match.joueurs) do if j.role == role then return id end end
    end
    local function villageois(s, sauf)
        for _, id in ipairs(Match.vivants(s.match)) do
            if not Match.est_loup(s.match, id) and id ~= sauf then return id end
        end
    end
    local function tues(fx)
        local out = {}
        for _, e in ipairs(fx) do if e.kind == "kill" then out[#out + 1] = e.player end end
        return out
    end

    H.describe("werewolf/composition", function()
        H.it("refuse une partie impossible, accepte la composition par defaut", function()
            H.assert_false(Match.valider(compo(), 3), "trois joueurs")
            local ok, raison = Match.valider(compo({ wolf = 2 }), 4)
            H.assert_false(ok, "deux loups a quatre")
            H.assert_eq(raison, "trop_de_loups", "raison")
            H.assert_false(Match.valider(compo({ wolf = 0 }), 6), "aucun loup")
            H.assert_true(Match.valider(Roles.par_defaut(8), 8), "defaut a huit")
        end)

        H.it("tire un role par joueur, les villageois completent", function()
            local r = Match.tirer(ids(7), compo({ wolf = 2, seer = 1, hunter = 1 }), premier)
            local n = {}
            for _, role in pairs(r) do n[role] = (n[role] or 0) + 1 end
            H.assert_eq(n.wolf, 2, "loups")
            H.assert_eq(n.seer, 1, "voyante")
            H.assert_eq(n.hunter, 1, "chasseur")
            H.assert_eq(n.villager, 3, "villageois")
        end)
    end)

    H.describe("werewolf/vote", function()
        H.it("egalite : personne au village, au hasard chez les loups", function()
            local b = Voting.nouveau()
            Voting.designer(b, 1, 3); Voting.designer(b, 2, 4)
            H.assert_nil(Voting.depouiller(b, "aucun", premier), "le village ne tranche pas")
            H.assert_eq(Voting.depouiller(b, "hasard", premier), 3, "tirage parmi les ex aequo")
            Voting.designer(b, 5, 4)
            H.assert_eq(Voting.depouiller(b, "aucun", premier), 4, "majorite")
        end)
    end)

    H.describe("werewolf/victoire", function()
        local function etat(roles, morts)
            local s = Match.nouveau(ids(#roles), roles)
            for _, id in ipairs(morts or {}) do Match.tuer(s, id) end
            return s
        end
        H.it("village, loups, loup blanc, amoureux", function()
            H.assert_eq(Outcome.verdict(etat({ "wolf", "villager", "villager", "villager" }, { 1 })), "village", "plus de loup")
            H.assert_eq(Outcome.verdict(etat({ "wolf", "villager", "villager", "villager" }, { 2, 3 })), "wolves", "parite")
            H.assert_nil(Outcome.verdict(etat({ "wolf", "white_wolf", "villager", "villager" }, { 3, 4 })), "le loup blanc empeche la victoire des loups")
            H.assert_eq(Outcome.verdict(etat({ "wolf", "white_wolf", "villager", "villager" }, { 1, 3, 4 })), "white_wolf", "loup blanc seul")
            local s = etat({ "wolf", "villager", "villager", "villager" }, { 3, 4 })
            s.amoureux = { 1, 2 }
            H.assert_eq(Outcome.verdict(s), "lovers", "amoureux de camps opposes, derniers vivants")
        end)
    end)

    H.describe("werewolf/machine", function()
        H.it("refuse de demarrer sous le minimum", function()
            local s = Engine.nouveau()
            local fx, raison = Engine.demarrer(s, ids(3), compo(), premier)
            H.assert_nil(fx, "aucun effet")
            H.assert_eq(raison, "pas_assez_de_joueurs", "raison")
            H.assert_nil(Engine.phase(s), "toujours en attente")
        end)

        H.it("la premiere nuit suit la composition", function()
            H.assert_eq(Engine.phase((partie(5))), "night_wolves", "loups d'abord sans cupidon ni gardien")
            H.assert_eq(Engine.phase((partie(6, { cupid = 1, guard = 1 }))), "night_cupid", "cupidon ouvre la premiere nuit")
        end)

        H.it("aucun role ni vision ne part a un autre que son destinataire", function()
            local s, fx = partie(6, { seer = 1 })
            local vus = {}
            for _, e in ipairs(fx) do vus[#vus + 1] = e end
            local loup = s.match and Match.loups_vivants(s.match)[1]
            for _, e in ipairs(Engine.designer(s, loup, villageois(s, porteur(s, "seer")) or villageois(s)) or {}) do vus[#vus + 1] = e end
            for _, e in ipairs(jusqua(s, "night_seer")) do vus[#vus + 1] = e end
            local voyante = porteur(s, "seer")
            for _, e in ipairs(Engine.designer(s, voyante, loup) or {}) do vus[#vus + 1] = e end
            for _, e in ipairs(vus) do
                if e.kind == "assign_role" then H.assert_eq(e.audience, e.player, "role prive") end
                if e.kind == "reveal" then H.assert_eq(e.audience, e.viewer, "vision privee") end
                if e.kind == "votes" and Engine.phase(s) ~= "day_vote" then
                    H.assert_true(e.audience == "wolves", "vote des loups aux loups")
                end
            end
        end)

        H.it("les loups designent, la victime meurt a l'aube", function()
            local s = partie(5)
            local loup = Match.loups_vivants(s.match)[1]
            local proie = villageois(s)
            H.assert_true(Engine.designer(s, loup, proie) ~= nil, "designation acceptee")
            H.assert_eq(Engine.phase(s), "dawn", "un seul loup : la nuit se termine, l'aube tombe")
            H.assert_false(Match.vivant(s.match, proie), "la proie est morte")
        end)

        H.it("le gardien sauve la victime", function()
            local s = partie(6, { guard = 1 })
            local gardien = porteur(s, "guard")
            local loup = Match.loups_vivants(s.match)[1]
            local proie = villageois(s, gardien)
            Engine.designer(s, gardien, proie)
            H.assert_eq(Engine.phase(s), "night_wolves", "au tour des loups")
            Engine.designer(s, loup, proie)
            H.assert_true(Match.vivant(s.match, proie), "protegee cette nuit")
        end)

        H.it("mort au vote, le chasseur tire", function()
            local s = partie(6, { hunter = 1 })
            local chasseur = porteur(s, "hunter")
            local loup = Match.loups_vivants(s.match)[1]
            Engine.designer(s, loup, villageois(s, chasseur))
            jusqua(s, "day_vote")
            for _, id in ipairs(Match.vivants(s.match)) do
                if id ~= chasseur then Engine.designer(s, id, chasseur) end
            end
            jusqua(s, "hunter_shot")
            H.assert_false(Match.vivant(s.match, chasseur), "le chasseur est mort")
            local fx = Engine.designer(s, chasseur, loup)
            H.assert_true(fx ~= nil, "tir accepte une fois mort")
            H.assert_false(Match.vivant(s.match, loup), "il emporte le loup")
            H.assert_eq(s.statut, "finie", "plus de loup : le village gagne")
        end)

        H.it("l'amoureux meurt de chagrin", function()
            local s = partie(6, { cupid = 1 })
            local cupidon = porteur(s, "cupid")
            local loup = Match.loups_vivants(s.match)[1]
            local a, b = villageois(s, cupidon), nil
            for _, id in ipairs(Match.vivants(s.match)) do
                if id ~= a and id ~= loup and id ~= cupidon then b = id break end
            end
            Engine.designer(s, cupidon, a)
            local fx = Engine.designer(s, cupidon, b)
            local prives = 0
            for _, e in ipairs(fx) do if e.kind == "lovers" then prives = prives + 1 end end
            H.assert_eq(prives, 2, "chacun apprend son lien")
            Engine.designer(s, loup, a)
            H.assert_eq(#tues(Engine.avancer(s, 0)), 0, "rien de plus")
            H.assert_false(Match.vivant(s.match, a), "victime des loups")
            H.assert_false(Match.vivant(s.match, b), "morte de chagrin")
        end)

        H.it("le maire est elu au jour prevu, sa voix compte double et departage", function()
            local s = partie(7, { wolf = 1 })
            local loup = Match.loups_vivants(s.match)[1]
            -- Premiere nuit, premier jour sans election.
            Engine.designer(s, loup, villageois(s))
            jusqua(s, "day_vote")
            jusqua(s, "night_wolves")
            Engine.designer(s, loup, villageois(s))
            jusqua(s, "day_mayor")
            local vivants = Match.vivants(s.match)
            local maire = vivants[1] == loup and vivants[2] or vivants[1]
            for _, id in ipairs(vivants) do Engine.designer(s, id, maire) end
            local vus = jusqua(s, "day_debate")
            local elu
            for _, e in ipairs(vus) do if e.kind == "mayor" then elu = e.player end end
            H.assert_eq(elu, maire, "elu")
            jusqua(s, "day_vote")
            -- Egalite 1 contre 1 : le choix du maire l'emporte (sa voix compte double).
            local autre = nil
            for _, id in ipairs(Match.vivants(s.match)) do
                if id ~= maire and id ~= loup then autre = id break end
            end
            Engine.designer(s, maire, loup)
            Engine.designer(s, autre, maire)
            -- L'execution tue le loup et le village gagne dans la meme seconde.
            for _ = 1, 120 do
                if s.statut == "finie" or Engine.phase(s) == "execution" then break end
                Engine.avancer(s, 1)
            end
            H.assert_false(Match.vivant(s.match, loup), "le loup est elimine grace au maire")
            H.assert_eq(s.statut, "finie", "plus de loup : le village gagne")
        end)

        H.it("le maire mort designe son successeur", function()
            local s = partie(7, { wolf = 1 })
            local loup = Match.loups_vivants(s.match)[1]
            Engine.designer(s, loup, villageois(s))
            jusqua(s, "night_wolves")
            Engine.designer(s, loup, villageois(s))
            jusqua(s, "day_mayor")
            local maire = villageois(s)
            for _, id in ipairs(Match.vivants(s.match)) do Engine.designer(s, id, maire) end
            jusqua(s, "night_wolves")
            Engine.designer(s, loup, maire)
            jusqua(s, "mayor_succession")
            local heritier = villageois(s)
            H.assert_true(Engine.designer(s, maire, heritier) ~= nil, "le maire mort nomme")
            H.assert_eq(s.maire, heritier, "nouveau maire")
        end)

        H.it("un depart sous le minimum arrete la partie sans vainqueur", function()
            local s = partie(4)
            local fx = Engine.depart(s, villageois(s))
            local fin
            for _, e in ipairs(fx) do if e.kind == "match_ended" then fin = e end end
            H.assert_true(fin ~= nil, "fin de partie")
            H.assert_eq(s.statut, "finie", "partie finie")
        end)
    end)
end
