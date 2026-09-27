-- Catalogue des vetements a combiner : hauts et bas, du commun au legendaire.
--
-- Genere depuis les manifestes des scripts Blender (art/cosmetics/*, hors
-- depot) ; importe dans my-asset-pack par scripts/unreal/import_cosmetiques.py.
-- piece : maillage squelettique accroche au personnage (AddSkeletalMeshAttached) ;
-- materiau : pose ensuite sur cette piece (SetMaterial avec son identifiant,
-- doc Paintable). Une meme coupe porte ainsi plusieurs motifs.
--
-- Prix et achat viendront avec le vestiaire en pieces ; pour l'instant ce
-- catalogue habille les bots au hasard (Shared/appearances.lua, Aleatoire).

local PACK = "my-asset-pack"

local Cosmetiques = {}

-- Les pieces SK_COS_* sont-elles cuites dans my-asset-pack ? Tant que non,
-- les tenues aleatoires ne piochent que dans les pieces du kit (SK_*), deja
-- cuites : sinon un bot se retrouverait sans vetement.
Cosmetiques.cuits = false

Cosmetiques.liste = {
    -- Hauts du kit Creative et de ChatGPT
    { id = "haut_kit_tshirt", nom = "T-shirt Creative", rarete = "common", emplacement = "haut", piece = "SK_T_Shirt_009" },
    { id = "haut_kit_veste_029", nom = "Veste", rarete = "common", emplacement = "haut", piece = "SK_Outerwear_029" },
    { id = "haut_kit_veste_036", nom = "Blouson", rarete = "common", emplacement = "haut", piece = "SK_Outerwear_036" },
    { id = "haut_effiloche", nom = "T-shirt effiloché", rarete = "uncommon", emplacement = "haut", piece = "SK_COS_TShirt_Uncommon_Frayed" },
    { id = "haut_eclaireur", nom = "T-shirt Éclaireur", rarete = "rare", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_Rare_Compass" },
    { id = "haut_eclipse", nom = "T-shirt Éclipse", rarete = "epic", emplacement = "haut", piece = "SK_COS_TShirt_Epic_Eclipse", materiau = "MI_COS_TShirt_Epic_Eclipse" },
    { id = "haut_soleil_or", nom = "T-shirt Soleil d'or", rarete = "legendary", emplacement = "haut", piece = "SK_COS_TShirt_Legendary_Sun", materiau = "MI_COS_TShirt_Legendary_Sun" },
    -- T-shirts a motifs (scripts/blender/create_tshirt_motifs.py)
    { id = "haut_delave", nom = "T-shirt Délavé", rarete = "common", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Delave" },
    { id = "haut_pois", nom = "T-shirt Pois pastel", rarete = "common", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Pois" },
    { id = "haut_mariniere", nom = "T-shirt Marinière", rarete = "uncommon", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Mariniere" },
    { id = "haut_bucheron", nom = "T-shirt Bûcheron", rarete = "uncommon", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Bucheron" },
    { id = "haut_camouflage", nom = "T-shirt Camouflage", rarete = "rare", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Camouflage" },
    { id = "haut_peinture", nom = "T-shirt Éclaboussures", rarete = "rare", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Peinture" },
    { id = "haut_vagues", nom = "T-shirt Grande vague", rarete = "rare", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Vagues" },
    { id = "haut_tiedye", nom = "T-shirt Tie & Dye", rarete = "epic", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_TieDye" },
    { id = "haut_hawai", nom = "T-shirt Hawaï", rarete = "epic", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Hawai" },
    { id = "haut_leopard", nom = "T-shirt Léopard", rarete = "epic", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Leopard" },
    { id = "haut_flammes", nom = "T-shirt Flammes", rarete = "epic", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Flammes" },
    { id = "haut_dark", nom = "T-shirt Nuit noire", rarete = "legendary", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Dark" },
    { id = "haut_galaxie", nom = "T-shirt Galaxie", rarete = "legendary", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Galaxie" },
    { id = "haut_soleilretro", nom = "T-shirt Soleil rétro", rarete = "legendary", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_SoleilRetro" },
    -- Bas du kit Creative
    { id = "bas_kit_cargo", nom = "Cargo Creative", rarete = "common", emplacement = "bas", piece = "SK_Pants_010" },
    { id = "bas_kit_pantalon", nom = "Pantalon Creative", rarete = "common", emplacement = "bas", piece = "SK_Pants_014" },
    { id = "bas_kit_short", nom = "Short Creative", rarete = "common", emplacement = "bas", piece = "SK_Shorts_003" },
    -- Pantalons et shorts (scripts/blender/create_pantalons.py)
    { id = "bas_jeanbrut", nom = "Jean brut", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Droit", materiau = "MI_COS_Pants_JeanBrut" },
    { id = "bas_jogging", nom = "Jogging", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Jogger", materiau = "MI_COS_Pants_Jogging" },
    { id = "bas_cargo", nom = "Cargo kaki", rarete = "uncommon", emplacement = "bas", piece = "SK_COS_Pants_Cargo", materiau = "MI_COS_Pants_Cargo" },
    { id = "bas_velours", nom = "Pattes d'eph velours", rarete = "uncommon", emplacement = "bas", piece = "SK_COS_Pants_PattesEph", materiau = "MI_COS_Pants_Velours" },
    { id = "bas_jeanbaggy", nom = "Baggy délavé", rarete = "rare", emplacement = "bas", piece = "SK_COS_Pants_Baggy", materiau = "MI_COS_Pants_JeanBaggy" },
    { id = "bas_tartan", nom = "Slim tartan", rarete = "rare", emplacement = "bas", piece = "SK_COS_Pants_Slim", materiau = "MI_COS_Pants_Tartan" },
    { id = "bas_camocargo", nom = "Cargo camo", rarete = "rare", emplacement = "bas", piece = "SK_COS_Pants_Cargo", materiau = "MI_COS_Pants_CamoCargo" },
    { id = "bas_shorthawai", nom = "Short hawaïen", rarete = "rare", emplacement = "bas", piece = "SK_COS_Shorts", materiau = "MI_COS_Pants_ShortHawai" },
    { id = "bas_tiedye", nom = "Pattes d'eph tie & dye", rarete = "epic", emplacement = "bas", piece = "SK_COS_Pants_PattesEph", materiau = "MI_COS_Pants_TieDye" },
    { id = "bas_flammes", nom = "Flammes", rarete = "epic", emplacement = "bas", piece = "SK_COS_Pants_Droit", materiau = "MI_COS_Pants_Flammes" },
    { id = "bas_leopard", nom = "Slim léopard", rarete = "epic", emplacement = "bas", piece = "SK_COS_Pants_Slim", materiau = "MI_COS_Pants_Leopard" },
    { id = "bas_galaxie", nom = "Pattes d'eph galaxie", rarete = "legendary", emplacement = "bas", piece = "SK_COS_Pants_PattesEph", materiau = "MI_COS_Pants_Galaxie" },
    { id = "bas_dark", nom = "Cargo nuit noire", rarete = "legendary", emplacement = "bas", piece = "SK_COS_Pants_Cargo", materiau = "MI_COS_Pants_Dark" },
    { id = "bas_pyjamableu", nom = "Pyjama bleu ciel", rarete = "uncommon", emplacement = "bas", piece = "SK_COS_Pants_Slim", materiau = "MI_COS_Pants_PyjamaBleu" },
    { id = "bas_pyjamarose", nom = "Pyjama rose", rarete = "uncommon", emplacement = "bas", piece = "SK_COS_Pants_Slim", materiau = "MI_COS_Pants_PyjamaRose" },
    { id = "bas_pyjamavert", nom = "Pyjama menthe", rarete = "uncommon", emplacement = "bas", piece = "SK_COS_Pants_Slim", materiau = "MI_COS_Pants_PyjamaVert" },
    { id = "bas_pyjamamarine", nom = "Pyjama marine", rarete = "uncommon", emplacement = "bas", piece = "SK_COS_Pants_Slim", materiau = "MI_COS_Pants_PyjamaMarine" },
    { id = "bas_pyjamarouge", nom = "Pyjama rouge", rarete = "uncommon", emplacement = "bas", piece = "SK_COS_Pants_Slim", materiau = "MI_COS_Pants_PyjamaRouge" },
    { id = "bas_pyjamaviolet", nom = "Pyjama violet", rarete = "uncommon", emplacement = "bas", piece = "SK_COS_Pants_Slim", materiau = "MI_COS_Pants_PyjamaViolet" },
    { id = "bas_shortpoussins", nom = "Short poussins", rarete = "rare", emplacement = "bas", piece = "SK_COS_Shorts", materiau = "MI_COS_Pants_ShortPoussins" },
    { id = "bas_shortchauvessouris", nom = "Short chauves-souris", rarete = "rare", emplacement = "bas", piece = "SK_COS_Shorts", materiau = "MI_COS_Pants_ShortChauvesSouris" },
    { id = "bas_shorttoile", nom = "Short toile", rarete = "rare", emplacement = "bas", piece = "SK_COS_Shorts", materiau = "MI_COS_Pants_ShortToile" },
    { id = "bas_shortbananes", nom = "Short bananes", rarete = "rare", emplacement = "bas", piece = "SK_COS_Shorts", materiau = "MI_COS_Pants_ShortBananes" },
    { id = "bas_shortpasteques", nom = "Short pastèques", rarete = "rare", emplacement = "bas", piece = "SK_COS_Shorts", materiau = "MI_COS_Pants_ShortPasteques" },
    { id = "bas_shortdonuts", nom = "Short donuts", rarete = "rare", emplacement = "bas", piece = "SK_COS_Shorts", materiau = "MI_COS_Pants_ShortDonuts" },
    { id = "bas_amplenoir", nom = "Ample noir", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Ample", materiau = "MI_COS_Pants_AmpleNoir" },
    { id = "bas_amplebeige", nom = "Ample beige", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Ample", materiau = "MI_COS_Pants_AmpleBeige" },
    { id = "bas_amplemarron", nom = "Ample marron", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Ample", materiau = "MI_COS_Pants_AmpleMarron" },
    { id = "bas_amplegris", nom = "Ample gris", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Ample", materiau = "MI_COS_Pants_AmpleGris" },
    { id = "bas_amplemarine", nom = "Ample marine", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Ample", materiau = "MI_COS_Pants_AmpleMarine" },
    { id = "bas_ampleolive", nom = "Ample olive", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Ample", materiau = "MI_COS_Pants_AmpleOlive" },
    { id = "bas_amplecreme", nom = "Ample crème", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Ample", materiau = "MI_COS_Pants_AmpleCreme" },
}

Cosmetiques.par_emplacement = {}
Cosmetiques.par_id = {}
for _, c in ipairs(Cosmetiques.liste) do
    c.piece_chemin = PACK .. "::" .. c.piece
    c.materiau_chemin = c.materiau and (PACK .. "::" .. c.materiau) or nil
    Cosmetiques.par_id[c.id] = c
    local e = Cosmetiques.par_emplacement[c.emplacement] or {}
    e[#e + 1] = c
    Cosmetiques.par_emplacement[c.emplacement] = e
end

-- Accroche une tenue resolue (Shared/appearances.lua) a un corps : tete,
-- vetements, puis le materiau de chaque vetement qui en a un.
function Cosmetiques.Habiller(corps, look, prefixe)
    prefixe = prefixe or "tenue"
    corps:SetMesh(look.body)
    corps:RemoveAllSkeletalMeshesAttached()
    for i, mesh in ipairs(look.head or {}) do corps:AddSkeletalMeshAttached(prefixe .. "_tete_" .. i, mesh) end
    for i, mesh in ipairs(look.worn or {}) do
        local id = prefixe .. "_piece_" .. i
        corps:AddSkeletalMeshAttached(id, mesh)
        local mat = look.materiaux and look.materiaux[i]
        if mat then pcall(function() corps:SetMaterial(mat, -1, id) end) end
    end
end

return Cosmetiques
