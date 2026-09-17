-- Catalogue des apparences jouables.
--
-- Compose a partir du kit modulaire "Creative Characters FREE" : 31 pieces qui
-- partagent une seule texture, donc un pack cuit tres leger.
--
-- Deux modes d'assemblage, imposes par le moteur :
--
--   head  -> AddStaticMeshAttached(id, mesh, "head")
--            Maillages statiques accroches a l'os de la tete. Aucun rigging
--            necessaire : visages, coiffures, chapeaux, lunettes, moustaches.
--
--   worn  -> AddSkeletalMeshAttached(id, mesh)
--            Attaches en "master pose" : ils suivent le corps, donc ils doivent
--            etre skinnes sur le squelette nanos world.
--
-- A produire dans l'ADK avant que ce fichier serve a quoi que ce soit :
--   1. Body_010 rigge sur le squelette nanos world, cuit en skeletal mesh.
--   2. Les pieces "worn" skinnees sur ce meme squelette.
--   3. Les pieces "head" cuites en static meshes — rien de plus.
--   4. Le tout cuit dans un pack dont le nom de dossier est EXACTEMENT celui de
--      PACK ci-dessous, en minuscules (voir le piege des noms de dossier).
--
-- Le nom de l'os de la tete reste a confirmer en jeu : "head" est l'usage
-- courant, mais le squelette nanos world peut le nommer autrement.
--
-- Choix de conception : a Liar's Bar les joueurs sont assis, visibles du buste
-- vers le haut. Les bas et les chaussures ne se verront presque jamais, donc
-- toute la lisibilite entre joueurs est portee par la tete. C'est la que la
-- variete est concentree, volontairement.

local PACK = "creative-characters"

local function ref(nom)
    return PACK .. "::" .. nom
end

local Apparences = {}

Apparences.pack = PACK
Apparences.body = ref("Body_010")

-- L'ordre de cette liste est celui dans lequel les apparences seront presentees.
--
-- Revise apres rendu : Costume_10_001 est un costume de clown et Costume_6_001 un
-- pyjama-souris dont Hat_049 est la tete assortie — ils ne sont donc pas des
-- vetements ordinaires et ne vont qu'a un personnage chacun. Hat_057 est ecarte :
-- il est decale dans son propre repere, contrairement aux trente autres pieces.
--
-- Trois hauts ordinaires seulement (T_Shirt_009, Outerwear_029, Outerwear_036) pour
-- huit personnages : la reutilisation est assumee, et toute la distinction repose
-- sur la tete. Ce qui tombe bien, des joueurs assis ne montrant que leur buste.
Apparences.list = {
    {
        id = "clown", label = "Le Clown",
        head = { "Male_emotion_happy_002", "Clown_nose_001" },
        worn = { "Costume_10_001", "Shoe_Slippers_005" },
    },
    {
        id = "souris", label = "La Souris",
        head = { "Hat_049", "Male_emotion_usual_001" },
        worn = { "Costume_6_001", "Shoe_Slippers_002" },
    },
    {
        id = "chapeau", label = "Le Chapeau",
        head = { "Hat_010", "Male_emotion_usual_001", "Glasses_006" },
        worn = { "Outerwear_036", "Pants_010", "Shoe_Sneakers_009" },
    },
    {
        id = "etudiant", label = "L'Etudiant",
        head = { "Hairstyle_male_010", "Male_emotion_usual_001", "Glasses_004" },
        worn = { "T_Shirt_009", "Shorts_003", "Shoe_Sneakers_009" },
    },
    {
        id = "ronchon", label = "Le Ronchon",
        head = { "Hairstyle_male_012", "Male_emotion_angry_003", "Moustache_002" },
        worn = { "Outerwear_029", "Pants_014", "Shoe_Slippers_002" },
    },
    {
        id = "casque", label = "Le Casque",
        head = { "Hairstyle_male_010", "Male_emotion_happy_002", "Headphones_002" },
        worn = { "T_Shirt_009", "Pants_014", "Socks_008" },
    },
    {
        id = "nourrisson", label = "Le Nourrisson",
        head = { "Male_emotion_usual_001", "Pacifier_001" },
        worn = { "T_Shirt_009", "Shorts_003", "Socks_008" },
    },
    {
        id = "chauve", label = "Le Chauve",
        head = { "Male_emotion_angry_003", "Moustache_001" },
        worn = { "Outerwear_036", "Pants_010", "Shoe_Slippers_005", "Gloves_006" },
    },
    {
        id = "bavard", label = "Le Bavard",
        head = { "Hairstyle_male_012", "Male_emotion_happy_002", "Glasses_006" },
        worn = { "Outerwear_029", "Pants_010", "Shoe_Sneakers_009" },
    },
    {
        id = "gantier", label = "Le Gantier",
        head = { "Hairstyle_male_010", "Male_emotion_angry_003", "Glasses_004", "Moustache_002" },
        worn = { "T_Shirt_009", "Pants_010", "Gloves_014", "Shoe_Sneakers_009" },
    },
}

-- Index par identifiant, construit une fois au chargement.
Apparences.by_id = {}
for i, a in ipairs(Apparences.list) do
    a.rank = i
    Apparences.by_id[a.id] = a
end

-- Rend les references completes a passer au moteur, prefixees par le pack.
function Apparences.Resolve(id)
    local a = Apparences.by_id[id]
    if not a then return nil end

    local head, worn = {}, {}
    for _, nom in ipairs(a.head) do head[#head + 1] = ref(nom) end
    for _, nom in ipairs(a.worn) do worn[#worn + 1] = ref(nom) end

    return { id = a.id, label = a.label, body = Apparences.body, head = head, worn = worn }
end

-- Identifiant par defaut, utilise quand un joueur n'a jamais choisi.
Apparences.default_id = Apparences.list[1].id

return Apparences
