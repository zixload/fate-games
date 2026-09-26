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

    local ANIMATIONS = {
        accuse = {
            left = "my-asset-pack::ANIM_Seated_Accuse_Left",
            center = "my-asset-pack::ANIM_Seated_Accuse_Center",
            right = "my-asset-pack::ANIM_Seated_Accuse_Right",
        },
        take = "my-asset-pack::ANIM_Seated_Revolver_Take",
        fire = "my-asset-pack::ANIM_Seated_Revolver_Fire",
        fatal = "my-asset-pack::ANIM_Seated_Revolver_Fatal",
        card_play = "my-asset-pack::ANIM_Seated_Card_Play",
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
    -- Salon d'avant-partie (salon.lua) et argent en jeu (domain/boutique.lua,
    -- injecte par Adapter.SetBoutique) : la mise de la partie en cours.
    local Salon          = Package.Require("games/liars_bar/salon.lua")(config)
    local salon          = Salon.New()
    local Boutique       = nil
    local mise_en_cours  = nil   -- { partie, mise, comptes = chaise -> compte, avec_bots }
    local numero_partie  = 0
    -- Pause de lecture apres une revelation : jeton de la pause en cours et
    -- departs survenus pendant (rejoues apres, comme pendant un tir).
    local pause_lecture  = nil
    local player_by_seat = {}
    local seat_by_player = {}
    local chair_of       = {}    -- place moteur -> chaise, le temps d'une partie
    local started_at     = nil

    local shoot_timer      = nil
    local shoot_timer_seat = nil   -- la place pour laquelle ce delai court
    local shot_sequence    = nil   -- resultat valide, en attente de la fin du geste
    local gun_raised       = nil   -- { seat, chair, ready } : arme prise, verdict encore secret
    local debug_body       = nil   -- mannequin de reglage hors partie
    local debug_gun        = nil   -- copie de l'arme ; ne touche pas au jeu
    local debug_owner      = nil

    -- Un revolver par chaise. Le centre reste l'ancre du plateau et du tas de
    -- cartes ; chaque arme a sa propre position et son propre barillet moteur.
    local revolver_props = {}    -- chaise -> Prop
    local revolver_home  = nil   -- ancre au centre de la table
    local devant_chaise  = {}    -- chaise -> position du revolver
    local revolver_offset = {}   -- chaise -> decalage ajuste a l'atelier
    local revolver_rotation = {} -- chaise -> orientation au repos
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

    local function position_assise(chair_n)
        local loc = config.layout.chairs[chair_n].location
        local home = config.layout.revolver_home
        local dx, dy = home.x - loc.x, home.y - loc.y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance < 1 then distance = 1 end
        local avance = config.layout.seat_forward or 0
        return loc.x + dx / distance * avance,
            loc.y + dy / distance * avance,
            loc.z + config.layout.character_height,
            math.deg(math.atan(dy, dx))
    end

    -- La meme position sur le coussin sert aux joueurs et aux bots Creative.
    local function asseoir_personnage(player, chair_n)
        if not player or player.bot then return end
        local x, y, z, yaw = position_assise(chair_n)
        Characters.Sit(player:GetID(), x, y, yaw, z)
    end

    local function relever_personnage(player)
        if not player or player.bot then return end
        local player_id = player:GetID()
        local session = Characters.SessionByPlayer(player_id)
        local character = session and session.character
        if character and character:IsValid() then
            -- La chute fatale reste volontairement sur sa derniere image pendant
            -- la partie. Il faut retirer ce montage avant de repasser debout :
            -- Assis=false dans l'Animation Blueprint ne suffit pas a l'ecraser.
            if character:GetValue("liars_dead", false) and character:IsA(CharacterSimple) then
                local ok, err = pcall(function() character:StopAnimation(ANIMATIONS.fatal) end)
                if not ok then Log.Warn("liars", "arret de la chute fatale : " .. tostring(err)) end
            end
            character:SetValue("liars_dead", false, true)
            character:SetValue("liars_alive", false, true)
        end
        return Characters.Stand(player_id)
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
            if c and c:IsValid() then
                c:SetValue("liars_name", chaise > 0 and entry.name or "", true)
                c:SetValue("liars_chair", chaise, true)
            end
        end)
        if not ok then
            Log.Warn("liars", "marque de chaise impossible : " .. tostring(err))
        end
    end

    local function ranger_revolvers(force)
        for chair_n, prop in ipairs(revolver_props) do
            if prop and prop:IsValid() and devant_chaise[chair_n] then
                -- Un nouveau tour peut etre annonce avant que la main ait
                -- repose l'arme : sa propre animation termine ce geste.
                if force or not (shot_sequence and shot_sequence.chair == chair_n
                    and prop:GetAttachedTo()) then
                    if prop:GetAttachedTo() then prop:Detach() end
                    prop:SetLocation(devant_chaise[chair_n])
                    local pose = revolver_rotation[chair_n]
                    prop:SetRotation(pose and Rotator(pose.p, pose.ya, pose.r) or POSE_REVOLVER.rot)
                    prop:SetCollision(CollisionType.IgnoreOnlyPawn)
                    prop:SetVisibility(true)
                end
            end
        end
    end

    -- Meme calage pour l'arme du jeu et celle du mannequin de reglage.
    local function poser_dans_la_main(prop)
        local g = config.revolver_prise or {}
        prop:SetRelativeLocation(Vector(g.x or 0, g.y or 0, g.z or 0))
        prop:SetRelativeRotation(Rotator(g.p or 0, g.ya or 0, g.r or 0))
    end

    local function attacher_a_la_main(prop, character)
        local ok = prop:AttachTo(character, AttachmentRule.SnapToTarget, "RightHandProp", -1)
        if not ok then return false end
        poser_dans_la_main(prop)
        prop:SetCollision(CollisionType.NoCollision)
        return true
    end

    local function arreter_pose_revolver(preparation)
        if not preparation then return end
        local character = character_of(preparation.seat)
        if character and character:IsValid() and character:IsA(CharacterSimple) then
            local ok, err = pcall(function() character:StopAnimation(ANIMATIONS.take) end)
            if not ok then Log.Warn("liars", "arret de la pose du revolver : " .. tostring(err)) end
        end
    end

    -- Reglage en jeu de la prise (commande /prise, mode dev) : s'applique
    -- aussitot aux revolvers deja en main.
    function Adapter.SetPrise(prise)
        config.revolver_prise = prise
        for _, prop in ipairs(revolver_props) do
            if prop and prop:IsValid() and prop:GetAttachedTo() then
                poser_dans_la_main(prop)
            end
        end
        if debug_gun and debug_gun:IsValid() and debug_gun:GetAttachedTo() then
            poser_dans_la_main(debug_gun)
        end
        return prise
    end

    function Adapter.GetPrise()
        return config.revolver_prise
    end

    function Adapter.AdjustPrise(axis, delta)
        if not ({ x = true, y = true, z = true, p = true, ya = true, r = true })[axis]
            or type(delta) ~= "number" or delta ~= delta
            or math.abs(delta) > 90 then return nil end
        local current = config.revolver_prise or {}
        local prise = {
            x = current.x or 0, y = current.y or 0, z = current.z or 0,
            p = current.p or 0, ya = current.ya or 0, r = current.r or 0,
        }
        prise[axis] = prise[axis] + delta
        return Adapter.SetPrise(prise)
    end

    function Adapter.StopPoseBot()
        if debug_gun and debug_gun:IsValid() then debug_gun:Destroy() end
        if debug_body and debug_body:IsValid() then debug_body:Destroy() end
        debug_gun, debug_body, debug_owner = nil, nil, nil
    end

    -- Mannequin Creative independant des places et de l'etat de partie. Le
    -- premier clip garde sa derniere pose indefiniment (blend_out = -1).
    -- L'arme utilise exactement le meme socket et le meme calage que le jeu.
    function Adapter.PoseBot(player, chair_n)
        if state or gun_raised or shot_sequence then return false, "partie_en_cours" end
        if not player then return false, "joueur_absent" end
        local player_chair = seat_by_player[player:GetID()]
        chair_n = chair_n or (player_chair and ((player_chair + 1) % 4 + 1)) or 1
        if not config.layout.chairs[chair_n] then return false, "chaise_invalide" end
        if player_by_seat[chair_n] then return false, "chaise_occupee" end
        Adapter.StopPoseBot()

        local x, y, z, yaw = position_assise(chair_n)
        local body = Characters.CorpsAssis(x, y, z, yaw)
        if not (body and body:IsValid() and body:IsA(CharacterSimple)) then
            if body and body:IsValid() then body:Destroy() end
            return false, "mannequin_creative_indisponible"
        end
        local home = devant_chaise[chair_n]
        local rest = revolver_rotation[chair_n] or { p = 90, ya = 0, r = 0 }
        local gun = Prop(home, Rotator(rest.p, rest.ya, rest.r), ASSETS.revolver,
            CollisionType.NoCollision, false, GrabMode.Disabled)
        if not (gun and gun:IsValid()) then
            body:Destroy()
            return false, "revolver_indisponible"
        end
        debug_body, debug_gun, debug_owner = body, gun, player:GetID()
        gun:SetVisibility(false)
        local ok, err = pcall(function()
            body:PlayAnimation(ANIMATIONS.take, "DefaultSlot", false, 0.08, -1, 1.0, true)
        end)
        if not ok then
            Log.Warn("liars", "posebot : animation impossible : " .. tostring(err))
            Adapter.StopPoseBot()
            return false, "animation_indisponible"
        end
        Timer.SetTimeout(function()
            if debug_body ~= body or not body:IsValid() or not gun:IsValid() then return end
            if attacher_a_la_main(gun, body) then
                gun:SetVisibility(true)
            else
                Log.Warn("liars", "posebot : attache a RightHandProp refusee")
                Adapter.StopPoseBot()
            end
        end, 300)
        return true, chair_n
    end

    function Adapter.PoseBotLook(yaw, pitch)
        if not (debug_body and debug_body:IsValid()) then return false end
        debug_body:SetValue("liars_look", {
            yaw = math.max(-30, math.min(30, yaw)),
            pitch = math.max(-15, math.min(15, pitch)),
        }, true)
        return true
    end

    -- Le premier clip s'arrete a la tempe et conserve sa derniere pose jusqu'au
    -- clic. La meme attache que /posebot est appliquee a l'image 10.
    local function prendre_revolver(preparation, character)
        local chair_n = preparation.chair
        local prop = revolver_props[chair_n]
        if not (prop and prop:IsValid() and character and character:IsValid()) then return end

        if character:IsA(CharacterSimple) then
            character:PlayAnimation(ANIMATIONS.take, "DefaultSlot", false, 0.08, -1, 1.0, true)
            Timer.SetTimeout(function()
                if gun_raised ~= preparation
                    or not prop:IsValid() or not character:IsValid() then return end
                if not attacher_a_la_main(prop, character) then
                    Log.Warn("liars", "revolver : attache a RightHandProp refusee")
                end
            end, 300)
            return
        end

        local depart = devant_chaise[chair_n]
        local tete = character:GetLocation()
        local dx, dy = tete.X - revolver_home.X, tete.Y - revolver_home.Y
        local longueur = math.sqrt(dx * dx + dy * dy)
        if longueur < 1 then longueur = 1 end
        -- Sur la tempe droite, un peu devant le visage, sans masquer toute la
        -- vue du joueur assis. La hauteur suit le personnage reel.
        local cible = Vector(tete.X - dy / longueur * 23 - dx / longueur * 12,
            tete.Y + dx / longueur * 23 - dy / longueur * 12, tete.Z + 119)
        local leve = Vector(depart.X, depart.Y, depart.Z + 28)
        local repose = revolver_rotation[chair_n] or { p = 90, ya = 0, r = 0 }
        local orientation = math.deg(math.atan(tete.Y - cible.Y, tete.X - cible.X)) - 90

        local function melanger(a, b, t)
            return Vector(a.X + (b.X - a.X) * t,
                a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
        end

        for step = 1, 12 do
            Timer.SetTimeout(function()
                if gun_raised ~= preparation or not prop:IsValid() then return end
                local progress = step / 12
                local location
                if progress < 0.34 then
                    local t = progress / 0.34
                    location = melanger(depart, leve, t * t * (3 - 2 * t))
                else
                    local t = (progress - 0.34) / 0.66
                    location = melanger(leve, cible, t * t * (3 - 2 * t))
                end
                prop:SetLocation(location)
                prop:SetRotation(Rotator(
                    repose.p + (0 - repose.p) * progress,
                    repose.ya + (orientation - repose.ya) * progress,
                    repose.r))
            end, step * 65)
        end
    end

    ---------------------------------------------------------------- regard des bots

    -- Les bots tournent la tete vers la chaise qui compte : celle dont c'est
    -- le tour, celle designee pour tirer, celle qu'on accuse. La valeur
    -- "liars_look" est celle des joueurs assis ; chaque client l'interpole
    -- (Client/regard_assis.lua), bornee comme celle des joueurs
    -- (Shared/config.lua, regard_assis).
    local chaise_regardee = nil
    local REGARD = Package.Require("Shared/config.lua").regard_assis

    local function angle(degres)
        return (degres + 180) % 360 - 180
    end

    local function regarder(entry, yaw, pitch)
        if not (entry.body and entry.body:IsValid()) then return end
        entry.body:SetValue("liars_look", {
            yaw = math.max(-REGARD.lacet_max, math.min(REGARD.lacet_max, yaw)),
            pitch = math.max(-REGARD.tangage_max, math.min(REGARD.tangage_max, pitch)),
        }, true)
    end

    local function regards_bots()
        for _, entry in ipairs(seated) do
            if entry.bot then
                local bx, by, _, face = position_assise(entry.chair)
                if not chaise_regardee then
                    regarder(entry, 0, 0)
                elseif chaise_regardee == entry.chair then
                    -- A lui de jouer : il regarde ses cartes, sur la table.
                    regarder(entry, 0, -20)
                else
                    local tx, ty = position_assise(chaise_regardee)
                    regarder(entry, angle(math.deg(math.atan(ty - by, tx - bx)) - face), 0)
                end
            end
        end
    end

    local function viser_chaise(c)
        chaise_regardee = c
        regards_bots()
    end

    -- Hors partie, un coup d'oeil au hasard de temps en temps, pour qu'ils
    -- ne restent pas figes face a la table.
    local function coups_d_oeil()
        if state then return end
        for _, entry in ipairs(seated) do
            if entry.bot and math.random() < 0.4 then
                regarder(entry, math.random(-60, 60), math.random(-15, 10))
            end
        end
    end

    ---------------------------------------------------------------- remise a zero

    local function remettre_a_zero()
        chaise_regardee = nil
        -- Detacher avant de detruire un corps de bot porteur du revolver.
        arreter_pose_revolver(gun_raised)
        ranger_revolvers(true)
        gun_raised = nil
        for _, entry in ipairs(seated) do
            marquer_chaise(entry, 0)
            if entry.body then entry.body:Destroy() end
        end
        state, started_at = nil, nil
        player_by_seat, seat_by_player, chair_of, seated = {}, {}, {}, {}
        salon = Salon.New()
        pause_lecture = nil
    end

    ---------------------------------------------------------------- traducteurs

    local TRANSLATORS = {}

    TRANSLATORS.appearance = function(e)
        if not APPARENCES_CUITES then
            Log.Info("liars", ("apparence %s pour la chaise %s : pack non cuit, rien applique")
                :format(tostring(e.look), tostring(chair(e.seat))))
            return
        end

        -- Un joueur garde la tenue choisie au vestiaire (decision du 25/09) :
        -- seuls les bots recoivent celle que le moteur a tiree.
        local occupant = player_by_seat[e.seat]
        if occupant and not occupant.bot then return end

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

    -- Chaque joueur garde son revolver devant sa chaise pendant la partie.
    TRANSLATORS.table_card = function(e)
        ranger_revolvers()
        send(e.audience, "liars:table_card", e.rank)
    end

    TRANSLATORS.cards_played = function(e)
        send(e.audience, "liars:cards_played", chair(e.seat), e.count)
        local character = character_of(e.seat)
        if character and character:IsValid() and character:IsA(CharacterSimple) then
            local ok, err = pcall(function()
                character:PlayAnimation(ANIMATIONS.card_play, "DefaultSlot", false,
                    0.08, 0.12, 1.0, true)
            end)
            if not ok then Log.Warn("liars", "pose des cartes : " .. tostring(err)) end
        end
    end

    TRANSLATORS.reveal = function(e)
        send(e.audience, "liars:reveal", chair(e.seat), e.cards)
    end

    TRANSLATORS.turn = function(e)
        send(e.audience, "liars:turn", chair(e.seat))
        viser_chaise(chair(e.seat))
    end

    TRANSLATORS.round_ended = function(e)
        send(e.audience, "liars:round_ended", e.reason)
    end

    -- L'arme du perdant est deja devant sa propre chaise.
    TRANSLATORS.designated = function(e)
        local c = chair(e.seat)
        send(e.audience, "liars:designated", c)
        viser_chaise(c)
    end

    TRANSLATORS.shoot = function(e)
        -- Le nombre de chambres deja essayees est public et doit aussi etre
        -- visible chez un joueur arrive apres le debut de la partie.
        local character = character_of(e.seat)
        if character and character:IsValid() then
            character:SetValue("liars_fired", e.chamber, true)
        end
        send(e.audience, "liars:shoot", chair(e.seat), e.chamber, e.fatal)
    end

    local function jouer_accusation(character, accuser_chair, target_chair)
        if not (character and character:IsValid() and character:IsA(CharacterSimple)) then
            return false, "corps Creative indisponible"
        end
        local origin = config.layout.chairs[accuser_chair].location
        local target = config.layout.chairs[target_chair].location
        local _, _, _, facing = position_assise(accuser_chair)
        local yaw = math.rad(facing)
        -- (-sin, cos) est la gauche du personnage dans le plan XY.
        local lateral = (target.x - origin.x) * -math.sin(yaw)
            + (target.y - origin.y) * math.cos(yaw)
        -- En jeu les clips importes Left/Right pointent du cote oppose :
        -- on inverse ici leur choix sans modifier les assets deja cuits.
        local side = lateral > 40 and "right" or lateral < -40 and "left" or "center"
        local ok, result = pcall(function()
            return character:PlayAnimation(ANIMATIONS.accuse[side], "DefaultSlot", false,
                0.08, 0.15, 1.0, true)
        end)
        if not ok then return false, tostring(result) end
        if result == false then return false, "animation refusee : " .. ANIMATIONS.accuse[side] end
        return true, side
    end

    TRANSLATORS.accuse = function(e)
        local accuser_chair, target_chair = chair(e.accuser), chair(e.target)
        send(e.audience, "liars:accuse", accuser_chair, target_chair)
        viser_chaise(target_chair)
        local ok, detail = jouer_accusation(character_of(e.accuser), accuser_chair, target_chair)
        if not ok then Log.Warn("liars", "geste d'accusation : " .. tostring(detail)) end
    end

    TRANSLATORS.eliminated = function(e)
        -- Il garde la parole : il n'y a precisement RIEN a faire sur son micro.
        -- Il reste assis, il voit tout, il peut commenter.
        local c = chair(e.seat)
        local character = character_of(e.seat)
        if character and character:IsValid() then
            character:SetValue("liars_alive", false, true)
            character:SetValue("liars_dead", true, true)
            character:SetValue("liars_look", { yaw = 0, pitch = 0 }, true)
            character:SetValue("cartes", false, true)
            if shot_sequence and shot_sequence.chair == c
                and character:IsA(CharacterSimple) then
                local ok, err = pcall(function()
                    character:PlayAnimation(ANIMATIONS.fatal, "DefaultSlot", false,
                        0.04, -1, 1.0, true)
                end)
                if not ok then Log.Warn("liars", "chute fatale : " .. tostring(err)) end
            end
        end
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
        local ok_solde, err_solde = pcall(solder_partie, chaise_gagnante)
        if not ok_solde then Log.Error("liars", "solde de la partie : " .. tostring(err_solde)) end
        local a_relever = {}
        for _, entry in ipairs(seated) do a_relever[#a_relever + 1] = entry.player end

        remettre_a_zero()

        -- Tout le monde se leve. Sous pcall, apres la remise a zero : un
        -- personnage qui refuse de se relever ne doit pas bloquer la table.
        for _, p in ipairs(a_relever) do
            local ok, releve_ou_err = pcall(relever_personnage, p)
            if not ok then
                Log.Error("liars", "relever un joueur a echoue : " .. tostring(releve_ou_err))
            elseif not p.bot and not releve_ou_err then
                Log.Warn("liars", "joueur non releve a la fin de partie : " .. tostring(p:GetID()))
            end
            if not p.bot then
                pcall(Events.CallRemote, "liars:salon", p, Reliability.Reliable, nil)
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
        ranger_revolvers()

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
                Adapter.Act({ kind = "shoot", seat = designe, auto = true })
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
            if act.kind == "shoot" then act.auto = true end
            local ok, raison = Adapter.Act(act)
            if not ok then
                Log.Warn("liars", "coup de bot refuse : " .. tostring(raison))
            end
        end, math.floor(config.bots.delay * 1000))
    end

    function Adapter.PrepareShot(seat)
        if not (state and state.pending) then return false, "aucun_tir_en_attente" end
        if state.pending.seat ~= seat then return false, "pas_designe" end
        if shot_sequence then return false, "tir_en_cours" end
        if gun_raised then return false, "arme_deja_prise" end

        local chair_n = chair(seat)
        local preparation = { seat = seat, chair = chair_n, ready = false }
        gun_raised = preparation
        send("all", "liars:shoot_prepare", chair_n)
        local ok, err = pcall(prendre_revolver, preparation, character_of(seat))
        if not ok then Log.Warn("liars", "prise du revolver : " .. tostring(err)) end
        Timer.SetTimeout(function()
            if gun_raised ~= preparation then return end
            preparation.ready = true
            send("all", "liars:gun_ready", chair_n)
        end, 900)
        return true
    end

    function Adapter.Act(act, cid)
        if not state then
            return false, "aucune partie en cours"
        end
        if shot_sequence then
            return false, "tir_en_cours"
        end
        if pause_lecture then
            return false, "revelation_en_cours"
        end

        if act.kind == "shoot" then
            if not (state.pending and state.pending.seat == act.seat) then
                return false, "aucun_tir_en_attente"
            end
            if not gun_raised then
                if not act.auto then return false, "arme_non_preparee" end
                local ok, raison = Adapter.PrepareShot(act.seat)
                if not ok then return false, raison end
            end
            if gun_raised.seat ~= act.seat then return false, "pas_designe" end
            if not gun_raised.ready then
                if not act.auto then return false, "arme_pas_prete" end
                local attente = gun_raised
                Timer.SetTimeout(function()
                    if gun_raised == attente and state and state.pending
                        and state.pending.seat == act.seat then
                        Adapter.Act({ kind = "shoot", seat = act.seat, auto = true })
                    end
                end, 950)
                return true
            end
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

        if act.kind ~= "shoot" and gun_raised
            and not (state.pending and state.pending.seat == gun_raised.seat) then
            local ancienne_chaise = gun_raised.chair
            arreter_pose_revolver(gun_raised)
            gun_raised = nil
            ranger_revolvers(true)
            send("all", "liars:gun_cancelled", ancienne_chaise)
        end

        if act.kind == "shoot" then
            -- Le moteur ne tranche qu'au clic (ou au delai de secours). Le
            -- clip de tir commence a la pose maintenue contre la tempe.
            local chair_n = chair(act.seat)
            local sequence = { chair = chair_n, departures = {} }
            shot_sequence = sequence
            gun_raised = nil
            Adapter.ArmShootTimeout()
            local character = character_of(act.seat)
            if character and character:IsValid() and character:IsA(CharacterSimple) then
                local ok_anim, err_anim = pcall(function()
                    character:PlayAnimation(ANIMATIONS.fire, "DefaultSlot", false,
                        0.05, 0.15, 1.0, true)
                end)
                if not ok_anim then Log.Warn("liars", "tir du revolver : " .. tostring(err_anim)) end
            end
            Timer.SetTimeout(function()
                if shot_sequence ~= sequence then return end
                -- Une derniere elimination laisse voir la chute avant que la
                -- fin de partie ne releve les joueurs et detruise les bots.
                local fin
                local immediats = {}
                for _, effect in ipairs(effects) do
                    if effect.kind == "match_ended" then
                        fin = effect
                    else
                        immediats[#immediats + 1] = effect
                    end
                end
                dispatch(immediats, cid)
                if fin then
                    Timer.SetTimeout(function()
                        if state then dispatch({ fin }, cid) end
                    end, 1450)
                end
            end, 70)
            Timer.SetTimeout(function()
                if shot_sequence ~= sequence then return end
                ranger_revolvers(true)
                shot_sequence = nil
                Adapter.ArmShootTimeout()
                Adapter.ScheduleBots()
                -- Un deconnecte pendant le geste est elimine apres le coup.
                -- Son depart ne peut ainsi devancer le verdict deja valide.
                for _, player_id in ipairs(sequence.departures) do
                    local seat = seat_by_player[player_id]
                    if state and seat then Adapter.Act({ kind = "leave", seat = seat }) end
                end
            end, 850)
        else
            -- Une revelation : ses cartes restent sous les yeux de tous
            -- config.pause_revelation secondes avant que la suite (le tireur
            -- designe) parte. Rien ne se joue pendant la pause.
            local avant, apres = {}, {}
            for _, effect in ipairs(effects) do
                if #apres == 0 and (avant[#avant] == nil or avant[#avant].kind ~= "reveal") then
                    avant[#avant + 1] = effect
                else
                    apres[#apres + 1] = effect
                end
            end
            local pause = config.pause_revelation or 0
            if pause <= 0 or #apres == 0 or avant[#avant].kind ~= "reveal" then
                dispatch(effects, cid)
                Adapter.ArmShootTimeout()
                Adapter.ScheduleBots()
                return true
            end
            dispatch(avant, cid)
            local jeton = { departures = {} }
            pause_lecture = jeton
            Timer.SetTimeout(function()
                if pause_lecture ~= jeton then return end
                pause_lecture = nil
                dispatch(apres, cid)
                Adapter.ArmShootTimeout()
                Adapter.ScheduleBots()
                for _, player_id in ipairs(jeton.departures) do
                    local seat = seat_by_player[player_id]
                    if state and seat then Adapter.Act({ kind = "leave", seat = seat }) end
                end
            end, math.floor(pause * 1000))
        end
        return true
    end

    ---------------------------------------------------------------- salon

    -- Les assis vus par le salon, dans l'ordre d'arrivee.
    local function assis_salon()
        local out = {}
        for i, e in ipairs(seated) do
            out[i] = { chair = e.chair, nom = e.name, bot = e.bot or nil }
        end
        return out
    end

    -- Le panneau part aux humains assis, hors partie ; celui qui se leve
    -- recoit un salon vide et son panneau se ferme.
    local function diffuser_salon(parti)
        if parti and not parti.bot then
            pcall(Events.CallRemote, "liars:salon", parti, Reliability.Reliable, nil)
        end
        if state then return end
        local a = assis_salon()
        Salon.Accorder(salon, a)
        local vue = Salon.Vue(salon, a)
        for _, e in ipairs(seated) do
            if not e.bot then
                pcall(Events.CallRemote, "liars:salon", e.player, Reliability.Reliable, vue)
            end
        end
    end

    -- Tous prets : on preleve la mise de chaque humain (tout ou rien), puis on
    -- lance. Une table avec un bot ne met rien en jeu.
    local function lancer_salon()
        local a = assis_salon()
        Salon.Accorder(salon, a)
        if state or mise_en_cours or not Salon.ToutPret(salon, a) then return end

        local avec_bots = Salon.AvecBots(a)
        local mise = (avec_bots or not Boutique) and 0 or salon.mise
        local comptes, liste, noms, premier = {}, {}, {}, nil
        for _, e in ipairs(seated) do
            if not e.bot then
                premier = premier or e.player
                local s = Characters.SessionByPlayer(e.player:GetID())
                if s and s.account then
                    comptes[e.chair] = s.account
                    liste[#liste + 1] = s.account
                    noms[s.account] = e.name
                end
            end
        end
        numero_partie = numero_partie + 1
        local partie = ("liars:%d:%d"):format(os.time(), numero_partie)
        mise_en_cours = { partie = partie, mise = mise, comptes = comptes, avec_bots = avec_bots }

        -- Rien ne part : chacun redevient "pas pret" et apprend pourquoi.
        local function annuler(raison, contexte)
            mise_en_cours = nil
            salon.pret = {}
            for _, e in ipairs(seated) do refuser(e.player, raison, contexte) end
            diffuser_salon()
        end

        local function partir()
            local ok, raison, contexte = Adapter.Begin(premier)
            if ok then return end
            -- La mise prelevee revient a chacun, a parts egales.
            if mise > 0 and Boutique then
                Boutique.Solder(partie, {}, liste, mise * #liste, 0)
            end
            annuler(raison, contexte)
        end

        if mise <= 0 then return partir() end
        Boutique.Miser(liste, mise, partie, nil, function(ok, raison, fauches)
            if ok then return partir() end
            local qui = {}
            for _, account in ipairs(fauches or {}) do qui[#qui + 1] = noms[account] or "?" end
            annuler(raison == "solde" and "solde_insuffisant" or "mise_impossible",
                { noms = table.concat(qui, ", ") })
        end)
    end

    -- Fin de partie : la cagnotte au vainqueur, le bonus a chacun.
    local function solder_partie(chaise_gagnante)
        local m = mise_en_cours
        mise_en_cours = nil
        if not (m and Boutique) then return end
        local participants, gagnants = {}, {}
        for chair, account in pairs(m.comptes) do
            participants[#participants + 1] = account
            if chair == chaise_gagnante then gagnants[1] = account end
        end
        -- Un bot vainqueur ne gagne rien : chacun reprend sa mise.
        if #gagnants == 0 then gagnants = participants end
        local cagnotte = m.mise * #participants
        local bonus = m.avec_bots and 0 or config.bonus_participation
        Boutique.Solder(m.partie, participants, gagnants, cagnotte, bonus, nil, function()
            Log.Info("liars", ("partie %s : cagnotte %d a la chaise %s")
                :format(m.partie, cagnotte, tostring(chaise_gagnante)))
        end)
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
        diffuser_salon()
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
        diffuser_salon(player)
        return true
    end

    -- Se lever sans viser sa chaise : Espace chez le client (Client/se_lever.lua).
    -- Un joueur qui n'est pas a table n'a rien a entendre.
    function Adapter.Lever(player, cid)
        local ok, raison = Adapter.Stand(player, cid)
        if not ok and raison ~= "pas_a_table" then refuser(player, raison) end
        return ok, raison
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
        local x, y, z, vers_table = position_assise(chair_n)
        local assis = Characters.CorpsAssis(x, y, z, vers_table)
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
    -- Demo de reglage des cartes (/fan demo) : des bots sur toutes les chaises
    -- libres, en pose "cartes en main", pour verifier chaque place. Hors partie.
    function Adapter.DemoCartes(actif)
        local ok, detail = Adapter.SetBots(actif and #config.layout.chairs or 0)
        if not ok then return ok, detail end
        if actif then
            for _, entry in ipairs(seated) do
                if entry.bot and entry.body and entry.body:IsValid() then
                    entry.body:SetValue("cartes", true, true)
                end
            end
        end
        return true, detail
    end

    function Adapter.SetBots(n)
        if state then return false, "partie_en_cours" end
        if debug_body then Adapter.StopPoseBot() end

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
        diffuser_salon()
        return true, assis
    end

    -- Previsualisation hors partie : le meme clip et le meme corps que lors
    -- d'une accusation reelle, sans attendre la decision aleatoire du bot.
    function Adapter.PreviewBotAccusation(player, bot_chair, target_chair)
        if state then return false, "partie_en_cours" end
        target_chair = target_chair or (player and seat_by_player[player:GetID()])
        if not target_chair or not config.layout.chairs[target_chair] then
            return false, "chaise_cible_invalide"
        end
        if not bot_chair then
            local opposite = (target_chair + 1) % #config.layout.chairs + 1
            local premier_bot
            for _, entry in ipairs(seated) do
                if entry.bot and entry.chair ~= target_chair then
                    premier_bot = premier_bot or entry.chair
                    if entry.chair == opposite then
                        bot_chair = opposite
                        break
                    end
                end
            end
            bot_chair = bot_chair or premier_bot
        end
        if not bot_chair or not config.layout.chairs[bot_chair] or bot_chair == target_chair then
            return false, "chaise_bot_invalide"
        end
        for _, entry in ipairs(seated) do
            if entry.chair == bot_chair and entry.bot then
                local ok, detail = jouer_accusation(entry.body, bot_chair, target_chair)
                if not ok then return false, detail end
                return true, bot_chair, target_chair, detail
            end
        end
        return false, "aucun_bot_sur_cette_chaise"
    end

    -- L'argent des mises (domain/boutique.lua). Sans elle, on joue pour
    -- l'honneur.
    function Adapter.SetBoutique(b)
        Boutique = b
    end

    function Adapter.Begin(player, cid)
        if state then
            return false, "partie_en_cours"
        end
        if debug_body then return false, "mode_reglage_actif" end
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
            local character = character_of(i)
            if character and character:IsValid() then
                character:SetValue("liars_fired", 0, true)
                character:SetValue("liars_alive", true, true)
                character:SetValue("liars_dead", false, true)
            end
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

    -- Chaque arme repose devant sa chaise, sur le bord du plateau.
    local function recalculer_devant()
        local home = config.layout.revolver_home
        for chair_n, marker in ipairs(config.layout.chairs) do
            local loc = marker.location
            local offset = revolver_offset[chair_n] or { x = 0, y = 0, z = 0 }
            local dx, dy = loc.x - home.x, loc.y - home.y
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance < 1 then distance = 1 end
            local rayon = config.layout.revolver_radius
            devant_chaise[chair_n] = Vector(
                home.x + dx / distance * rayon + offset.x,
                home.y + dy / distance * rayon + offset.y,
                revolver_home.Z + offset.z)
            if not revolver_rotation[chair_n] then
                revolver_rotation[chair_n] = {
                    p = 90, ya = math.deg(math.atan(dy, dx)) + 90, r = 0,
                }
            end
        end
        ranger_revolvers()
    end

    ---------------------------------------------------------------- atelier

    -- Le revolver et les reperes des chaises se deplacent a l'atelier
    -- (panneau dev, F2 : Physics Gun, Tool Gun). Une place enregistree
    -- revient par "atelier:place" a chaque demarrage ; c'est ici qu'elle
    -- devient la disposition de la table. Le prefixe furniture2 evite que
    -- des decalages sauvegardes pour l'ancienne table recouvrent la nouvelle.
    local JEU = "fate-games"

    local function declarer_objets()
        if #revolver_props == 0 then return end
        local liste = {}
        for chair_n, prop in ipairs(revolver_props) do
            liste[#liste + 1] = {
                id = "liars.furniture2.revolver." .. chair_n,
                label = "Revolver " .. chair_n,
                entite = prop,
            }
        end
        for chair_n, prop in ipairs(reperes) do
            liste[#liste + 1] = { id = "liars.furniture2.chaise." .. chair_n,
                label = "Chaise " .. chair_n, entite = prop }
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

    -- Une arme de chaise deplacee dans l'atelier garde son decalage quand le
    -- centre ou la chaise bouge ensuite.
    local function placer_revolver_chaise(chair_n, lieu)
        local marker = config.layout.chairs[chair_n]
        local prop = revolver_props[chair_n]
        if not (marker and prop) then return end
        local home = config.layout.revolver_home
        local dx, dy = marker.location.x - home.x, marker.location.y - home.y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance < 1 then distance = 1 end
        local rayon = config.layout.revolver_radius
        revolver_offset[chair_n] = {
            x = lieu.x - (home.x + dx / distance * rayon),
            y = lieu.y - (home.y + dy / distance * rayon),
            z = lieu.z - revolver_home.Z,
        }
        revolver_rotation[chair_n] = { p = lieu.p, ya = lieu.ya, r = lieu.r }
        prop:SetRotation(Rotator(lieu.p, lieu.ya, lieu.r))
        recalculer_devant()
    end

    -- La place d'une chaise est celle de son repere : on s'y assoit, et le
    -- revolver glisse vers elle.
    local function placer_chaise(chair_n, lieu)
        local marker = config.layout.chairs[chair_n]
        if not marker then return end
        marker.location = { x = lieu.x, y = lieu.y,
            z = lieu.z - config.layout.seat_height }
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
            local r = tonumber(id:match("^liars%.furniture2%.revolver%.(%d+)$"))
            local c = tonumber(id:match("^liars%.furniture2%.chaise%.(%d+)$"))
            if r then placer_revolver_chaise(r, lieu)
            elseif c then placer_chaise(c, lieu) end
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
        Timer.SetInterval(function()
            local ok, err = pcall(coups_d_oeil)
            if not ok then Log.Warn("liars", "regard des bots : " .. tostring(err)) end
        end, 2500)
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
                Vector(loc.x, loc.y, loc.z + layout.seat_height),
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
                kind = "seat",
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

        -- Une arme par place, accessible depuis sa chaise. Le joueur ne peut
        -- lancer la partie et tirer qu'avec la sienne ; le moteur garde la
        -- decision sur la place designee et le barillet de chaque joueur.
        for chair_n = 1, #layout.chairs do
            local gun_chair = chair_n
            local prop = Prop(
                devant_chaise[gun_chair],
                Rotator(revolver_rotation[gun_chair].p,
                    revolver_rotation[gun_chair].ya, revolver_rotation[gun_chair].r),
                ASSETS.revolver,
                CollisionType.IgnoreOnlyPawn,
                false,
                GrabMode.Disabled
            )
            -- Le mouvement du geste est pilote par le serveur, meme quand un
            -- joueur est tout pres de l'arme.
            prop:SetNetworkAuthorityAutoDistributed(false)
            prop:SetValue("liars_revolver_chair", gun_chair, true)
            prop:SetValue("liars_home", layout.revolver_home, true)
            revolver_props[gun_chair] = prop

            Interactables.Register(prop, {
                label = ("Prendre son revolver (place %d)"):format(gun_chair),
                kind = "revolver",
                on_interact = function(player, session, entry, cid)
                    local seat = seat_by_player[player:GetID()]
                    if not seat then return refuser(player, "pas_a_table") end
                    local own_chair = state and chair_of[seat] or seat
                    if own_chair ~= gun_chair then
                        return refuser(player, "pas_ton_revolver")
                    end
                    -- Hors partie, son revolver sert a se dire pret (comme R).
                    if not state then
                        if mise_en_cours then return end
                        local a = assis_salon()
                        Salon.Accorder(salon, a)
                        Salon.Pret(salon, a, own_chair, not salon.pret[own_chair])
                        diffuser_salon()
                        return lancer_salon()
                    end
                    local ok, raison = Adapter.PrepareShot(seat)
                    if not ok then refuser(player, raison) end
                end,
            })
        end

        -- Les deux intentions heritent du pipeline : audit et correlation
        -- viennent gratuitement. Elles ne revalident PAS la distance — seule
        -- l'intention interact du registre le fait. Ce qui fait foi ici, c'est
        -- d'etre inscrit a une place de la partie en cours.
        -- Salon : R (pret) et fleches (mise, createur seulement), depuis
        -- Client/liars_bar/salon.lua.
        Events.SubscribeRemote("liars:pret", function(player, oui)
            if state or mise_en_cours then return end
            local chair = seat_by_player[player:GetID()]
            if not chair then return end
            local a = assis_salon()
            Salon.Accorder(salon, a)
            if Salon.Pret(salon, a, chair, oui == true) then
                diffuser_salon()
                lancer_salon()
            end
        end)
        Events.SubscribeRemote("liars:mise", function(player, mise)
            if state or mise_en_cours then return end
            local chair = seat_by_player[player:GetID()]
            if not chair then return end
            local a = assis_salon()
            Salon.Accorder(salon, a)
            if Salon.ChoisirMise(salon, a, chair, tonumber(mise)) then diffuser_salon() end
        end)

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

        Intents.Register("liars_shoot", {
            validate = function(player)
                local seat = seat_by_player[player:GetID()]
                if not (state and state.pending and seat == state.pending.seat) then
                    return false, "pas_designe"
                end
                if not (gun_raised and gun_raised.seat == seat and gun_raised.ready) then
                    return false, "arme_pas_prete"
                end
                return true
            end,
            apply = function(player, _, cid)
                local seat = seat_by_player[player:GetID()]
                local chair_n = chair_of[seat]
                local ok, raison = Adapter.Act({ kind = "shoot", seat = seat }, cid)
                return ok, {
                    target = "chair:" .. tostring(chair_n),
                    audit = ok and "tir" or tostring(raison),
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
        if debug_owner == player_id then Adapter.StopPoseBot() end
        local seat = seat_by_player[player_id]
        if not seat then return end

        if gun_raised and gun_raised.seat == seat then
            local ancienne_chaise = gun_raised.chair
            arreter_pose_revolver(gun_raised)
            gun_raised = nil
            ranger_revolvers(true)
            send("all", "liars:gun_cancelled", ancienne_chaise)
        end

        if state then
            if shot_sequence then
                shot_sequence.departures[#shot_sequence.departures + 1] = player_id
                return
            end
            if pause_lecture then
                pause_lecture.departures[#pause_lecture.departures + 1] = player_id
                return
            end
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
        diffuser_salon()
    end

    return Adapter
end
