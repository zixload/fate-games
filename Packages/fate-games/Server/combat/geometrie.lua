-- Geometrie du combat, en Lua pur (docs/COMBAT.md). Vecteurs en tables
-- { x, y, z }, distances en cm, angles en degres. Le serveur de nanos ne sait
-- pas tracer de rayon : le corps a corps et la verification des tirs passent
-- par ces calculs sur les positions connues.
--
-- Un combattant est une capsule verticale : `centre` est le milieu du corps
-- (ce que rend GetLocation d'un Character), `demi_hauteur` va du centre aux
-- pieds, `rayon` est l'epaisseur.

local G = {}

function G.v(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function G.copie(a) return { x = a.x, y = a.y, z = a.z } end
function G.plus(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end
function G.moins(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
function G.fois(a, k) return { x = a.x * k, y = a.y * k, z = a.z * k } end
function G.scalaire(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function G.longueur(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function G.distance(a, b) return G.longueur(G.moins(a, b)) end

function G.distance_plane(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function G.normal(a)
    local l = G.longueur(a)
    if l < 1e-9 then return G.v(1, 0, 0) end
    return G.fois(a, 1 / l)
end

-- Interpolation lineaire entre deux points.
function G.lerp(a, b, k)
    return { x = a.x + (b.x - a.x) * k, y = a.y + (b.y - a.y) * k, z = a.z + (b.z - a.z) * k }
end

-- Angle ramene dans ]-180, 180].
function G.angle(deg)
    local a = (deg + 180) % 360 - 180
    if a == -180 then a = 180 end
    return a
end

-- Direction de regard depuis un lacet et un tangage (tangage positif : vers le haut).
function G.direction(yaw, pitch)
    local y, p = math.rad(yaw or 0), math.rad(pitch or 0)
    return { x = math.cos(p) * math.cos(y), y = math.cos(p) * math.sin(y), z = math.sin(p) }
end

-- Lacet (degres) qui regarde de a vers b.
function G.lacet_vers(a, b)
    return math.deg(math.atan(b.y - a.y, b.x - a.x))
end

-- Ecart horizontal (degres, absolu) entre le lacet de `depuis` et la direction
-- de `depuis_pos` vers `cible`.
function G.ecart(yaw, depuis_pos, cible)
    return math.abs(G.angle(G.lacet_vers(depuis_pos, cible) - (yaw or 0)))
end

-- Vrai si `cible` est dans l'arc horizontal devant `pos` (demi-angle en
-- degres) et a moins de `portee` (distance plane, bord de la capsule compris).
function G.dans_arc(pos, yaw, cible, portee, demi_angle, rayon_cible)
    local d = G.distance_plane(pos, cible) - (rayon_cible or 0)
    if d > portee then return false end
    if G.distance_plane(pos, cible) < 1 then return true end
    return G.ecart(yaw, pos, cible) <= demi_angle
end

-- Point le plus proche de p sur le segment [a, b], et son parametre (0..1).
function G.proche_segment(p, a, b)
    local ab = G.moins(b, a)
    local l2 = G.scalaire(ab, ab)
    if l2 < 1e-9 then return G.copie(a), 0 end
    local k = math.max(0, math.min(1, G.scalaire(G.moins(p, a), ab) / l2))
    return G.plus(a, G.fois(ab, k)), k
end

-- Distance minimale entre deux segments [p1, q1] et [p2, q2], avec les
-- parametres des deux points les plus proches (Ericson, Real-Time Collision
-- Detection, 5.1.9).
function G.segments(p1, q1, p2, q2)
    local d1, d2, r = G.moins(q1, p1), G.moins(q2, p2), G.moins(p1, p2)
    local a, e, f = G.scalaire(d1, d1), G.scalaire(d2, d2), G.scalaire(d2, r)
    local s, t
    if a <= 1e-9 and e <= 1e-9 then
        s, t = 0, 0
    elseif a <= 1e-9 then
        s, t = 0, math.max(0, math.min(1, f / e))
    else
        local c = G.scalaire(d1, r)
        if e <= 1e-9 then
            t, s = 0, math.max(0, math.min(1, -c / a))
        else
            local b = G.scalaire(d1, d2)
            local denom = a * e - b * b
            s = denom ~= 0 and math.max(0, math.min(1, (b * f - c * e) / denom)) or 0
            t = (b * s + f) / e
            if t < 0 then
                t, s = 0, math.max(0, math.min(1, -c / a))
            elseif t > 1 then
                t, s = 1, math.max(0, math.min(1, (b - c) / a))
            end
        end
    end
    local c1, c2 = G.plus(p1, G.fois(d1, s)), G.plus(p2, G.fois(d2, t))
    return G.distance(c1, c2), s, t, c1, c2
end

-- Axe d'une capsule verticale : du bas (pieds + rayon) au haut (tete - rayon).
function G.axe_capsule(centre, demi_hauteur, rayon)
    local h = math.max(0, demi_hauteur - rayon)
    return G.v(centre.x, centre.y, centre.z - h), G.v(centre.x, centre.y, centre.z + h)
end

-- Un segment (tir, projectile) touche-t-il une capsule ? Rend la part du
-- segment ou il y entre (0..1), le point d'entree, et la distance minimale
-- entre le segment et l'axe du corps (un tir qui frole touche un bras), ou nil.
function G.segment_capsule(p, q, centre, demi_hauteur, rayon)
    local a, b = G.axe_capsule(centre, demi_hauteur, rayon)
    local d, s, _, c1 = G.segments(p, q, a, b)
    if d > rayon then return nil end
    -- Recule jusqu'a l'entree dans la capsule (approche par dichotomie : le
    -- point exact compte pour la zone touchee et l'ordre des cibles).
    local lo, hi = 0, s
    for _ = 1, 12 do
        local mid = (lo + hi) / 2
        local pt = G.lerp(p, q, mid)
        local proche = G.proche_segment(pt, a, b)
        if G.distance(pt, proche) <= rayon then hi = mid else lo = mid end
    end
    return hi, G.lerp(p, q, hi), d
end

-- Zone touchee d'apres la hauteur du point au-dessus des pieds et l'ecart du
-- coup a l'axe du corps (0 : plein centre). `z` : proportions de la
-- silhouette (regles.lua).
function G.zone(point, centre, demi_hauteur, rayon, z, ecart)
    local pieds = centre.z - demi_hauteur
    local h = (point.z - pieds) / (2 * demi_hauteur)
    if h >= z.tete then return "tete" end
    if h < z.jambes then return "jambes" end
    if (ecart or 0) > rayon * z.bras then return "bras" end
    return "torse"
end

return G
