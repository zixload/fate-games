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

    -- Le Nagant M1895 n'est pas encore cuit. Tant que ce drapeau est faux, un
    -- maillage integre sert de revolver : sans maillage, la trace du client ne
    -- touche rien et aucune partie ne peut demarrer.
    local REVOLVER_CUIT = false

    -- Les dix apparences attendent leur pack (voir Shared/appearances.lua).
    -- Tant que ce drapeau est faux, l'apparence est journalisee et rien
    -- d'autre : habiller un personnage de references absentes le laisserait
    -- sans corps ni tete.
    local APPARENCES_CUITES = false

    -- Les references d'assets, rassemblees ici et nulle part ailleurs. Une
    -- reference de mesh invalide echoue EN SILENCE cote Lua : le prop est quand
    -- meme cree et seul le log serveur signale "Asset Pack not found". Les
    -- avoir au meme endroit rend ce diagnostic possible.
    local ASSETS = {
        seat_marker = "nanos-world::SM_Cube",

        revolver = REVOLVER_CUIT and "liars-props::SM_Nagant_M1895"
            or "nanos-world::SM_Bottle_01",
    }

    -- Les cinq FBX Mixamo attendent leur retargeting dans l'ADK. Tant que ces
    -- references sont vides, l'adaptateur ne joue rien : le jeu fonctionne sans,
    -- seulement moins expressif. Remplir une seule ligne suffit a l'activer.
    local ANIMATIONS = {
        accuse = "",   -- bras tendu, slot UpperBody, pour garder la posture assise
    }

    -- Deux numerotations coexistent, et il ne faut jamais les confondre.
    --
    --   CHAISE : physique, de 1 a max_seats. C'est la seule que voient les
    --            clients et la base.
    --   PLACE  : celle du moteur, de 1 a n sans trou, attribuee au demarrage
    --            dans l'ordre des chaises.
    --
    -- Hors partie, player_by_seat et seat_by_player sont indexees par chaise.
    -- En partie, par place, parce qu'Act parle au moteur ; chair_of fait alors
    -- le chemin inverse pour tout ce qui sort.
    local state          = nil   -- etat du moteur, nil hors partie
    local seated         = {}    -- { { player, chair, character_id, seat } }
    local player_by_seat = {}
    local seat_by_player = {}
    local chair_of       = {}    -- place moteur -> chaise, le temps d'une partie
    local started_at     = nil

    local shoot_timer      = nil
    local shoot_timer_seat = nil   -- la place pour laquelle ce delai court

    -- Mobilier retenu par Init, pour faire glisser le revolver.
    local revolver_prop  = nil
    local revolver_home  = nil   -- au centre de la table
    local devant_chaise  = {}    -- chaise -> position du revolver devant elle

    ---------------------------------------------------------------- envois

    -- La seule porte vers les clients. C'est l'audience fixee par le moteur qui
    -- choisit le destinataire, jamais le traducteur : un numero de place -> le
    -- seul joueur de cette place ; "all" -> tout le monde. Toute autre valeur
    -- est refusee — dans le doute on n'envoie rien, on ne diffuse pas.
    local function send(audience, event, ...)
        if audience == "all" then
            Events.BroadcastRemote(event, Reliability.Reliable, ...)
            return
        end

        local player = (type(audience) == "number") and player_by_seat[audience] or nil
        if not player then
            Log.Warn("liars", ("%s : aucun destinataire pour l'audience %s, rien envoye")
                :format(event, tostring(audience)))
            return
        end

        -- Cote serveur : (evenement, joueur, fiabilite, ...). Omettre la
        -- fiabilite decale le premier argument utile dans ce parametre.
        Events.CallRemote(event, player, Reliability.Reliable, ...)
    end

    -- Une place moteur traduite en chaise, pour tout ce qui sort. Une place
    -- sans chaise est un defaut de comptabilite : on leve plutot que d'envoyer
    -- un numero faux, et dispatch journalise l'echec.
    local function chair(seat)
        if seat == nil then return nil end
        local c = chair_of[seat]
        if c == nil then
            error("place moteur sans chaise : " .. tostring(seat))
        end
        return c
    end

    local function character_of(seat)
        local player = player_by_seat[seat]
        return player and player:GetControlledCharacter() or nil
    end

    local function placer_revolver(position)
        if revolver_prop and position then
            revolver_prop:SetLocation(position)
        end
    end

    ---------------------------------------------------------------- remise a zero

    local function remettre_a_zero()
        state, started_at = nil, nil
        player_by_seat, seat_by_player, chair_of, seated = {}, {}, {}, {}
    end

    ---------------------------------------------------------------- traducteurs

    local TRANSLATORS = {}

    TRANSLATORS.appearance = function(e)
        if not APPARENCES_CUITES then
            Log.Info("liars", ("apparence %s pour la chaise %s : pack non cuit, rien applique")
                :format(tostring(e.look), tostring(chair(e.seat))))
            return
        end

        local character = character_of(e.seat)
        if not character then
            Log.Warn("liars", ("apparence : aucun personnage a la chaise %s")
                :format(tostring(chair(e.seat))))
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

        Log.Debug("liars", ("chaise %s habillee en %s (%d tete, %d vetements)")
            :format(tostring(chair(e.seat)), look.label, #look.head, #look.worn))
    end

    TRANSLATORS.deal = function(e)
        send(e.audience, "liars:deal", e.cards)
    end

    -- Chaque manche s'ouvre sur sa carte de table : le revolver revient au
    -- centre, d'ou qu'il soit parti.
    TRANSLATORS.table_card = function(e)
        placer_revolver(revolver_home)
        send(e.audience, "liars:table_card", e.rank)
    end

    TRANSLATORS.cards_played = function(e)
        send(e.audience, "liars:cards_played", chair(e.seat), e.count)
    end

    TRANSLATORS.reveal = function(e)
        send(e.audience, "liars:reveal", chair(e.seat), e.cards)
    end

    TRANSLATORS.turn = function(e)
        send(e.audience, "liars:turn", chair(e.seat))
    end

    TRANSLATORS.round_ended = function(e)
        send(e.audience, "liars:round_ended", e.reason)
    end

    -- "Le perdant est designe, le revolver glisse devant lui."
    TRANSLATORS.designated = function(e)
        local c = chair(e.seat)
        send(e.audience, "liars:designated", c)
        placer_revolver(devant_chaise[c])
    end

    TRANSLATORS.shoot = function(e)
        send(e.audience, "liars:shoot", chair(e.seat), e.chamber, e.fatal)
        placer_revolver(revolver_home)
    end

    TRANSLATORS.accuse = function(e)
        send(e.audience, "liars:accuse", chair(e.accuser), chair(e.target))

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
        local c = chair(e.seat)
        send(e.audience, "liars:eliminated", c)
        Log.Info("liars", ("chaise %s eliminee"):format(tostring(c)))
    end

    TRANSLATORS.match_ended = function(e)
        -- Tout ce que l'ecriture et les annonces demandent est releve AVANT la
        -- remise a zero, et la remise a zero passe AVANT tout ce qui peut lever :
        -- une ecriture en base qui echoue ne doit plus pouvoir laisser la table
        -- occupee jusqu'au redemarrage du serveur.
        local releve = {
            started_at = started_at,
            seated     = {},
            looks      = {},
            chair_of   = {},
        }
        for i, entry in ipairs(seated) do
            releve.seated[i] = {
                seat         = entry.seat,
                chair        = entry.chair,
                character_id = entry.character_id,
            }
        end
        for seat, look in pairs(state and state.match.looks or {}) do
            releve.looks[seat] = look
        end
        for seat, c in pairs(chair_of) do
            releve.chair_of[seat] = c
        end
        local chaise_gagnante = e.winner ~= nil and releve.chair_of[e.winner] or nil

        remettre_a_zero()

        local ok, err = pcall(Adapter.PersistResult, e.winner, e.summary, releve)
        if not ok then
            Log.Error("liars", "resultat non ecrit : " .. tostring(err))
        end

        send(e.audience, "liars:match_ended", chaise_gagnante)
        for _, entry in ipairs(releve.seated) do
            send("all", "liars:unseated", entry.chair)
        end
        placer_revolver(revolver_home)

        Log.Info("liars", ("partie terminee, vainqueur chaise %s"):format(tostring(chaise_gagnante)))
    end

    ---------------------------------------------------------------- persistance

    -- Donnee transactionnelle, donc ecriture immediate (R3). C'est la seule
    -- chose que le jeu laisse derriere lui. Elle ne lit que le releve fait par
    -- match_ended : l'etat de l'adaptateur est deja remis a zero quand elle
    -- tourne. La base ne connait que des chaises et des personnages — une place
    -- moteur n'a de sens que le temps d'une partie.
    function Adapter.PersistResult(winner, summary, releve)
        local match_id = Ids.Next("liars_matches")
        local ended_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

        local winner_id = nil
        for _, entry in ipairs(releve.seated) do
            if winner ~= nil and entry.seat == winner then
                winner_id = entry.character_id
            end
        end

        DB.Execute(
            [[INSERT INTO liars_matches (id, started_at, ended_at, rounds, winner_id)
              VALUES (:0, :1, :2, :3, :4)]],
            function(_, err)
                if err then
                    Log.Error("liars", "resultat non ecrit : " .. tostring(err))
                end
            end,
            match_id, releve.started_at or ended_at, ended_at,
            summary and summary.rounds or 0, winner_id
        )

        -- Le classement se lit a l'envers de l'ordre des eliminations : le
        -- dernier tombe est deuxieme, l'avant-dernier troisieme, et ainsi de suite.
        local placement = {}
        local dead = summary and summary.dead or {}
        for i = #dead, 1, -1 do
            placement[dead[i]] = (#dead - i) + 2
        end
        if winner then placement[winner] = 1 end

        for _, entry in ipairs(releve.seated) do
            DB.Execute(
                [[INSERT INTO liars_participants (match_id, seat, character_id, look, placement)
                  VALUES (:0, :1, :2, :3, :4)]],
                function(_, err)
                    if err then
                        Log.Error("liars", "participant non ecrit : " .. tostring(err))
                    end
                end,
                match_id, entry.chair, entry.character_id,
                tostring(releve.looks[entry.seat] or "?"),
                placement[entry.seat]
            )
        end
    end

    ---------------------------------------------------------------- application

    -- Chaque traducteur tourne sous pcall. Un seul qui leve — un os mal nomme,
    -- un maillage absent — ne doit ni priver les clients des effets suivants,
    -- ni sauter le delai de tir, ni empecher la remise a zero de fin de partie.
    local function dispatch(effects, cid)
        for _, e in ipairs(effects) do
            local translate = TRANSLATORS[e.kind]
            if translate then
                local ok, err = pcall(translate, e)
                if not ok then
                    Log.Error("liars", ("traduction de %s en echec : %s")
                        :format(tostring(e.kind), tostring(err)), cid)
                end
            else
                Log.Warn("liars", "effet sans traducteur : " .. tostring(e.kind), cid)
            end
        end
    end

    -- Sans ce filet, un joueur deconnecte ou inerte bloque la partie entiere.
    -- Le hasard etait fixe a la creation du barillet : resoudre sans lui ne lui
    -- retire rien.
    function Adapter.ArmShootTimeout()
        local designe = state and state.pending and state.pending.seat or nil

        -- Le delai court deja pour ce tireur : on le laisse courir. Le rearmer a
        -- chaque acte accepte pendant l'attente repousserait l'echeance.
        if shoot_timer and designe == shoot_timer_seat then return end

        if shoot_timer then
            Timer.ClearTimeout(shoot_timer)
            shoot_timer, shoot_timer_seat = nil, nil
        end
        if not designe then return end

        shoot_timer_seat = designe
        shoot_timer = Timer.SetTimeout(function()
            shoot_timer, shoot_timer_seat = nil, nil
            if state and state.pending and state.pending.seat == designe then
                Log.Info("liars", ("tir resolu d'office pour la chaise %s")
                    :format(tostring(chair_of[designe])))
                Adapter.Act({ kind = "shoot", seat = designe })
            end
        end, math.floor(config.shoot_timeout * 1000))
    end

    -- Le texte d'une erreur Lua sans le prefixe "fichier:ligne: " qu'error()
    -- y ajoute : le chemin des sources du serveur ne regarde pas le client.
    local function message_seul(err)
        local texte = tostring(err)
        return texte:match("^.-:%d+: (.*)$") or texte
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
            -- une erreur nommee. Le journal garde le texte complet, le client
            -- n'en recoit que le message.
            Log.Info("liars", "acte refuse : " .. tostring(nouveau), cid)
            return false, message_seul(nouveau)
        end

        state = nouveau
        dispatch(effects, cid)
        Adapter.ArmShootTimeout()
        return true
    end

    ---------------------------------------------------------------- assise

    -- Hors partie : chair_n est une chaise, et les tables sont indexees par chaise.
    function Adapter.Seat(player, chair_n, cid)
        if state then
            return false, "partie_en_cours"
        end
        if player_by_seat[chair_n] then
            return false, "place_occupee"
        end

        local ancienne = seat_by_player[player:GetID()]
        if ancienne then
            player_by_seat[ancienne] = nil
            for i = #seated, 1, -1 do
                if seated[i].chair == ancienne then table.remove(seated, i) end
            end
            send("all", "liars:unseated", ancienne)
        end

        player_by_seat[chair_n] = player
        seat_by_player[player:GetID()] = chair_n
        -- Le personnage se retrouve par la session : il n'y a pas de valeur
        -- posee sur le joueur dans ce depot.
        local session = Characters.SessionByPlayer(player:GetID())
        seated[#seated + 1] = {
            player       = player,
            chair        = chair_n,
            character_id = session and session.character_id or 0,
        }

        send("all", "liars:seated", chair_n, player:GetID())
        Log.Info("liars", ("chaise %d occupee (%d assis)"):format(chair_n, #seated), cid)
        return true
    end

    function Adapter.Begin(player, cid)
        if state then
            return false, "partie_en_cours"
        end
        -- Seul un joueur assis lance la partie : un passant qui touche le
        -- revolver ne la declenche pas pour les autres.
        if not (player and seat_by_player[player:GetID()]) then
            return false, "pas_assis"
        end
        if #seated < config.min_players then
            return false, "pas_assez_de_joueurs"
        end

        -- Ordre des chaises croissant : la table doit tourner dans le sens ou on
        -- la voit, pas dans l'ordre d'arrivee des joueurs.
        table.sort(seated, function(a, b) return a.chair < b.chair end)

        local ids = {}
        for i, entry in ipairs(seated) do
            ids[i] = entry.player:GetID()
        end

        -- Reindexation : le moteur numerote ses places de 1 a n sans trou, alors
        -- que les chaises occupees peuvent etre la 2, la 3 et la 4. Les tables
        -- passent sur la numerotation du moteur, dans l'ordre autour de la
        -- table — c'est a cela que servait le tri —, et chair_of garde le chemin
        -- inverse jusqu'a la fin de la partie.
        player_by_seat, seat_by_player, chair_of = {}, {}, {}
        for i, entry in ipairs(seated) do
            entry.seat = i
            player_by_seat[i] = entry.player
            seat_by_player[entry.player:GetID()] = i
            chair_of[i] = entry.chair
        end

        started_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

        local ok, nouveau, effects = pcall(Engine.Start, ids, function(n) return math.random(n) end)
        if not ok then
            Log.Error("liars", "demarrage impossible : " .. tostring(nouveau), cid)

            -- Retour aux chaises. Sans cela, un joueur assis en chaise 4 vivrait
            -- a l'indice 2 et une chaise vide se declarerait occupee, sans que
            -- rien ne le repare hors redemarrage du serveur.
            player_by_seat, seat_by_player, chair_of = {}, {}, {}
            for _, entry in ipairs(seated) do
                entry.seat = nil
                player_by_seat[entry.chair] = entry.player
                seat_by_player[entry.player:GetID()] = entry.chair
            end
            started_at = nil

            return false, "demarrage_impossible"
        end

        state = nouveau
        dispatch(effects, cid)
        Adapter.ArmShootTimeout()

        Log.Info("liars", ("partie demarree a %d joueurs"):format(#ids), cid)
        return true
    end

    ---------------------------------------------------------------- init

    function Adapter.Init()
        local layout = config.layout
        local home = layout.revolver_home
        revolver_home = Vector(home.x, home.y, home.z)

        for chair_n, marker in ipairs(layout.chairs) do
            local loc = marker.location

            -- Le revolver s'arrete aux deux tiers du chemin vers la chaise et
            -- reste a hauteur du plateau.
            devant_chaise[chair_n] = Vector(
                home.x + (loc.x - home.x) * 0.66,
                home.y + (loc.y - home.y) * 0.66,
                home.z)

            local debug_chair = layout.debug_visible_chair
            if debug_chair == nil or debug_chair == chair_n then
                -- IgnoreOnlyPawn laisse traverser le volume par le personnage
                -- tout en le gardant detectable par la trace d'interaction.
                -- Un petit Prop est saisissable par defaut, et la saisie
                -- emporterait le repere loin de sa chaise : on l'interdit.
                local prop = Prop(
                    Vector(loc.x, loc.y, loc.z),
                    Rotator(0, marker.yaw, 0),
                    ASSETS.seat_marker,
                    CollisionType.IgnoreOnlyPawn,
                    false,
                    GrabMode.Disabled
                )
                prop:SetScale(Vector(marker.scale.x, marker.scale.y, marker.scale.z))

                if debug_chair == nil then
                    prop:SetVisibility(false)
                end

                Interactables.Register(prop, {
                    label = ("S'asseoir (place %d)"):format(chair_n),
                    on_interact = function(player, session, entry, cid)
                        Adapter.Seat(player, chair_n, cid)
                    end,
                })
            end
        end

        -- Le revolver au centre porte deux actes : lancer la partie, et tirer.
        -- C'est le meme objet parce que c'est le meme geste — on y pose la main.
        revolver_prop = Prop(
            revolver_home,
            Rotator(0, 0, 0),
            ASSETS.revolver,
            CollisionType.IgnoreOnlyPawn,
            false,
            GrabMode.Disabled
        )

        Interactables.Register(revolver_prop, {
            label = "Prendre le revolver",
            on_interact = function(player, session, entry, cid)
                if not state then
                    return Adapter.Begin(player, cid)
                end
                local seat = seat_by_player[player:GetID()]
                if seat then
                    Adapter.Act({ kind = "shoot", seat = seat }, cid)
                end
            end,
        })

        -- Les deux intentions heritent du pipeline : audit et correlation
        -- viennent gratuitement. Elles ne revalident PAS la distance — seule
        -- l'intention interact du registre le fait. Ce qui fait foi ici, c'est
        -- d'etre inscrit a une place de la partie en cours.
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
                -- La cible part chez le client : c'est donc une chaise, relevee
                -- AVANT l'acte, qu'une fin de partie remettrait a zero.
                local c = chair_of[seat]
                local ok, raison = Adapter.Act(
                    { kind = "play", seat = seat, indices = payload.indices }, cid)
                return ok, {
                    target = "chair:" .. tostring(c),
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
                local c = chair_of[seat]
                local ok, raison = Adapter.Act({ kind = "challenge", seat = seat }, cid)
                return ok, {
                    target = "chair:" .. tostring(c),
                    audit  = ok and "conteste" or tostring(raison),
                }
            end,
        })

        if layout.debug_visible_chair then
            Log.Info("liars", ("calibration : place %d visible")
                :format(layout.debug_visible_chair))
        else
            Log.Info("liars", ("table initialisee : %d places"):format(config.max_seats))
        end
    end

    -- Un joueur qui part compte comme elimine si une partie tourne. Mais il faut
    -- AUSSI liberer sa chaise quand aucune partie n'a commence : sinon elle reste
    -- occupee pour la vie du serveur, le fantome est encore compte parmi les
    -- assis, et il peut recevoir une main — apres quoi la partie se bloque des que
    -- le tour l'atteint, puisqu'il n'y a pas de delai de tour.
    function Adapter.OnPlayerLeave(player)
        local player_id = player:GetID()
        local seat = seat_by_player[player_id]
        if not seat then return end

        if state then
            Adapter.Act({ kind = "leave", seat = seat })
            return
        end

        -- Hors partie, `seat` est une chaise.
        seat_by_player[player_id] = nil
        player_by_seat[seat] = nil
        for i = #seated, 1, -1 do
            if seated[i].chair == seat then table.remove(seated, i) end
        end

        send("all", "liars:unseated", seat)
        Log.Info("liars", ("chaise %d liberee, joueur parti avant le debut"):format(seat))
    end

    return Adapter
end
