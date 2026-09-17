-- Un barillet de roulette russe.
--
-- Six chambres, une balle a une position tiree au hasard a la creation. Le
-- decompte des tirs TRAVERSE les manches : c'est le seul element du jeu qui
-- survive a une remise a zero. Le premier tir est a une chance sur six, le
-- suivant sur cinq, puis sur quatre — la menace monte a mesure qu'on survit,
-- et le decompte de chacun est public.
--
-- Un barillet ne se recharge jamais : celui dont le coup part quitte la partie.

return function(config)
    local Revolver = {}

    function Revolver.New(rng)
        return {
            bullet   = rng(config.chambers),
            fired    = 0,
            chambers = config.chambers,
        }
    end

    function Revolver.Remaining(rev)
        return rev.chambers - rev.fired
    end

    -- Rend l'issue du tir et le numero de la chambre tiree. L'issue etait fixee
    -- a la creation du barillet : rien ne se joue a cet instant, et c'est
    -- justement ce qui permet de resoudre un tir sans son proprietaire.
    function Revolver.Pull(rev)
        if rev.fired >= rev.chambers then
            error("barillet epuise : aucune chambre restante")
        end

        rev.fired = rev.fired + 1
        return rev.fired == rev.bullet, rev.fired
    end

    return Revolver
end
