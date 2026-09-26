-- HUD de Liar's Bar : dessine le journal en haut a gauche et ecoute les
-- touches. La main est en 3D dans la main du personnage (rendu.lua), le
-- tas, l'invite "Menteur !" et les consignes dans la superposition
-- (nametags.lua).
--
-- Tout ce qui se decide sur l'affichage est dans journal.lua, teste hors
-- jeu ; ici on branche et on dessine.

return function(config, Journal, send_intent)
    local journal = Journal.New()
    local chat_ouvert = false
    -- Un outil de l'atelier en main : la molette et les clics sont a lui.
    local outil_atelier = Package.Require("outil_atelier.lua")

    -- Evenements relayes tels quels, sous leur nom court.
    local EVENTS = {
        "unseated", "started", "deal", "table_card", "turn", "cards_played",
        "accuse", "reveal", "designated", "shoot_prepare", "gun_ready",
        "gun_cancelled", "shoot", "eliminated",
        "round_ended", "match_ended", "refused",
    }
    for _, name in ipairs(EVENTS) do
        Events.SubscribeRemote("liars:" .. name, function(...)
            journal:On(name, ...)
            if name == "shoot_prepare" and select(1, ...) == journal.my_chair then
                Events.Call("liars:gun_state", "preparing")
            elseif name == "gun_ready" and select(1, ...) == journal.my_chair then
                Events.Call("liars:gun_state", "ready")
            elseif name == "shoot" or name == "gun_cancelled"
                or name == "round_ended" or name == "match_ended"
                or name == "unseated" then
                Events.Call("liars:gun_state", nil)
            end
        end)
    end

    -- "seated" porte l'identifiant du joueur : on le compare au joueur local
    -- ici, pour que journal.lua reste sans globale.
    Events.SubscribeRemote("liars:seated", function(chair, player_id, name)
        local me = Client.GetLocalPlayer()
        journal:On("seated", chair, name, me ~= nil and me:GetID() == player_id)
    end)

    Events.SubscribeRemote("zix:intent_result", function(name, ok, detail)
        journal:On("intent_result", name, ok, detail)
        if name == "liars_shoot" and not ok and journal.gun_ready then
            Events.Call("liars:gun_state", "ready")
        end
    end)

    -- Taper "/bots 3" ne doit pas poser de cartes.
    Chat.Subscribe("Open", function() chat_ouvert = true end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    -- Pendant mon tour, une touche du HUD est retenue (retour false, doc
    -- Input) : elle ne doit pas aussi declencher son action native. Hors de
    -- mon tour, on ne touche a rien.
    Input.Subscribe("KeyPress", function(key_name)
        if chat_ouvert or outil_atelier.actif or not journal:IsMyTurn() then return end
        local keys = config.keys

        for i, noms in ipairs(keys.select) do
            for _, k in ipairs(noms) do
                if key_name == k then
                    journal:Toggle(i)
                    return false
                end
            end
        end

        -- Personne ne pose ni n'accuse pendant qu'un joueur doit tirer : E
        -- sert alors a prendre son revolver (interaction).
        if journal.designated ~= nil then return end

        -- E pose les cartes choisies, R accuse le joueur precedent : deux
        -- touches, pas d'ambiguite entre poser et dire menteur.
        if key_name == keys.play then
            local indices = journal:Selection()
            if #indices > 0 then
                journal:MarkPending(indices)
                send_intent("liars_play", { indices = indices })
            end
            return false
        elseif key_name == keys.accuse then
            send_intent("liars_challenge", {})
            return false
        end
    end)

    -- Molette : parcourir sa main, a tout moment tant qu'on a des cartes.
    -- Clic gauche : choisir la carte sous le curseur, a son tour seulement.
    -- Retenus quand ils servent, pour ne pas declencher d'action native.
    Input.Subscribe("MouseScroll", function(mouse_x, mouse_y, delta)
        if chat_ouvert or outil_atelier.actif or #journal.hand == 0 or delta == 0 then return end
        journal:MoveCursor(delta > 0 and -1 or 1)
        return false
    end)

    Input.Subscribe("MouseDown", function(key_name)
        if chat_ouvert or outil_atelier.actif or key_name ~= "LeftMouseButton" then return end
        if journal.designated == journal.my_chair and journal.designated ~= nil then
            if journal.gun_ready then
                journal.gun_ready = false -- evite deux intentions sur un double clic
                Events.Call("liars:gun_state", "preparing")
                send_intent("liars_shoot", {})
            end
            return false
        end
        if not journal:IsMyTurn() or not journal.cursor then return end
        journal:ToggleCursor()
        return false
    end)

    ---------------------------------------------------------------- dessin

    local FOND   = Color(0.02, 0.02, 0.02, 0.75)
    local ROUGE  = Color(1.0, 0.4, 0.4, 1.0)
    local JAUNE  = Color(1.0, 0.85, 0.3, 1.0)

    local function texte(c, s, x, y, taille, couleur, centre)
        c:DrawText(s, Vector2D(x, y), FontType.Roboto, taille, couleur,
            0, centre or false, false, Color.BLACK, Vector2D(1, 1), true, Color.BLACK)
    end

    -- Taux 0 : redessine a chaque image. -1 couperait le rafraichissement
    -- automatique (doc Canvas:SetAutoRepaintRate) : le HUD se dessinerait une
    -- fois, vide, au chargement, et plus jamais.
    local canvas = Canvas(true, Color.TRANSPARENT, 0, true, true)

    local photo = Package.Require("photo.lua")

    canvas:Subscribe("Update", function(self, width, height)
        -- Rien a montrer tant que la table n'a rien dit.
        if #journal.lines == 0 then return end
        -- Caches par defaut, F1 les montre (photo.lua).
        if photo.cache then return end

        -- L'etat, en haut a gauche.
        local etat = { journal.my_chair and ("Ta chaise : %d"):format(journal.my_chair) or "Spectateur" }
        if journal.table_rank then
            etat[#etat + 1] = "Carte de table : " .. Journal.RankName(journal.table_rank)
        end
        if journal:IsMyTurn() then
            etat[#etat + 1] = "À toi !"
        elseif journal.turn then
            etat[#etat + 1] = "Tour : " .. journal:Who(journal.turn)
        end
        texte(self, table.concat(etat, "   |   "), 20, 20, 20,
            journal:IsMyTurn() and JAUNE or Color.WHITE)

        -- Le journal, sous l'etat.
        local hauteur_ligne = 24
        local n = #journal.lines
        self:DrawRect("", Vector2D(12, 52), Vector2D(560, n * hauteur_ligne + 16),
            FOND, BlendMode.AlphaBlend)
        for i, l in ipairs(journal.lines) do
            texte(self, l.text, 20, 52 + (i - 1) * hauteur_ligne + 8, 17,
                l.kind == "refus" and ROUGE or Color.WHITE)
        end
    end)

    return journal
end
