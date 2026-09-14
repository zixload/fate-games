-- Test d'integration au demarrage, sans client de jeu.
--
-- Le banc de test de tests/ bouchonne le moteur : il verifie la logique, jamais que
-- les API de nanos world se comportent comme on le croit. Ce module comble ce trou en
-- fabriquant un faux joueur et en poussant la vraie chaine de connexion dans le vrai
-- serveur : vrai Character(), vraie base SQLite, vraie roue d'ordonnancement.
--
-- Ce qu'il NE teste pas : Player:Possess() et les evenements Player.Subscribe, qui
-- exigent un vrai client connecte.
--
-- Active par config.dev.smoke_test. Laisse la base propre : ses lignes sont
-- supprimees a la fin.

return function(Log, DB, Characters)
    local Smoke = {}

    local STEAM_ID = "smoke:" .. tostring(os.time())
    local PLAYER_ID = 999001

    local results = {}
    local session = nil

    local function check(label, ok, detail)
        results[#results + 1] = { label = label, ok = ok, detail = detail }
        if ok then
            Log.Info("smoke", "ok   " .. label)
        else
            Log.Error("smoke", "ECHEC " .. label .. " : " .. tostring(detail))
        end
    end

    -- Faux joueur : juste ce que domain/characters lui demande.
    local function fake_player()
        local player = { possessed = nil }
        function player:GetID()      return PLAYER_ID end
        function player:GetSteamID() return STEAM_ID end
        function player:Possess(pawn) self.possessed = pawn end
        return player
    end

    local player = fake_player()

    ----------------------------------------------------------------------------

    local function step_cleanup()
        local character_id = session and session.character_id

        Characters.OnPlayerLeave(player)
        check("session fermee", Characters.SessionByPlayer(PLAYER_ID) == nil)

        -- Menage : ce test ne doit rien laisser derriere lui.
        if character_id then
            DB.Execute("DELETE FROM character_state WHERE character_id = :0", nil, character_id)
            DB.Execute("DELETE FROM characters WHERE id = :0", nil, character_id)
        end
        DB.Execute("DELETE FROM accounts WHERE steam_id = :0", function()
            local failed = 0
            for _, r in ipairs(results) do
                if not r.ok then failed = failed + 1 end
            end

            if failed == 0 then
                Log.Info("smoke", ("=== %d verification(s), tout est passe ==="):format(#results))
            else
                Log.Error("smoke", ("=== %d verification(s), %d ECHEC(S) ==="):format(#results, failed))
            end
        end, STEAM_ID)
    end

    local function step_read_back(expected)
        DB.Select(
            "SELECT pos_x, pos_y, pos_z FROM character_state WHERE character_id = :0",
            function(rows, err)
                if err then
                    check("relecture de l'etat", false, err)
                elseif not rows or not rows[1] then
                    check("relecture de l'etat", false, "aucune ligne ecrite")
                else
                    local saved = tonumber(rows[1].pos_x)
                    check("position persistee", math.abs(saved - expected) < 2.0,
                        ("attendu %.1f, lu %s"):format(expected, tostring(saved)))
                end

                Timer.SetTimeout(step_cleanup, 500)
            end,
            session.character_id
        )
    end

    local function step_move_and_flush()
        session = Characters.SessionByPlayer(PLAYER_ID)

        check("session ouverte", session ~= nil)
        if not session then return step_cleanup() end

        check("personnage attribue", session.character_id ~= nil, session.character_id)
        check("entite du moteur creee", session.character ~= nil)
        check("possession demandee", player.possessed ~= nil)

        if not session.character then return step_cleanup() end

        -- Lecture reelle de la transformation : c'est ici qu'on verifie que les noms
        -- de champs du moteur (X/Y/Z, Yaw) sont bien ceux qu'on croit.
        local location = session.character:GetLocation()
        local rotation = session.character:GetRotation()

        check("GetLocation renvoie des coordonnees",
            type(location) == "table" and type(location.X) == "number",
            tostring(location and location.X))
        check("GetRotation renvoie un Yaw",
            type(rotation) == "table" and type(rotation.Yaw) == "number",
            tostring(rotation and rotation.Yaw))

        if type(location) ~= "table" or type(location.X) ~= "number" then
            return step_cleanup()
        end

        local target_x = 4242.0
        session.character:SetLocation(Vector(target_x, location.Y, location.Z))

        Characters.Flush(session.character_id, function(written)
            check("ecriture declenchee par le deplacement", written == true)
            Timer.SetTimeout(function() step_read_back(target_x) end, 500)
        end)
    end

    function Smoke.Run()
        Log.Info("smoke", "=== test d'integration sans client : demarrage ===")

        Characters.OnPlayerReady(player)

        -- Laisser les allers-retours asynchrones en base se terminer.
        Timer.SetTimeout(step_move_and_flush, 2000)
    end

    return Smoke
end
