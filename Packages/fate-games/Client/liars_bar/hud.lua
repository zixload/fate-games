-- HUD de Liar's Bar : dessine le journal et ma main, et ecoute les touches.
--
-- Le seul fichier du HUD qui touche au moteur. Tout ce qui se decide sur
-- l'affichage est dans journal.lua et cartes.lua, testes hors jeu ; ici on
-- branche et on dessine. La main est dessinee en cartes, avec les images du
-- jeu de 52 rangees dans le pack d'assets (liars_cards.images).

return function(config, Journal, send_intent, cartes_cfg)
    local journal = Journal.New()
    local Cartes = Package.Require("liars_bar/cartes.lua")(cartes_cfg)
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

    -- L'etiquette d'une carte : le premier nom de sa touche.
    local function touche(i)
        local noms = config.keys.select[i]
        return noms and noms[1] or tostring(i)
    end

    ---------------------------------------------------------------- dessin

    local FOND   = Color(0.02, 0.02, 0.02, 0.75)
    local ROUGE  = Color(1.0, 0.4, 0.4, 1.0)
    local JAUNE  = Color(1.0, 0.85, 0.3, 1.0)
    local LAITON = Color(0.79, 0.64, 0.29, 1.0)
    local GRISE  = Color(0.45, 0.45, 0.45, 1.0)
    local TERNE  = Color(0.82, 0.82, 0.82, 1.0)

    -- Les images font 357 x 537.
    local PROPORTION = 537 / 357
    -- Eventail : chevauchement, angle entre deux cartes, bords plus bas.
    local EVENTAIL = { ecart = 0.62, angle = 6 }
    -- Bas des cartes, au-dessus de la barre d'outils de l'atelier.
    local MARGE_BAS = 118

    -- Une couleur par carte, pour le decor : nouvelle a chaque donne, gardee
    -- par position quand la main ne fait que retrecir.
    local couleurs, derniere_main = {}, ""
    local function suivre_couleurs(main)
        local sig = table.concat(main, ",")
        if sig ~= derniere_main and #main >= #couleurs then
            couleurs = Cartes.Couleurs(#main, function(n) return math.random(n) end)
        end
        derniere_main = sig
    end

    local function texte(c, s, x, y, taille, couleur, centre)
        c:DrawText(s, Vector2D(x, y), FontType.Roboto, taille, couleur,
            0, centre or false, false, Color.BLACK, Vector2D(1, 1), true, Color.BLACK)
    end

    -- Ma main en eventail, en bas au centre. La carte sous la molette est
    -- relevee et bordee de blanc, les cartes choisies bien relevees et bordees
    -- de laiton, les cartes envoyees grisees. Sous chacune, sa touche et son
    -- nom : le Joker a l'image du Valet de pique. Cachee pendant un outil de
    -- l'atelier, qui a la souris et la barre du bas.
    local function carte(c, image, x, bas, w, h, angle, teinte)
        c:DrawTexture(image, Vector2D(x - w / 2, bas - h), Vector2D(w, h),
            Vector2D(0, 0), Vector2D(1, 1), teinte, BlendMode.AlphaBlend, angle, Vector2D(0.5, 1))
    end

    -- Un cadre de la couleur donnee, derriere la carte, tourne autour du
    -- meme point (le bas de la carte).
    local function cadre(c, x, bas, w, h, angle, b, couleur)
        c:DrawTexture("", Vector2D(x - w / 2 - b, bas - h - b), Vector2D(w + 2 * b, h + 2 * b),
            Vector2D(0, 0), Vector2D(1, 1), couleur, BlendMode.AlphaBlend, angle,
            Vector2D(0.5, (h + b) / (h + 2 * b)))
    end

    local function dessiner_main(c, width, height)
        local main = journal.hand
        local n = #main
        if n == 0 or outil_atelier.actif then return end
        suivre_couleurs(main)

        local h = math.max(110, math.min(220, height * 0.17))
        local w = h / PROPORTION
        local disposition = { largeur = w, ecart = EVENTAIL.ecart, angle = EVENTAIL.angle, courbure = h * 0.08 }
        local base = height - MARGE_BAS
        local cx = width / 2
        local mon_tour = journal:IsMyTurn()

        for i, rang in ipairs(main) do
            local p = Cartes.Main2D(n, i, disposition)
            local choisie = journal:IsSelected(i)
            local curseur = i == journal.cursor
            local leve = choisie and h * 0.22 or (curseur and h * 0.08 or 0)
            local x, bas = cx + p.x, base + p.y - leve
            if choisie then
                cadre(c, x, bas, w, h, p.angle, 4, LAITON)
            elseif curseur then
                cadre(c, x, bas, w, h, p.angle, 2, Color.WHITE)
            end
            local teinte = journal:IsPending(i) and GRISE or (mon_tour and Color.WHITE or TERNE)
            carte(c, Cartes.Image(rang, couleurs[i]), x, bas, w, h, p.angle, teinte)
            texte(c, ("%s · %s"):format(touche(i), Journal.RankName(rang)), x, base + 6, 16,
                choisie and JAUNE or Color.WHITE, true)
        end

        -- Au-dessus : la carte de table et mon tour.
        local titre = {}
        if journal.table_rank then
            titre[#titre + 1] = "Carte de table : " .. Journal.RankName(journal.table_rank)
        end
        if mon_tour then titre[#titre + 1] = "À toi !" end
        if #titre > 0 then
            texte(c, table.concat(titre, "   ·   "), cx, base - h * 1.3 - 30, 22,
                mon_tour and JAUNE or Color.WHITE, true)
        end

        -- Dessous : les commandes, a mon tour.
        if mon_tour then
            local choix = {}
            for i = 1, n do choix[i] = touche(i) end
            texte(c, ("molette parcourir · clic ou %s choisir · %s poser · %s accuser"):format(
                table.concat(choix, " "), config.keys.play, config.keys.accuse),
                cx, base + 30, 16, JAUNE, true)
        end
    end

    -- Taux 0 : redessine a chaque image. -1 couperait le rafraichissement
    -- automatique (doc Canvas:SetAutoRepaintRate) : le HUD se dessinerait une
    -- fois, vide, au chargement, et plus jamais.
    local canvas = Canvas(true, Color.TRANSPARENT, 0, true, true)

    local photo = Package.Require("photo.lua")

    canvas:Subscribe("Update", function(self, width, height)
        -- Rien a montrer tant que la table n'a rien dit.
        if #journal.lines == 0 then return end
        -- Mode capture (F1) : l'etat et le journal en haut a gauche
        -- disparaissent, la main reste.
        if photo.cache then return dessiner_main(self, width, height) end

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

        dessiner_main(self, width, height)
    end)

    return journal
end
