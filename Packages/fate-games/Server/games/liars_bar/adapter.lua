-- Le seul fichier de ce module qui connaisse nanos world.
--
-- Il ne prend AUCUNE decision : il ne verifie pas un tour, ne juge pas une
-- contestation, ne tire pas au hasard. S'il faut un `if` sur une regle du jeu,
-- il est au mauvais endroit — cela appartient au moteur. Ici, de la traduction
-- et de la comptabilite, rien d'autre.
--
-- C'est aussi pour cette raison qu'il n'est pas couvert par le banc de test :
-- il n'y a rien a y verifier qui ne soit deja verifie ailleurs.

return function(Log, DB, Ids, Characters, Interactables, Intents, Engine, Appearances, config, spawn)
    local Adapter = {}

    -- Les references d'assets, rassemblees ici et nulle part ailleurs. Une
    -- reference de mesh invalide echoue EN SILENCE cote Lua : le prop est quand
    -- meme cree et seul le log serveur signale "Asset Pack not found". Les
    -- avoir au meme endroit rend ce diagnostic possible.
    local ASSETS = {
        table = "nanos-world::SM_WoodenTable",   -- integre au jeu
        chair = "nanos-world::SM_WoodenChair",   -- integre, meme famille de textures

        -- Le Nagant M1895 attend sa cuisson. Tant que le pack n'existe pas, le
        -- prop est invisible — mais le jeu reste fonctionnel, parce que c'est le
        -- REGISTRE qui fait autorite pour l'interaction, pas le maillage.
        revolver = "liars-props::SM_Nagant_M1895",
    }

    -- Les cinq FBX Mixamo attendent leur retargeting dans l'ADK. Tant que ces
    -- references sont vides, l'adaptateur ne joue rien : le jeu fonctionne sans,
    -- seulement moins expressif. Remplir une seule ligne suffit a l'activer.
    local ANIMATIONS = {
        accuse = "",   -- bras tendu, slot UpperBody, pour garder la posture assise
    }

    local state          = nil   -- etat du moteur, nil hors partie
    local seated         = {}    -- { { player = ..., seat = n } }, avant le debut
    local player_by_seat = {}
    local seat_by_player = {}
    local shoot_timer    = nil
    local started_at     = nil

    ---------------------------------------------------------------- envois

    local function to_one(seat, event, ...)
        local player = player_by_seat[seat]
        if not player then return end
        -- Cote serveur : (evenement, joueur, fiabilite, ...). Omettre la
        -- fiabilite decale le premier argument utile dans ce parametre.
        Events.CallRemote(event, player, Reliability.Reliable, ...)
    end

    local function to_all(event, ...)
        Events.BroadcastRemote(event, Reliability.Reliable, ...)
    end

    local function character_of(seat)
        local player = player_by_seat[seat]
        return player and player:GetControlledCharacter() or nil
    end

    ---------------------------------------------------------------- traducteurs

    local TRANSLATORS = {}

    TRANSLATORS.appearance = function(e)
        local character = character_of(e.seat)
        if not character then
            Log.Warn("liars", ("apparence : aucun personnage a la place %d"):format(e.seat))
            return
        end

        local look = Appearances.Resolve(e.look)
        if not look then
            Log.Error("liars", "apparence inconnue : " .. tostring(e.look))
            return
        end

        character:SetMesh(look.body)
        character:RemoveAllStaticMeshesAttached()
        character:RemoveAllSkeletalMeshesAttached()

        -- Les pieces de tete sont des maillages STATIQUES accroches a un os :
        -- aucun rigging necessaire. Le nom "head" est l'usage courant mais reste
        -- A CONFIRMER sur le squelette nanos world.
        for i, mesh in ipairs(look.head) do
            character:AddStaticMeshAttached("liars_head_" .. i, mesh, "head")
        end

        -- Les vetements sont attaches en "master pose" : ils suivent le corps,
        -- donc ils doivent etre skinnes sur le meme squelette.
        for i, mesh in ipairs(look.worn) do
            character:AddSkeletalMeshAttached("liars_worn_" .. i, mesh)
        end

        Log.Debug("liars", ("place %d habillee en %s (%d tete, %d vetements)")
            :format(e.seat, look.label, #look.head, #look.worn))
    end

    TRANSLATORS.deal         = function(e) to_one(e.seat, "liars:deal", e.cards) end
    TRANSLATORS.table_card   = function(e) to_all("liars:table_card", e.rank) end
    TRANSLATORS.cards_played = function(e) to_all("liars:cards_played", e.seat, e.count) end
    TRANSLATORS.reveal       = function(e) to_all("liars:reveal", e.seat, e.cards) end
    TRANSLATORS.turn         = function(e) to_all("liars:turn", e.seat) end
    TRANSLATORS.round_ended  = function(e) to_all("liars:round_ended", e.reason) end
    TRANSLATORS.shoot        = function(e) to_all("liars:shoot", e.seat, e.chamber, e.fatal) end

    TRANSLATORS.accuse = function(e)
        to_all("liars:accuse", e.accuser, e.target)

        if ANIMATIONS.accuse ~= "" then
            local character = character_of(e.accuser)
            if character then
                character:PlayAnimation(ANIMATIONS.accuse, AnimationSlotType.UpperBody)
            end
        end
    end

    TRANSLATORS.eliminated = function(e)
        -- Il garde la parole : il n'y a precisement RIEN a faire sur son micro.
        -- Il reste assis, il voit tout, il peut commenter.
        to_all("liars:eliminated", e.seat)
        Log.Info("liars", ("place %d eliminee"):format(e.seat))
    end

    TRANSLATORS.match_ended = function(e)
        to_all("liars:match_ended", e.winner)
        Adapter.PersistResult(e.winner, e.summary)

        state, player_by_seat, seat_by_player, seated, started_at = nil, {}, {}, {}, nil
        Log.Info("liars", ("partie terminee, vainqueur place %s"):format(tostring(e.winner)))
    end

    ---------------------------------------------------------------- persistance

    -- Donnee transactionnelle, donc ecriture immediate (R3). C'est la seule
    -- chose que le jeu laisse derriere lui.
    function Adapter.PersistResult(winner, summary)
        local match_id = Ids.Next("liars_matches")
        local ended_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

        DB.Execute(
            [[INSERT INTO liars_matches (id, started_at, ended_at, rounds, winner_id)
              VALUES (:0, :1, :2, :3, :4)]],
            function(_, err)
                if err then
                    Log.Error("liars", "resultat non ecrit : " .. tostring(err))
                end
            end,
            match_id, started_at or ended_at, ended_at,
            summary and summary.rounds or 0, winner
        )

        -- Le classement se lit a l'envers de l'ordre des eliminations : le
        -- dernier tombe est deuxieme, l'avant-dernier troisieme, et ainsi de suite.
        local placement = {}
        local dead = summary and summary.dead or {}
        for i = #dead, 1, -1 do
            placement[dead[i]] = (#dead - i) + 2
        end
        if winner then placement[winner] = 1 end

        for _, entry in ipairs(seated) do
            DB.Execute(
                [[INSERT INTO liars_participants (match_id, seat, character_id, look, placement)
                  VALUES (:0, :1, :2, :3, :4)]],
                function(_, err)
                    if err then
                        Log.Error("liars", "participant non ecrit : " .. tostring(err))
                    end
                end,
                match_id, entry.seat, entry.character_id,
                tostring(state and state.match.looks[entry.seat] or "?"),
                placement[entry.seat]
            )
        end
    end

    ---------------------------------------------------------------- application

    local function dispatch(effects, cid)
        for _, e in ipairs(effects) do
            local translate = TRANSLATORS[e.kind]
            if translate then
                translate(e)
            else
                Log.Warn("liars", "effet sans traducteur : " .. tostring(e.kind), cid)
            end
        end
    end

    -- Sans ce filet, un joueur deconnecte ou inerte bloque la partie entiere.
    -- Le hasard etait fixe a la creation du barillet : resoudre sans lui ne lui
    -- retire rien.
    function Adapter.ArmShootTimeout()
        if shoot_timer then
            Timer.ClearTimeout(shoot_timer)
            shoot_timer = nil
        end
        if not state or not state.pending then return end

        local designe = state.pending.seat
        shoot_timer = Timer.SetTimeout(function()
            shoot_timer = nil
            if state and state.pending and state.pending.seat == designe then
                Log.Info("liars", ("tir resolu d'office pour la place %d"):format(designe))
                Adapter.Act({ kind = "shoot", seat = designe })
            end
        end, math.floor(config.shoot_timeout * 1000))
    end

    function Adapter.Act(act, cid)
        if not state then
            return false, "aucune partie en cours"
        end

        -- pcall sur une fonction a plusieurs valeurs de retour les rend TOUTES
        -- apres le booleen : ok, etat, effets. En n'en recuperant que deux on
        -- perdrait silencieusement les effets, et le code compilerait.
        local ok, nouveau, effects = pcall(Engine.Apply, state, act)
        if not ok then
            -- Un acte refuse est une information, pas une panne : le moteur leve
            -- une erreur nommee, on la journalise et on la rend au client.
            Log.Info("liars", "acte refuse : " .. tostring(nouveau), cid)
            return false, tostring(nouveau)
        end

        state = nouveau
        dispatch(effects, cid)
        Adapter.ArmShootTimeout()
        return true
    end

    ---------------------------------------------------------------- assise

    function Adapter.Seat(player, seat, cid)
        if state then
            return false, "partie_en_cours"
        end
        if player_by_seat[seat] then
            return false, "place_occupee"
        end

        local ancienne = seat_by_player[player:GetID()]
        if ancienne then
            player_by_seat[ancienne] = nil
            for i = #seated, 1, -1 do
                if seated[i].seat == ancienne then table.remove(seated, i) end
            end
        end

        player_by_seat[seat] = player
        seat_by_player[player:GetID()] = seat
        -- Le personnage se retrouve par la session : il n'y a pas de valeur
        -- posee sur le joueur dans ce depot.
        local session = Characters.SessionByPlayer(player:GetID())
        seated[#seated + 1] = {
            player       = player,
            seat         = seat,
            character_id = session and session.character_id or 0,
        }

        to_all("liars:seated", seat, player:GetID())
        Log.Info("liars", ("place %d occupee (%d assis)"):format(seat, #seated), cid)
        return true
    end

    function Adapter.Begin(cid)
        if state then
            return false, "partie_en_cours"
        end
        if #seated < config.min_players then
            return false, "pas_assez_de_joueurs"
        end

        -- Ordre des places croissant : la table doit tourner dans le sens ou on
        -- la voit, pas dans l'ordre d'arrivee des joueurs.
        table.sort(seated, function(a, b) return a.seat < b.seat end)

        local ids = {}
        for i, entry in ipairs(seated) do
            ids[i] = entry.player:GetID()
        end

        -- Reindexation : le moteur numerote les places de 1 a n sans trou, alors
        -- que les chaises occupees peuvent etre la 2, la 4 et la 5. On reecrit
        -- donc les correspondances sur la numerotation du moteur, en conservant
        -- l'ordre autour de la table — c'est a cela que servait le tri.
        player_by_seat = {}
        for i, entry in ipairs(seated) do
            player_by_seat[i] = entry.player
            seat_by_player[entry.player:GetID()] = i
            entry.seat = i
        end

        started_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

        local effects
        state, effects = Engine.Start(ids, function(n) return math.random(n) end)
        dispatch(effects, cid)
        Adapter.ArmShootTimeout()

        Log.Info("liars", ("partie demarree a %d joueurs"):format(#ids), cid)
        return true
    end

    ---------------------------------------------------------------- init

    function Adapter.Init()
        Prop(Vector(spawn.x, spawn.y, spawn.z), Rotator(0, 0, 0), ASSETS.table)

        local rayon = 120.0
        for seat = 1, config.max_seats do
            local angle = (seat - 1) * (360.0 / config.max_seats)
            local rad   = math.rad(angle)

            local chair = Prop(
                Vector(spawn.x + math.cos(rad) * rayon,
                       spawn.y + math.sin(rad) * rayon,
                       spawn.z),
                Rotator(0, angle + 180.0, 0),   -- tournee vers la table
                ASSETS.chair
            )

            Interactables.Register(chair, {
                label = ("S'asseoir (place %d)"):format(seat),
                on_interact = function(player, session, entry, cid)
                    Adapter.Seat(player, seat, cid)
                end,
            })
        end

        -- Le revolver au centre porte deux actes : lancer la partie, et tirer.
        -- C'est le meme objet parce que c'est le meme geste — on y pose la main.
        local revolver = Prop(
            Vector(spawn.x, spawn.y, spawn.z + 60.0),
            Rotator(0, 0, 0),
            ASSETS.revolver
        )

        Interactables.Register(revolver, {
            label = "Prendre le revolver",
            on_interact = function(player, session, entry, cid)
                if not state then
                    return Adapter.Begin(cid)
                end
                local seat = seat_by_player[player:GetID()]
                if seat then
                    Adapter.Act({ kind = "shoot", seat = seat }, cid)
                end
            end,
        })

        -- Les deux intentions heritent du pipeline : revalidation de distance,
        -- audit et correlation viennent gratuitement.
        Intents.Register("liars_play", {
            validate = function(player, payload)
                if not state then return false, "aucune_partie" end
                if type(payload) ~= "table" or type(payload.indices) ~= "table" then
                    return false, "charge_invalide"
                end
                if not seat_by_player[player:GetID()] then return false, "pas_a_table" end
                return true
            end,
            apply = function(player, payload, cid)
                local seat = seat_by_player[player:GetID()]
                local ok, raison = Adapter.Act(
                    { kind = "play", seat = seat, indices = payload.indices }, cid)
                return ok, {
                    target = "seat:" .. tostring(seat),
                    audit  = ok and ("pose de %d carte(s)"):format(#payload.indices)
                        or tostring(raison),
                }
            end,
        })

        Intents.Register("liars_challenge", {
            validate = function(player, payload)
                if not state then return false, "aucune_partie" end
                if not seat_by_player[player:GetID()] then return false, "pas_a_table" end
                return true
            end,
            apply = function(player, payload, cid)
                local seat = seat_by_player[player:GetID()]
                local ok, raison = Adapter.Act({ kind = "challenge", seat = seat }, cid)
                return ok, {
                    target = "seat:" .. tostring(seat),
                    audit  = ok and "conteste" or tostring(raison),
                }
            end,
        })

        Log.Info("liars", ("table posee : %d places"):format(config.max_seats))
    end

    -- Un joueur qui quitte le serveur en cours de partie compte comme elimine.
    function Adapter.OnPlayerLeave(player)
        if not state then return end
        local seat = seat_by_player[player:GetID()]
        if seat then
            Adapter.Act({ kind = "leave", seat = seat })
        end
    end

    return Adapter
end
