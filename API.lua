-- Composants, l'API publique (README.md) : un seul global, Composants, sur le modèle du socle. Seul ce qui est ici est
-- promis aux autres add-ons (Handshake s'en sert pour ses commandes et sa Réponse) ; l'intérieur peut changer.
local _, ns = ...

Composants = {
  -- Projets. p = le projet lui-même (une table : p.id son identité stable, p.name, p.lines, p.choix, p.tenu) ; on le lit,
  -- on ne le modifie que par ces fonctions. Une ligne : un objet { id = itemID, qty = quantité }, ou une fabrication
  -- { recette = sortID (la clé de la base des recettes), fois = nombre de fois }.
  NouveauProjet = function(t) return ns.nouveauProjet(t) end,          -- t = { name, lines } facultatif ; il devient le projet affiché
  Projet = function(id) return (ns.projet(id)) end,                    -- nil s'il n'existe plus
  Projets = function() return ns.db().projets end,                     -- dans l'ordre de la liste
  Renommer = function(p, nom) ns.projetRenommer(p, nom) end,
  Supprimer = function(id) -- renvoie le projet supprimé, ou nil
    local _, i = ns.projet(id)
    if not i then return nil end
    ns.db().courant = i
    local p = ns.supprimerProjet()
    ns.refreshCraftWindow()
    return p
  end,
  -- Lignes et choix de case : true, ou false et la raison (un projet tenu refuse ses lignes avec la raison de celui qui le
  -- tient, telle quelle). choix = "fabriquer", "acheter" ou nil (le calcul des prix décide).
  Ajouter = function(p, id, qty) return ns.projetAjouter(p, id, qty) end,
  Quantite = function(p, i, qty) return ns.projetQuantite(p, i, qty) end,
  Retirer = function(p, i) return ns.projetRetirer(p, i) end,
  Choix = function(p, id, choix) return ns.projetChoix(p, id, choix) end,
  Peut = function(p, quoi) return ns.projetPeut(p, quoi) end,          -- quoi = "lignes" ou "choix"
  -- Projet tenu : Tenir(p, raison, lignes) prend les lignes (les nouvelles, ou nil pour garder celles qu'il a) ; appelé de
  -- nouveau, remet les lignes à jour, les choix de case restent ; Tenir(p, nil) le lâche. Une ligne fabrication
  -- { recette, fois } (CONTEXT.md) : sa case racine est toujours fabriquée avec cette recette (ni stock, ni achat ;
  -- Choix(p, son objet, "acheter") refuse) ; sans objet produit (un enchantement), seuls ses composants sont des cases.
  -- Dessous, les choix de case restent libres.
  Tenir = function(p, raison, lignes) ns.projetTenir(p, raison, lignes) end,
  -- L'arbre et les blocs : p = un projet, ou toute table { lines, choix }. sansStock = true : toutes les recettes, aucun
  -- stock déduit (ce que verrait un artisan) ; sinon les options de la fenêtre. apports = { [id] = true } facultatif : ces
  -- cases sortent de l'arbre. Renvoie { roots, cases, caseDe, liens, blocs, blocDe, livraisons, total, incomplete, market }.
  Arbre = function(p, sansStock, apports) return ns.projetArbre(p, sansStock and { unlearned = true } or nil, apports) end,
  -- « Ce projet a changé » : fn(p, quoi), quoi = "nouveau", "lignes", "choix", "nom", "tenu" ou "supprime".
  QuandChange = function(fn) ns.quandChange(fn) end,
  -- La fenêtre : ouverte sur le projet id (ou celui affiché) ; redessinée (un autre add-on a changé ce qu'elle montre).
  Ouvrir = function(id)
    if id then ns.ouvrirProjet(id) end
    ns.openCraftWindow()
  end,
  Rafraichir = function() ns.refreshCraftWindow() end,
}
