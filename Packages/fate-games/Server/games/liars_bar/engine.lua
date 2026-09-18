-- La machine.
--
-- Un acte entre, un etat et une liste d'effets sortent. Le moteur ne connait
-- pas nanos world : il ne coupe pas un micro, ne cree aucun prop, ne joue
-- aucune animation. Et il est pilote par les actes, pas par l'horloge — c'est
-- ce qui le distingue de la pile de phases minutees du loup-garou.
--
-- Toute decision est ici. L'adaptateur ne fait que traduire.

return function(config, Deck, Revolver, Challenge, Round, Match, Effects)
    local Engine = {}

    -- Utilitaire de test et de diagnostic : une place vivante differente de
    -- celle donnee. Expose parce que les suites en ont besoin pour verifier
    -- qu'un tir ne peut pas etre usurpe.
    function Engine.OtherThan(match, seat)
        for _, s in ipairs(Match.AliveSeats(match)) do
            if s ~= seat then return s end
        end
        return nil
    end

    local function copier(list)
        local copie = {}
        for i, v in ipairs(list) do copie[i] = v end
        return copie
    end

    local function ouvrir_manche(state, opener, out)
        local vivants = Match.AliveSeats(state.match)
        state.match.rounds = state.match.rounds + 1
        state.round = Round.Start(vivants, opener, state.rng)
        state.pending = nil

        out[#out + 1] = Effects.TableCard(state.round.rank)
        for _, seat in ipairs(vivants) do
            -- Une COPIE et non la main vivante : Round.Play retirera ensuite des
            -- cartes de cette table, et un effet emis ne doit plus changer.
            out[#out + 1] = Effects.Deal(seat, copier(state.round.hands[seat]))
        end
        out[#out + 1] = Effects.Turn(state.round.turn)
    end

    local function terminer_partie(state, out)
        state.finished = true
        out[#out + 1] = Effects.MatchEnded(Match.Winner(state.match), {
            rounds = state.match.rounds,
            dead   = state.match.dead_order,
        })
    end

    -- Rend true si la partie s'est terminee, false sinon.
    local function verifier_victoire(state, out)
        local vivants = Match.AliveSeats(state.match)
        if #vivants <= 1 then
            terminer_partie(state, out)
            return true
        end
        return false
    end

    -- Fin de manche par epuisement : personne ne tire, on redistribue et
    -- l'ouverture passe au joueur vivant suivant celui qui venait d'ouvrir.
    local function epuiser(state, out)
        out[#out + 1] = Effects.RoundEnded("exhausted")
        local suivant = Match.NextAlive(state.match, state.round.opener)
        ouvrir_manche(state, suivant, out)
    end

    -- Une contestation est jugee, mais son perdant n'est plus a table : il est
    -- parti avant de tirer, ou avant meme qu'on l'accuse. Le hasard etait fixe
    -- a la creation du barillet, personne n'y perd rien — on clot la manche ici,
    -- et la suivante s'ouvre sur le vivant qui suit ce perdant.
    local function clore_sans_tireur(state, perdant, out)
        state.pending = nil
        out[#out + 1] = Effects.RoundEnded("challenged")

        if verifier_victoire(state, out) then return end

        return ouvrir_manche(state, Match.NextAlive(state.match, perdant), out)
    end

    function Engine.Start(player_ids, rng)
        local state = {
            match    = Match.New(player_ids, rng),
            round    = nil,
            pending  = nil,
            finished = false,
            rng      = rng,
        }

        local out = {}
        for _, seat in ipairs(state.match.seats) do
            out[#out + 1] = Effects.Appearance(seat, state.match.looks[seat])
        end
        ouvrir_manche(state, state.match.seats[1], out)

        for _, e in ipairs(out) do Effects.Validate(e) end
        Effects.AssertNoLeak(out)
        return state, out
    end

    local handlers = {}

    handlers.play = function(state, act, out)
        if state.pending then
            error("un tir est en attente : impossible de poser")
        end
        if act.seat ~= state.round.turn then
            error(("place %s : pas son tour"):format(tostring(act.seat)))
        end

        local cards = Round.Play(state.round, act.seat, act.indices)
        out[#out + 1] = Effects.CardsPlayed(act.seat, #cards)

        local vivants = Match.AliveSeats(state.match)
        if Round.Exhausted(state.round, vivants) then
            return epuiser(state, out)
        end

        local suivant = Round.NextTurn(state.round, vivants)
        if not suivant then
            return epuiser(state, out)
        end

        state.round.turn = suivant
        out[#out + 1] = Effects.Turn(suivant)
    end

    handlers.challenge = function(state, act, out)
        if state.pending then
            error("un tir est en attente : impossible de contester")
        end
        if act.seat ~= state.round.turn then
            error(("place %s : pas son tour"):format(tostring(act.seat)))
        end

        local last = state.round.last
        if not last then
            error("aucune pose a contester")
        end
        -- Garde-fou : inatteignable par le jeu normal, puisque le tour avance
        -- toujours apres une pose. Conserve parce que handlers.leave reassigne
        -- le tour et qu'un chemin futur pourrait la rendre joignable.
        if last.seat == act.seat then
            error("on ne conteste pas sa propre pose")
        end

        out[#out + 1] = Effects.Accuse(act.seat, last.seat)
        out[#out + 1] = Effects.Reveal(last.seat, last.cards)

        local verdict = Challenge.Resolve(last.cards, state.round.rank)
        local perdant = (verdict == "liar") and last.seat or act.seat

        -- Le menteur a pu quitter la table entre sa pose et l'accusation. Poser
        -- un tir en attente sur un mort ferait attendre tout le monde jusqu'au
        -- delai, puis tirerait son revolver et l'eliminerait une seconde fois.
        if not state.match.alive[perdant] then
            return clore_sans_tireur(state, perdant, out)
        end

        state.pending = { seat = perdant }
        out[#out + 1] = Effects.Designated(perdant)
    end

    handlers.shoot = function(state, act, out)
        if not state.pending then
            error("aucun tir en attente")
        end
        if act.seat ~= state.pending.seat then
            error(("place %s : pas designee pour tirer"):format(tostring(act.seat)))
        end

        local tireur       = act.seat
        local vivant_avant = state.match.alive[tireur]
        local fatal, chamber = Revolver.Pull(state.match.revolvers[tireur])
        out[#out + 1] = Effects.Shoot(tireur, chamber, fatal)

        if fatal then
            Match.Eliminate(state.match, tireur)
            -- Garde-fou : un tireur deja mort a deja ete annonce elimine. Une
            -- seconde annonce ferait croire aux clients a une nouvelle mort.
            if vivant_avant then
                out[#out + 1] = Effects.Eliminated(tireur)
            end
        end

        state.pending = nil
        out[#out + 1] = Effects.RoundEnded("challenged")

        if verifier_victoire(state, out) then return end

        -- Le perdant ouvre la manche suivante s'il est vivant ; s'il est mort,
        -- la place vivante suivante.
        local opener = state.match.alive[tireur] and tireur
            or Match.NextAlive(state.match, tireur)
        ouvrir_manche(state, opener, out)
    end

    handlers.leave = function(state, act, out)
        if not state.match.alive[act.seat] then
            return
        end

        Match.Eliminate(state.match, act.seat)
        out[#out + 1] = Effects.Eliminated(act.seat)

        -- Le partant devait tirer : le hasard etait fixe a la creation du barillet,
        -- on resout sans lui plutot que de bloquer la partie. La manche se termine
        -- donc ici, et il faut OUVRIR LA SUIVANTE, exactement comme le fait
        -- handlers.shoot. Sans ce retour, on retomberait dans la branche du depart
        -- de spectateur, qui laisse l'etat de manche perime alors que les clients
        -- ont deja ete prevenus de sa fin — et rien ne pourrait plus la clore.
        if state.pending and state.pending.seat == act.seat then
            -- Le partant est mort, donc l'ouverture revient au vivant suivant.
            return clore_sans_tireur(state, act.seat, out)
        end

        if verifier_victoire(state, out) then return end

        local vivants = Match.AliveSeats(state.match)
        if state.pending then return end

        if Round.Exhausted(state.round, vivants) or not Round.NextTurn(state.round, vivants) then
            return epuiser(state, out)
        end

        if not state.match.alive[state.round.turn] then
            local suivant = Round.NextTurn(state.round, vivants)
            state.round.turn = suivant
            out[#out + 1] = Effects.Turn(suivant)
        end
    end

    function Engine.Apply(state, act)
        if state.finished then
            error("partie terminee : aucun acte accepte")
        end

        local handler = handlers[act and act.kind]
        if not handler then
            error("acte inconnu : " .. tostring(act and act.kind))
        end

        local out = {}
        handler(state, act, out)

        for _, e in ipairs(out) do Effects.Validate(e) end
        Effects.AssertNoLeak(out)
        return state, out
    end

    return Engine
end
