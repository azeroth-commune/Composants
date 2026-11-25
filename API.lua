-- Composants, l'API publique (README.md) : un seul global, Composants, sur le modèle du socle. Seul ce qui est ici est
-- promis aux autres add-ons (Maîtrise, Handshake) ; l'intérieur peut changer.
local _, ns = ...

Composants = {
  -- Projets. p = le projet lui-même (une table : p.id son identité stable, p.name, p.lines, p.choix, p.tenu, p.phase : nil
  -- = Préparer, "reunir", "fabriquer" ou "fini", CONTEXT.md) ; on le lit, on ne le modifie que par ces fonctions. Changer ses
  -- lignes ou un choix de case (Tenir avec des lignes compris) le remet en Préparer. Une ligne : un objet { id = itemID,
  -- qty = quantité }, ou une fabrication { recette = sortID (la clé de la base des recettes), fois = nombre de fois }.
  NouveauProjet = function(t) return ns.nouveauProjet(t) end,          -- t = { name, lines } facultatif ; il devient le projet affiché
  Projet = function(id) return (ns.projet(id)) end,                    -- nil s'il n'existe plus
  Projets = function() return ns.db().projets end,                     -- dans l'ordre de la liste
  Renommer = function(p, nom) ns.projetRenommer(p, nom) end,
  Supprimer = function(id) -- renvoie le projet supprimé, ou nil
    local _, i = ns.projet(id)
    if not i then return nil end
    ns.db().courant = i
    local p = ns.supprimerProjet()
    ns.refreshCraftWindow(); ns.refreshNeeds() -- la petite vue aussi : elle montrait peut-être le projet supprimé
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
  -- stock déduit (ce que verrait un artisan) ; sinon les options du calcul (réglages). apports = { [id] = true } facultatif : ces
  -- cases sortent de l'arbre. Renvoie { roots, cases, caseDe, liens, blocs, blocDe, livraisons, total, incomplete, market }.
  Arbre = function(p, sansStock, apports) return ns.projetArbre(p, sansStock and { unlearned = true } or nil, apports) end,
  -- « Ce projet a changé » : fn(p, quoi), quoi = "nouveau", "lignes", "choix", "nom", "tenu", "phase" ou "supprime".
  QuandChange = function(fn) ns.quandChange(fn) end,
  -- La fenêtre : ouverte sur le projet id (ou celui affiché), dans la vue de sa phase ; redessinée (un autre add-on a changé
  -- ce qu'elle montre).
  Ouvrir = function(id)
    if id then ns.ouvrirProjet(id) end
    ns.openCraftWindow()
  end,
  Rafraichir = function() ns.refreshCraftWindow(); ns.refreshNeeds() end,
  -- L'emplacement du bloc (CONTEXT.md, Bloc) : un autre add-on dessine dans les blocs de l'arbre de la grande vue et dit
  -- lesquels il a pris en charge (confiés : réduits à une seule case). f = { confie = fn(p, bloc) → vrai si confié ;
  -- bloc = fn(zone, p, bloc, confie) dessine dans zone, un Frame posé par Composants (confié : la case du bloc ; sinon
  -- une bande haute de 16 sur sa ligne de titre, dont f règle la largeur) ; apports = fn(p) → { [itemID] = true } ou nil,
  -- les cases fournies par un autre, qui sortent de l'arbre }. bloc = un bloc de Composants.Arbre(p).blocs, ou nil = le
  -- projet entier (sa bande : la ligne d'en-tête de l'arbre). Jamais appelé pour le Brouillon. Un seul fournisseur ;
  -- rend celui d'avant (nil retire le fournisseur).
  -- L'emplacement des Besoins (CONTEXT.md, Besoins), le même fournisseur, champs facultatifs : besoins = fn(zone, p) →
  -- hauteur, dessine ses lignes dans zone (un Frame large d'une ligne des Besoins, sous elles) et rend la hauteur prise
  -- (0 ou nil : rien) ; clos = fn(p) → vrai quand tout ce qu'il a pris en charge pour p est arrivé (Réunir → Fabriquer et
  -- Fabriquer → Fini l'attendent ; sans clos : vrai) ; aDonner = fn(p) → { [itemID] = true } ou nil, les cases que le
  -- joueur donne lui-même à un bloc confié : elles restent des lignes de ses Besoins. Un bloc confié sort des Besoins (ses
  -- cases et ce qui n'est fabriqué que pour lui), sauf ce qu'on lui donne.
  -- Les phases (CONTEXT.md, Phase), champs facultatifs : lancer = fn(p) → une raison (chaîne) qui refuse Lancer, ou nil ;
  -- refusé, le bouton dit « Lancer (<raison>) », grisé, et le fil ne quitte pas Préparer non plus. fini = fn(p) → true,
  -- false ou nil : nil garde la règle de Composants (plus rien à fabriquer, et clos) ; true ou false, le fournisseur décide
  -- seul, sans l'arbre (true : un projet lancé, en Réunir ou en Fabriquer, passe en Fini).
  -- ponytail: un seul fournisseur (Handshake) ; une liste le jour où un deuxième add-on veut dessiner dans les blocs.
  Emplacements = function(f)
    local avant = ns.fournisseur
    ns.fournisseur = f
    ns.refreshCraftWindow(); ns.refreshNeeds()
    return avant
  end,
}
