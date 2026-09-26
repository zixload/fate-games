-- Fait tourner l'adaptateur du combat (games/pvp/adapter.lua) avec de faux
-- objets nanos : entrer en PvP, un bot, le temps qui passe, une attaque, une
-- balle native, sortir. Attrape ce que seul le jeu montrerait sinon (appel a
-- une fonction absente, fiabilite oubliee dans un envoi, erreur dans un pas).
return function(H, Stubs)
    -- Une entite nanos factice : toute methode inconnue ne fait rien.
    local prochain = 1000
    local function entite(loc, rot)
        prochain = prochain + 1
        local e = { id = prochain, loc = loc or Vector(0, 0, 90), rot = rot or Rotator(0, 0, 0), valeurs = {},
            abonnements = {}, sante = 100, max = 100, valide = true, appels = {} }
        function e:GetID() return self.id end
        function e:IsValid() return self.valide end
        function e:Destroy() self.valide = false end
        function e:GetLocation() return self.loc end
        function e:SetLocation(v) self.loc = v end
        function e:GetRotation() return self.rot end
        function e:SetRotation(r) self.rot = r end
        function e:GetControlRotation() return self.rot end
        function e:SetValue(k, v) self.valeurs[k] = v end
        function e:GetValue(k, d) local v = self.valeurs[k] if v == nil then return d end return v end
        function e:Subscribe(nom, f) self.abonnements[nom] = f end
        function e:SetHealth(h) self.sante = h end
        function e:GetHealth() return self.sante end
        function e:SetMaxHealth(m) self.max = m end
        function e:GetMaxHealth() return self.max end
        return setmetatable(e, { __index = function(_, nom)
            return function(self, ...) self.appels[#self.appels + 1] = { nom, ... } end
        end })
    end

    local function vecteur(x, y, z)
        local v = { X = x, Y = y, Z = z }
        return setmetatable(v, {
            __add = function(a, b) return vecteur(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
            __sub = function(a, b) return vecteur(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
            __mul = function(a, k) return vecteur(a.X * k, a.Y * k, a.Z * k) end,
            __index = {
                Distance = function(a, b)
                    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
                    return math.sqrt(dx * dx + dy * dy + dz * dz)
                end,
            },
        })
    end

    local function monter()
        Stubs.current = Stubs.reset()
        Stubs.install()
        _G.Vector = vecteur
        _G.Character = function(loc, rot) return entite(loc, rot) end
        _G.DamageType = { Shot = 0, Explosion = 1, Punch = 2, Fall = 3, Melee = 6 }
        _G.GaitMode = { None = 0, Walking = 1, Sprinting = 2 }
        _G.StanceMode = { None = 0, Standing = 1, Crouching = 2, Proning = 3 }
        _G.AnimationSlotType = { FullBody = 0, UpperBody = 1, Head = 2 }
        _G.CollisionType = { Normal = 0, StaticOnly = 1, NoCollision = 2, IgnoreOnlyPawn = 3, Auto = 4 }
        local chat = {}
        _G.Chat = {
            Subscribe = function(nom, f) chat[nom] = f end,
            SendMessage = function(_, texte) chat.dernier = texte end,
        }
        local erreurs = {}
        local Log = {
            Info = function() end, Debug = function() end,
            Warn = function(_, m) erreurs[#erreurs + 1] = "WARN " .. tostring(m) end,
            Error = function(_, m) erreurs[#erreurs + 1] = "ERROR " .. tostring(m) end,
        }
        local Armes = {
            creer = function() return entite() end,
            anim_attaque = function() return "nanos-world::AM_Mannequin_Melee_Slash_Attack" end,
        }
        local Combat = Package.Require("combat/init.lua")
        local A = Package.Require("games/pvp/adapter.lua")(Log, {}, Combat, Armes, { dev = true, reapparition = 1 })
        A.Init()
        local function nouveau_joueur(id)
            local j = Stubs.player(id)
            function j:IsValid() return true end
            function j:GetPing() return 60 end
            return j
        end
        local joueur = nouveau_joueur(1)
        joueur:Possess(entite(vecteur(0, 0, 90)))
        local function dire(texte, qui) return chat.PlayerSubmit(texte, qui or joueur) end
        local function temps(secondes)
            for _ = 1, math.floor(secondes / 0.05 + 0.5) do
                for id, t in pairs(Stubs.current.timers.registry) do
                    t.acc = t.acc + 50
                    if t.acc >= t.ms then
                        t.acc = 0
                        if t.ms ~= 50 then Stubs.current.timers.registry[id] = nil end
                        t.callback()
                    end
                end
            end
        end
        return A, joueur, dire, temps, erreurs, nouveau_joueur
    end

    H.describe("pvp/adaptateur", function()
        H.it("entrer, un bot, se battre, une balle native, sortir", function()
            local _, joueur, dire, temps, erreurs = monter()
            local ancien = joueur:GetControlledCharacter()
            dire("/pvp")
            local perso = joueur:GetControlledCharacter()
            H.assert_true(perso ~= ancien, "un personnage natif")
            H.assert_eq(perso:GetValue("pvp", false), true, "marque pvp")
            H.assert_eq(perso:GetValue("pvp_arme", nil), "epee_longue", "arme par defaut")

            dire("/pvp bot epee_courte difficile")
            temps(3)
            local fx_diffuses = #Stubs.current.events.broadcast
            H.assert_true(fx_diffuses > 0, "des effets diffuses")
            local etats = 0
            for _, e in ipairs(Stubs.current.events.sent) do if e.name == "pvp:etat" then etats = etats + 1 end end
            H.assert_true(etats >= 20, "le HUD recoit son etat")

            -- Une attaque du joueur.
            Stubs.current.events.subscriptions["pvp:attaque"](joueur, "legere", "droite")
            temps(1.3)                      -- changer d'arme est refuse pendant une attaque

            -- Une balle native du joueur (arme a feu) sur le bot : le moteur la reecrit.
            dire("/pvp arme pistolet")
            H.assert_eq(perso:GetValue("pvp_arme", nil), "pistolet", "pistolet en main")
            local bot
            for _, e in ipairs(Stubs.current.events.broadcast) do
                for _, f in ipairs(e.args[1] or {}) do
                    if f.id and f.id ~= perso:GetID() and not bot then bot = f.id end
                end
            end
            H.assert_true(bot ~= nil, "le bot existe")
            temps(5)
            H.assert_eq(#erreurs, 0, "aucune erreur : " .. table.concat(erreurs, " | "))

            dire("/pvp")
            H.assert_eq(joueur:GetControlledCharacter(), ancien, "on retrouve son personnage")
            H.assert_false(perso:IsValid(), "le personnage natif est detruit")
        end)

        H.it("TakeDamage : une balle au torse passe par le moteur, les degats natifs sont annules", function()
            local A, joueur, dire, temps, erreurs, nouveau_joueur = monter()
            dire("/pvp")
            dire("/pvp arme revolver")
            local joueur2 = nouveau_joueur(2)
            joueur2:Possess(entite(vecteur(1000, 0, 90)))
            dire("/pvp", joueur2)
            local cible = joueur2:GetControlledCharacter()
            local rendu = cible.abonnements.TakeDamage(cible, 45, "spine_02", DamageType.Shot, nil, joueur)
            H.assert_eq(rendu, 0, "degats natifs annules")
            H.assert_eq(cible:GetHealth(), 62, "38 du revolver au torse, par le moteur")
            cible.abonnements.TakeDamage(cible, 45, "head", DamageType.Shot, nil, joueur)
            H.assert_eq(cible:GetHealth(), 0, "76 a la tete sur 62 : mort")
            temps(0.1)
            H.assert_eq(#erreurs, 0, "aucune erreur : " .. table.concat(erreurs, " | "))
        end)

        H.it("une chute passe par le moteur, sans armure", function()
            local _, joueur, dire = monter()
            dire("/pvp")
            dire("/pvp armure plaques")
            local perso = joueur:GetControlledCharacter()
            perso.abonnements.TakeDamage(perso, 30, "foot_l", DamageType.Fall, nil, nil)
            H.assert_eq(perso:GetHealth(), 70, "30 de chute pleins")
        end)

        H.it("mort puis reapparition", function()
            local _, joueur, dire, temps, _, nouveau_joueur = monter()
            dire("/pvp")
            dire("/pvp arme fusil_precision")
            local joueur2 = nouveau_joueur(2)
            joueur2:Possess(entite(vecteur(1000, 0, 90)))
            dire("/pvp", joueur2)
            local cible = joueur2:GetControlledCharacter()
            cible.abonnements.TakeDamage(cible, 90, "head", DamageType.Shot, nil, joueur)
            H.assert_eq(cible:GetHealth(), 0, "mort")
            temps(1.2)
            H.assert_eq(cible:GetHealth(), 100, "reapparu")
        end)
    end)
end
