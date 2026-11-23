-- Composants, la base : les données dont le calcul a besoin, toutes lues par le socle Azeroth Commune (requis, lib:Lire) :
-- recettes connues, base des recettes (avec sa réserve), inventaires, métiers, marchands, objets et cours de l'HV (son scan,
-- ou un fournisseur : Auctionator…). Aucune donnée relevée n'est sauvegardée ici (ADR 0002 de l'atelier).
-- ComposantsDB ne garde que les données propres de Composants : projets, réglages (options de calcul, angle du bouton).
local _, ns = ...

local lib = AzerothCommune
-- Ce que Composants lit : le socle ne relève que les types auxquels un add-on a souscrit.
for _, t in ipairs({ "recettes connues", "base des recettes", "inventaires", "métiers et compétences", "marchands", "objets",
  "cours de l'HV" }) do lib:Souscrire(t) end

-- Recettes connues de tous les persos relevés : { [GUID] = { [métier] = { rank, max, known = { [clé] = difficulté } } } }
function ns.knownRecipes()
  local d = lib:Lire("recettes connues", "tous")
  return d and d.persos or {}
end
-- Un type par perso, tous les persos relevés : { [GUID] = … }.
local function parPerso(t) local d = lib:Lire(t, "tous") return d and d.persos or {} end

-- Recettes : la base des recettes du socle (celles vues dans les fenêtres de métier, puis sa réserve extraite du client
-- pour les objets qu'aucune recette vue ne fabrique). Chaque recette porte sa compétence requise (level) quand la réserve
-- la connaît.
local nomsDemandes = {} -- recettes dont on a déjà demandé les noms d'objets
function ns.recipes()
  local recettes = lib:Lire("base des recettes") or {}
  if not lib:Lire("objets") then -- catalogue des objets pas encore relevé : personne d'autre ne demande ces noms au serveur
    for k, r in pairs(recettes) do
      if not nomsDemandes[k] and not r.provenance then -- les recettes vues seulement, pas la réserve
        nomsDemandes[k] = true
        if r.output then ns.rememberItem(r.output) end
        for _, rg in ipairs(r.reagents or {}) do ns.rememberItem(rg.id) end
      end
    end
  end
  return recettes
end
-- { [GUID] = { bags, bank, … } } ; { [GUID] = { professions, skills } }
function ns.inventaires() return parPerso("inventaires") end
function ns.metiers() return parPerso("métiers et compétences") end
-- Mes sacs, lus à l'instant (la fenêtre se recalcule à chaque changement de sac).
function ns.mesSacs() return lib.Conteneurs(lib.EstSac) end

-- Noms d'objets : le catalogue des objets du socle, sinon ceux arrivés du serveur cette session, en mémoire seulement.
local nomsDeSession = {}
function ns.items() return lib:Lire("objets") or nomsDeSession end

-- Cours de l'HV (scan du socle, sinon un fournisseur) : { items = { [id] = { min, qty, tiers, … } }, scanned (date du scan
-- du socle), source (le fournisseur) }, ou nil et la raison du socle.
function ns.market()
  local d, lot = lib:Lire("cours de l'HV")
  if not d then return nil, lot end
  local h = d.hv and d.hv[lib.MaisonHV()]
  -- ponytail: une ligne lue au plus une fois par calcul (un calcul = un ns.market())
  local items = setmetatable({}, { __index = function(t, id)
    local l = d.objet(id) or false
    rawset(t, id, l)
    return l
  end })
  return { items = items, scanned = h and h.scanned, source = lot and lot.fournisseur }
end
-- L'état des prix de l'HV, pour la barre d'état : d'où ils viennent, ou comment les avoir.
function ns.texteHV(m)
  if not m then m = ns.market() end
  if m and m.scanned then return "HV du " .. m.scanned end
  if m then return "prix de l'HV : " .. (m.source or "?") end
  return "HV jamais scanné : ouvre l'hôtel des ventes"
end

-- Un perso du joueur est rangé sous son GUID ; son nom « Prénom Nom » (« ? » si le socle ne le connaît pas) ; son prénom,
-- pour un affichage court.
function ns.nomPerso(guid)
  local p = lib.Personnage(guid)
  return p and p.nom or "?"
end
function ns.prenom(guid) return (ns.nomPerso(guid):match("^%S+")) end

-- Montants, noms d'objets, fenêtres : ceux du socle. Un nom d'objet arrivé du serveur est retenu en mémoire
-- (nomsDeSession), jamais sauvegardé.
ns.money, ns.moneyShort, ns.moneySigned, ns.newWindow = lib.Argent, lib.ArgentCourt, lib.ArgentSigne, lib.Fenetre
function ns.rememberItem(id) return lib.RetenirObjet(id, nomsDeSession) end
function ns.itemLabel(id) return lib.NomObjet(id, ns.items(), nomsDeSession) end
function ns.findItem(text) return lib.TrouverObjet(text, ns.items(), ns.recipes()) end
-- Suggestions de la barre de recherche : la recherche d'objets du socle (Composants souscrit aux deux types qu'elle lit).
ns.chercherObjets = lib.ChercherObjets

-- ComposantsDB : { projets, projetSeq, courant, brouillon (Projet.lua), besoins et recolte (Besoins.lua), options (de calcul),
--   minimap_angle (le socle) }.
local OPTIONS = { bags = true, bank = true, alts = false, unlearned = false }
function ns.db()
  ComposantsDB = ComposantsDB or {}
  ComposantsDB.projets = ComposantsDB.projets or {}
  if not ComposantsDB.options then
    ComposantsDB.options = {}
    for k, v in pairs(OPTIONS) do ComposantsDB.options[k] = v end
  end
  return ComposantsDB
end
