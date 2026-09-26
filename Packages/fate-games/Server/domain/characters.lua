-- Personnages.
--
-- Boucle de persistance de la V0.1 :
--     connexion -> compte -> personnage -> spawn -> jeu -> deconnexion -> meme etat
--
-- L'etat volatil (position) suit R3 : il vit en memoire et n'est ecrit qu'en differe,
-- par la roue d'ordonnancement (R4). Les donnees transactionnelles — creation du
-- personnage, mort — s'ecrivent immediatement.
--
-- La creation d'un personnage est ici un bouchon : le vrai parcours passe par le
-- Vestibule et son questionnaire (voir SYSTEME-EPREUVE.md), qui n'existe pas encore.

return function(Log, DB, Ids, Scheduler, Accounts, config, Appearances)
    local Characters = {}

    -- Par joueur connecte. Cle : l'identifiant d'entite du joueur.
    local sessions = {}

    -- Appele a la place du spawn quand le joueur est pret, s'il est fixe
    -- (vestiaire d'arrivee, voir Server/Index.lua).
    local sur_arrivee = nil

    -- Reference d'asset, au format <pack>::<NomDeclare dans Assets.toml>.
    -- Le pack doit etre liste dans `assets` de Config.toml pour etre monte.
    local MESH = config.character_mesh or "nanos-world::SK_Male"

    local function now()
        return os.date("!%Y-%m-%dT%H:%M:%SZ")
    end

    local function wheel_key(character_id)
        return "character:" .. tostring(character_id)
    end

    ----------------------------------------------------------------------------
    -- Persistance
    ----------------------------------------------------------------------------

    -- Lit la position courante depuis l'entite du moteur.
    local function read_transform(session)
        local character = session.character
        if not character then return nil end

        local location = character:GetLocation()
        local rotation = character:GetRotation()

        return {
            x   = location.X,
            y   = location.Y,
            z   = location.Z,
            yaw = rotation.Yaw,
        }
    end

    local function moved(a, b)
        if not a or not b then return true end
        -- Un seuil plutot qu'une egalite stricte : un personnage immobile bouge
        -- quand meme de quelques millimetres sous l'effet de la physique.
        return math.abs(a.x - b.x) > 1.0
            or math.abs(a.y - b.y) > 1.0
            or math.abs(a.z - b.z) > 1.0
            or math.abs(a.yaw - b.yaw) > 1.0
    end

    -- Ecrit l'etat d'un personnage si et seulement si quelque chose a change.
    -- C'est le write-behind de R3 : appele par la roue, jamais par un changement.
    function Characters.Flush(character_id, callback)
        local session = Characters.SessionByCharacter(character_id)
        if not session then
            if callback then callback(false) end
            return
        end

        local transform = read_transform(session)
        if not transform then
            if callback then callback(false) end
            return
        end

        -- Assis, on garderait la chaise comme point de retour : a la reconnexion
        -- le personnage reapparaitrait dans son meuble. On garde la derniere
        -- position debout. Au vestiaire, dans le ciel, pareil.
        if session.assis or session.vestiaire or not moved(transform, session.saved) then
            if callback then callback(false) end
            return
        end

        DB.Execute(
            [[INSERT INTO character_state (character_id, pos_x, pos_y, pos_z, yaw, updated_at)
              VALUES (:0, :1, :2, :3, :4, :5)
              ON CONFLICT(character_id) DO UPDATE SET
                  pos_x = :1, pos_y = :2, pos_z = :3, yaw = :4, updated_at = :5]],
            function(_, err)
                if err then
                    Log.Error("characters", ("ecriture d'etat impossible pour %d : %s")
                        :format(character_id, tostring(err)))
                    if callback then callback(false) end
                    return
                end

                session.saved = transform
                if callback then callback(true) end
            end,
            character_id, transform.x, transform.y, transform.z, transform.yaw, now()
        )
    end

    ----------------------------------------------------------------------------
    -- Chargement et creation
    ----------------------------------------------------------------------------

    -- ESSAI, a trancher : un personnage Creative Characters sur son propre
    -- squelette, anime par sa propre Animation Blueprint. CharacterSimple
    -- accepte n'importe quel maillage (doc CharacterSimple), Character exige
    -- le squelette UE4 Mannequin, que ce pack n'a pas.
    -- La camera du jeu, reglee ici et publiee sur le personnage : un outil
    -- de l'atelier la remplace chez son client (premiere personne, epaule),
    -- puis la remet a l'identique (Client/camera_outil.lua).
    -- `retard` : le retard de camera du moteur (actif par defaut, doc
    -- CharacterSimple). Coupe en premiere personne assise, sinon la camera
    -- glisse jusqu'a la tete au lieu d'y sauter.
    local function regler_camera(c, relative, bras, retard)
        retard = retard ~= false
        c:SetSpringArmSettings(relative, bras, Vector(0, 0, 0), retard)
        c:SetValue("camera_jeu", { x = relative.X, y = relative.Y, z = relative.Z, bras = bras, retard = retard }, true)
    end

    -- La longueur du bras, elle, est toujours interpolee par le moteur : on la
    -- force sans transition par la camera du joueur (doc Player, [Client/Server]).
    local function bras_immediat(session, bras)
        session.player:SetCameraArmLength(bras, true)
    end

    -- Rotation d'un personnage debout. Face camera (use_controller_desired
    -- _rotation) pour que les pas de cote se voient ; sinon oriente vers son
    -- mouvement, comme avant. Fixee ici plutot que laissee au defaut : Stand
    -- doit pouvoir la retablir, et la doc ne donne pas la valeur par defaut.
    local function rotation_debout(c, essai)
        local face = essai.face_camera == true
        c:SetRotationSettings(Rotator(0, essai.rotation_rate, 0), face, not face)
    end

    -- Impulsion et pesanteur, pour accorder le temps en l'air a l'animation.
    local function regler_saut(c, essai)
        if essai.jump_z then c:SetJumpZVelocity(essai.jump_z) end
        if essai.gravity_scale then c:SetGravityScale(essai.gravity_scale) end
    end

    local function creer_essai(point, essai)
        local character = CharacterSimple(
            Vector(point.x, point.y, point.z),
            Rotator(0, point.yaw or 0, 0),
            essai.body,
            essai.anim_blueprint
        )
        for i, piece in ipairs(essai.parts or {}) do
            character:AddSkeletalMeshAttached("essai_" .. i, piece)
        end
        if essai.scale and essai.scale ~= 1 then
            character:SetScale(Vector(essai.scale, essai.scale, essai.scale))
        end
        character:SetSpeedSettings(essai.walk_speed, essai.walk_speed / 2)
        rotation_debout(character, essai)
        regler_saut(character, essai)
        regler_camera(character, Vector(0, 0, essai.eye_height), essai.arm_length)
        return character
    end

    -- Donne le personnage au joueur et le met dans la roue de persistance.
    local function entrer_en_jeu(session)
        session.player:Possess(session.character)

        Scheduler.Add(wheel_key(session.character_id), function()
            Characters.Flush(session.character_id)
        end)

        Log.Info("characters", ("personnage %d en jeu (%s)")
            :format(session.character_id, session.character_name))
    end

    local function spawn(session, transform)
        local point = transform or config.spawn

        local essai = config.dev and config.dev.creative_character
        local character
        if essai and essai.enabled then
            character = creer_essai(point, essai)
        else
            character = Character(
                Vector(point.x, point.y, point.z),
                Rotator(0, point.yaw or 0, 0),
                MESH
            )
            -- Premiere personne : la trace de visee part de la camera, donc des
            -- yeux. En troisieme personne elle partait de derriere le personnage.
            character:SetCameraMode(CameraMode.FPSOnly)
        end

        session.character = character
        session.saved     = transform   -- nil si le personnage est neuf
        session.essai     = (essai and essai.enabled) and essai or nil

        entrer_en_jeu(session)
    end

    ----------------------------------------------------------------------------
    -- Posture (ESSAI) : seul le personnage d'essai sait s'asseoir, par la
    -- variable "Assis" de son Animation Blueprint. Le personnage nanos
    -- habituel reste debout, comme avant : ces deux fonctions ne font rien.
    ----------------------------------------------------------------------------

    -- La posture assise d'un corps Creative, joueur ou bot : immobile,
    -- collision et gravite coupees (sinon la chaise cuite dans la carte le
    -- repousse), pose en (x, y, z) et tourne vers yaw.
    local function poser_assis(c, x, y, z, yaw)
        c:StopMovement(true)
        c:SetSpeedSettings(0, 0)
        -- Vitesse nulle ne suffit pas : le corps s'orientait encore vers la
        -- direction demandee (Q/D le faisaient tourner sur la chaise).
        c:SetRotationSettings(Rotator(0, 0, 0), false, false)
        c:SetGravityEnabled(false)
        c:SetCollision(CollisionType.NoCollision)
        c:SetLocation(Vector(x, y, z))
        c:SetRotation(Rotator(0, yaw, 0))
        -- Le client utilise aussi cet angle pour initialiser sa camera apres
        -- la possession : un joueur peut s'asseoir depuis n'importe quelle vue.
        c:SetValue("seat_yaw", yaw, true)
        -- SetAnimationBlueprintPropertyValue n'existe que cote client : le
        -- serveur publie une valeur synchronisee, chaque client l'applique
        -- (Client/posture.lua).
        c:SetValue("assis", true, true)
        c:SetValue("liars_look", { yaw = 0, pitch = 0 }, true)
    end

    -- Pose le personnage sur la chaise (x, y), tourne vers yaw. La hauteur
    -- de marche est gardee : les pieds restent au niveau du sol.
    function Characters.Sit(player_id, x, y, yaw, z)
        local session = sessions[player_id]
        if not (session and session.essai and session.character) then return false end

        local c = session.character
        -- Marque d'abord : si un appel ci-dessous leve, Stand saura encore
        -- tout defaire au lieu de laisser le joueur fige.
        session.assis = true
        poser_assis(c, x, y, z or c:GetLocation().Z, yaw)
        session.player:SetCameraRotation(Rotator(0, yaw, 0))
        -- Premiere personne a hauteur des yeux : derriere, le bras de la camera
        -- butait sur le dossier et rentrait dans le corps.
        local cam = session.essai.seated_camera
        regler_camera(c, Vector(cam.forward, cam.side or 0, cam.up), 0, false)
        bras_immediat(session, 0)
        return true
    end

    -- Un corps Creative sans joueur (bot de test), assis comme un joueur :
    -- meme corps, meme animation. z est la hauteur d'un personnage debout
    -- sur le plancher. nil si le personnage d'essai est coupe.
    function Characters.CorpsAssis(x, y, z, yaw)
        local essai = config.dev and config.dev.creative_character
        if not (essai and essai.enabled) then return nil end
        local c = creer_essai({ x = x, y = y, z = z, yaw = yaw }, essai)
        poser_assis(c, x, y, z, yaw)
        return c
    end

    -- Reglage en jeu de la camera assise (commande /cam, mode dev). Modifie
    -- la config d'essai partagee et reapplique tout de suite si on est assis.
    function Characters.SetSeatedCamera(player_id, forward, up, side)
        local session = sessions[player_id]
        if not (session and session.essai) then return false end
        session.essai.seated_camera = { forward = forward, up = up, side = side or 0 }
        if session.assis and session.character then
            regler_camera(session.character, Vector(forward, side or 0, up), 0, false)
            bras_immediat(session, 0)
        end
        return true
    end

    -- La vitesse du moment : marche ou course, et moins vite en reculant.
    local function appliquer_vitesse(session)
        local e = session.essai
        local vitesse
        if session.arriere then
            vitesse = session.course and (e.run_back_speed or e.run_speed)
                or (e.walk_back_speed or e.walk_speed)
        else
            vitesse = session.course and e.run_speed or e.walk_speed
        end
        session.character:SetSpeedSettings(vitesse, e.walk_speed / 2)
    end

    local function peut_regler(player_id)
        local session = sessions[player_id]
        if not (session and session.essai and session.character) or session.assis then
            return nil
        end
        return session
    end

    -- Reglage en jeu des vitesses (commande /vitesse, mode dev). Le
    -- personnage d'essai est a l'echelle 0.8 : sa foulee l'est aussi, donc la
    -- vitesse qui ne fait pas glisser les pieds se trouve en jeu. Les bonnes
    -- valeurs vont ensuite dans dev.creative_character.
    function Characters.SetVitesses(player_id, marche, course)
        local session = sessions[player_id]
        if not (session and session.essai and session.character) then return false end
        local e = session.essai
        e.walk_speed = marche
        if course then e.run_speed = course end
        -- Assis, la vitesse reste nulle : Stand la remettra.
        if not session.assis then appliquer_vitesse(session) end
        return true
    end

    -- Reglage en jeu du saut (commande /saut, mode dev).
    function Characters.SetSaut(player_id, z, pesanteur)
        local session = sessions[player_id]
        if not (session and session.essai and session.character) then return false end
        local e = session.essai
        e.jump_z = z
        if pesanteur then e.gravity_scale = pesanteur end
        regler_saut(session.character, e)
        return true
    end

    -- Memes reglages, pour le recul.
    function Characters.SetVitessesArriere(player_id, marche, course)
        local session = sessions[player_id]
        if not (session and session.essai and session.character) then return false end
        local e = session.essai
        e.walk_back_speed = marche
        if course then e.run_back_speed = course end
        if not session.assis then appliquer_vitesse(session) end
        return true
    end

    -- Pose « cartes en main » (ESSAI) : valeur synchronisee que chaque client
    -- recopie dans la variable "Cartes" de ABP_Creative (Client/posture.lua).
    function Characters.SetHolding(player_id, en_main)
        local session = sessions[player_id]
        if not (session and session.essai and session.character) then return false end
        session.character:SetValue("cartes", en_main == true, true)
        return true
    end

    -- Maj pour courir (ESSAI). Assis, la vitesse reste bloquee.
    function Characters.SetRunning(player_id, course)
        local session = peut_regler(player_id)
        if not session then return false end
        session.course = course == true
        appliquer_vitesse(session)
        return true
    end

    -- Le client a vu que le personnage recule (il s'eloigne de la direction
    -- qu'il regarde) : on ralentit, le temps que dure ce recul.
    function Characters.SetArriere(player_id, arriere)
        local session = peut_regler(player_id)
        if not session then return false end
        session.arriere = arriere == true
        appliquer_vitesse(session)
        return true
    end

    function Characters.Stand(player_id)
        local session = sessions[player_id]
        if not (session and session.assis and session.character) then return false end

        local c = session.character
        local essai = session.essai
        c:SetValue("cartes", false, true)
        c:SetValue("assis", false, true)
        c:SetValue("liars_look", { yaw = 0, pitch = 0 }, true)
        c:SetCollision(CollisionType.Normal)
        c:SetGravityEnabled(true)
        c:SetSpeedSettings(essai.walk_speed, essai.walk_speed / 2)
        rotation_debout(c, essai)
        regler_camera(c, Vector(0, 0, essai.eye_height), essai.arm_length)
        bras_immediat(session, essai.arm_length)
        session.assis = nil
        return true
    end

    ----------------------------------------------------------------------------
    -- Vestiaire d'arrivee : le personnage attend dans le ciel, face a une
    -- camera fixe, le temps que le joueur choisisse ses cartes. Il n'est
    -- possede qu'a l'entree en jeu.
    ----------------------------------------------------------------------------

    local function essai_actif()
        local essai = config.dev and config.dev.creative_character
        return (essai and essai.enabled) and essai or nil
    end

    -- Habille un corps Creative d'une apparence du catalogue. Memes pieces et
    -- meme "master pose" que Liar's Bar (games/liars_bar/adapter.lua).
    local function habiller(c, look_id)
        local look = Appearances and Appearances.Resolve(look_id)
        if not look then return false end
        c:SetMesh(look.body)
        c:RemoveAllSkeletalMeshesAttached()
        for i, mesh in ipairs(look.head) do c:AddSkeletalMeshAttached("tete_" .. i, mesh) end
        for i, mesh in ipairs(look.worn) do c:AddSkeletalMeshAttached("tenue_" .. i, mesh) end
        return true
    end

    -- Places du vestiaire : index -> player_id. La plus petite libre.
    local places = {}

    local function prendre_place(player_id)
        local i = 1
        while places[i] do i = i + 1 end
        places[i] = player_id
        return i
    end

    function Characters.SurArrivee(fn)
        sur_arrivee = fn
    end

    function Characters.AuVestiaire(player_id)
        local session = sessions[player_id]
        return session ~= nil and session.vestiaire ~= nil
    end

    -- transform : la position sauvee, ou nil pour un personnage neuf.
    function Characters.OuvrirVestiaire(session, transform, look_id)
        local essai = essai_actif()
        local v = config.vestiaire
        local base = config.spawn
        local place = prendre_place(session.player_id)

        local pied = Vector(base.x + (place - 1) * v.ecart, base.y, base.z + v.altitude)
        -- Socle : un cube aplati sous les pieds, pour que le personnage tienne
        -- debout et joue son animation de repos au lieu de tomber.
        local socle = StaticMesh(pied - Vector(0, 0, 10), Rotator(0, 0, 0), "nanos-world::SM_Cube")
        socle:SetScale(Vector(2, 2, 0.2))
        if not v.socle_visible then socle:SetVisibility(false) end

        if session.character then
            session.character:SetLocation(Vector(pied.X, pied.Y, pied.Z + 120))
            session.character:SetRotation(Rotator(0, 0, 0))
        else
            session.character = creer_essai({ x = pied.X, y = pied.Y, z = pied.Z + 120, yaw = 0 }, essai)
        end
        habiller(session.character, look_id)
        session.character:SetVisibility(true)

        session.saved     = transform
        session.essai     = essai
        session.vestiaire = { place = place, socle = socle, retour = transform }

        -- Tourne vers +X : la camera se place devant lui et le regarde.
        local camera = pied + Vector(v.camera_distance, 0, 120 + v.camera_hauteur)
        session.player:SetCameraLocation(camera)
        session.player:SetCameraRotation(Rotator(v.camera_tangage, 180, 0))

        Log.Info("characters", ("personnage %d au vestiaire, place %d")
            :format(session.character_id, place))
    end

    -- Remonter au vestiaire en cours de jeu, debout seulement. La position
    -- quittee est ecrite d'abord : c'est la que l'on redescendra.
    function Characters.RetournerVestiaire(player_id, look_id)
        local session = sessions[player_id]
        if not (session and session.essai and session.character) then return false, "indisponible" end
        if session.vestiaire then return false, "deja" end
        if session.assis then return false, "assis" end

        local ici = read_transform(session)
        Scheduler.Remove(wheel_key(session.character_id))
        Characters.Flush(session.character_id)
        session.player:UnPossess()
        Characters.OuvrirVestiaire(session, ici, look_id)
        return true
    end

    -- Au vestiaire, le personnage s'efface pendant qu'on regarde les armes :
    -- il passerait sinon derriere l'arme posee devant la camera.
    function Characters.MontrerAuVestiaire(player_id, visible)
        local session = sessions[player_id]
        if not (session and session.vestiaire and session.character) then return false end
        session.character:SetVisibility(visible == true)
        return true
    end

    -- Change la tenue du personnage du joueur, au vestiaire ou en jeu.
    function Characters.Habiller(player_id, look_id)
        local session = sessions[player_id]
        if not (session and session.essai and session.character) then return false end
        return habiller(session.character, look_id)
    end

    local function liberer_vestiaire(session)
        local v = session.vestiaire
        if not v then return end
        session.vestiaire = nil
        places[v.place] = nil
        if v.socle and v.socle:IsValid() then v.socle:Destroy() end
        return v
    end

    -- Descend du ciel a la derniere position debout, ou au point d'apparition.
    function Characters.QuitterVestiaire(player_id)
        local session = sessions[player_id]
        if not (session and session.vestiaire) then return false end

        local v = liberer_vestiaire(session)
        local point = v.retour or config.spawn
        session.character:SetVisibility(true)
        session.character:SetLocation(Vector(point.x, point.y, point.z))
        session.character:SetRotation(Rotator(0, point.yaw or 0, 0))
        entrer_en_jeu(session)
        return true
    end

    -- Sans vestiaire : apparait directement, deja habille.
    function Characters.Apparaitre(session, transform, look_id)
        spawn(session, transform)
        if session.essai and session.character then habiller(session.character, look_id) end
    end

    local function load_state(session, callback)
        DB.Select(
            "SELECT pos_x, pos_y, pos_z, yaw FROM character_state WHERE character_id = :0",
            function(rows, err)
                if err then
                    Log.Error("characters", "lecture d'etat impossible : " .. tostring(err))
                    return callback(nil)
                end

                if rows and rows[1] then
                    local row = rows[1]
                    return callback({
                        x   = tonumber(row.pos_x),
                        y   = tonumber(row.pos_y),
                        z   = tonumber(row.pos_z),
                        yaw = tonumber(row.yaw),
                    })
                end

                return callback(nil)
            end,
            session.character_id
        )
    end

    local function create_character(session, account, callback)
        local id = Ids.Next("characters")

        -- Nom bouchon. Le vrai nom viendra du Vestibule, et c'est lui que le monde
        -- retiendra : voir la section sur la legende dans UNIVERS.md.
        local first_name = "Player"
        local last_name  = tostring(id)

        DB.Execute(
            [[INSERT INTO characters (id, account_id, first_name, last_name, created_at)
              VALUES (:0, :1, :2, :3, :4)]],
            function(_, err)
                if err then
                    Log.Error("characters", "creation impossible : " .. tostring(err))
                    return callback(nil, "db_insert")
                end

                Log.Audit({
                    actor          = "account:" .. tostring(account.id),
                    target         = "character:" .. tostring(id),
                    action         = "personnage_cree",
                    position       = "-",
                    payload        = first_name .. " " .. last_name,
                })

                return callback({
                    id         = id,
                    account_id = account.id,
                    first_name = first_name,
                    last_name  = last_name,
                })
            end,
            id, account.id, first_name, last_name, now()
        )
    end

    -- Charge le personnage vivant du compte, ou en cree un.
    local function resolve_character(session, account, callback)
        DB.Select(
            [[SELECT id, first_name, last_name FROM characters
              WHERE account_id = :0 AND died_at IS NULL
              ORDER BY id DESC]],
            function(rows, err)
                if err then
                    Log.Error("characters", "lecture impossible : " .. tostring(err))
                    return callback(nil, "db_select")
                end

                if rows and rows[1] then
                    local row = rows[1]
                    return callback({
                        id         = tonumber(row.id),
                        account_id = account.id,
                        first_name = row.first_name,
                        last_name  = row.last_name,
                    })
                end

                return create_character(session, account, callback)
            end,
            account.id
        )
    end

    ----------------------------------------------------------------------------
    -- Cycle de vie du joueur
    ----------------------------------------------------------------------------

    function Characters.OnPlayerReady(player)
        local player_id = player:GetID()

        if sessions[player_id] then
            Log.Warn("characters", "session deja ouverte pour le joueur " .. tostring(player_id))
            return
        end

        local steam_id = player:GetSteamID()
        local session  = { player = player, player_id = player_id }
        sessions[player_id] = session

        Accounts.Resolve(steam_id, function(account, err)
            if not account then
                Log.Error("characters", ("compte irresolu pour %s : %s")
                    :format(tostring(steam_id), tostring(err)))
                sessions[player_id] = nil
                return
            end

            session.account = account

            -- Verrou de whitelist. Le compte est cree quoi qu'il arrive : on veut
            -- savoir qui a essaye d'entrer, et pouvoir le whitelister ensuite sans
            -- qu'il ait a se reconnecter une premiere fois pour exister.
            if config.whitelist and config.whitelist.enabled
                and not Accounts.IsWhitelisted(account) then

                Log.Info("characters", ("entree refusee, compte %d hors whitelist (%s)")
                    :format(account.id, tostring(steam_id)))

                sessions[player_id] = nil

                if player.Kick then
                    player:Kick(config.whitelist.kick_reason or "Acces sur whitelist uniquement.")
                end
                return
            end

            resolve_character(session, account, function(character, char_err)
                if not character then
                    Log.Error("characters", "personnage irresolu : " .. tostring(char_err))
                    sessions[player_id] = nil
                    return
                end

                -- Le joueur a pu se deconnecter pendant les allers-retours en base.
                if not sessions[player_id] then
                    Log.Debug("characters", "joueur parti avant le spawn, abandon")
                    return
                end

                session.character_id   = character.id
                session.character_name = character.first_name .. " " .. character.last_name

                load_state(session, function(transform)
                    if not sessions[player_id] then return end
                    if sur_arrivee and essai_actif() then
                        return sur_arrivee(session, transform)
                    end
                    spawn(session, transform)
                end)
            end)
        end)
    end

    function Characters.OnPlayerLeave(player)
        local player_id = player:GetID()
        local session   = sessions[player_id]
        if not session then return end

        -- Sortir de la roue avant le flush final, pour ne pas ecrire deux fois.
        if session.character_id then
            Scheduler.Remove(wheel_key(session.character_id))
            Characters.Flush(session.character_id)
        end

        liberer_vestiaire(session)

        if session.character then
            session.character:Destroy()
        end

        sessions[player_id] = nil

        Log.Info("characters", ("joueur %s parti, session fermee")
            :format(tostring(player_id)))
    end

    ----------------------------------------------------------------------------
    -- Acces
    ----------------------------------------------------------------------------

    function Characters.SessionByPlayer(player_id)
        return sessions[player_id]
    end

    function Characters.SessionByCharacter(character_id)
        for _, session in pairs(sessions) do
            if session.character_id == character_id then
                return session
            end
        end
        return nil
    end

    function Characters.CountOnline()
        local n = 0
        for _ in pairs(sessions) do n = n + 1 end
        return n
    end

    -- Ecrit tout, sans condition. Appele a l'arret du serveur.
    function Characters.FlushAll()
        for _, session in pairs(sessions) do
            if session.character_id then
                session.saved = nil   -- force l'ecriture
                Characters.Flush(session.character_id)
            end
        end
    end

    return Characters
end
