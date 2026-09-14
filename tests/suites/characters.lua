return function(H, Stubs)
    local make_characters = Package.Require("domain/characters.lua")
    local make_accounts   = Package.Require("domain/accounts.lua")
    local make_scheduler  = Package.Require("core/scheduler.lua")
    local make_ids        = Package.Require("core/ids.lua")
    local make_db         = Package.Require("db/init.lua")
    local make_log        = Package.Require("core/log.lua")

    local SPAWN = { x = 10, y = 20, z = 30, yaw = 90 }

    -- Monte la chaine complete. Roue d'un seul slot : un tick traite tout le monde.
    local function build(c, whitelist)
        c.answer("MAX(id)", { { max_id = 0 } })

        local Log = make_log({ log = { min_level = "DEBUG" } })
        local DB  = make_db(Log, { db = { connection = "db=test.db", pool_size = 1 } })
        DB.Connect()

        local Ids = make_ids(Log, DB)
        Ids.Seed({ "accounts", "characters" })
        DB.EndStartup()

        local Scheduler = make_scheduler(Log, {
            scheduler = { wheel_seconds = 1, tick_ms = 1000 },
        })
        Scheduler.Start()

        local config = {
            spawn     = SPAWN,
            whitelist = whitelist or { enabled = false, bootstrap = {} },
        }

        local Accounts   = make_accounts(Log, DB, Ids, config)
        local Characters = make_characters(Log, DB, Ids, Scheduler, Accounts, config)

        return Characters, Scheduler
    end

    local function with_account(c, whitelisted)
        c.answer("FROM accounts WHERE steam_id", {
            {
                id          = 5,
                steam_id    = "steam:joueur",
                whitelisted = whitelisted == nil and 1 or whitelisted,
                created_at  = "x",
            },
        })
    end

    H.describe("domain/characters", function()

        H.it("cree un personnage quand le compte n'en a aucun", function()
            local c = Stubs.reset()
            local Characters = build(c)
            with_account(c)
            c.answer("FROM characters", {})
            c.answer("FROM character_state", {})

            Characters.OnPlayerReady(Stubs.player(1, "steam:joueur"))

            local insert = nil
            for _, call in ipairs(c.db.executed) do
                if call.query:find("INSERT INTO characters", 1, true) then insert = call end
            end

            H.assert_true(insert ~= nil, "insertion du personnage")
            H.assert_eq(insert.params[2], 5, "rattache au bon compte")
            H.assert_eq(c.count_lines("action=personnage_cree"), 1, "creation auditee")
            H.assert_eq(Characters.CountOnline(), 1, "une session ouverte")
        end)

        H.it("fait apparaitre un nouveau personnage au point de depart", function()
            local c = Stubs.reset()
            local Characters = build(c)
            with_account(c)
            c.answer("FROM characters", {})
            c.answer("FROM character_state", {})

            Characters.OnPlayerReady(Stubs.player(1, "steam:joueur"))

            local character = c.world.characters[1]
            H.assert_true(character ~= nil, "entite creee")
            H.assert_eq(character.location.X, SPAWN.x, "position X")
            H.assert_eq(character.location.Z, SPAWN.z, "position Z")
            H.assert_eq(character.rotation.Yaw, SPAWN.yaw, "orientation")
        end)

        H.it("restaure la position enregistree a la reconnexion", function()
            local c = Stubs.reset()
            local Characters = build(c)
            with_account(c)
            c.answer("FROM characters", { { id = 77, first_name = "Baihuan", last_name = "77" } })
            c.answer("FROM character_state", {
                { pos_x = 1500, pos_y = -400, pos_z = 92, yaw = 180 },
            })

            Characters.OnPlayerReady(Stubs.player(1, "steam:joueur"))

            local character = c.world.characters[1]
            H.assert_eq(character.location.X, 1500, "position X restauree")
            H.assert_eq(character.location.Y, -400, "position Y restauree")
            H.assert_eq(character.rotation.Yaw, 180, "orientation restauree")

            for _, call in ipairs(c.db.executed) do
                H.assert_false(call.query:find("INSERT INTO characters", 1, true) ~= nil,
                    "aucun personnage ne doit etre recree")
            end
        end)

        H.it("prend possession du personnage", function()
            local c = Stubs.reset()
            local Characters = build(c)
            with_account(c)
            c.answer("FROM characters", { { id = 77, first_name = "Baihuan", last_name = "77" } })
            c.answer("FROM character_state", {})

            local player = Stubs.player(1, "steam:joueur")
            Characters.OnPlayerReady(player)

            H.assert_eq(#c.world.possessed, 1, "une prise de possession")
            H.assert_true(player:GetControlledCharacter() ~= nil, "joueur rattache a son pion")
        end)

        H.it("n'ecrit rien tant que le personnage n'a pas bouge", function()
            local c = Stubs.reset()
            local Characters = build(c)
            with_account(c)
            c.answer("FROM characters", { { id = 77, first_name = "Baihuan", last_name = "77" } })
            c.answer("FROM character_state", {
                { pos_x = SPAWN.x, pos_y = SPAWN.y, pos_z = SPAWN.z, yaw = SPAWN.yaw },
            })

            Characters.OnPlayerReady(Stubs.player(1, "steam:joueur"))
            local writes_before = #c.db.executed

            c.advance(5 * 1000)   -- cinq tours de roue, immobile

            H.assert_eq(#c.db.executed, writes_before, "aucune ecriture inutile")
        end)

        H.it("ecrit la position quand le personnage a bouge", function()
            local c = Stubs.reset()
            local Characters = build(c)
            with_account(c)
            c.answer("FROM characters", { { id = 77, first_name = "Baihuan", last_name = "77" } })
            c.answer("FROM character_state", {
                { pos_x = 0, pos_y = 0, pos_z = 0, yaw = 0 },
            })

            Characters.OnPlayerReady(Stubs.player(1, "steam:joueur"))
            c.world.characters[1]:MoveTo(900, 0, 0)

            c.advance(1000)

            local state_write = nil
            for _, call in ipairs(c.db.executed) do
                if call.query:find("INSERT INTO character_state", 1, true) then state_write = call end
            end

            H.assert_true(state_write ~= nil, "etat ecrit")
            H.assert_eq(state_write.params[1], 77, "bon personnage")
            H.assert_eq(state_write.params[2], 900, "nouvelle position X")
        end)

        H.it("ecrit une seule fois pour un deplacement unique", function()
            local c = Stubs.reset()
            local Characters = build(c)
            with_account(c)
            c.answer("FROM characters", { { id = 77, first_name = "Baihuan", last_name = "77" } })
            c.answer("FROM character_state", { { pos_x = 0, pos_y = 0, pos_z = 0, yaw = 0 } })

            Characters.OnPlayerReady(Stubs.player(1, "steam:joueur"))
            c.world.characters[1]:MoveTo(900, 0, 0)

            c.advance(4 * 1000)

            local writes = 0
            for _, call in ipairs(c.db.executed) do
                if call.query:find("INSERT INTO character_state", 1, true) then writes = writes + 1 end
            end

            H.assert_eq(writes, 1, "une seule ecriture pour un seul deplacement")
        end)

        H.it("ecrit, retire de la roue et detruit l'entite au depart", function()
            local c = Stubs.reset()
            local Characters = build(c)
            with_account(c)
            c.answer("FROM characters", { { id = 77, first_name = "Baihuan", last_name = "77" } })
            c.answer("FROM character_state", { { pos_x = 0, pos_y = 0, pos_z = 0, yaw = 0 } })

            local player = Stubs.player(1, "steam:joueur")
            Characters.OnPlayerReady(player)
            local character = c.world.characters[1]
            character:MoveTo(1234, 0, 0)

            Characters.OnPlayerLeave(player)

            local last_write = nil
            for _, call in ipairs(c.db.executed) do
                if call.query:find("INSERT INTO character_state", 1, true) then last_write = call end
            end

            H.assert_true(last_write ~= nil, "etat ecrit au depart")
            H.assert_eq(last_write.params[2], 1234, "derniere position sauvee")
            H.assert_true(character.destroyed, "entite detruite")
            H.assert_eq(Characters.CountOnline(), 0, "session fermee")

            -- La roue ne doit plus rien declencher pour ce personnage.
            local writes_after = #c.db.executed
            c.advance(3 * 1000)
            H.assert_eq(#c.db.executed, writes_after, "plus rien apres le depart")
        end)

        H.it("ignore un depart sans session ouverte", function()
            local c = Stubs.reset()
            local Characters = build(c)

            Characters.OnPlayerLeave(Stubs.player(42, "steam:fantome"))

            H.assert_eq(Characters.CountOnline(), 0, "toujours aucune session")
            H.assert_eq(#c.db.executed, 0, "aucune ecriture")
        end)

        H.it("signale une double ouverture de session", function()
            local c = Stubs.reset()
            local Characters = build(c)
            with_account(c)
            c.answer("FROM characters", { { id = 77, first_name = "Baihuan", last_name = "77" } })
            c.answer("FROM character_state", {})

            local player = Stubs.player(1, "steam:joueur")
            Characters.OnPlayerReady(player)
            Characters.OnPlayerReady(player)

            H.assert_eq(c.count_lines("session deja ouverte"), 1, "avertissement emis")
            H.assert_eq(Characters.CountOnline(), 1, "une seule session")
        end)

        H.it("n'ecrit pas si le compte est irresolu", function()
            local c = Stubs.reset()
            local Characters = build(c)
            c.db.select_error = "base verrouillee"

            Characters.OnPlayerReady(Stubs.player(1, "steam:joueur"))

            H.assert_eq(Characters.CountOnline(), 0, "session refermee")
            H.assert_eq(#c.world.characters, 0, "aucune entite creee")
        end)

        H.it("expulse un compte hors whitelist quand le verrou est arme", function()
            local c = Stubs.reset()
            local Characters = build(c, { enabled = true, bootstrap = {} })
            with_account(c, 0)
            c.answer("FROM characters", {})
            c.answer("FROM character_state", {})

            local player = Stubs.player(1, "steam:joueur")
            Characters.OnPlayerReady(player)

            H.assert_true(player.kicked ~= nil, "joueur expulse")
            H.assert_eq(Characters.CountOnline(), 0, "aucune session")
            H.assert_eq(#c.world.characters, 0, "aucune entite creee")
            H.assert_eq(c.count_lines("entree refusee"), 1, "refus journalise")
        end)

        H.it("cree quand meme le compte d'un joueur refuse", function()
            local c = Stubs.reset()
            local Characters = build(c, { enabled = true, bootstrap = {} })
            c.answer("FROM accounts WHERE steam_id", {})

            Characters.OnPlayerReady(Stubs.player(1, "steam:inconnu"))

            local created = false
            for _, call in ipairs(c.db.executed) do
                if call.query:find("INSERT INTO accounts", 1, true) then created = true end
            end

            -- On veut savoir qui a essaye d'entrer, et pouvoir le whitelister
            -- ensuite sans qu'il ait a se reconnecter pour exister.
            H.assert_true(created, "compte cree malgre le refus")
            H.assert_eq(Characters.CountOnline(), 0, "mais pas d'entree en jeu")
        end)

        H.it("laisse entrer un compte whiteliste quand le verrou est arme", function()
            local c = Stubs.reset()
            local Characters = build(c, { enabled = true, bootstrap = {} })
            with_account(c, 1)
            c.answer("FROM characters", { { id = 77, first_name = "Baihuan", last_name = "77" } })
            c.answer("FROM character_state", {})

            local player = Stubs.player(1, "steam:joueur")
            Characters.OnPlayerReady(player)

            H.assert_nil(player.kicked, "aucune expulsion")
            H.assert_eq(Characters.CountOnline(), 1, "session ouverte")
        end)

        H.it("laisse entrer tout le monde quand le verrou est desarme", function()
            local c = Stubs.reset()
            local Characters = build(c, { enabled = false, bootstrap = {} })
            with_account(c, 0)
            c.answer("FROM characters", { { id = 77, first_name = "Baihuan", last_name = "77" } })
            c.answer("FROM character_state", {})

            local player = Stubs.player(1, "steam:joueur")
            Characters.OnPlayerReady(player)

            H.assert_nil(player.kicked, "aucune expulsion")
            H.assert_eq(Characters.CountOnline(), 1, "session ouverte")
        end)

        H.it("force l'ecriture de tout le monde sur FlushAll", function()
            local c = Stubs.reset()
            local Characters = build(c)
            with_account(c)
            c.answer("FROM characters", { { id = 77, first_name = "Baihuan", last_name = "77" } })
            c.answer("FROM character_state", {
                { pos_x = SPAWN.x, pos_y = SPAWN.y, pos_z = SPAWN.z, yaw = SPAWN.yaw },
            })

            Characters.OnPlayerReady(Stubs.player(1, "steam:joueur"))
            local before = #c.db.executed

            -- Personnage immobile : la roue n'ecrirait rien, FlushAll doit ecrire.
            Characters.FlushAll()

            H.assert_true(#c.db.executed > before, "ecriture forcee a l'arret")
        end)
    end)
end
