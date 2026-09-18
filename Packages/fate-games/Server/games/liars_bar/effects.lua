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

    local KINDS = {
        appearance   = true,
        deal         = true,
        table_card   = true,
        cards_played = true,
        reveal       = true,
        accuse       = true,
        designated   = true,
        shoot        = true,
        eliminated   = true,
        turn         = true,
        round_ended  = true,
        match_ended  = true,
    }

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
        if not KINDS[effect.kind] then
            error("effet de nature inconnue : " .. tostring(effect.kind))
        end
        if effect.audience == nil then
            error("audience manquante sur l'effet " .. tostring(effect.kind))
        end
        if effect.kind == "round_ended" and not ROUND_REASONS[effect.reason] then
            error("motif inconnu : " .. tostring(effect.reason))
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
