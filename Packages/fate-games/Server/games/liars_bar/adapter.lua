-- Le seul fichier de ce module qui connaisse nanos world.
--
-- Il ne prend AUCUNE decision : il ne verifie pas un tour, ne juge pas une
-- contestation, ne tire pas au hasard. S'il faut un `if` sur une regle du jeu,
-- il est au mauvais endroit — cela appartient au moteur. Ici, de la traduction
-- et de la comptabilite, rien d'autre.
--
-- C'est aussi pour cette raison qu'il n'est pas couvert par le banc de test :
-- il n'y a rien a y verifier qui ne soit deja verifie ailleurs.

return function(Log, DB, Ids, Characters, Interactables, Intents, Engine, Bots, Appearances, config, spawn)
    local Adapter = {}

    -- Le Nagant M1895 est cuit dans my-asset-pack (MyAssetPack/Revolver) depuis
    -- le 19/09/2026. Faux, la bouteille integre reprend sa place : sans
    -- maillage, la trace du client ne touche rien et aucune partie ne peut
    -- demarrer.
    --
    -- Le FBX prepare (Downloads/nagant-m1895) est a l'echelle reelle, 23.5 cm
    -- de long et 4.3 d'epaisseur, pivot au centre : debout a l'import, canon
    -- sur Y. On le couche sur le flanc (tangage 90) et on le leve de la moitie
    -- de son epaisseur pour qu'il repose sur le plateau.
    local REVOLVER_CUIT = true

    -- Les dix apparences sont cuites dans my-asset-pack (bilan du 19/09/2026 :
    -- toutes leurs pieces y sont). Faux, l'apparence serait seulement
    -- journalisee. Elles n'habillent que les personnages Creative : le corps
    -- nanos des bots est laisse tel quel.
    local APPARENCES_CUITES = true

    -- Les references d'assets, rassemblees ici et nulle part ailleurs. Une
    -- reference de mesh invalide echoue EN SILENCE cote Lua : le prop est quand
    -- meme cree et seul le log serveur signale "Asset Pack not found". Les
    -- avoir au meme endroit rend ce diagnostic possible.
    local ASSETS = {
        seat_marker = "nanos-world::SM_Cube",
        bot_body    = "nanos-world::SK_Male",

        revolver = REVOLVER_CUIT and "my-asset-pack::SM_Nagant_M1895"
            or "nanos-world::SM_Bottle_01",
    }

    -- Pose du revolver sur la table : hauteur au-dessus du plateau (cm) et
    -- orientation. La bouteille tient debout sur son pied.
    local POSE_REVOLVER = REVOLVER_CUIT and { lever = 2.2, rot = Rotator(90, 0, 0) }
        or { lever = 0, rot = Rotator(0, 0, 0) }

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
    local reperes        = {}    -- chaise -> son repere (Prop invisible)

    -- Bots de test. Chaque lot d'effets incremente la generation : un
    -- minuteur de bot arme avant ne joue que si rien n'a bouge depuis.
    local bot_generation = 0
    local function bot_rng(n) return math.random(n) end

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

        -- Un bot n'a pas de client : rien a lui envoyer, et ce n'est pas une anomalie.
        if player.bot then return end

        -- Cote serveur : (evenement, joueur, fiabilite, ...). Omettre la
        -- fiabilite decale le premier argument utile dans ce parametre.
        Events.CallRemote(event, player, Reliability.Reliable, ...)
    end

    -- Un refus par E doit revenir au joueur : le registre d'interaction ignore
    -- ce que rend on_interact, et le client recevrait "ok".
    local function refuser(player, raison, contexte)
        if player and not player.bot then
            Events.CallRemote("liars:refused", player, Reliability.Reliable, raison, contexte)
        end
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
        if not player then return nil end
        -- Un bot n'a pas de session : son corps est range dans son entree d'assise.
        if player.bot then
            for _, entry in ipairs(seated) do
                if entry.player == player then return entry.body end
            end
            return nil
        end
        return player:GetControlledCharacter()
    end

    -- ESSAI : le personnage d'un vrai joueur s'assoit sur le repere de sa
    -- chaise, tourne vers le centre de la table. Characters decide si ce
    -- personnage sait s'asseoir ; un bot garde son corps debout.
    local function asseoir_personnage(player, chair_n)
        if not player or player.bot then return end
        local loc  = config.layout.chairs[chair_n].location
        local home = config.layout.revolver_home
        local yaw  = math.deg(math.atan(home.y - loc.y, home.x - loc.x))
        Characters.Sit(player:GetID(), loc.x, loc.y, yaw)
    end

    local function relever_personnage(player)
        if not player or player.bot then return end
        Characters.Stand(player:GetID())
    end

    -- Le personnage qui occupe une place : le corps d'un bot, sinon celui du
    -- joueur. Sa chaise est publiee sur lui en valeur synchronisee : chaque
    -- client s'en sert pour savoir a qui donner des dos de cartes. 0 = aucune.
    local function personnage_de(entry)
        if entry.bot then return entry.body end
        local session = Characters.SessionByPlayer(entry.player:GetID())
        return session and session.character or nil
    end

    local function marquer_chaise(entry, chaise)
        local ok, err = pcall(function()
            local c = personnage_de(entry)
            if c and c:IsValid() then c:SetValue("liars_chair", chaise, true) end
        end)
        if not ok then
            Log.Warn("liars", "marque de chaise impossible : " .. tostring(err))
        end
    end

    local function placer_revolver(position)
        if revolver_prop and position then
            revolver_prop:SetLocation(position)
        end
    end

    ---------------------------------------------------------------- remise a zero

    local function remettre_a_zero()
        for _, entry in ipairs(seated) do
            marquer_chaise(entry, 0)
            if entry.body then entry.body:Destroy() end
        end
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

        -- Les pieces du pack n'habillent que le squelette Creative, donc un
        -- CharacterSimple. Le corps nanos d'un bot n'a pas ce squelette : on
        -- le laisse tel quel plutot que de le deformer.
        if not character:IsA(CharacterSimple) then
            Log.Info("liars", ("apparence %s ignoree a la chaise %s : pas un personnage Creative")
                :format(tostring(e.look), tostring(chair(e.seat))))
            return
        end

        character:SetMesh(look.body)
        character:RemoveAllStaticMeshesAttached()
        character:RemoveAllSkeletalMeshesAttached()

        -- Tetes et vetements sont tous des maillages squelettiques du pack,
        -- attaches en "master pose" : ils suivent les os du corps.
        for i, mesh in ipairs(look.head) do
            character:AddSkeletalMeshAttached("liars_head_" .. i, mesh)
        end
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
        local avec_bots = false
        for i, entry in ipairs(seated) do
            releve.seated[i] = {
                seat         = entry.seat,
                chair        = entry.chair,
                character_id = entry.character_id,
            }
            if entry.bot then avec_bots = true end
        end
        for seat, look in pairs(state and state.match.looks or {}) do
            releve.looks[seat] = look
        end
        for seat, c in pairs(chair_of) do
            releve.chair_of[seat] = c
        end
        local chaise_gagnante = e.winner ~= nil and releve.chair_of[e.winner] or nil
        local a_relever = {}
        for _, entry in ipairs(seated) do a_relever[#a_relever + 1] = entry.player end

        remettre_a_zero()

        -- Tout le monde se leve. Sous pcall, apres la remise a zero : un
        -- personnage qui refuse de se relever ne doit pas bloquer la table.
        for _, p in ipairs(a_relever) do
            local ok, err = pcall(relever_personnage, p)
            if not ok then
                Log.Error("liars", "relever un joueur a echoue : " .. tostring(err))
            end
        end

        if avec_bots then
            Log.Info("liars", "partie avec bots : resultat non enregistre")
        else
            local ok, err = pcall(Adapter.PersistResult, e.winner, e.summary, releve)
            if not ok then
                Log.Error("liars", "resultat non ecrit : " .. tostring(err))
            end
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

    -- Si le jeu attend un bot, on lui demande son coup apres un delai. Le
    -- coup est decide sur l'etat COURANT a l'echeance, et seulement si aucun
    -- lot d'effets n'est passe entre-temps : un minuteur perime ne joue pas.
    function Adapter.ScheduleBots()
        bot_generation = bot_generation + 1
        local seat = Bots.Awaited(state)
        local player = seat and player_by_seat[seat]
        if not (player and player.bot) then return end

        local generation = bot_generation
        Timer.SetTimeout(function()
            if generation ~= bot_generation then return end
            local act = Bots.Decide(state, seat, bot_rng)
            if not act then return end
            local ok, raison = Adapter.Act(act)
            if not ok then
                Log.Warn("liars", "coup de bot refuse : " .. tostring(raison))
            end
        end, math.floor(config.bots.delay * 1000))
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
        Adapter.ScheduleBots()
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
            name         = player:GetName(),
            bot          = player.bot or nil,
        }

        send("all", "liars:seated", chair_n, player:GetID(), player:GetName())
        Log.Info("liars", ("chaise %d occupee (%d assis)"):format(chair_n, #seated), cid)
        asseoir_personnage(player, chair_n)
        marquer_chaise(seated[#seated], chair_n)
        return true
    end

    -- Se lever : E sur sa propre chaise, hors partie seulement. En partie on
    -- reste a sa place jusqu'au bout.
    function Adapter.Stand(player, cid)
        if state then
            return false, "partie_en_cours"
        end
        local chair_n = seat_by_player[player:GetID()]
        if not chair_n then
            return false, "pas_a_table"
        end

        seat_by_player[player:GetID()] = nil
        player_by_seat[chair_n] = nil
        for i = #seated, 1, -1 do
            if seated[i].chair == chair_n then table.remove(seated, i) end
        end

        send("all", "liars:unseated", chair_n)
        Log.Info("liars", ("chaise %d liberee (%d assis)"):format(chair_n, #seated), cid)
        relever_personnage(player)
        marquer_chaise({ player = player }, 0)
        return true
    end

    ---------------------------------------------------------------- bots de test

    -- Un bot est un pseudo-joueur : il repond a GetID et GetName comme un
    -- Player. Son identifiant est l'oppose de sa chaise, jamais celui d'un
    -- vrai joueur.
    local function nouveau_bot(chair_n)
        local id = -chair_n
        return {
            bot     = true,
            GetID   = function() return id end,
            GetName = function() return "Bot " .. chair_n end,
        }
    end

    -- Un personnage Creative assis sur sa chaise, tourne vers la table, comme
    -- un joueur : son eventail et ses tenues suivent les memes regles. Sans
    -- personnage Creative, l'ancien corps nanos, debout derriere la chaise
    -- (il n'a pas d'animation assise et heurterait la chaise cuite).
    local function corps_de_bot(chair_n)
        local loc  = config.layout.chairs[chair_n].location
        local home = config.layout.revolver_home
        local vers_table = math.deg(math.atan(home.y - loc.y, home.x - loc.x))
        local assis = Characters.CorpsAssis(loc.x, loc.y, config.layout.z_assis, vers_table)
        if assis then return assis end

        local dx, dy = loc.x - home.x, loc.y - home.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1 then len = 1 end
        local recul = config.bots.body_offset
        local yaw = math.deg(math.atan(-dy, -dx))
        return Character(
            Vector(loc.x + dx / len * recul, loc.y + dy / len * recul, loc.z + 100.0),
            Rotator(0, yaw, 0),
            ASSETS.bot_body
        )
    end

    -- Fixe le nombre de bots assis : on retire ceux qui sont la, puis on en
    -- assoit n aux chaises libres, par ordre croissant. Hors partie seulement.
    function Adapter.SetBots(n)
        if state then return false, "partie_en_cours" end

        for i = #seated, 1, -1 do
            local entry = seated[i]
            if entry.bot then
                if entry.body then entry.body:Destroy() end
                player_by_seat[entry.chair] = nil
                seat_by_player[entry.player:GetID()] = nil
                table.remove(seated, i)
                send("all", "liars:unseated", entry.chair)
            end
        end

        local assis = 0
        for chair_n = 1, #config.layout.chairs do
            if assis >= n then break end
            if not player_by_seat[chair_n] and Adapter.Seat(nouveau_bot(chair_n), chair_n) then
                seated[#seated].body = corps_de_bot(chair_n)
                marquer_chaise(seated[#seated], chair_n)
                assis = assis + 1
            end
        end

        Log.Info("liars", ("%d bot(s) a la table"):format(assis))
        return true, assis
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
            return false, "pas_assez_de_joueurs", { assis = #seated, minimum = config.min_players }
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

        -- Le moteur n'annonce pas le debut : les clients l'apprennent ici,
        -- avant la premiere carte de table.
        local annonce = {}
        for i, entry in ipairs(seated) do
            annonce[i] = { chair = entry.chair, name = entry.name }
        end
        send("all", "liars:started", annonce)

        -- ESSAI : chacun prend ses cartes en main, bots compris quand leur
        -- corps est un personnage Creative. Sous pcall : une pose qui echoue
        -- ne doit pas empecher la partie.
        for _, entry in ipairs(seated) do
            local ok, err = pcall(function()
                if not entry.bot then
                    Characters.SetHolding(entry.player:GetID(), true)
                elseif entry.body and entry.body:IsValid() and entry.body:IsA(CharacterSimple) then
                    entry.body:SetValue("cartes", true, true)
                end
            end)
            if not ok then Log.Warn("liars", "pose cartes en main : " .. tostring(err)) end
        end

        dispatch(effects, cid)
        Adapter.ArmShootTimeout()
        Adapter.ScheduleBots()

        Log.Info("liars", ("partie demarree a %d joueurs"):format(#ids), cid)
        return true
    end

    ---------------------------------------------------------------- disposition

    -- Le revolver s'arrete aux deux tiers du chemin vers chaque chaise et
    -- reste a la hauteur de sa place de repos.
    local function recalculer_devant()
        local home = config.layout.revolver_home
        for chair_n, marker in ipairs(config.layout.chairs) do
            local loc = marker.location
            devant_chaise[chair_n] = Vector(
                home.x + (loc.x - home.x) * 0.66,
                home.y + (loc.y - home.y) * 0.66,
                revolver_home.Z)
        end
    end

    ---------------------------------------------------------------- atelier

    -- Le revolver et les reperes des chaises se deplacent a l'atelier
    -- (panneau dev, F2 : Physics Gun, Tool Gun). Une place enregistree
    -- revient par "atelier:place" a chaque demarrage ; c'est ici qu'elle
    -- devient la disposition de la table. Sans atelier, rien ne se passe.
    local JEU = "fate-games"

    local function declarer_objets()
        if not revolver_prop then return end
        local liste = { { id = "liars.revolver", label = "Revolver", entite = revolver_prop } }
        for chair_n, prop in ipairs(reperes) do
            liste[#liste + 1] = { id = "liars.chaise." .. chair_n, label = "Chaise " .. chair_n, entite = prop }
        end
        Events.Call("atelier:declarer_objets", JEU, liste)
    end

    local function lieu_valide(l)
        if type(l) ~= "table" then return false end
        for _, k in ipairs({ "x", "y", "z", "p", "ya", "r" }) do
            if type(l[k]) ~= "number" or l[k] ~= l[k] then return false end
        end
        return true
    end

    -- La place du revolver est sa pose de repos : position (levee comprise)
    -- et rotation. Le plateau est a la moitie de son epaisseur plus bas ; le
    -- centre de la table est publie aux clients pour le tas de cartes.
    local function placer_revolver_repos(lieu)
        revolver_home = Vector(lieu.x, lieu.y, lieu.z)
        config.layout.revolver_home = { x = lieu.x, y = lieu.y, z = lieu.z - POSE_REVOLVER.lever }
        recalculer_devant()
        if revolver_prop then
            revolver_prop:SetRotation(Rotator(lieu.p, lieu.ya, lieu.r))
            revolver_prop:SetValue("liars_home", config.layout.revolver_home, true)
            if not state then revolver_prop:SetLocation(revolver_home) end
        end
    end

    -- La place d'une chaise est celle de son repere : on s'y assoit, et le
    -- revolver glisse vers elle.
    local function placer_chaise(chair_n, lieu)
        local marker = config.layout.chairs[chair_n]
        if not marker then return end
        marker.location = { x = lieu.x, y = lieu.y, z = lieu.z }
        marker.yaw = lieu.ya
        recalculer_devant()
        local prop = reperes[chair_n]
        if prop then
            prop:SetLocation(Vector(lieu.x, lieu.y, lieu.z))
            prop:SetRotation(Rotator(lieu.p, lieu.ya, lieu.r))
        end
    end

    Events.Subscribe("atelier:place", function(id, lieu)
        if type(id) ~= "string" or not lieu_valide(lieu) then return end
        local ok, err = pcall(function()
            if id == "liars.revolver" then
                placer_revolver_repos(lieu)
            else
                local n = tonumber(id:match("^liars%.chaise%.(%d+)$"))
                if n then placer_chaise(n, lieu) end
            end
        end)
        if ok then
            Log.Info("liars", ("place %s appliquee"):format(id))
        else
            Log.Warn("liars", ("place %s refusee : %s"):format(id, tostring(err)))
        end
    end)

    -- L'atelier peut se charger apres le jeu : il le signale.
    Events.Subscribe("atelier:pret", declarer_objets)

    ---------------------------------------------------------------- init

    function Adapter.Init()
        local layout = config.layout
        local home = layout.revolver_home
        revolver_home = Vector(home.x, home.y, home.z + POSE_REVOLVER.lever)
        recalculer_devant()

        for chair_n, marker in ipairs(layout.chairs) do
            local loc = marker.location

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
            reperes[chair_n] = prop

            if not layout.debug_visible then
                prop:SetVisibility(false)
            end

            Interactables.Register(prop, {
                label = ("S'asseoir (place %d)"):format(chair_n),
                on_interact = function(player, session, entry, cid)
                    -- E sur sa propre chaise, hors partie : on se leve.
                    local ok, raison
                    if not state and seat_by_player[player:GetID()] == chair_n then
                        ok, raison = Adapter.Stand(player, cid)
                    else
                        ok, raison = Adapter.Seat(player, chair_n, cid)
                    end
                    if not ok then refuser(player, raison) end
                end,
            })
        end

        -- Le revolver au centre porte deux actes : lancer la partie, et tirer.
        -- C'est le meme objet parce que c'est le meme geste — on y pose la main.
        revolver_prop = Prop(
            revolver_home,
            POSE_REVOLVER.rot,
            ASSETS.revolver,
            CollisionType.IgnoreOnlyPawn,
            false,
            GrabMode.Disabled
        )

        Interactables.Register(revolver_prop, {
            label = "Prendre le revolver",
            on_interact = function(player, session, entry, cid)
                if not state then
                    local ok, raison, contexte = Adapter.Begin(player, cid)
                    if not ok then refuser(player, raison, contexte) end
                    return
                end
                local seat = seat_by_player[player:GetID()]
                if not seat then
                    return refuser(player, "pas_a_table")
                end
                local ok, raison = Adapter.Act({ kind = "shoot", seat = seat }, cid)
                if not ok then refuser(player, raison) end
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

        declarer_objets()

        if layout.debug_visible then
            Log.Info("liars", ("calibration : %d places visibles"):format(#layout.chairs))
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
