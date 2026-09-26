-- Vocabulaire des effets du loup-garou : le contrat entre le moteur et
-- l'adaptateur (spec, "Vocabulaire des effets"). Pur.
--
-- Chaque effet porte une audience : "all", "wolves", "dead", ou l'id d'un
-- joueur. C'est ce qui protege le jeu : un role ou une vision ne part qu'a son
-- destinataire, la designation des loups qu'aux loups. Un effet sans audience
-- valide est une erreur, pas un oubli silencieux.

return function()
    local E = {}

    local AUDIENCES = { all = true, wolves = true, dead = true }

    local function effet(kind, champs, audience)
        if not (AUDIENCES[audience] or type(audience) == "number") then
            error(("effet %s : audience invalide (%s)"):format(kind, tostring(audience)), 2)
        end
        champs.kind, champs.audience = kind, audience
        return champs
    end

    -- Le role, a son seul destinataire ; allies : les autres loups, pour un loup.
    function E.assign_role(joueur, role, allies)
        return effet("assign_role", { player = joueur, role = role, allies = allies or {} }, joueur)
    end

    function E.phase(id, duree) return effet("phase", { id = id, duree = duree }, "all") end

    -- Le decompte d'un vote : public le jour, aux loups la nuit.
    function E.votes(compte, audience) return effet("votes", { compte = compte }, audience) end

    -- Vision de la voyante : le role de la cible, a la seule voyante.
    function E.reveal(voyant, cible, role)
        return effet("reveal", { viewer = voyant, target = cible, role = role }, voyant)
    end

    -- Cupidon a lie ce joueur a son partenaire : il ne le sait que pour lui.
    function E.lovers(joueur, partenaire)
        return effet("lovers", { player = joueur, partner = partenaire }, joueur)
    end

    function E.point_at(joueur, cible, audience)
        return effet("point_at", { player = joueur, target = cible }, audience)
    end

    function E.kill(joueur, cause) return effet("kill", { player = joueur, cause = cause }, "all") end

    function E.voice_channel(joueur, canal)
        return effet("voice_channel", { player = joueur, channel = canal }, joueur)
    end

    -- Le maire du village, public.
    function E.mayor(joueur) return effet("mayor", { player = joueur }, "all") end

    function E.announce(cle, args) return effet("announce", { key = cle, args = args or {} }, "all") end

    function E.world_light(phase) return effet("world_light", { phase = phase }, "all") end

    function E.match_ended(gagnant, resume)
        return effet("match_ended", { winner = gagnant, summary = resume or {} }, "all")
    end

    return E
end
