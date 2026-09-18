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

return function(Log, DB, Ids, Scheduler, Accounts, config)
    local Characters = {}

    -- Par joueur connecte. Cle : l'identifiant d'entite du joueur.
    local sessions = {}

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
        -- position debout.
        if session.assis or not moved(transform, session.saved) then
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
        character:SetSpringArmSettings(Vector(0, 0, essai.eye_height), essai.arm_length)
        return character
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

        session.player:Possess(character)

        Scheduler.Add(wheel_key(session.character_id), function()
            Characters.Flush(session.character_id)
        end)

        Log.Info("characters", ("personnage %d en jeu (%s)")
            :format(session.character_id, session.character_name))
    end

    ----------------------------------------------------------------------------
    -- Posture (ESSAI) : seul le personnage d'essai sait s'asseoir, par la
    -- variable "Assis" de son Animation Blueprint. Le personnage nanos
    -- habituel reste debout, comme avant : ces deux fonctions ne font rien.
    ----------------------------------------------------------------------------

    -- Pose le personnage sur la chaise (x, y), tourne vers yaw. La hauteur
    -- de marche est gardee : les pieds restent au niveau du sol. Collision et
    -- gravite coupees, sinon la chaise cuite dans la carte le repousse.
    function Characters.Sit(player_id, x, y, yaw)
        local session = sessions[player_id]
        if not (session and session.essai and session.character) then return false end

        local c = session.character
        local ici = c:GetLocation()
        -- Marque d'abord : si un appel ci-dessous leve, Stand saura encore
        -- tout defaire au lieu de laisser le joueur fige.
        session.assis = true
        c:StopMovement(true)
        c:SetSpeedSettings(0, 0)
        c:SetGravityEnabled(false)
        c:SetCollision(CollisionType.NoCollision)
        c:SetLocation(Vector(x, y, ici.Z))
        c:SetRotation(Rotator(0, yaw, 0))
        -- SetAnimationBlueprintPropertyValue n'existe que cote client : le
        -- serveur publie une valeur synchronisee, chaque client l'applique
        -- (Client/posture.lua).
        c:SetValue("assis", true, true)
        -- Premiere personne a hauteur des yeux : derriere, le bras de la camera
        -- butait sur le dossier et rentrait dans le corps.
        local cam = session.essai.seated_camera
        c:SetSpringArmSettings(Vector(cam.forward, 0, cam.up), 0)
        return true
    end

    -- Reglage en jeu de la camera assise (commande /cam, mode dev). Modifie
    -- la config d'essai partagee et reapplique tout de suite si on est assis.
    function Characters.SetSeatedCamera(player_id, forward, up)
        local session = sessions[player_id]
        if not (session and session.essai) then return false end
        session.essai.seated_camera = { forward = forward, up = up }
        if session.assis and session.character then
            session.character:SetSpringArmSettings(Vector(forward, 0, up), 0)
        end
        return true
    end

    function Characters.Stand(player_id)
        local session = sessions[player_id]
        if not (session and session.assis and session.character) then return false end

        local c = session.character
        local essai = session.essai
        c:SetValue("assis", false, true)
        c:SetCollision(CollisionType.Normal)
        c:SetGravityEnabled(true)
        c:SetSpeedSettings(essai.walk_speed, essai.walk_speed / 2)
        c:SetSpringArmSettings(Vector(0, 0, essai.eye_height), essai.arm_length)
        session.assis = nil
        return true
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
