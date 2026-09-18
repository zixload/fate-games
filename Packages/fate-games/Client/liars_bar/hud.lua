-- HUD provisoire de Liar's Bar : dessine le journal et ecoute les touches.
--
-- Le seul fichier du HUD qui touche au moteur. Tout ce qui se decide sur
-- l'affichage est dans journal.lua, teste hors jeu ; ici on branche et on
-- dessine. Il disparaitra avec l'eventail 3D.

return function(config, Journal, send_intent)
    local journal = Journal.New()
    local chat_ouvert = false

    -- Evenements relayes tels quels, sous leur nom court.
    local EVENTS = {
        "unseated", "started", "deal", "table_card", "turn", "cards_played",
        "accuse", "reveal", "designated", "shoot", "eliminated",
        "round_ended", "match_ended", "refused",
    }
    for _, name in ipairs(EVENTS) do
        Events.SubscribeRemote("liars:" .. name, function(...)
            journal:On(name, ...)
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
    end)

    -- Taper "/bots 3" ne doit pas poser de cartes.
    Chat.Subscribe("Open", function() chat_ouvert = true end)
    Chat.Subscribe("Close", function() chat_ouvert = false end)

    Input.Subscribe("KeyPress", function(key_name)
        if chat_ouvert then return end
        local keys = config.keys

        for i, noms in ipairs(keys.select) do
            for _, k in ipairs(noms) do
                if key_name == k then
                    journal:Toggle(i)
                    return
                end
            end
        end

        if key_name == keys.play then
            local indices = journal:Selection()
            if #indices > 0 and journal:IsMyTurn() then
                journal:MarkPending(indices)
                send_intent("liars_play", { indices = indices })
            end
        elseif key_name == keys.accuse then
            if journal:IsMyTurn() then
                send_intent("liars_challenge", {})
            end
        end
    end)

    ---------------------------------------------------------------- dessin

    local FOND  = Color(0.02, 0.02, 0.02, 0.75)
    local ROUGE = Color(1.0, 0.4, 0.4, 1.0)
    local JAUNE = Color(1.0, 0.85, 0.3, 1.0)

    local function texte(c, s, x, y, taille, couleur, centre)
        c:DrawText(s, Vector2D(x, y), FontType.Roboto, taille, couleur,
            0, centre or false, false, Color.BLACK, Vector2D(1, 1), true, Color.BLACK)
    end

    -- Taux 0 : redessine a chaque image. -1 couperait le rafraichissement
    -- automatique (doc Canvas:SetAutoRepaintRate) : le HUD se dessinerait une
    -- fois, vide, au chargement, et plus jamais.
    local canvas = Canvas(true, Color.TRANSPARENT, 0, true, true)

    canvas:Subscribe("Update", function(self, width, height)
        -- Rien a montrer tant que la table n'a rien dit.
        if #journal.lines == 0 then return end

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

        -- Ma main, en bas, seulement si j'en ai une.
        if #journal.hand > 0 then
            local cartes = {}
            for i, c in ipairs(journal.hand) do
                local nom = ("[%d] %s"):format(i, Journal.RankName(c))
                cartes[i] = journal:IsSelected(i) and ("> " .. nom .. " <") or nom
            end
            texte(self, table.concat(cartes, "    "), width / 2, height - 110, 24, Color.WHITE, true)
            if journal:IsMyTurn() then
                texte(self, "1-5 choisir   ·   P poser   ·   M accuser", width / 2, height - 76, 16, JAUNE, true)
            end
        end
    end)

    return journal
end
