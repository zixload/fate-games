-- Bouchons des globales du moteur nanos world.
--
-- C'est ce qui permet de tester la logique metier sans lancer le serveur. Les modules du
-- package ne touchent le moteur qu'en cinq points : Console, Timer, Database (plus
-- DatabaseEngine), Events et Package.Require. Tout le reste est du Lua pur.
--
-- Les fonctions globales sont installees UNE SEULE FOIS et delegent a Stubs.current.
-- C'est necessaire parce que certains modules capturent une fonction du moteur au moment
-- de leur chargement (core/log.lua garde une reference a Console.Warn), et que
-- Package.Require met les modules en cache : si on reinstallait des fonctions neuves a
-- chaque test, les modules deja charges continueraient a pointer vers les anciennes.

local Stubs = {}

Stubs.current = nil

-- Cree un jeu d'enregistreurs vierge. Appele au debut de chaque test.
function Stubs.reset()
    local ctrl = {
        console = { lines = {} },
        timers  = { registry = {}, next_id = 1 },
        events  = {
            subscriptions       = {},
            local_subscriptions = {},
            sent                = {},
            broadcast           = {},
            called              = {},
        },
        db      = {
            constructed  = nil,
            executed     = {},
            selected     = {},
            select_rows  = {},
            answers      = {},        -- reponses ciblees par motif de requete
            select_error = nil,
            execute_error_on = nil,   -- motif : toute requete le contenant echouera
            closed       = false,
            startup_over = false,
        },
        world   = {
            characters   = {},        -- entites Character creees
            subscriptions = {},       -- Player.Subscribe par nom d'evenement
            possessed    = {},
        },
    }

    -- Fait repondre `rows` a toute requete contenant `pattern`. Sans cela,
    -- c'est `select_rows` qui repond a tout.
    function ctrl.answer(pattern, rows)
        ctrl.db.answers[#ctrl.db.answers + 1] = { pattern = pattern, rows = rows }
    end

    -- Declenche un evenement moteur cote joueur.
    function ctrl.fire_player_event(name, ...)
        local callback = ctrl.world.subscriptions[name]
        if not callback then
            error("aucun abonnement Player pour " .. tostring(name))
        end
        return callback(...)
    end

    -- Avance le temps de `ms` et declenche les intervalles autant de fois que necessaire.
    function ctrl.advance(ms)
        local ids = {}
        for id in pairs(ctrl.timers.registry) do ids[#ids + 1] = id end
        table.sort(ids)

        for _, id in ipairs(ids) do
            local t = ctrl.timers.registry[id]
            if t then
                t.acc = t.acc + ms
                while t.acc >= t.ms and ctrl.timers.registry[id] do
                    t.acc = t.acc - t.ms
                    t.callback()
                end
            end
        end
    end

    -- Simule un appel distant venant d'un client.
    function ctrl.fire_remote(name, ...)
        local callback = ctrl.events.subscriptions[name]
        if not callback then
            error("aucun abonnement distant pour " .. tostring(name))
        end
        return callback(...)
    end

    -- Derniere reponse envoyee au client pour un evenement donne.
    function ctrl.last_sent(name)
        for i = #ctrl.events.sent, 1, -1 do
            if ctrl.events.sent[i].name == name then
                return ctrl.events.sent[i]
            end
        end
        return nil
    end

    -- Compte les lignes de log contenant un motif.
    function ctrl.count_lines(pattern)
        local n = 0
        for _, line in ipairs(ctrl.console.lines) do
            if line:find(pattern, 1, true) then n = n + 1 end
        end
        return n
    end

    Stubs.current = ctrl
    return ctrl
end

local function record_line(level, line)
    local c = Stubs.current
    if c then
        c.console.lines[#c.console.lines + 1] = level .. " " .. tostring(line)
    end
end

-- Faux objet Database. Reproduit les signatures reelles du moteur :
--   Execute(query, params...) -> affected_rows, error
--   Select(query, params...)  -> rows, error
local function make_database(engine, connection_string, pool_size)
    local c = Stubs.current
    c.db.constructed = {
        engine = engine, connection = connection_string, pool_size = pool_size,
    }

    local db = {}

    function db:Execute(query, ...)
        local cur = Stubs.current
        cur.db.executed[#cur.db.executed + 1] = { query = query, params = { ... } }

        if cur.db.execute_error_on and query:find(cur.db.execute_error_on, 1, true) then
            return 0, "erreur simulee"
        end
        return 1, nil
    end

    function db:Select(query, ...)
        local cur = Stubs.current
        cur.db.selected[#cur.db.selected + 1] = { query = query, params = { ... } }

        if cur.db.select_error then
            return nil, cur.db.select_error
        end

        for _, answer in ipairs(cur.db.answers) do
            if query:find(answer.pattern, 1, true) then
                return answer.rows, nil
            end
        end

        return cur.db.select_rows, nil
    end

    function db:ExecuteAsync(query, callback, ...)
        local rows, err = self:Execute(query, ...)
        if callback then callback(rows, err) end
    end

    function db:SelectAsync(query, callback, ...)
        local rows, err = self:Select(query, ...)
        if callback then callback(rows, err) end
    end

    function db:Close()
        Stubs.current.db.closed = true
    end

    return db
end

-- Installe les globales. A n'appeler qu'une fois, avant tout Package.Require.
function Stubs.install()
    _G.Console = {
        Log   = function(line) record_line("LOG  ", line) end,
        Warn  = function(line) record_line("WARN ", line) end,
        Error = function(line) record_line("ERROR", line) end,
    }

    _G.Timer = {
        SetInterval = function(callback, ms)
            local c  = Stubs.current
            local id = c.timers.next_id
            c.timers.next_id = id + 1
            c.timers.registry[id] = { callback = callback, ms = ms, acc = 0 }
            return id
        end,

        ClearInterval = function(id)
            Stubs.current.timers.registry[id] = nil
        end,

        SetTimeout = function(callback, ms)
            return _G.Timer.SetInterval(callback, ms)
        end,

        ClearTimeout = function(id)
            _G.Timer.ClearInterval(id)
        end,
    }

    _G.Events = {
        SubscribeRemote = function(name, callback)
            Stubs.current.events.subscriptions[name] = callback
        end,

        -- Reproduit la signature REELLE du serveur :
        --     CallRemote(evenement, joueur, fiabilite, ...)
        -- La fiabilite est un parametre positionnel optionnel. L'omettre y fait
        -- glisser le premier argument utile, silencieusement, et le bug ne se voit
        -- qu'en jeu. On l'exige donc ici pour que le banc de test l'attrape.
        CallRemote = function(name, player, reliability, ...)
            if reliability ~= 0 and reliability ~= 1 then
                error(("Events.CallRemote(%q) : fiabilite attendue en 3e position, recu <%s>")
                    :format(tostring(name), tostring(reliability)), 2)
            end

            local c = Stubs.current
            c.events.sent[#c.events.sent + 1] = {
                name = name, player = player, reliability = reliability, args = { ... },
            }
        end,

        -- BroadcastRemote(evenement, fiabilite, ...) : pas de joueur cible.
        BroadcastRemote = function(name, reliability, ...)
            if reliability ~= 0 and reliability ~= 1 then
                error(("Events.BroadcastRemote(%q) : fiabilite attendue en 2e position, recu <%s>")
                    :format(tostring(name), tostring(reliability)), 2)
            end

            local c = Stubs.current
            c.events.broadcast[#c.events.broadcast + 1] = {
                name = name, reliability = reliability, args = { ... },
            }
        end,

        Subscribe = function(name, callback)
            Stubs.current.events.local_subscriptions[name] = callback
        end,

        Call = function(name, ...)
            local c = Stubs.current
            c.events.called[#c.events.called + 1] = { name = name, args = { ... } }
        end,
    }

    _G.Reliability = { Reliable = 1, Unreliable = 0 }

    _G.DatabaseEngine = { SQLite = "sqlite", MySQL = "mysql", PostgreSQL = "postgresql" }
    _G.Database       = make_database

    _G.Vector = function(x, y, z)
        return { X = x, Y = y, Z = z }
    end

    _G.Rotator = function(pitch, yaw, roll)
        return { Pitch = pitch, Yaw = yaw, Roll = roll }
    end

    -- Entite Character du moteur. On la rend deplacable pour pouvoir simuler
    -- un joueur qui bouge entre deux tours de roue.
    _G.Character = function(location, rotation, mesh)
        local character = {
            location  = location,
            rotation  = rotation,
            mesh      = mesh,
            destroyed = false,
        }

        function character:GetLocation() return self.location end
        function character:GetRotation() return self.rotation end
        function character:SetLocation(v) self.location = v end
        function character:Destroy() self.destroyed = true end

        -- Aide de test : deplace le personnage.
        function character:MoveTo(x, y, z)
            self.location = { X = x, Y = y, Z = z }
        end

        local world = Stubs.current.world
        world.characters[#world.characters + 1] = character
        return character
    end

    _G.Player = {
        Subscribe = function(name, callback)
            Stubs.current.world.subscriptions[name] = callback
        end,
        Unsubscribe = function() end,
    }
end

-- Faux acteur du moteur, pour ce qui n'est ni joueur ni personnage : une porte,
-- un coffre, un etabli.
function Stubs.actor(id, x, y, z)
    local actor = { location = { X = x or 0, Y = y or 0, Z = z or 0 } }

    function actor:GetID()       return id end
    function actor:GetLocation() return self.location end
    function actor:MoveTo(nx, ny, nz) self.location = { X = nx, Y = ny, Z = nz } end

    return actor
end

-- Faux joueur.
function Stubs.player(id, steam_id)
    local player = {}

    function player:GetID()      return id or 1 end
    function player:GetSteamID() return steam_id or ("steam:" .. tostring(id or 1)) end

    function player:Possess(pawn)
        local world = Stubs.current.world
        world.possessed[#world.possessed + 1] = { player = self, pawn = pawn }
        self.pawn = pawn
    end

    function player:UnPossess() self.pawn = nil end
    function player:GetControlledCharacter() return self.pawn end

    function player:Kick(reason)
        self.kicked = reason or true
    end

    return player
end

return Stubs
