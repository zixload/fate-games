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
Cosmetiques.cuits = true   -- cuites le 27/09
-- Les bots portent-ils ces vetements ? Non pour l'instant (27/09) : ils gardent
-- les apparences d'origine, le temps de tester les vetements au mannequin.
Cosmetiques.pour_bots = false

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
    { id = "haut_hawai", nom = "T-shirt Hawaï", rarete = "epic", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Hawai" },
    { id = "haut_leopard", nom = "T-shirt Léopard", rarete = "epic", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Leopard" },
    { id = "haut_dark", nom = "T-shirt Nuit noire", rarete = "legendary", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_Dark" },
    { id = "haut_soleilretro", nom = "T-shirt Soleil rétro", rarete = "legendary", emplacement = "haut", piece = "SK_COS_TShirt_Rare_Compass", materiau = "MI_COS_TShirt_M_SoleilRetro" },
    -- Tete, chaussures et accessoires du kit Creative
    { id = "cheveux_kit_010", nom = "Coiffure bouclée", rarete = "common", emplacement = "cheveux", piece = "SK_Hairstyle_male_010" },
    { id = "cheveux_kit_012", nom = "Coiffure classique", rarete = "common", emplacement = "cheveux", piece = "SK_Hairstyle_male_012" },
    { id = "visage_kit_usual", nom = "Visage tranquille", rarete = "common", emplacement = "visage", piece = "SK_Male_emotion_usual_001" },
    { id = "visage_kit_happy", nom = "Visage content", rarete = "common", emplacement = "visage", piece = "SK_Male_emotion_happy_002" },
    { id = "visage_kit_angry", nom = "Visage ronchon", rarete = "common", emplacement = "visage", piece = "SK_Male_emotion_angry_003" },
    { id = "chapeau_kit_010", nom = "Chapeau", rarete = "common", emplacement = "chapeau", piece = "SK_Hat_010" },
    { id = "lunettes_kit_004", nom = "Lunettes rondes", rarete = "common", emplacement = "lunettes", piece = "SK_Glasses_004" },
    { id = "lunettes_kit_006", nom = "Lunettes carrées", rarete = "common", emplacement = "lunettes", piece = "SK_Glasses_006" },
    { id = "barbe_kit_001", nom = "Moustache", rarete = "common", emplacement = "barbe", piece = "SK_Moustache_001" },
    { id = "barbe_kit_002", nom = "Grosse moustache", rarete = "common", emplacement = "barbe", piece = "SK_Moustache_002" },
    { id = "chaussures_kit_baskets", nom = "Baskets", rarete = "common", emplacement = "chaussures", piece = "SK_Shoe_Sneakers_009" },
    { id = "chaussures_kit_chaussons", nom = "Chaussons", rarete = "common", emplacement = "chaussures", piece = "SK_Shoe_Slippers_002" },
    { id = "chaussures_kit_pantoufles", nom = "Pantoufles", rarete = "common", emplacement = "chaussures", piece = "SK_Shoe_Slippers_005" },
    { id = "chaussures_kit_chaussettes", nom = "Chaussettes", rarete = "common", emplacement = "chaussures", piece = "SK_Socks_008" },
    { id = "accessoire_kit_casque", nom = "Casque audio", rarete = "common", emplacement = "accessoire", piece = "SK_Headphones_002" },
    { id = "accessoire_kit_nez", nom = "Nez de clown", rarete = "common", emplacement = "accessoire", piece = "SK_Clown_nose_001" },
    { id = "accessoire_kit_tetine", nom = "Tétine", rarete = "common", emplacement = "accessoire", piece = "SK_Pacifier_001" },
    { id = "accessoire_kit_gants", nom = "Gants", rarete = "common", emplacement = "accessoire", piece = "SK_Gloves_006" },
    -- Tete : accessoires, coiffures, expressions (scripts/blender/create_tete.py)
    -- (27/09 : seuls les visages, l'aureole et les cornes sont valides ; chapeaux,
    -- lunettes, pirate et coiffures sont a refaire, retires en attendant)
    { id = "accessoire_cornes", nom = "Cornes de diable", rarete = "epic", emplacement = "accessoire", piece = "SK_COS_Accessoire_Cornes" },
    { id = "accessoire_aureole", nom = "Auréole", rarete = "legendary", emplacement = "accessoire", piece = "SK_COS_Accessoire_Aureole" },
    { id = "visage_petitsyeux", nom = "Petits yeux", rarete = "common", emplacement = "visage", piece = "SK_COS_Visage_PetitsYeux" },
    { id = "visage_enerve", nom = "Énervé", rarete = "common", emplacement = "visage", piece = "SK_COS_Visage_Enerve" },
    { id = "visage_etonne", nom = "Étonné", rarete = "uncommon", emplacement = "visage", piece = "SK_COS_Visage_Etonne" },
    { id = "visage_endormi", nom = "Endormi", rarete = "uncommon", emplacement = "visage", piece = "SK_COS_Visage_Endormi" },
    { id = "visage_triste", nom = "Triste", rarete = "uncommon", emplacement = "visage", piece = "SK_COS_Visage_Triste" },
    { id = "visage_clinoeil", nom = "Clin d'œil", rarete = "rare", emplacement = "visage", piece = "SK_COS_Visage_ClinOeil" },
    { id = "visage_grandsourire", nom = "Grand sourire", rarete = "rare", emplacement = "visage", piece = "SK_COS_Visage_GrandSourire" },
    -- Bas du kit Creative
    { id = "bas_kit_cargo", nom = "Cargo Creative", rarete = "common", emplacement = "bas", piece = "SK_Pants_010" },
    { id = "bas_kit_pantalon", nom = "Pantalon Creative", rarete = "common", emplacement = "bas", piece = "SK_Pants_014" },
    { id = "bas_kit_short", nom = "Short Creative", rarete = "common", emplacement = "bas", piece = "SK_Shorts_003" },
    -- Pantalons et shorts (scripts/blender/create_pantalons.py)
    { id = "bas_jeanbrut", nom = "Jean brut", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Droit", materiau = "MI_COS_Pants_JeanBrut" },
    { id = "bas_jogging", nom = "Jogging", rarete = "common", emplacement = "bas", piece = "SK_COS_Pants_Jogger", materiau = "MI_COS_Pants_Jogging" },
    { id = "bas_cargo", nom = "Cargo kaki", rarete = "uncommon", emplacement = "bas", piece = "SK_COS_Pants_Cargo", materiau = "MI_COS_Pants_Cargo" },
    { id = "bas_tartan", nom = "Slim tartan", rarete = "rare", emplacement = "bas", piece = "SK_COS_Pants_Slim", materiau = "MI_COS_Pants_Tartan" },
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
    -- Ajouts du 27/09, en fin de liste : les numeros deja vus ne bougent pas.
    -- Coiffures sur le crane (scripts/blender/create_cheveux.py), atlas du kit
    { id = "cheveux_courte", nom = "Coupe courte", rarete = "common", emplacement = "cheveux", piece = "SK_COS_Cheveux_Courte" },
    { id = "cheveux_lisses", nom = "Cheveux lisses", rarete = "common", emplacement = "cheveux", piece = "SK_COS_Cheveux_Lisses" },
    { id = "cheveux_afro", nom = "Afro", rarete = "uncommon", emplacement = "cheveux", piece = "SK_COS_Cheveux_Afro" },
    -- Manches longues tartan (scripts/blender/create_manches_longues.py)
    { id = "haut_ml_rouge", nom = "Manches longues tartan rouge", rarete = "rare", emplacement = "haut", piece = "SK_COS_TShirt_ManchesLongues", materiau = "MI_COS_ML_Rouge" },
    { id = "haut_ml_foret", nom = "Manches longues tartan forêt", rarete = "rare", emplacement = "haut", piece = "SK_COS_TShirt_ManchesLongues", materiau = "MI_COS_ML_Foret" },
    { id = "haut_ml_gris", nom = "Manches longues tartan gris", rarete = "uncommon", emplacement = "haut", piece = "SK_COS_TShirt_ManchesLongues", materiau = "MI_COS_ML_Gris" },
    { id = "haut_ml_moutarde", nom = "Manches longues tartan moutarde", rarete = "rare", emplacement = "haut", piece = "SK_COS_TShirt_ManchesLongues", materiau = "MI_COS_ML_Moutarde" },
    { id = "haut_ml_ciel", nom = "Manches longues tartan ciel", rarete = "uncommon", emplacement = "haut", piece = "SK_COS_TShirt_ManchesLongues", materiau = "MI_COS_ML_Ciel" },
    { id = "haut_ml_rose", nom = "Manches longues tartan rose", rarete = "rare", emplacement = "haut", piece = "SK_COS_TShirt_ManchesLongues", materiau = "MI_COS_ML_Rose" },
    -- Chapeaux et lunettes telecharges (scripts/blender/create_accessoires.py)
    { id = "chapeau_capitaine", nom = "Casquette de capitaine", rarete = "epic", emplacement = "chapeau", piece = "SK_COS_Capitaine", materiau = "MI_COS_Capitaine" },
    { id = "chapeau_clown", nom = "Bonnet de bouffon", rarete = "rare", emplacement = "chapeau", piece = "SK_COS_Clown", materiau = "MI_COS_Clown" },
    { id = "lunettes_coeur", nom = "Lunettes cœur", rarete = "rare", emplacement = "lunettes", piece = "SK_COS_LunettesCoeur", materiau = "MI_COS_LunettesCoeur" },
    { id = "chapeau_magicien", nom = "Chapeau de magicien", rarete = "legendary", emplacement = "chapeau", piece = "SK_COS_Magicien", materiau = "MI_COS_Magicien" },
    { id = "chapeau_officier", nom = "Casquette d'officier", rarete = "rare", emplacement = "chapeau", piece = "SK_COS_Officier", materiau = "MI_COS_Officier" },
    { id = "chapeau_sorciere", nom = "Chapeau de sorcière", rarete = "epic", emplacement = "chapeau", piece = "SK_COS_Sorciere", materiau = "MI_COS_Sorciere" },
    { id = "chapeau_tricorne", nom = "Tricorne", rarete = "epic", emplacement = "chapeau", piece = "SK_COS_Tricorne", materiau = "MI_COS_Tricorne" },
    -- Chaussures (scripts/blender/create_creative_footwear.py) : materiaux poses a l'import.
    { id = "chaussures_geta", nom = "Geta en bois", rarete = "rare", emplacement = "chaussures", piece = "SK_COS_Geta_Wood" },
    { id = "chaussures_chaussettes_ecrues", nom = "Chaussettes écrues", rarete = "common", emplacement = "chaussures", piece = "SK_COS_Socks_Ivory" },
    { id = "chaussures_chaussettes_anthracite", nom = "Chaussettes anthracite", rarete = "common", emplacement = "chaussures", piece = "SK_COS_Socks_Charcoal" },
    { id = "chaussures_chaussettes_rayees", nom = "Chaussettes rayées", rarete = "common", emplacement = "chaussures", piece = "SK_COS_Socks_BlackStripe" },
}

-- Les categories, dans l'ordre du mannequin et du vestiaire. Une categorie
-- vide s'affiche "a venir" : les pieces arriveront (accessoires chers...).
Cosmetiques.emplacements = {
    { id = "cheveux", nom = "Cheveux" },
    { id = "visage", nom = "Visage" },
    { id = "chapeau", nom = "Chapeau" },
    { id = "lunettes", nom = "Lunettes" },
    { id = "barbe", nom = "Barbe" },
    { id = "haut", nom = "Haut" },
    { id = "bas", nom = "Bas" },
    { id = "chaussures", nom = "Chaussures" },
    { id = "accessoire", nom = "Accessoire" },
}

-- Un meme modele en plusieurs couleurs = un seul article (27/09) : on
-- l'achete une fois, puis on choisit sa couleur chez le tailleur. Chaque
-- couleur garde son identifiant (la tenue enregistree le reference) ;
-- l'article, lui, porte l'identifiant du groupe, le prix et le numero.
local GROUPES = {
    bas_ample = { nom = "Pantalon ample", rarete = "common", couleurs = {
        bas_amplenoir = { "noir", "#1e1e21" }, bas_amplebeige = { "beige", "#cbb68f" },
        bas_amplemarron = { "marron", "#5a3b24" }, bas_amplegris = { "gris", "#6e7176" },
        bas_amplemarine = { "marine", "#1f2a44" }, bas_ampleolive = { "olive", "#4f5a2c" },
        bas_amplecreme = { "crème", "#ebe4d4" } } },
    bas_pyjama = { nom = "Pyjama", rarete = "uncommon", couleurs = {
        bas_pyjamableu = { "bleu ciel", "#7fb3e0" }, bas_pyjamarose = { "rose", "#f2a0b8" },
        bas_pyjamavert = { "menthe", "#7cc49a" }, bas_pyjamamarine = { "marine", "#23355c" },
        bas_pyjamarouge = { "rouge", "#c2303b" }, bas_pyjamaviolet = { "violet", "#8e6cc4" } } },
    chaussures_chaussettes = { nom = "Chaussettes", rarete = "common", couleurs = {
        chaussures_chaussettes_ecrues = { "écrues", "#ece3cf" },
        chaussures_chaussettes_anthracite = { "anthracite", "#3a3b3e" },
        chaussures_chaussettes_rayees = { "rayées", "#f4f1ea" } } },
    haut_ml_tartan = { nom = "Manches longues tartan", rarete = "rare", couleurs = {
        haut_ml_rouge = { "rouge", "#b3202a" }, haut_ml_foret = { "forêt", "#27543a" },
        haut_ml_gris = { "gris", "#8d9095" }, haut_ml_moutarde = { "moutarde", "#c99a2e" },
        haut_ml_ciel = { "ciel", "#6fa9da" }, haut_ml_rose = { "rose", "#dd8fab" } } },
}

Cosmetiques.par_emplacement = {}
Cosmetiques.par_id = {}
Cosmetiques.groupes = {}     -- id du groupe -> { id, nom, rarete, emplacement, numero, variantes }
local numeros = {}           -- emplacement -> { [id ou groupe] = numero }
for _, c in ipairs(Cosmetiques.liste) do
    c.piece_chemin = PACK .. "::" .. c.piece
    c.materiau_chemin = c.materiau and (PACK .. "::" .. c.materiau) or nil
    Cosmetiques.par_id[c.id] = c
    local e = Cosmetiques.par_emplacement[c.emplacement] or {}
    e[#e + 1] = c
    Cosmetiques.par_emplacement[c.emplacement] = e
    for gid, g in pairs(GROUPES) do
        local couleur = g.couleurs[c.id]
        if couleur then
            c.groupe, c.teinte, c.couleur = gid, couleur[1], couleur[2]
            local groupe = Cosmetiques.groupes[gid] or { id = gid, nom = g.nom, rarete = g.rarete,
                                                         emplacement = c.emplacement, variantes = {} }
            groupe.variantes[#groupe.variantes + 1] = c
            Cosmetiques.groupes[gid] = groupe
        end
    end
    -- Numero dans sa categorie (Cheveux 01, 02...) : le meme au mannequin et
    -- chez le tailleur, pour retrouver vite une piece reperee. Les couleurs
    -- d'un meme article partagent son numero. Ajouter les nouvelles pieces en
    -- fin de liste garde les numeros existants.
    local n = numeros[c.emplacement] or { _total = 0 }
    local cle = c.groupe or c.id
    if not n[cle] then
        n._total = n._total + 1
        n[cle] = n._total
    end
    c.numero = n[cle]
    if c.groupe then Cosmetiques.groupes[c.groupe].numero = n[cle] end
    numeros[c.emplacement] = n
end

-- L'identifiant qu'on achete pour une piece : son groupe s'il en a un.
function Cosmetiques.achat_id(id)
    local c = Cosmetiques.par_id[id]
    return c and c.groupe or id
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
