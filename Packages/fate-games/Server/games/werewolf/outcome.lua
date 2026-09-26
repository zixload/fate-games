-- Conditions de victoire du loup-garou (spec, "Victoire" et "Roles ajoutes").
-- Verifiees apres chaque resolution de mort, jamais ailleurs. Pur.
--
--   "lovers"      les deux amoureux, de camps opposes, sont les deux derniers
--   "village"     plus aucun loup vivant
--   "white_wolf"  le loup blanc est le dernier vivant
--   "wolves"      autant de loups que d'autres vivants, et plus de loup blanc
--   "none"        plus personne

return function(Match, Roles)
    local O = {}

    local function camp(s, id) return Roles.roles[Match.role(s, id)].camp end

    function O.verdict(s)
        local vivants = Match.vivants(s)
        if #vivants == 0 then return "none" end

        local a = s.amoureux
        if a and #vivants == 2 and Match.vivant(s, a[1]) and Match.vivant(s, a[2])
            and camp(s, a[1]) ~= camp(s, a[2]) then
            return "lovers"
        end

        local loups = #Match.loups_vivants(s)
        if loups == 0 then return "village" end

        -- Le loup blanc joue seul : tant qu'il vit, les loups ne gagnent pas.
        if Match.porteur(s, "white_wolf") then
            if #vivants == 1 then return "white_wolf" end
            return nil
        end

        if loups >= #vivants - loups then return "wolves" end
        return nil
    end

    return O
end
