-- Catalogue de la boutique : ce qui s'achete avec l'argent du jeu.
--
-- Partage parce que le client en affiche les prix. Seule la copie du serveur
-- fait foi : un client qui modifie la sienne ne paie pas moins, il voit faux.
--
-- Deux rayons. Les personnages reprennent les identifiants de
-- Shared/appearances.lua, dans le meme ordre. Les armes n'ont pas encore
-- d'effet en jeu : aucun mode de tir n'existe, on n'achete et n'equipe pour
-- l'instant que le droit de la porter plus tard. Un prix de 0 veut dire
-- possede d'office, sans passer par la caisse.
--
-- Prix provisoires, a revoir quand les gains par mode seront fixes.

local Catalogue = {}

Catalogue.persos = {
    { id = "clown",      prix = 0 },
    { id = "souris",     prix = 0 },
    { id = "chapeau",    prix = 0 },
    { id = "etudiant",   prix = 0 },
    { id = "ronchon",    prix = 0 },
    { id = "casque",     prix = 0 },
    { id = "nourrisson", prix = 400 },
    { id = "chauve",     prix = 600 },
    { id = "bavard",     prix = 800 },
    { id = "gantier",    prix = 1200 },
}

-- L'arme de base, gratuite, sert dans tous les modes de tir (FFA et suite).
-- `rendu` nomme les images du vestiaire (Client/vestiaire/img/armes/).
-- `mesh` : le modele cuit dans le pack (scripts/unreal/import_armes.py), long
-- de 100 cm a l'import ; `taille` est sa longueur reelle en jeu, en cm.
Catalogue.armes = {
    { id = "revolver",  prix = 0,    rendu = "revolver", mesh = "my-asset-pack::SM_Arme_revolver", taille = 30 },
    { id = "canon",     prix = 500,  rendu = "old",      mesh = "my-asset-pack::SM_Arme_canon",    taille = 45 },
    { id = "duel",      prix = 900,  rendu = "lawgiver", mesh = "my-asset-pack::SM_Arme_duel",     taille = 45 },
    { id = "flammes",   prix = 1400, rendu = "stylized", mesh = "my-asset-pack::SM_Arme_flammes",  taille = 70 },
    -- Le 26/09, afficher ce modele faisait planter le jeu (textures 4096, verres
    -- transparents) : image 2D au vestiaire tant qu'il n'est pas reimporte allege.
    { id = "glace",     prix = 2000, rendu = "ice",      mesh = "my-asset-pack::SM_Arme_glace",    taille = 30, vitrine_3d = false },
    { id = "physique",  prix = 3000, rendu = "physics",  mesh = "my-asset-pack::SM_Arme_physique", taille = 70 },
}

-- A passer a true une fois les SM_Arme_* importes et le pack recuit : le
-- vestiaire pose alors l'arme en 3D au lieu de son image.
Catalogue.armes_3d = true

Catalogue.arme_de_base = "revolver"

-- Index : Catalogue.article("persos", "clown") -> { id, prix, rang }
local index = {}
for _, rayon in ipairs({ "persos", "armes" }) do
    index[rayon] = {}
    for rang, article in ipairs(Catalogue[rayon]) do
        article.rang = rang
        index[rayon][article.id] = article
    end
end

function Catalogue.article(rayon, id)
    return index[rayon] and index[rayon][id] or nil
end

-- Vrai si l'arme se montre en 3D au vestiaire.
function Catalogue.en_3d(id)
    local a = Catalogue.article("armes", id)
    return Catalogue.armes_3d == true and a ~= nil and a.mesh ~= nil and a.vitrine_3d ~= false
end

function Catalogue.gratuit(rayon, id)
    local a = Catalogue.article(rayon, id)
    return a ~= nil and a.prix == 0
end

return Catalogue
