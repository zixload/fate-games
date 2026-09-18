-- Le contrat entre le moteur et l'adaptateur.
--
-- Le moteur ne coupe pas un micro, ne joue aucune animation, ne cree aucun
-- prop : il rend des effets, et l'adaptateur les traduit. Chaque effet porte
-- une AUDIENCE, et c'est elle qui protege l'information cachee.
--
-- L'effet decisif est cards_played, qui ne transporte QU'UN NOMBRE. Si le
-- moteur y mettait les cartes, un client curieux lirait le paquet et le jeu
-- serait mort. C'est la seule fuite qui compterait vraiment, d'ou AssertNoLeak.

return function()
    local Effects = {}

    -- Les champs propres a chaque nature, et aucun autre : kind et audience
    -- s'y ajoutent partout. Un champ en trop est refuse, si bien qu'une main
    -- glissee par megarde dans un effet public s'arrete ici, avant l'adaptateur.
    local FIELDS = {
        appearance   = { "seat", "look" },
        deal         = { "seat", "cards" },
        table_card   = { "rank" },
        cards_played = { "seat", "count" },
        reveal       = { "seat", "cards" },
        accuse       = { "accuser", "target" },
        designated   = { "seat" },
        shoot        = { "seat", "chamber", "fatal" },
        eliminated   = { "seat" },
        turn         = { "seat" },
        round_ended  = { "reason" },
        match_ended  = { "winner", "summary" },
    }

    -- Meme liste, en ensembles, pour la recherche.
    local ALLOWED = {}
    for kind, champs in pairs(FIELDS) do
        local permis = { kind = true, audience = true }
        for _, champ in ipairs(champs) do permis[champ] = true end
        ALLOWED[kind] = permis
    end

    local ROUND_REASONS = { challenged = true, exhausted = true }

    -- Les seuls effets autorises a porter des cartes : deal, qui est prive, et
    -- reveal, dont la publication est precisement le but.
    local CARDS_ALLOWED = { deal = true, reveal = true }

    function Effects.Appearance(seat, look)
        return { kind = "appearance", seat = seat, look = look, audience = "all" }
    end

    function Effects.Deal(seat, cards)
        return { kind = "deal", seat = seat, cards = cards, audience = seat }
    end

    function Effects.TableCard(rank)
        return { kind = "table_card", rank = rank, audience = "all" }
    end

    function Effects.CardsPlayed(seat, count)
        return { kind = "cards_played", seat = seat, count = count, audience = "all" }
    end

    function Effects.Reveal(seat, cards)
        return { kind = "reveal", seat = seat, cards = cards, audience = "all" }
    end

    function Effects.Accuse(accuser, target)
        return { kind = "accuse", accuser = accuser, target = target, audience = "all" }
    end

    -- Qui doit tirer. Emis apres la revelation, et seulement quand un tir est
    -- reellement mis en attente : sans lui, un client devrait rejuger la
    -- contestation lui-meme pour savoir vers qui glisser le revolver.
    function Effects.Designated(seat)
        return { kind = "designated", seat = seat, audience = "all" }
    end

    function Effects.Shoot(seat, chamber, fatal)
        return {
            kind = "shoot", seat = seat, chamber = chamber,
            fatal = fatal and true or false, audience = "all",
        }
    end

    function Effects.Eliminated(seat)
        return { kind = "eliminated", seat = seat, audience = "all" }
    end

    function Effects.Turn(seat)
        return { kind = "turn", seat = seat, audience = "all" }
    end

    function Effects.RoundEnded(reason)
        return { kind = "round_ended", reason = reason, audience = "all" }
    end

    function Effects.MatchEnded(winner, summary)
        return { kind = "match_ended", winner = winner, summary = summary, audience = "all" }
    end

    function Effects.Validate(effect)
        if type(effect) ~= "table" then
            error("effet invalide : table attendue")
        end
        local permis = ALLOWED[effect.kind]
        if not permis then
            error("effet de nature inconnue : " .. tostring(effect.kind))
        end
        if effect.audience == nil then
            error("audience manquante sur l'effet " .. tostring(effect.kind))
        end
        for champ in pairs(effect) do
            if not permis[champ] then
                error(("champ inconnu %s dans l'effet %s")
                    :format(tostring(champ), effect.kind))
            end
        end
        if effect.kind == "round_ended" and not ROUND_REASONS[effect.reason] then
            error("motif inconnu : " .. tostring(effect.reason))
        end
        if effect.kind == "cards_played" then
            -- Une pose de zero carte, ou d'un nombre non entier, n'existe pas :
            -- elle effacerait la pose precedente sans rien mettre a juger.
            local n = effect.count
            if type(n) ~= "number" or n < 1 or n % 1 ~= 0 then
                error("compte de cartes invalide : " .. tostring(n))
            end
        end
        return true
    end

    -- Le test de securite du jeu, sous forme de fonction : aucun effet public
    -- ne doit porter l'identite d'une carte.
    function Effects.AssertNoLeak(list)
        for _, effect in ipairs(list) do
            if effect.cards ~= nil and not CARDS_ALLOWED[effect.kind] then
                error(("fuite de cartes dans un effet %s"):format(tostring(effect.kind)))
            end
        end
        return true
    end

    return Effects
end
