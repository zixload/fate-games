-- Les armes en jeu : l'objet que le personnage natif tient, pour chaque
-- archetype du moteur (combat/armes.lua). Armes a feu : Weapon natif, avec les
-- reglages officiels du package nanos-world-weapons (sons, poses des mains,
-- viseur, particules) ; ses degats natifs sont reecrits par le moteur
-- (TakeDamage). Corps a corps : Melee natif sans son attaque (can_use false),
-- c'est le moteur qui frappe. Arc, poings : rien en main pour l'instant.
--
-- Les modeles sont ceux du pack par defaut ; `config.visuels[archetype]`
-- permet de mettre ceux de my-asset-pack (epees, arcs...) plus tard.

return function(config)
    config = config or {}
    local visuels = config.visuels or {}
    local N = {}

    local function arme_a_feu(t)
        return function(id, archetype, loc, rot)
            local w = Weapon(loc, rot, visuels[id] or t.mesh, CollisionType.Auto, true)
            w:SetAmmoSettings(archetype.chargeur, 1000)
            w:SetDamage(archetype.degats)
            w:SetSpread(t.spread)
            w:SetRecoil(t.recoil)
            w:SetBulletSettings(archetype.plombs or 1, archetype.portee, 30000, t.couleur or Color(100, 58, 0))
            w:SetSightTransform(t.sight[1], t.sight[2])
            w:SetLeftHandTransform(t.gauche[1], t.gauche[2])
            w:SetRightHandOffset(t.droite)
            w:SetHandlingMode(t.mains)
            w:SetCadence(archetype.cadence)
            if not archetype.auto then w:SetUsageSettings(false, false) end
            if t.fov then w:SetSightFOVMultiplier(t.fov) end
            w:SetParticlesBulletTrail("nanos-world::P_Bullet_Trail")
            w:SetParticlesBarrel("nanos-world::P_Weapon_BarrelSmoke")
            w:SetParticlesShells(t.douilles)
            w:SetSoundDry(t.son_vide)
            w:SetSoundLoad(t.son_charge)
            w:SetSoundZooming("nanos-world::A_AimZoom")
            w:SetSoundAim("nanos-world::A_Rattle")
            w:SetSoundFire(t.son_tir)
            w:SetAnimationCharacterFire(t.anim_tir)
            w:SetAnimationReload(t.anim_recharge)
            if t.anim_arme then w:SetAnimationFire(t.anim_arme) end
            if t.chargeur_mesh then w:SetMagazineMesh(t.chargeur_mesh) end
            if t.lunette then w:AddStaticMeshAttached("sight", "nanos-world::SM_Scope_25x56", "", Vector(20, 0, 11.175)) end
            return w
        end
    end

    N.pistolet = arme_a_feu {
        mesh = "nanos-world::SK_Glock", spread = 20, recoil = 0.5, mains = HandlingMode.SingleHandedWeapon,
        sight = { Vector(0, 0, 1), Rotator(-0.5, 0, 0) }, gauche = { Vector(0, 0, -4), Rotator(0, 60, 100) },
        droite = Vector(-25, 0, 0), fov = 0.6, douilles = "nanos-world::P_Weapon_Shells_9mm",
        son_vide = "nanos-world::A_Pistol_Dry", son_charge = "nanos-world::A_Pistol_Load", son_tir = "nanos-world::A_Glock_Shot",
        anim_tir = "nanos-world::A_Mannequin_Sight_Fire_Pistol", anim_recharge = "nanos-world::AM_Mannequin_Reload_Pistol",
        anim_arme = "nanos-world::A_Glock_Fire", chargeur_mesh = "nanos-world::SM_Glock_Mag_Empty",
    }
    N.revolver = arme_a_feu {
        mesh = "nanos-world::SK_ColtPython", spread = 50, recoil = 2, mains = HandlingMode.SingleHandedWeapon,
        sight = { Vector(0, 0, -2), Rotator(-0.1, 0, 0) }, gauche = { Vector(0, 0, -4), Rotator(0, 60, 100) },
        droite = Vector(-25, 0, 0), fov = 0.6, douilles = "nanos-world::P_Weapon_Shells_45ap",
        son_vide = "nanos-world::A_Pistol_Dry", son_charge = "nanos-world::A_Shotgun_Load_Bullet", son_tir = "nanos-world::A_Shotgun_Shot_C",
        anim_tir = "nanos-world::A_Mannequin_Sight_Fire_Pistol", anim_recharge = "nanos-world::AM_Mannequin_Reload_Shotgun",
    }
    N.fusil = arme_a_feu {
        mesh = "nanos-world::SK_AK47", spread = 30, recoil = 0.25, mains = HandlingMode.DoubleHandedWeapon,
        sight = { Vector(0, 0, -1), Rotator(-1.5, 0, 0) }, gauche = { Vector(22, 0, 9), Rotator(0, 60, 90) },
        droite = Vector(-10, 0, 0), douilles = "nanos-world::P_Weapon_Shells_762x39",
        son_vide = "nanos-world::A_Rifle_Dry", son_charge = "nanos-world::A_Rifle_Load", son_tir = "nanos-world::A_AK47_Shot",
        anim_tir = "nanos-world::AM_Mannequin_Sight_Fire", anim_recharge = "nanos-world::AM_Mannequin_Reload_Rifle",
        anim_arme = "nanos-world::A_AK47_Fire", chargeur_mesh = "nanos-world::SM_AK47_Mag_Empty",
    }
    N.fusil_pompe = arme_a_feu {
        mesh = "nanos-world::SK_Moss500", spread = 70, recoil = 3, mains = HandlingMode.DoubleHandedWeapon,
        sight = { Vector(0, 0, 3.6), Rotator(-2, 0, 0) }, gauche = { Vector(36.8, 0, 3.8), Rotator(-5, 10, 190) },
        droite = Vector(0, 0, 3), fov = 0.75, douilles = "nanos-world::P_Weapon_Shells_12Gauge",
        son_vide = "nanos-world::A_Shotgun_Dry", son_charge = "nanos-world::A_Shotgun_Load_Bullet", son_tir = "nanos-world::A_Shotgun_Shot",
        anim_tir = "nanos-world::AM_Mannequin_Sight_Fire_Heavy", anim_recharge = "nanos-world::AM_Mannequin_Reload_Shotgun",
        anim_arme = "nanos-world::A_Moss500_Fire",
    }
    N.fusil_precision = arme_a_feu {
        mesh = "nanos-world::SK_AWP", spread = 10, recoil = 1.5, mains = HandlingMode.DoubleHandedWeapon,
        sight = { Vector(-15, 0, -4.5), Rotator(0, 0, 0) }, gauche = { Vector(25, 0, 6), Rotator(0, 60, 90) },
        droite = Vector(-10, 0, 2), fov = 0.1, douilles = "nanos-world::P_Weapon_Shells_762x39", lunette = true,
        son_vide = "nanos-world::A_Shotgun_Dry", son_charge = "nanos-world::A_Shotgun_Load_Bullet", son_tir = "nanos-world::A_SniperRifle_Shot",
        anim_tir = "nanos-world::A_Mannequin_Sight_Fire_Pistol", anim_recharge = "nanos-world::AM_Mannequin_Reload_Rifle",
        anim_arme = "nanos-world::A_AWP_Fire",
    }

    local function corps_a_corps(mesh, mains, echelle)
        return function(id, archetype, loc, rot)
            local m = Melee(loc, rot, visuels[id] or mesh, CollisionType.NoCollision, true, mains, "", false)
            if echelle then m:SetScale(Vector(echelle, echelle, echelle)) end
            m:SetBaseDamage(0)
            return m
        end
    end
    local UNE, DEUX = HandlingMode.SingleHandedMelee, HandlingMode.DoubleHandedMelee
    N.dague = corps_a_corps("nanos-world::SM_M9", UNE)
    N.epee_courte = corps_a_corps("nanos-world::SM_Crowbar_01", UNE, 1.5)
    N.epee_longue = corps_a_corps("nanos-world::SM_Crowbar_01", DEUX, 2)
    N.hache = corps_a_corps("nanos-world::SM_Axe_01", DEUX)
    N.masse = corps_a_corps("nanos-world::SM_Hammer", UNE, 1.6)
    N.lance = corps_a_corps("nanos-world::SM_BaseballBat_01", DEUX, 2.2)
    N.epee_bouclier = corps_a_corps("nanos-world::SM_Crowbar_01", UNE, 1.5)
    N.baton = corps_a_corps("nanos-world::SM_BaseballBat_01", DEUX, 1.8)

    -- Animations de corps a corps du pack par defaut, par arme et direction ;
    -- a remplacer par les vraies quand elles existeront (config.anims).
    local ANIMS = config.anims or {
        defaut = { gauche = "nanos-world::AM_Mannequin_Melee_Slash_Outward_Attack",
            droite = "nanos-world::AM_Mannequin_Melee_Slash_Attack", haut = "nanos-world::AM_Mannequin_Melee_Slash_Attack" },
        dague = { gauche = "nanos-world::AM_Mannequin_Melee_Stab_Attack", droite = "nanos-world::AM_Mannequin_Melee_Stab_Attack",
            haut = "nanos-world::AM_Mannequin_Melee_Stab_Attack" },
        lance = { gauche = "nanos-world::AM_Mannequin_Melee_Bayonet_Stab_Attack", droite = "nanos-world::AM_Mannequin_Melee_Bayonet_Stab_Attack",
            haut = "nanos-world::AM_Mannequin_Melee_Bayonet_Stab_Attack" },
    }

    -- L'objet a tenir pour un archetype (nil : mains nues).
    function N.creer(id, archetype, loc, rot)
        local f = N[id]
        if type(f) ~= "function" or not archetype then return nil end
        local ok, objet = pcall(f, id, archetype, loc or Vector(), rot or Rotator())
        return ok and objet or nil, (not ok) and objet or nil
    end

    function N.anim_attaque(arme, dir)
        local t = ANIMS[arme] or ANIMS.defaut
        return t[dir] or ANIMS.defaut[dir]
    end

    return N
end
