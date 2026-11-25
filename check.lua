-- Vérification hors jeu (non chargée par la TOC) : luajit Composants/check.lua, depuis le dossier des add-ons.
-- Juste assez de l'API WoW pour le calcul. Le socle Azeroth Commune est chargé avant, comme dans le jeu : ses
-- SavedVariables (AzerothCommuneDB, AzerothCommuneItems, AzerothCommuneMarket) servent de données, lues par ses vrais
-- accesseurs. Rien de relevé n'est écrit dans ComposantsDB (ADR 0002 de l'atelier). Handshake n'est pas chargé : Composants
-- sert seul (ses tests avec Composants sont dans Handshake/check.lua).
local noop = function() end
local stubMT = { __index = function() return noop end }
CreateFrame = function() return setmetatable({}, stubMT) end
SlashCmdList, StaticPopupDialogs, UISpecialFrames = {}, {}, {}
C_Timer = { After = noop, NewTicker = noop }
C_Item = { GetItemInfo = noop, GetItemIconByID = noop }
date, time = os.date, os.time
GetTime = function() return 0 end
UnitFactionGroup = function() return "Alliance" end
geterrorhandler = function() return function(e) error(e, 0) end end
-- Un perso est rangé sous son GUID ; son numéro de serveur est le royaume du socle.
UnitGUID = function(u) if u == "player" then return "Player-6942-0000000E" end end
AzerothCommuneDB, AzerothCommuneItems, AzerothCommuneMarket = { recipes = {}, chars = {}, lots = {} }, { items = {} }, {}
ComposantsDB = nil
-- Rien de relevé dans les SavedVariables de Composants : seulement ses données propres.
local RELEVES = { "recipes", "chars", "items", "market" }
local function aucunReleve(quand)
  for _, k in ipairs(RELEVES) do assert((ComposantsDB or {})[k] == nil, quand .. " : relevé « " .. k .. " » écrit dans ComposantsDB") end
end
-- Le socle (dépôt voisin, chargé avant Composants comme dans le jeu), fichiers dans l'ordre de sa TOC avec son espace de
-- noms privé. ponytail: ses fichiers générés (VendorData, RecettesReserve, CatalogueObjets, hors du repo) sont sautés : les
-- marchands et la réserve des recettes sont ceux du test (acns.recettesReserve).
local acns = {}
for f in io.open("AzerothCommune/AzerothCommune.toc"):read("*a"):gmatch("([%w_]+)%.lua") do
  if f ~= "VendorData" and f ~= "RecettesReserve" and f ~= "CatalogueObjets" then assert(loadfile("AzerothCommune/" .. f .. ".lua"))("AzerothCommune", acns) end
end
local ns = {}
local TOC = io.open("Composants/Composants.toc"):read("*a")
for f in TOC:gmatch("([%w_]+)%.lua") do assert(loadfile("Composants/" .. f .. ".lua"))("Composants", ns) end
assert(Handshake == nil and Composants, "Composants chargé seul, son global posé")
local commune = AzerothCommune
assert(ns.newWindow == commune.Fenetre and ns.money == commune.Argent, "fenêtres et montants : ceux du socle")

-- Acheter ou fabriquer : 20 barres de fer, barre à l'HV plus chère que son minerai fondu.

local market = {
  [3575] = { min = 300, qty = 50, tiers = { { price = 300, qty = 10 }, { price = 310, qty = 40 } } }, -- barre
  [2772] = { min = 270, qty = 15, tiers = { { price = 270, qty = 15 } } },                            -- minerai : 15 seulement
}
assert(commune:PrixAchat(3575, 20, market) == 10 * 300 + 10 * 310, "achat palier par palier")
local ore, how, partial = commune:PrixAchat(2772, 20, market)
assert(ore == 20 * 270 and how == "HV" and partial, "pas assez en vente : le reste au dernier prix, signalé")
AzerothCommuneDB.vendors = { [1] = { items = { { id = 2880, price = 90, stack = 1 } } } }
assert(select(2, commune:PrixAchat(2880, 2, market)) == "marchand")
local by = { [3575] = { { key = 3307, known = true, r = { name = "Fonte du fer", made_min = 1, reagents = { { id = 2772, qty = 1 } } } } } }
local p = ns.plan(3575, 20, { market = market, by = by }, 0, {})
assert(p.how == "fabriquer" and p.cost == 5400 and p.buy == 6100 and p.parts[1].qty == 20, "fondre est moins cher")
local list = ns.shopping(p, {})
assert(list[2772].qty == 20 and not list[3575], "liste de courses : le minerai, pas la barre")
market[2772].tiers[1].price = 400 -- minerai devenu cher : on achète la barre
assert(ns.plan(3575, 20, { market = market, by = by }, 0, {}).how == "HV")
-- Recette que personne n'a apprise : pas prise par le calcul, mais le « + » existe et la force.
local byU = { [3575] = { { key = 3307, known = false, r = by[3575][1].r } } }
local pu = ns.plan(3575, 20, { market = market, by = byU }, 0, {})
assert(pu.how == "HV" and pu.craftable, "recette pas apprise : achetée, mais « + » possible")
pu = ns.plan(3575, 20, { market = market, by = byU, force = { [3575] = "fabriquer" } }, 0, {})
assert(pu.how == "fabriquer" and pu.known == false, "« + » : décomposé avec la recette pas apprise")
-- Déjà en stock : « + » possible, et forcé il fabrique au lieu de prendre le stock.
local ps = ns.plan(3575, 1, { market = market, by = by, stock = { [3575] = { 1, 0, 0 } } }, 0, {})
assert(ps.how == "stock" and ps.craftable, "en stock : « + » possible")
ps = ns.plan(3575, 1, { market = market, by = by, stock = { [3575] = { 1, 0, 0 } }, force = { [3575] = "fabriquer" } }, 0, {})
assert(ps.how == "fabriquer" and ps.have[1] == 0 and ps.parts[1].id == 2772, "forcé : fabriqué, stock non pris")
print("Composants : acheter ou fabriquer OK")

-- Stock partagé entre deux lignes (seam interne ns.plan).
market[2772].tiers[1].price = 270
local stock = { [2772] = { 15, 5, 0 }, [3575] = { 4, 0, 0 } } -- 20 minerais (15 sacs + 5 banque), 4 barres en sac
local ctx = { market = market, by = by, stock = stock }
local a = ns.plan(3575, 10, ctx, 0, {})  -- 1re ligne : 4 barres en stock, 6 à fondre avec 6 minerais du sac
assert(a.have[1] == 4 and a.need == 6 and a.how == "fabriquer" and a.cost == 0, "barres du sac puis minerai du sac : gratuit")
local b = ns.plan(3575, 20, ctx, 0, {})  -- 2e ligne : plus de barres ; 14 minerais restants (9 sac + 5 banque), 6 à acheter
assert(b.have[1] == 0 and b.parts[1].have[1] == 9 and b.parts[1].have[2] == 5 and b.parts[1].need == 6, "stock partagé")
assert(b.cost == 6 * 270)

-- Les cases d'un projet (Projet.lua) : une par objet, le même stock pour toutes ses lignes. Les données sont celles que
-- Composants lit (par le socle) : HV, recettes, persos ; mes sacs et ma banque.
UnitName = function() return "Moi", "Dupont" end
local MOI = UnitGUID("player")
local TOUT = { unlearned = true } -- options de calcul : toutes les recettes, aucun stock
local function donnees(d) -- d.sacs / d.banque = { [id] = nombre }, d.persos = fiches des autres persos dans la base du socle
  local function sac(t)
    local items = {}
    for id, n in pairs(t or {}) do items[#items + 1] = { id = id, count = n } end
    return { b = { items = items } }
  end
  AzerothCommuneMarket = { ["6942-Alliance"] = { scanned = "test", items = d.hv } }
  AzerothCommuneDB.recipes = d.recettes
  AzerothCommuneDB.chars = d.persos or {}
  AzerothCommuneDB.chars[MOI] = { bank = sac(d.banque) }
  commune.Conteneurs = function(garder) return garder("Backpack") and sac(d.sacs) or {} end -- mes sacs, lus à l'instant
end
local realContainers = commune.Conteneurs
donnees({ hv = market, recettes = { [3307] = { name = "Fonte du fer", output = 3575, reagents = { { id = 2772, qty = 1 } } } },
  sacs = { [2772] = 15, [3575] = 4 }, banque = { [2772] = 5 } })
local fer = ns.nouveauProjet({ lines = { { id = 3575, qty = 10 }, { id = 3575, qty = 20 } } })
local arbre = ns.projetArbre(fer, { bags = true, bank = true, unlearned = true })
local t1, ore = arbre.caseDe.T1, arbre.caseDe.I2772
assert(t1.have[1] == 4 and t1.made == 6 and arbre.caseDe.T2.made == 20, "barres : 4 du sac, le reste à fondre")
assert(ore.qty == 26 and ore.need == 6 and ore.have[1] == 15 and ore.have[2] == 5 and #ore.parents == 2, "minerai : une case pour les deux lignes")
-- Une case retirée de l'arbre (Handshake : l'apport d'une commande) : la case entière, le projet n'en garde rien.
arbre = ns.projetArbre(fer, { bags = true, bank = true, unlearned = true }, { [2772] = true })
assert(arbre.caseDe.I2772.apport == 26 and arbre.caseDe.I2772.need == 0 and not fer.apports, "minerai apporté : la case entière")
print("Composants : cases d'un projet, stock partagé OK")

-- Valeur à l'HV (CONTEXT.md) : les objets du projet au prix le plus bas de l'HV × leur quantité ; ce que ça rapporte = la
-- valeur, moins la part de l'HV (5 %) et le dépôt 24 h (taux du socle × revente au marchand, compté comme perdu), moins le coût.
local getItemInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id) if id == 3575 then return "Barre de fer", nil, nil, nil, nil, nil, nil, nil, nil, nil, 100 end end
AzerothCommuneDB.deposit = { rate24 = 0.2 }
arbre = ns.projetArbre(fer, TOUT) -- 30 barres fondues : 30 minerais à 270 = 8 100
assert(arbre.total == 8100 and not arbre.incomplete, "coût des 30 barres")
assert(arbre.valeur == 30 * 300, "valeur : 30 barres au prix le plus bas de l'HV")
-- 9 000 − 5 % = 8 550 ; dépôt 100 × 0,2 × 10 = 200 et × 20 = 400 ; 8 550 − 600 − 8 100 = −150
assert(arbre.rapporte == -150, "rapporte : " .. tostring(arbre.rapporte))
-- Coût incomplet (un composant sans prix ni recette) : la valeur seule, rien de rapporté.
donnees({ hv = { [3575] = market[3575] }, recettes = { [3307] = { name = "Fonte du fer", output = 3575, reagents = { { id = 2772, qty = 1 } } } } })
local inc = ns.nouveauProjet({ lines = { { id = 3575, qty = 1 } } })
ns.projetChoix(inc, 3575, "fabriquer") -- décomposée : le minerai n'a ni prix ni recette
inc = ns.projetArbre(inc, TOUT)
assert(inc.incomplete and inc.valeur == 300 and inc.rapporte == nil, "coût incomplet : valeur seule")
-- Un objet du projet sans prix à l'HV : ni valeur, ni rapporté (rien de faux).
local sans = ns.projetArbre(ns.nouveauProjet({ lines = { { id = 3575, qty = 1 }, { id = 2772, qty = 1 } } }), TOUT)
assert(sans.valeur == nil and sans.rapporte == nil, "un objet sans prix : rien")
C_Item.GetItemInfo, AzerothCommuneDB.deposit = getItemInfo, nil
donnees({ hv = market, recettes = { [3307] = { name = "Fonte du fer", output = 3575, reagents = { { id = 2772, qty = 1 } } } },
  sacs = { [2772] = 15, [3575] = 4 }, banque = { [2772] = 5 } })
print("Composants : valeur à l'HV et ce que ça rapporte OK")

-- Les Besoins (CONTEXT.md) : ceux d'un seul projet, qui compte le stock comme s'il était seul (rien de partagé entre
-- projets). Réuni = tout dans les sacs : la banque et les autres persos disent où le trouver, ils ne comptent pas.
do
  donnees({ hv = market, recettes = {}, sacs = { [3575] = 12 } })
  local OPT = { bags = true, bank = true }
  local function besoin(res, id) -- la ligne des Besoins de cet objet
    for _, r in ipairs((ns.orderNeeds(res))) do if r.id == id then return r end end
  end
  local pa = ns.nouveauProjet({ name = "A", lines = { { id = 3575, qty = 10 } } })
  local pb = ns.nouveauProjet({ name = "B", lines = { { id = 3575, qty = 10 } } })
  for _, p in ipairs({ pa, pb }) do
    local r = besoin(ns.besoinsArbre(p, OPT), 3575)
    assert(r.required == 10 and r.have[1] == 10 and r.need == 0, "les Besoins de " .. p.name .. " : tout le stock pour lui")
    assert(ns.toutReuni(p, OPT), p.name .. " : réuni")
  end
  -- À la banque seulement : rien à acheter (on sait où le trouver), mais pas réuni.
  donnees({ hv = market, recettes = {}, banque = { [3575] = 10 } })
  local r = besoin(ns.besoinsArbre(pa, OPT), 3575)
  assert(r.need == 0 and r.have[1] == 0 and r.have[2] == 10, "à la banque : où le trouver")
  assert(not ns.toutReuni(pa, OPT), "à la banque : pas réuni")
  -- « Déduire mes sacs » décoché : pour réunir, les sacs comptent quand même.
  donnees({ hv = market, recettes = {}, sacs = { [3575] = 10 } })
  assert(ns.toutReuni(pa, { bags = false }), "les sacs comptent toujours pour réunir")
  assert(not ns.toutReuni(ns.nouveauProjet({ name = "vide" }), OPT), "un projet vide n'est pas réuni")
  -- Une recette à apprendre : pas réuni (il faut l'avoir pour fabriquer, comme les composants).
  local orderNeeds = ns.orderNeeds
  ns.orderNeeds = function(res) return (orderNeeds(res)), { { name = "Fonte du fer", product = 3575 } } end
  assert(not ns.toutReuni(pa, OPT), "une recette à apprendre : pas réuni")
  ns.orderNeeds = orderNeeds
  -- Les anciennes SavedVariables : la liste ordonnée des Besoins est purgée.
  ComposantsDB.besoins = { pa.id, pb.id }
  assert(ns.db().besoins == nil, "la liste des Besoins d'avant : purgée")
end
print("Composants : Besoins d'un projet seul, réuni = dans les sacs OK")

-- La Récolte (CONTEXT.md, #18) et la liste d'achats d'Auctionator « Besoins (Composants) » : les lignes qui manquent
-- encore, sauf la Récolte et ce qu'un marchand vend ; repasser sur « Achat » ne demande que ce qui manque encore.
do
  donnees({ hv = market, recettes = {}, sacs = { [3575] = 3 } })
  AzerothCommuneDB.vendors = {}
  local p = ns.nouveauProjet({ name = "Récolte", lines = { { id = 3575, qty = 10 } } })
  ns.ouvrirProjet(p.id) -- la liste d'Auctionator suit les Besoins du projet affiché
  local function achats() return ns.achatsHV((ns.orderNeeds(ns.besoinsArbre(p)))) end
  local a = achats()
  assert(#a == 1 and a[1].id == 3575 and a[1].qty == 7, "sans choix : à acheter, ce qui manque (10 − 3)")
  assert(not ns.estRecolte(3575))
  ns.basculerRecolte(3575)
  assert(ns.estRecolte(3575) and ComposantsDB.recolte[3575] == true and #achats() == 0, "Récolte : hors de la liste")
  donnees({ hv = market, recettes = {}, sacs = { [3575] = 6 } }) -- on en a récolté 3, on en a marre
  ns.basculerRecolte(3575)
  a = achats()
  assert(not ns.estRecolte(3575) and ComposantsDB.recolte[3575] == nil, "retour à l'achat : plus rien de noté")
  assert(#a == 1 and a[1].qty == 4, "de nouveau à acheter : seulement ce qui manque encore (10 − 6)")
  -- Ce qu'un marchand vend n'est pas dans la liste de l'HV ; une ligne complète non plus.
  assert(#ns.achatsHV({ { id = 1, need = 2, how = "marchand" }, { id = 2, need = 0, how = "HV" }, { id = 3, need = 5 } }) == 1)

  -- Auctionator : la liste est remplacée à l'ouverture de l'HV, recherche exacte par le nom, quantité qui manque.
  assert(ns.pousserAuctionator() == nil, "sans Auctionator : rien")
  AzerothCommuneItems.items[3575] = { name = "Barre de fer" }
  local listes = {}
  Auctionator = { API = { v1 = {
    ConvertToSearchString = function(caller, t)
      assert(caller == "Composants" and t.isExact)
      return ('"%s";;0;0;0;0;0;0;0;0;;;;%d'):format(t.searchString, t.quantity)
    end,
    CreateShoppingList = function(caller, nom, termes) assert(caller == "Composants"); listes[nom] = termes end,
    GetShoppingListItems = function(_, nom) return assert(listes[nom], "pas de liste") end,
  } } }
  assert(ns.pousserAuctionator() == 1)
  local l = listes["Besoins (Composants)"]
  assert(#l == 1 and l[1] == '"Barre de fer";;0;0;0;0;0;0;0;0;;;;4', l[1])
  ns.basculerRecolte(3575) -- tout en Récolte : la liste existante est vidée
  assert(ns.pousserAuctionator() == 0 and #listes["Besoins (Composants)"] == 0, "liste vidée")
  listes = {}
  assert(ns.pousserAuctionator() == 0 and listes["Besoins (Composants)"] == nil, "pas de liste vide créée")
  -- En direct, HV ouvert : une modification faite dans Composants réécrit la liste, seulement si elle change.
  local ecritures, creer = 0, Auctionator.API.v1.CreateShoppingList
  Auctionator.API.v1.CreateShoppingList = function(...) ecritures = ecritures + 1; return creer(...) end
  ns.basculerRecolte(3575)
  assert(ecritures == 0, "HV fermé : rien d'écrit")
  AuctionHouseFrame = { IsShown = function() return true end }
  ns.basculerRecolte(3575) -- en Récolte : rien à acheter, pas de liste existante
  assert(ecritures == 0)
  ns.basculerRecolte(3575)
  assert(ecritures == 1 and listes["Besoins (Composants)"][1]:find(";4$"), "bascule HV ouvert : liste réécrite")
  ns.projetQuantite(p, 1, 12) -- « ce projet a changé » : 12 − 6
  assert(ecritures == 2 and listes["Besoins (Composants)"][1]:find(";6$"), listes["Besoins (Composants)"][1])
  ns.besoinsChanges() -- rien n'a changé : même liste
  assert(ecritures == 2, "même liste : pas réécrite")
  -- Un autre projet affiché : ses Besoins à lui ; le Brouillon n'entre dans aucuns Besoins.
  local autre = ns.nouveauProjet({ name = "Autre", lines = { { id = 3575, qty = 8 } } })
  ns.besoinsChanges()
  assert(ecritures == 3 and listes["Besoins (Composants)"][1]:find(";2$"), "l'autre projet : 8 − 6")
  autre.phase = "fini" -- un projet Fini ne fait plus rien acheter
  ns.besoinsChanges()
  assert(ecritures == 4 and #listes["Besoins (Composants)"] == 0, "un projet Fini : liste vide")
  ns.ouvrirBrouillon()
  ns.besoinsChanges()
  assert(ecritures == 4 and #listes["Besoins (Composants)"] == 0, "le Brouillon : liste vide")
  ns.ouvrirProjet(autre.id); ns.supprimerProjet()
  AuctionHouseFrame = nil
  Auctionator, AzerothCommuneItems.items[3575], ComposantsDB.recolte = nil, nil, nil
end
print("Composants : Récolte et liste d'achats d'Auctionator OK")

-- Les phases (CONTEXT.md) : Préparer → Lancer → Réunir → (tout dans les sacs) Fabriquer → (plus rien à fabriquer) Fini ;
-- jamais de retour en arrière tout seul, Fini gardé. Le fil va à n'importe quelle phase. Tout changement de lignes ou de
-- choix de case (Tenir compris) remet en Préparer. Lancer le Brouillon en fait un projet en Réunir, le Brouillon se vide.
do
  local fonte = { [3307] = { name = "Fonte du fer", output = 3575, profession = "Minage", reagents = { { id = 2772, qty = 1 } } } }
  local function poser(d)
    d.hv, d.recettes = market, fonte
    donnees(d)
    AzerothCommuneDB.chars[MOI].recipes = { Minage = { rank = 75, known = { [3307] = true } } }
  end
  local vus = {}
  Composants.QuandChange(function(q, quoi) if quoi == "phase" then vus[#vus + 1] = ns.phase(q) end end)
  poser({ banque = { [2772] = 5 } })
  local p = Composants.NouveauProjet({ name = "Phases", lines = { { id = 3575, qty = 5 } } })
  assert(ns.phase(p) == "preparer" and p.phase == nil, "un projet naît en Préparer")
  assert(ns.lancer(p) == p and ns.phase(p) == "reunir", "Lancer : Réunir")
  ns.avancerPhase(p)
  assert(ns.phase(p) == "reunir", "le minerai à la banque : toujours Réunir")
  poser({ sacs = { [2772] = 5 } })
  assert(ns.avancerPhase(p) and ns.phase(p) == "fabriquer", "le minerai dans les sacs : Fabriquer tout seul")
  poser({ banque = { [2772] = 5 } })
  assert(not ns.avancerPhase(p) and ns.phase(p) == "fabriquer", "rangé à la banque : pas de retour en Réunir")
  poser({ sacs = { [3575] = 5 } })
  assert(ns.avancerPhase(p) and ns.phase(p) == "fini", "les barres fondues : Fini")
  poser({})
  ns.avancerPhase(p)
  assert(ns.phase(p) == "fini", "les barres vendues : Fini gardé")
  assert(table.concat(vus, ",") == "reunir,fabriquer,fini", "le signal « phase » : " .. table.concat(vus, ","))
  -- Le fil : n'importe quelle phase, dans tous les sens.
  for _, ph in ipairs({ "preparer", "fabriquer", "reunir", "preparer" }) do
    assert(ns.allerPhase(p, ph) == p and ns.phase(p) == ph, "le fil : " .. ph)
  end
  -- Tout changement de lignes ou de choix de case remet en Préparer ; un nom changé, non.
  local function lance() ns.lancer(p); assert(ns.phase(p) == "reunir") end
  lance(); Composants.Choix(p, 2772, "acheter"); assert(ns.phase(p) == "preparer", "un choix de case : Préparer")
  lance(); Composants.Quantite(p, 1, 6); assert(ns.phase(p) == "preparer", "une quantité : Préparer")
  lance(); Composants.Ajouter(p, 2772, 1); assert(ns.phase(p) == "preparer", "une ligne ajoutée : Préparer")
  lance(); Composants.Retirer(p, 2); assert(ns.phase(p) == "preparer", "une ligne retirée : Préparer")
  lance(); Composants.Renommer(p, "Phases bis"); assert(ns.phase(p) == "reunir", "renommé : la phase reste")
  ns.allerPhase(p, "fabriquer")
  Composants.Tenir(p, "tenu par le test", { { id = 3575, qty = 7 } })
  assert(ns.phase(p) == "preparer", "Tenir avec des lignes (une tranche recalculée) : Préparer")
  lance(); Composants.Tenir(p, nil); assert(ns.phase(p) == "reunir", "lâché sans changer ses lignes : la phase reste")
  Composants.Supprimer(p.id)
  -- Le Brouillon lancé : un vrai projet en Réunir, nommé d'après sa première ligne ; un Brouillon vide le remplace.
  AzerothCommuneItems.items[3575] = { name = "Barre de fer" }
  local b = ns.brouillon()
  ns.viderBrouillon()
  assert(ns.lancer(b) == nil, "Brouillon vide : rien à lancer")
  ns.projetAjouter(b, 3575, 3); ns.projetAjouter(b, 2772, 2)
  ns.ouvrirBrouillon()
  local q = ns.lancer(b)
  assert(q and not ns.estBrouillon(q) and q.name == "Barre de fer" and ns.phase(q) == "reunir", "un vrai projet, en Réunir, nommé d'après sa 1re ligne")
  assert(#q.lines == 2 and #b.lines == 0 and ns.phase(b) == "preparer" and ns.projetCourant() == q, "le Brouillon vidé, le projet affiché")
  assert(ns.allerPhase(b, "reunir") == nil, "le fil sur un Brouillon vide : rien")
  Composants.Supprimer(q.id)
  AzerothCommuneItems.items[3575] = nil
  commune.Conteneurs, AzerothCommuneDB.chars = realContainers, {}
end
print("Composants : phases, Lancer, le fil, Réunir → Fabriquer tout seul, Fini gardé OK")

-- Recettes équivalentes (#46) : vrai-argent par le minage (10098) ou par la transmutation (11480), sans prix. Le choix ne
-- dépend pas de l'ordre de la base des recettes : personne ne les connaît → le plus petit identifiant ; un perso connaît la
-- transmutation → elle.
local function vraiArgent(ordre, persos)
  local r = { [10098] = { name = "Fonte du vrai-argent", output = 6037, profession = "Minage", reagents = { { id = 7911, qty = 1 } } },
    [11480] = { name = "Transmutation de mithril en vrai-argent", output = 6037, profession = "Alchimie", reagents = { { id = 3860, qty = 1 } } } }
  local recettes = {}
  for _, k in ipairs(ordre) do recettes[k] = r[k] end
  donnees({ hv = {}, recettes = recettes, persos = persos })
  return ns.projetArbre(ns.nouveauProjet({ lines = { { id = 6037, qty = 2 } } }), TOUT).caseDe.T1.recipeKey
end
for _, ordre in ipairs({ { 10098, 11480 }, { 11480, 10098 } }) do
  assert(vraiArgent(ordre) == 10098, "personne ne connaît : le plus petit identifiant")
  assert(vraiArgent(ordre, { ["Player-6942-00000A1C"] = { nom = "Al Dupont", recipes = { Alchimie = { rank = 225, known = { [11480] = "easy" } } } } }) == 11480,
    "la recette connue d'un perso d'abord")
end
-- Boucles de transmutation : Terre ↔ Vie, Eau ↔ Non-mort, et le tour Air → Feu → Terre → Eau → Air. Chaque recette
-- fabrique son essence à partir d'une essence qu'elle sert elle-même à fabriquer : toutes écartées, les essences
-- s'achètent. Une recette hors boucle reste prise (Terre à partir d'un cristal, qu'aucune essence ne fabrique).
local ESS = { terre = 7076, vie = 12803, eau = 7080, nonmort = 12808, air = 7082, feu = 7078 }
local function transmu(de, en) return { name = "Transmutation", output = ESS[en], profession = "Alchimie", reagents = { { id = ESS[de], qty = 1 } } } end
donnees({ hv = {}, recettes = { [17559] = transmu("air", "feu"), [17560] = transmu("feu", "terre"), [17561] = transmu("terre", "eau"),
  [17562] = transmu("eau", "air"), [17563] = transmu("nonmort", "eau"), [17564] = transmu("eau", "nonmort"),
  [17565] = transmu("vie", "terre"), [17566] = transmu("terre", "vie") } })
local essences = ns.projetArbre(ns.nouveauProjet({ lines = { { id = ESS.terre, qty = 10 }, { id = ESS.eau, qty = 10 } } }), TOUT)
for _, n in ipairs(essences.cases) do assert(n.made == 0, "boucle de transmutation : " .. n.id .. " fabriquée") end
assert(essences.caseDe.T1.need == 10 and essences.caseDe.T2.need == 10, "les essences s'achètent")
AzerothCommuneDB.recipes[20000] = { name = "Cristal en terre", output = ESS.terre, profession = "Alchimie", reagents = { { id = 7909, qty = 1 } } }
essences = ns.projetArbre(ns.nouveauProjet({ lines = { { id = ESS.terre, qty = 10 } } }), TOUT)
assert(essences.caseDe.T1.recipeKey == 20000 and essences.caseDe.I7909.need == 10, "hors boucle : décomposée")
local forcee = ns.nouveauProjet({ lines = { { id = ESS.vie, qty = 10 } } })
ns.projetChoix(forcee, ESS.vie, "fabriquer")
assert(ns.projetArbre(forcee, TOUT).caseDe.T1.recipeKey == 17566, "choix de case « décomposer » : la boucle reprise")
print("Composants : recettes équivalentes, choix stable, sans boucle OK")

-- Marteau (10 bronzes) et cuirasse (20 bronzes), bronze = cuivre + étain, ×2 par fonte. Forge : Bel 164 connaît le
-- marteau, pas la cuirasse ; minage : Alt 90.
local mk = { [2770] = { tiers = { { price = 10, qty = 999 } } }, [2771] = { tiers = { { price = 10, qty = 999 } } },
  [5500] = { tiers = { { price = 500, qty = 999 } } }, [2841] = { tiers = { { price = 100, qty = 999 } } },
  [5541] = { tiers = { { price = 99999, qty = 9 } } }, [2870] = { tiers = { { price = 99999, qty = 9 } } } }
local bronzeR = { name = "Fonte du bronze", output = 2841, made_min = 2, profession = "Minage", reagents = { { id = 2770, qty = 1 }, { id = 2771, qty = 1 } } }
donnees({ hv = mk, recettes = {
  [1] = { name = "Marteau", output = 5541, profession = "Forge", level = 100, reagents = { { id = 2841, qty = 10 }, { id = 5500, qty = 1 } } },
  [2] = { name = "Cuirasse", output = 2870, profession = "Forge", reagents = { { id = 2841, qty = 20 }, { id = 5500, qty = 2 } } },
  [3] = bronzeR },
  persos = { ["Player-6942-00000BE1"] = { nom = "Bel Dupont", recipes = { Forge = { rank = 164, known = { [1] = "easy" } } } },
    ["Player-6942-00000A17"] = { nom = "Alt Dupont", recipes = { Minage = { rank = 90, known = {} } } } } })
local function both(choix) -- un projet « marteau + cuirasse », avec ses choix de case
  local p = ns.nouveauProjet({ lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  for id, c in pairs(choix or {}) do ns.projetChoix(p, id, c) end
  return ns.projetArbre(p, TOUT)
end
local tree = both()
local bronze, pearl, copper = tree.caseDe.I2841, tree.caseDe.I5500, tree.caseDe.I2770
assert(bronze.qty == 30 and bronze.made == 30 and bronze.crafts == 15 and #bronze.parents == 2, "une case bronze pour les deux")
assert(copper.qty == 15 and copper.need == 15 and #copper.parents == 1 and pearl.qty == 3, "cuivre sous le bronze seulement")
-- « – » sur le bronze : acheté tout fait. « + » quand l'achat est moins cher : décomposé quand même.
local bought = both({ [2841] = "acheter" })
assert(bought.caseDe.I2841.need == 30 and bought.caseDe.I2841.made == 0 and not bought.caseDe.I2770, "bronze acheté")
assert(bought.caseDe.I2841.craftable and bought.caseDe.I2841.choix == "acheter", "le « + » reste proposé, le choix se voit")
mk[2841].tiers[1].price = 1
assert(both().caseDe.I2841.made == 0, "bronze à 1 pc : acheté d'office")
assert(both({ [2841] = "fabriquer" }).caseDe.I2841.made == 30, "décomposé à la main")
-- Blocs : marteau et cuirasse = Forge (Bel en connaît 1 sur 2), bronze = Minage (Alt, 0 sur 1).
local res = both({ [2841] = "fabriquer" })
local hammer, plate = res.caseDe.T1, res.caseDe.T2
bronze = res.caseDe.I2841
-- Les artisans par leur nom complet « Prénom Nom » : c'est lui qui devient le joueur d'une commande, et chuchoter au
-- prénom seul échoue sur le serveur (LibCommune#35).
assert(hammer.who == "Bel Dupont" and hammer.whoKnows and plate.who == "Bel Dupont" and not plate.whoKnows, "forge : Bel (marteau connu, cuirasse à apprendre)")
assert(bronze.who == "Alt Dupont" and not bronze.whoKnows, "bronze : Alt a le minage")
local forge, mine = res.blocDe.Forge, res.blocDe.Minage
assert(#res.blocs == 2 and res.blocs[1] == forge and #forge.cases == 2 and #forge.recipes == 2 and forge.level == 100, "un bloc par métier")
assert(forge.best == "Bel Dupont" and mine.best == "Alt Dupont", "qui peut faire chaque bloc, par son nom complet")
-- Un bloc = une commande, par étapes : le minage (étape 1) livre 30 bronzes ; la forge (étape 2) livre le marteau et la
-- cuirasse, et reçoit le bronze en apport.
assert(mine.step == 1 and #mine.deliver == 1 and mine.qty[2841] == 30 and not next(mine.inputs), "étape 1 : le minage")
assert(forge.step == 2 and forge.qty[5541] == 1 and forge.qty[2870] == 1 and forge.inputs[2841], "étape 2 : la forge, bronze fourni")
-- Le bronze du minage pour le marteau et la cuirasse = UNE livraison Minage -> Forge, par Alt.
local o = res.livraisons[1]
assert(#res.livraisons == 1 and o.maker == "Minage" and o.client == "Forge" and o.player == "Alt Dupont", "une livraison Minage -> Forge")
assert(#o.lines == 1 and o.lines[1] == 2841 and o.qty[2841] == 30 and #o.edges == 2, "30 barres de bronze, deux liens regroupés")
bronzeR.profession = "Couture"
res = both({ [2841] = "fabriquer" })
assert(res.caseDe.I2841.who == false and res.blocs[2].key == "Couture", "personne ne fait la couture : son bloc vient après")
bronzeR.profession = "Minage"
print("Composants : blocs d'un projet OK")

-- Identité stable (Handshake#37, parti avec les projets) : un projet garde la sienne quand on supprime ou réordonne les autres ; son rang, lui,
-- ne dit que sa place dans la liste.
do
  local pa, pb, pc = ns.nouveauProjet(), ns.nouveauProjet(), ns.nouveauProjet()
  local idB = pb.id
  assert(pa.id and idB and pc.id and pa.id ~= idB and idB ~= pc.id and pa.id ~= pc.id, "une identité par projet")
  assert(ns.ouvrirProjet(pa.id) == pa and ns.projetCourant() == pa, "un projet s'ouvre par son identité")
  ns.supprimerProjet()
  assert(pb.id == idB and ns.ouvrirProjet(idB) == pb and not ns.ouvrirProjet(pa.id), "un autre supprimé : la même identité")
  assert(ns.nouveauProjet().id ~= pa.id, "une identité n'est jamais redonnée")
end
print("Composants : identité stable d'un projet OK")

-- Projet tenu (CONTEXT.md de Composants) : un autre module prend les lignes d'un projet en donnant une raison ; ajouter,
-- retirer une ligne, changer une quantité sont refusés avec cette raison telle quelle ; les choix de case restent libres.
do
  local RAISON = "tenu par le test"
  local p = ns.nouveauProjet({ lines = { { id = 5541, qty = 1 } } })
  ns.projetTenir(p, RAISON, { { id = 2870, qty = 2 } })
  assert(#p.lines == 1 and p.lines[1].id == 2870 and p.lines[1].qty == 2, "celui qui le tient en donne les lignes")
  local function refuse(quoi, ok, raison) assert(ok == false and raison == RAISON, quoi .. " : refusé avec sa raison, " .. tostring(raison)) end
  refuse("lignes", ns.projetPeut(p, "lignes"))
  refuse("ajouter une ligne", ns.projetAjouter(p, 5541, 1))
  refuse("changer une quantité", ns.projetQuantite(p, 1, 5))
  refuse("retirer une ligne", ns.projetRetirer(p, 1))
  assert(#p.lines == 1 and p.lines[1].qty == 2, "ses lignes n'ont pas bougé")
  assert(ns.projetPeut(p, "choix") and ns.projetChoix(p, 2841, "acheter") and p.choix[2841] == "acheter", "choix de case : libres")
end
print("Composants : projet tenu OK")

-- Dessin (Fenetre.lua) : étages, relais, bandes, titres des blocs.
mk[2841].tiers[1].price = 100
local g = ns.dessinArbre(both())
bronze, pearl, copper = g.byKey.I2841, g.byKey.I5500, g.byKey.I2770
assert(g.cols == 3 and bronze.col == 1 and pearl.col == 1 and copper.col == 2, "étages : bronze et perle en 1, minerai en 2")
for _, n in ipairs(g.nodes) do -- pas de chevauchement dans un étage
  for _, m in ipairs(g.nodes) do
    assert(n == m or n.col ~= m.col or math.abs(n.y - m.y) >= 50, "cases superposées")
  end
end
assert(ns.dessinArbre(both({ [2841] = "acheter" })).cols == 2, "bronze acheté : plus d'étage 2")
-- Lien qui saute un étage (ta capture : barre de fer commandée + haubert qui en consomme) : il passe par un relais à
-- l'étage 1, et aucune case de cet étage ne lui marche dessus.
do
  local p = ns.nouveauProjet({ lines = { { id = 2841, qty = 2 }, { id = 5541, qty = 1 } } }) -- bronze commandé + marteau
  ns.projetChoix(p, 2841, "fabriquer")
  local gr = ns.dessinArbre(ns.projetArbre(p, TOUT))
  local e
  for _, x in ipairs(gr.edges) do if x.from.key == "T1" and x.to.key == "I2770" then e = x end end
  assert(e and #e.path == 3 and e.path[2].kind == "relay" and e.path[2].col == 1, "relais à l'étage 1")
  local r = e.path[2]
  for _, n in ipairs(gr.nodes) do
    assert(n.col ~= 1 or r.y + 14 <= n.y or n.y + 42 <= r.y, "une case de l'étage 1 recouvre le lien")
  end
end
do
  local gr = ns.dessinArbre(both({ [2841] = "fabriquer" }))
  local forge = gr.groupOf.Forge
  assert(forge.label == "Étape 2 · Forge · niv. 100 requis · Bel Dupont 164 (1/2)", forge.label)
  -- Rectangles : chaque métier dans sa bande, aucune case d'un autre dans son rectangle.
  for _, grp in ipairs(gr.groups) do
    local top, bottom, left, right = math.huge, -math.huge, math.huge, -math.huge
    for _, n in ipairs(grp.cards) do
      top, bottom = math.min(top, n.y), math.max(bottom, n.y + 42)
      left, right = math.min(left, n.col), math.max(right, n.col)
    end
    for _, n in ipairs(gr.nodes) do
      local inside = n.col >= left and n.col <= right and n.y + 42 > top and n.y < bottom
      assert(not inside or n.band == grp.key, "une case d'un autre dans le rectangle de " .. grp.key)
    end
  end
  assert(gr.byKey.I2770.band == "Minage", "minerai sous le bronze : dans la bande du minage")
  bronzeR.profession = "Couture"
  gr = ns.dessinArbre(both({ [2841] = "fabriquer" }))
  assert(gr.groupOf.Couture.label == "Étape 1 · Couture · personne de ta liste", gr.groupOf.Couture.label)
  for _, n in ipairs(gr.nodes) do -- rien ne se chevauche, bande sans artisan comprise
    for _, m in ipairs(gr.nodes) do
      assert(n == m or n.col ~= m.col or n.y + 42 <= m.y or m.y + 42 <= n.y, "cases superposées")
    end
  end
  bronzeR.profession = "Minage"
  -- L'emplacement du bloc (API.lua) : un bloc confié se réduit à une seule case. La forge (marteau, cuirasse) : la case du
  -- marteau la représente, la cuirasse s'y fond ; le bronze qui y entre (un autre bloc) et la perle (achetée, de sa part)
  -- restent liés à elle, un lien par paire, sans quantité quand deux liens s'y fondent.
  local res = both({ [2841] = "fabriquer" })
  local cases, liens = ns.reduire(res, nil)
  assert(cases == res.cases and liens == res.liens, "rien de confié : l'arbre tel quel")
  gr = ns.dessinArbre(res, { Forge = true })
  local forge = gr.groupOf.Forge
  local garde = {}
  for _, n in ipairs(gr.nodes) do garde[n.key] = n end
  assert(forge.case == res.caseDe.T1 and garde.T1 and not garde.T2, "la forge : une seule case, celle du marteau")
  assert(garde.I2841 and garde.I2770 and garde.I2771, "le minage reste entier")
  assert(#forge.cards == 1 or (#forge.cards == 2 and garde.I5500), "dans sa bande : sa case (et la perle, prise aussi ailleurs)")
  local vers = {}
  for _, e in ipairs(gr.edges) do vers[e.from.key .. ">" .. e.to.key] = (vers[e.from.key .. ">" .. e.to.key] or 0) + 1 end
  assert(vers["T1>I2841"] == 1 and not vers["T2>I2841"], "un seul lien de la forge au bronze")
  -- Le minage confié : le bronze le représente, le minerai (sa part, pris par personne d'autre) sort du dessin.
  gr = ns.dessinArbre(both({ [2841] = "fabriquer" }), { Minage = true })
  garde = {}
  for _, n in ipairs(gr.nodes) do garde[n.key] = n end
  assert(garde.I2841 and not garde.I2770 and not garde.I2771 and garde.T1 and garde.T2, "le minage : le bronze seul, la forge entière")
  assert(gr.cols == 2, "plus d'étage pour le minerai")
end
print("Composants : dessin de l'arbre (étages, relais, bandes) OK")

-- L'emplacement des Besoins (Composants#27) : un bloc confié sort des Besoins (ses cases et ce qui n'est fabriqué que pour
-- lui), et du coût à acheter ; ce que le joueur lui donne (aDonner) y reste, une ligne comme les autres. Réunir →
-- Fabriquer et Fabriquer → Fini attendent clos. Marteau + cuirasse : forge (perle, bronze du minage), minage (cuivre, étain).
do
  local p = ns.nouveauProjet({ name = "Confié", lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  ns.projetChoix(p, 2841, "fabriquer")
  local function lignes()
    local t, cout = {}, 0
    for _, r in ipairs((ns.orderNeeds(ns.besoinsArbre(p, TOUT)))) do t[r.id], cout = r, cout + r.cost end
    return t, cout
  end
  local l, cout = lignes()
  assert(l[2770] and l[2771] and l[5500] and not l[2841], "sans fournisseur : cuivre, étain, perle")
  local confier, donne, clos = {}, nil, false
  local avant = Composants.Emplacements({ confie = function(_, b) return confier[b and b.key or true] end,
    aDonner = function() return donne end, clos = function() return clos end })
  confier.Minage = true
  local l2, cout2 = lignes()
  assert(not l2[2770] and not l2[2771] and l2[5500], "le minage confié : cuivre et étain sortent, la perle reste")
  assert(cout2 < cout, "ni dans le coût à acheter")
  confier = { Forge = true }
  l = lignes()
  assert(l[2770] and l[2771] and not l[5500], "la forge confiée : sa perle sort ; le bronze, du minage, se fait toujours")
  donne = { [5500] = true }
  l = lignes()
  assert(l[5500] and l[5500].required == 3, "la perle donnée à la forge : une ligne des Besoins (il faut l'avoir sur soi)")
  confier, donne = { [true] = true }, { [2841] = true }
  l = lignes()
  assert(l[2770] and l[2771], "le bronze donné, que je fais : son cuivre et son étain restent des Besoins")
  confier, donne = { [true] = true }, nil
  assert(next((lignes())) == nil, "le projet entier confié : rien à réunir")
  -- Tout réuni (rien à réunir) mais pas clos : on reste en Réunir ; clos : Fabriquer. Fini attend clos aussi.
  assert(ns.lancer(p) == p and ns.phase(p) == "reunir", "Lancer, même si ce qui est confié n'est pas arrivé")
  assert(not ns.avancerPhase(p) and ns.phase(p) == "reunir", "pas clos : Réunir")
  clos = true
  assert(ns.avancerPhase(p) and ns.phase(p) == "fabriquer", "clos : Fabriquer")
  local projetFini = ns.projetFini
  ns.projetFini = function() return true end
  clos = false
  assert(not ns.avancerPhase(p) and ns.phase(p) == "fabriquer", "plus rien à fabriquer, pas clos : pas Fini")
  clos = true
  assert(ns.avancerPhase(p) and ns.phase(p) == "fini", "clos : Fini")
  -- Les phases dites par le fournisseur : lancer refuse Lancer (le fil aussi), fini décide seul de Fini.
  local refus, fini = "à signer", nil
  Composants.Emplacements({ lancer = function() return refus end, fini = function() return fini end, clos = function() return true end })
  ns.projetPhase(p, "preparer")
  local q, raison = ns.lancer(p)
  assert(q == nil and raison == "à signer" and ns.phase(p) == "preparer", "lancer refusé : Préparer, avec sa raison")
  q, raison = ns.allerPhase(p, "fabriquer")
  assert(q == nil and raison == "à signer" and ns.phase(p) == "preparer", "le fil ne contourne pas le refus")
  assert(ns.allerPhase(p, "preparer") == p, "rester en Préparer : permis")
  assert(ns.refusLancer(ns.brouillon()) == nil, "jamais demandé pour le Brouillon")
  refus = nil
  assert(ns.lancer(p) == p and ns.phase(p) == "reunir", "permis : Réunir")
  ns.allerPhase(p, "fabriquer")
  fini = false
  assert(not ns.avancerPhase(p) and ns.phase(p) == "fabriquer", "fini faux : pas Fini, même plus rien à fabriquer et clos")
  fini = nil
  assert(ns.avancerPhase(p) and ns.phase(p) == "fini", "fini nil : la règle de Composants")
  ns.projetPhase(p, "reunir")
  ns.projetFini = function() return false end
  fini = true
  assert(ns.avancerPhase(p) and ns.phase(p) == "fini", "fini vrai : Fini depuis Réunir, sans l'arbre")
  ns.projetFini = projetFini
  -- Une erreur chez le fournisseur : signalée, pas clos.
  local erreurs, handler = {}, geterrorhandler
  geterrorhandler = function() return function(e) erreurs[#erreurs + 1] = e end end
  Composants.Emplacements({ clos = function() error("boum") end })
  assert(not ns.closEmplacement(p) and #erreurs == 1, "erreur : pas clos, signalée")
  geterrorhandler = handler
  Composants.Emplacements(avant)
  assert(ns.closEmplacement(p), "sans fournisseur : clos")
  Composants.Supprimer(p.id)
end
print("Composants : l'emplacement des Besoins (part confiée, aDonner, clos ; lancer, fini) OK")
commune.Conteneurs, AzerothCommuneDB.chars = realContainers, {}

-- Suggestions : la barre de recherche du socle (AzerothCommune#60), plus de copie ni d'index d'objets à Composants.
local fen = io.open("Composants/Fenetre.lua"):read("*a")
assert(fen:find("AzerothCommune.RechercheObjets(", 1, true) and not io.open("Composants/Recherche.lua"), "la barre du socle")
assert(not fen:find("itemIndex", 1, true) and not fen:find("low:find", 1, true) and ns.rechercheObjets == nil, "plus de recherche à soi")
print("Composants : suggestions OK")



local function link(id, name) return ("|cff1eff00|Hitem:%d::::::::31:::::::::|h[%s]|h|r"):format(id, name) end
AzerothCommuneItems.items = { [7963] = { name = "Claymore en mithril", link = link(7963, "Claymore en mithril") },
  [3858] = { name = "Minerai de mithril" }, [7989] = { name = "Plans : Claymore en mithril" } }
-- Besoins : composants pas fabriqués avec ce qu'on a ; recette pas apprise -> l'objet « Plans : … ».
local res = { cases = {
  { id = 7963, kind = "target", qty = 1, made = 1, need = 0, have = { 0, 0, 0 }, unknown = true, recipe = { name = "Claymore en mithril" } },
  { id = 3858, kind = "item", qty = 36, made = 0, need = 30, cost = 3000, have = { 6, 0, 0 }, how = "HV" },
  { id = 7920, kind = "item", qty = 1, made = 0, need = 0, cost = 0, have = { 1, 0, 0 } },
}, total = 3000 }
local rows, recipes = ns.orderNeeds(res)
assert(#rows == 2 and rows[1].id == 3858 and rows[1].required == 36 and rows[2].need == 0, "manquants d'abord, le complet ensuite")
assert(#recipes == 1 and recipes[1].item == 7989, "recette trouvée par son nom")
print("Composants : besoins OK")

aucunReleve("après les calculs")

-- Les recettes connues de tous les persos de la base, par le socle.
local ALT, SANS = "Player-6942-00000A17", "Player-6942-00005A25"
AzerothCommuneDB.chars = { [ALT] = { nom = "Alt Dupont", recipes = { Forge = { rank = 50, max = 75, known = { [9] = "easy" } } },
  professions = { { name = "Couture", rank = 120 } }, bags = { b = { items = { { id = 2840, count = 4 } } } } }, [SANS] = {} }
assert(ns.knownRecipes()[ALT].Forge.known[9] and not ns.knownRecipes()[SANS], "recettes connues de la base, par GUID")
local alt
for _, e in ipairs(ns.crafters()) do if e.key == ALT then alt = e end end
assert(alt and alt.name == "Alt Dupont" and alt.ranks.Forge == 50 and alt.known[9], "artisan lu dans la base, prénom tiré de sa fiche")
assert(alt.ranks.Couture == 120, "métiers des persos (fiche de la base), par le socle")
-- Mes autres persos (option « mes autres persos ») : leurs sacs, par le socle.
AzerothCommuneDB.recipes = { [1] = { name = "Fonte du bronze", output = 2841, reagents = { { id = 2840, qty = 1 } } } }
AzerothCommuneMarket = { ["6942-Alliance"] = { scanned = "hier", items = { [2840] = { tiers = { { price = 50, qty = 99 } } } } } }
local bronze = ns.nouveauProjet({ lines = { { id = 2841, qty = 6 } } })
local arbreAlts = ns.projetArbre(bronze, { alts = true, unlearned = true })
assert(arbreAlts.caseDe.I2840.have[3] == 4 and arbreAlts.caseDe.I2840.need == 2, "sacs d'un autre perso déduits")
assert(ns.texteHV() == "HV du hier", "la date du scan du socle")
AzerothCommuneDB.chars = {}
aucunReleve("recettes connues")
print("Composants : recettes connues des persos de la base OK")

-- Les données relevées, toutes par le socle : catalogue des objets pas encore relevé (noms demandés au serveur), sacs et
-- banque du perso connecté, l'HV d'un fournisseur ; jamais rien de relevé dans ComposantsDB.
AzerothCommuneDB.recipes, AzerothCommuneItems.items, AzerothCommuneMarket = {}, {}, {}
assert(not ns.recipes()[5] and not next(ns.knownRecipes()), "rien de relevé")
-- Minage relevé par le socle (fenêtre de métier) ; le catalogue des objets, lui, pas encore.
local GMOI = UnitGUID("player")
AzerothCommuneDB.recipes = {
  [5] = { name = "Fonte du cuivre", profession = "Minage", output = 2840, reagents = { { id = 2770, qty = 1 } } },
  [6] = { name = "Fonte du bronze", profession = "Minage", output = 2841, reagents = { { id = 2840, qty = 1 } } } }
AzerothCommuneDB.chars = { [GMOI] = { recipes = { Minage = { rank = 75, max = 150, known = { [5] = "medium" } } } } }
-- Les noms des produits et composants des recettes relevées sont demandés au serveur ; arrivés, gardés en mémoire.
local demandes = {}
C_Item.RequestLoadItemDataByID = function(id) demandes[id] = true end
ns.recipes()
assert(demandes[2840] and demandes[2770] and demandes[2841], "noms des produits et composants demandés au serveur")
C_Item.RequestLoadItemDataByID = nil
C_Item.GetItemInfo = function(id) if id == 2840 then return "Barre de cuivre", "|Hitem:2840|h[Barre de cuivre]|h" end end
ns.rememberItem(2840)
C_Item.GetItemInfo = noop
assert(ns.recipes()[5] and ns.findItem("barre de cuivre") == 2840 and ns.findItem("Fonte du cuivre") == 2840, "noms en mémoire")
assert(ns.knownRecipes()[GMOI].Minage.known[5] and not ns.knownRecipes()[GMOI].Minage.known[6], "recettes connues du perso")
local moi = ns.crafters()[1]
assert(moi.key == GMOI and moi.ranks.Minage == 75 and moi.known[5], "artisan : mon perso, même sans sacs relevés")
-- Sacs (lus à l'instant, par le socle) et banque (dernier passage, dans la base) du perso connecté, déduits du calcul.
Enum = Enum or {}
Enum.BagIndex = { Backpack = 0, Bank = -1 }
local slots = { [0] = { { itemID = 2770, stackCount = 2, hyperlink = "|Hitem:2770|h" } }, [-1] = {} }
C_Container = { GetContainerNumSlots = function(b) return #slots[b] end, GetContainerItemInfo = function(b, i) return slots[b][i] end }
AzerothCommuneDB.chars[GMOI].bank = { Bank = { items = { { id = 2770, count = 3 } } } }
local cuivre = ns.nouveauProjet({ lines = { { id = 2840, qty = 10 } } })
local arbreSeul = ns.projetArbre(cuivre, { bags = true, bank = true, alts = true })
local minerai = arbreSeul.caseDe.I2770
assert(minerai.have[1] == 2 and minerai.have[2] == 3 and minerai.have[3] == 0 and minerai.need == 5, "sacs et banque du perso, pas d'autres persos")
-- HV : ni scan du socle ni fournisseur, rien à acheter ; la fenêtre dit comment l'avoir.
assert(minerai.unpriced and ns.market() == nil, "pas de prix de l'HV")
assert(ns.texteHV() == "HV jamais scanné : ouvre l'hôtel des ventes", "HV : " .. ns.texteHV())
-- Avec Auctionator (fournisseur) : ses prix du jour, sans paliers.
time = os.time
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) return id == 2770 and 30 or nil end,
  GetAuctionAgeByItemID = function() return 0 end } } }
arbreSeul = ns.projetArbre(cuivre, { bags = true, bank = true })
assert(arbreSeul.caseDe.I2770.cost == 5 * 30 and ns.texteHV() == "prix de l'HV : Auctionator", "prix d'Auctionator")
Auctionator = nil
aucunReleve("catalogue pas encore relevé, fournisseur")
-- Base des recettes du socle (AzerothCommune#48) : Composants y souscrit et la lit par Lire. La réserve
-- Classic est celle du socle (privée : acns.recettesReserve), ajoutée pour les objets sans recette vue, jamais par-dessus
-- une recette vue du même objet.
assert(AzerothCommuneDB.souscriptions["base des recettes"], "Composants souscrit à la base des recettes")
acns.recettesReserve = { [9001] = { 2840, 1, 1, "Minage", "Barre de cuivre (Classic)", { 2770, 2 }, 1 },
  [9002] = { 4255, 1, 1, "Travail du cuir", "Armure verte en cuir", { 4234, 9 }, 175 },
  [5] = { 2840, 1, 1, "Minage", "Fonte du cuivre", { 2770, 1 }, 25 } }
local merged = ns.recipes()
assert(merged[5] and not merged[9001], "barre de cuivre déjà vue : la recette Classic ne la double pas")
assert(merged[9002] and merged[9002].output == 4255 and merged[9002].reagents[1].qty == 9, "armure verte en cuir : recette Classic")
-- Compétence requise affichée dans les blocs : celle de la réserve, aussi pour une recette vue pas apprise (5).
local verte = ns.projetArbre(ns.nouveauProjet({ lines = { { id = 4255, qty = 1 }, { id = 2840, qty = 1 } } }),
  { unlearned = true, force = { [4255] = "fabriquer", [2840] = "fabriquer" } })
local niveaux = {}
for _, g in ipairs(verte.blocs) do for _, r in ipairs(g.recipes) do niveaux[r.key] = r.level end end
assert(niveaux[9002] == 175 and niveaux[5] == 25, "compétence requise de la réserve : " .. tostring(niveaux[9002]) .. ", " .. tostring(niveaux[5]))
acns.recettesReserve = nil
local demo = ns.demoProjet("hasard")
assert(demo.name == "Essai : au hasard" and #demo.lines == 1 and demo.lines[1].id == 2841, "essai : le bronze (son cuivre se fabrique)")
assert(#ns.demoProjet().lines == 3 and ns.demoProjet("ceinture").lines[1].id == 10721, "essais choisis : le set, les ceintures")
aucunReleve("relevés par le socle")
print("Composants : noms demandés, sacs et banque, fournisseur de l'HV, réserve des recettes OK")

-- Choix de case par projet (CONTEXT.md) : deux projets aux mêmes lignes ; le choix de l'un ne change ni l'arbre ni les
-- blocs de l'autre.
AzerothCommuneMarket = { ["6942-Alliance"] = { scanned = "hier", items = { [2770] = { tiers = { { price = 10, qty = 999 } } },
  [2771] = { tiers = { { price = 10, qty = 999 } } }, [2841] = { tiers = { { price = 100, qty = 999 } } }, [5541] = { tiers = { { price = 99999, qty = 9 } } } } } }
AzerothCommuneDB.recipes = {
  [1] = { name = "Marteau", output = 5541, profession = "Forge", reagents = { { id = 2841, qty = 10 } } },
  [3] = { name = "Fonte du bronze", output = 2841, made_min = 2, profession = "Minage", reagents = { { id = 2770, qty = 1 }, { id = 2771, qty = 1 } } } }
do
  local pa = Composants.NouveauProjet({ lines = { { id = 5541, qty = 1 } } })
  local pb = Composants.NouveauProjet({ lines = { { id = 5541, qty = 1 } } })
  assert(Composants.Arbre(pb, true).caseDe.I2841.made == 10, "témoin : le bronze se fond")
  assert(Composants.Choix(pa, 2841, "acheter") and pa.choix[2841] == "acheter" and not pb.choix, "le choix va au projet A")
  assert(Composants.Arbre(pa, true).caseDe.I2841.made == 0 and not Composants.Arbre(pa, true).blocDe.Minage, "projet A : bronze acheté, plus de bloc du minage")
  assert(Composants.Arbre(pb, true).caseDe.I2841.made == 10 and Composants.Arbre(pb, true).blocDe.Minage, "projet B : inchangé")
  assert(Composants.Choix(pa, 2841, nil) and pa.choix == nil, "sans choix : le calcul des prix décide")
end
print("Composants : choix de case propres à chaque projet OK")

-- Projet tenu, suite : appelé de nouveau, il remet les lignes à jour en gardant les choix de case ; lâché, tout se change.
do
  local p = Composants.NouveauProjet({ lines = { { id = 5541, qty = 1 } } })
  Composants.Choix(p, 2841, "acheter")
  Composants.Tenir(p, "tenu par le test", { { id = 5541, qty = 2 } })
  Composants.Tenir(p, "tenu par le test", { { id = 5541, qty = 3 } })
  assert(p.lines[1].qty == 3 and p.choix[2841] == "acheter" and not Composants.Ajouter(p, 2841, 1), "lignes remises à jour, choix gardés")
  Composants.Tenir(p, nil)
  assert(Composants.Peut(p, "lignes") and Composants.Ajouter(p, 2841, 1) and #p.lines == 2, "lâché : ses lignes se changent")
end
print("Composants : projet tenu remis à jour, lâché OK")

-- « Ce projet a changé » (API) : chaque modification le signale, avec ce qui a changé ; la suppression rend le projet parti.
do
  local vu = {}
  Composants.QuandChange(function(p, quoi) vu[#vu + 1] = quoi .. ":" .. tostring(p.id) end)
  local p = Composants.NouveauProjet()
  local id = tostring(p.id)
  Composants.Ajouter(p, 5541, 1); Composants.Quantite(p, 1, 2); Composants.Choix(p, 2841, "acheter"); Composants.Renommer(p, "x")
  Composants.Tenir(p, "r"); Composants.Retirer(p, 1); Composants.Tenir(p, nil); Composants.Retirer(p, 1)
  assert(Composants.Supprimer(p.id) == p and not Composants.Projet(p.id), "supprimé par son identité")
  local attendu = table.concat({ "nouveau", "lignes", "lignes", "choix", "nom", "tenu", "tenu", "lignes", "supprime" }, ":" .. id .. ",") .. ":" .. id
  assert(table.concat(vu, ",") == attendu, table.concat(vu, ","))
  assert(Composants.Supprimer(p.id) == nil, "déjà parti : rien")
  -- Un rappel qui plante ne prive pas les autres (erreur au jeu).
  local erreurs, apres = {}, false
  geterrorhandler = function() return function(e) erreurs[#erreurs + 1] = e end end
  Composants.QuandChange(function() error("boum") end)
  Composants.QuandChange(function() apres = true end)
  Composants.NouveauProjet()
  assert(#erreurs == 1 and apres, "un rappel qui plante ne prive pas les autres")
end
print("Composants : signal « ce projet a changé » OK")

-- L'API publique (README.md) : le global Composants, rien d'autre.
do
  local API = { "NouveauProjet", "Projet", "Projets", "Renommer", "Supprimer", "Ajouter", "Quantite", "Retirer", "Choix", "Peut",
    "Tenir", "Arbre", "QuandChange", "Ouvrir", "Rafraichir", "Emplacements" }
  local n = 0
  for _ in pairs(Composants) do n = n + 1 end
  for _, f in ipairs(API) do assert(type(Composants[f]) == "function", "Composants." .. f) end
  assert(n == #API, "l'API publique, rien de plus")
  local readme = assert(io.open("Composants/README.md"), "README.md"):read("*a")
  for _, f in ipairs(API) do assert(readme:find("C." .. f .. "(", 1, true), "README : Composants." .. f) end
  local p = Composants.NouveauProjet({ name = "API", lines = { { id = 5541, qty = 1 } } })
  assert(Composants.Projet(p.id) == p and Composants.Projets()[#Composants.Projets()] == p, "lire par identité, lister")
  -- L'arbre d'une table { lines, choix } qui n'est pas un projet (la part d'une commande Handshake), sans stock déduit.
  local part = Composants.Arbre({ lines = { { id = 2841, qty = 4 } }, choix = { [2841] = "fabriquer" } }, true)
  assert(part.caseDe.T1.made == 4 and part.caseDe.I2770.need == 2, "l'arbre d'une part")
end
print("Composants : API publique OK")

-- Le Brouillon (CONTEXT.md) : Ctrl+clic droit sur un objet (lien) l'y met, une fois, jamais dans le projet affiché ; il
-- n'est pas dans la liste des projets ; Lancer en fait un vrai projet (lignes et choix de case) et il se vide.
do
  C_Item.GetItemInfoInstant = function() return nil, nil, nil, nil, nil, 4 end -- une arme, pas une recette
  local ouvrir = ns.openCraftWindow
  ns.openCraftWindow = noop -- pas d'interface hors jeu
  local b = ns.brouillon()
  assert(ns.estBrouillon(b) and #b.lines == 0, "un Brouillon, vide au départ")
  local p = Composants.NouveauProjet()
  ns.ctrlClicDroit(link(5541, "Marteau"))
  assert(#p.lines == 0 and #b.lines == 1 and b.lines[1].id == 5541 and b.lines[1].qty == 1, "dans le Brouillon, pas le projet affiché")
  ns.projetQuantite(b, 1, 3)
  ns.ctrlClicDroit(link(5541, "Marteau"))
  assert(#b.lines == 1 and b.lines[1].qty == 3, "déjà dans le Brouillon : sa quantité ne bouge pas")
  ns.ctrlClicDroit("pas un lien")
  ns.ctrlClicDroit(link(2841, "Barre de bronze"))
  assert(#b.lines == 2 and #p.lines == 0, "deux objets au Brouillon")
  ns.openCraftWindow = ouvrir
  -- Hors de la liste des projets ; on l'affiche par la colonne des projets.
  for _, q in ipairs(Composants.Projets()) do assert(q ~= b, "le Brouillon dans la liste des projets") end
  assert(ns.ouvrirBrouillon() == b and ns.projetCourant() == b, "le Brouillon s'affiche")
  local n = #Composants.Projets()
  -- On y retire une ligne, on le vide.
  assert(ns.projetRetirer(b, 2) and #b.lines == 1, "une ligne retirée")
  ns.viderBrouillon()
  assert(#b.lines == 0, "vidé")
  -- Lancer : un vrai projet avec ses lignes et ses choix de case ; le Brouillon se vide.
  ns.projetAjouter(b, 5541, 2)
  ns.projetChoix(b, 2841, "acheter")
  ns.ouvrirBrouillon()
  local q = ns.lancer(b)
  assert(q and not ns.estBrouillon(q) and Composants.Projets()[#Composants.Projets()] == q, "un vrai projet, dans la liste")
  assert(#q.lines == 1 and q.lines[1].id == 5541 and q.lines[1].qty == 2 and q.choix[2841] == "acheter", "ses lignes, ses choix de case")
  assert(#b.lines == 0 and b.choix == nil and ns.projetCourant() == q, "le Brouillon vidé, le projet affiché")
  assert(ns.lancer(b) == nil and #Composants.Projets() == n + 1, "Brouillon vide : pas de projet vide")
  -- On n'y commande rien : Composants ne demande jamais au fournisseur des emplacements les apports du Brouillon.
  local demande
  local avant = Composants.Emplacements({ apports = function(x) demande = x return {} end })
  assert(ns.apportsEmplacement(b) == nil and not demande, "pas d'apports pour le Brouillon")
  assert(ns.apportsEmplacement(q) and demande == q, "un projet, si")
  Composants.Emplacements(avant)
end
print("Composants : Brouillon, Ctrl+clic droit OK")

-- Fabrication (CONTEXT.md) : une ligne « recette × nombre de fois » d'un projet tenu (une tranche de montée de Maîtrise).
-- Sa case racine est toujours fabriquée avec cette recette (ni stock pris, ni achat ; son choix de case ne peut pas être
-- « acheter ») ; une recette sans objet produit (un enchantement) n'a pour cases que ses composants ; dessous, les choix
-- de case restent libres, et ses Besoins comptent le stock de tous les persos comme pour les autres projets.
do
  local ALT = "Player-6942-00000A17"
  local function prix(pc) return { tiers = { { price = pc, qty = 999 } } } end
  donnees({ hv = { [2841] = prix(1), [2840] = prix(10), [3576] = prix(10), [2770] = prix(2), [10940] = prix(50) },
    recettes = {
      [2659] = { name = "Fonte du bronze", output = 2841, made_min = 2, profession = "Minage", reagents = { { id = 2840, qty = 1 }, { id = 3576, qty = 1 } } },
      [2657] = { name = "Fonte du cuivre", output = 2840, profession = "Minage", reagents = { { id = 2770, qty = 1 } } },
      [7420] = { name = "Enchanter le plastron - Vie mineure", profession = "Enchantement", reagents = { { id = 10940, qty = 1 } } } },
    sacs = { [2841] = 50, [10940] = 1 },
    persos = { [ALT] = { nom = "Alt Dupont", bags = { b = { items = { { id = 10940, count = 1 } } } } } } })
  local p = Composants.NouveauProjet({ name = "Tranche" })
  Composants.Tenir(p, "tenu par Maîtrise", { { recette = 2659, fois = 5 }, { recette = 7420, fois = 3 } })
  -- La barre de bronze : 1 pc à l'HV, 50 en sac, fabriquée quand même, avec cette recette, 5 fois (2 barres par fonte).
  local res = Composants.Arbre(p, true)
  local barre = res.caseDe.T1
  assert(barre and barre.id == 2841 and barre.kind == "target" and barre.made == 10 and barre.crafts == 5 and barre.recipeKey == 2659
    and barre.need == 0, "fabrication : la case racine fabriquée avec sa recette")
  assert(res.caseDe.I2840.qty == 5 and res.caseDe.I3576.qty == 5 and #res.caseDe.I2840.parents == 1, "ses composants : 5 cuivres, 5 étains")
  assert(res.blocDe.Minage and res.blocDe.Minage.qty[2841] == 10, "son bloc : le minage livre les 10 barres")
  local avecStock = ns.projetArbre(p, { bags = true, alts = true, unlearned = true })
  assert(avecStock.caseDe.T1.made == 10 and avecStock.caseDe.T1.have[1] == 0, "les barres en sac ne sont pas prises")
  -- L'enchantement : aucune case pour lui, seulement sa poussière, en tête de l'arbre.
  assert(not res.caseDe.T2 and res.caseDe.I10940.qty == 3 and #res.caseDe.I10940.parents == 0, "enchantement : ses composants seulement")
  assert(res.total == 5 * 2 + 5 * 10 + 3 * 50, "le coût : les composants (cuivre fondu, étain, poussière), pas la barre")
  assert(ns.dessinArbre(res).byKey.I10940.col == 0, "la poussière de l'enchantement dessinée à l'étage des lignes")
  -- Choix de case : la racine refuse « acheter » ; dessous, libres.
  local ok, raison = Composants.Choix(p, 2841, "acheter")
  assert(ok == false and type(raison) == "string" and not (p.choix and p.choix[2841]), "la racine ne s'achète pas")
  assert(res.caseDe.I2840.made == 5, "témoin : le cuivre se fond (le minerai est moins cher)")
  assert(Composants.Choix(p, 2840, "acheter") and Composants.Arbre(p, true).caseDe.I2840.made == 0, "dessous, libre : cuivre acheté")
  Composants.Choix(p, 2840, nil)
  -- Les Besoins : la barre fabriquée n'y est pas ; la poussière, avec le stock de mes sacs et d'un autre perso.
  local function besoin(r, id) for _, l in ipairs((ns.orderNeeds(r))) do if l.id == id then return l end end end
  local b = ns.besoinsArbre(p, { bags = true, alts = true, unlearned = true })
  local poussiere = besoin(b, 10940)
  assert(not besoin(b, 2841), "la barre fabriquée : rien à réunir")
  assert(poussiere and poussiere.required == 3 and poussiere.have[1] == 1 and poussiere.have[3] == 1 and poussiere.need == 1,
    "la poussière : 1 en sac, 1 chez un autre perso, 1 à acheter")
  assert(besoin(b, 2770).required == 5 and besoin(b, 3576).required == 5, "le minerai de cuivre et l'étain")
  -- Les fabrications faites (ns.compterFabrication, sur UNIT_SPELLCAST_SUCCEEDED) : seulement un projet lancé ; chacune pour
  -- un seul projet, l'affiché d'abord, sinon le premier de la liste à qui il en reste ; la ligne n'en demande plus que le reste.
  assert(ns.compterFabrication(2659) == nil and not p.faites, "en Préparer : rien de compté")
  local autre = Composants.NouveauProjet({ name = "Autre", lines = { { recette = 2659, fois = 1 } } }) -- l'affiché
  ns.projetPhase(p, "fabriquer"); ns.projetPhase(autre, "reunir")
  assert(ns.compterFabrication(2659) == autre and autre.faites[2659] == 1 and not p.faites, "l'affiché d'abord")
  assert(ns.projetFini(ns.projetArbre(autre)), "toutes faites : fini, ses composants ne sont plus demandés")
  assert(ns.projetArbre(autre).valeur == nil, "toutes faites : plus de valeur à l'HV")
  assert(ns.compterFabrication(2659) == p and p.faites[2659] == 1 and autre.faites[2659] == 1, "plus rien à l'affiché : le suivant")
  ns.compterFabrication(2659); ns.compterFabrication(2659)
  local reste = Composants.Arbre(p, true)
  assert(reste.caseDe.T1.made == 4 and reste.caseDe.T1.crafts == 2 and reste.caseDe.I2840.qty == 2, "3 faites sur 5 : 2 fontes, 4 barres")
  assert(reste.total == 2 * 2 + 2 * 10 + 3 * 50, "le coût du reste seulement")
  assert(besoin(ns.besoinsArbre(p, { bags = true, unlearned = true }), 2770).required == 2, "les Besoins du reste")
  assert(ns.allerPhase(p, "preparer") and p.faites[2659] == 3, "revenir à Préparer par le fil : rien d'oublié")
  assert(ns.compterFabrication(2659) == nil, "en Préparer : rien de compté")
  ns.projetPhase(p, "fabriquer")
  ns.compterFabrication(2659); ns.compterFabrication(2659)
  assert(ns.compterFabrication(2659) == nil and p.faites[2659] == 5, "les 5 faites : plus rien à compter")
  reste = Composants.Arbre(p, true)
  assert(reste.caseDe.T1.made == 0 and not reste.caseDe.I2840 and reste.caseDe.I10940.qty == 3, "la fonte finie ; l'enchantement reste")
  Composants.Tenir(p, "tenu par Maîtrise", { { recette = 2659, fois = 5 }, { recette = 7420, fois = 3 } })
  assert(not p.faites and p.phase == nil, "nouvelles lignes : les faites oubliées, Préparer")
  autre.phase = nil
  Composants.Supprimer(autre.id)
  -- Lâché, une ligne fabrication change de nombre de fois.
  Composants.Tenir(p, nil)
  assert(Composants.Quantite(p, 1, 7) and p.lines[1].fois == 7 and p.lines[1].qty == nil, "lâché : le nombre de fois se change")
  ns.projetPhase(p, "fabriquer"); ns.compterFabrication(2659); ns.compterFabrication(7420)
  assert(Composants.Quantite(p, 1, 6) and p.faites[2659] == nil and p.faites[7420] == 1, "Quantite : les faites de cette ligne oubliées")
  assert(Composants.Retirer(p, 2) and p.faites == nil, "Retirer : celles de la ligne retirée")
  commune.Conteneurs, AzerothCommuneDB.chars = realContainers, {}
end
print("Composants : lignes fabrication d'un projet tenu OK")

-- La prochaine fabrication (le bouton d'action en Fabriquer) : celle du projet affiché, tous métiers, dans l'ordre de
-- dépendance ; la première que les sacs permettent. Le projet de la capture du 25/11 : 4 Dory en bronze (8 barres de bronze et
-- 4 catalyseurs chacune), 7 barres de bronze, 13 de cuivre, 9 d'étain et 4 minerais d'étain en sac.
do
  local function prix(pc) return { tiers = { { price = pc, qty = 999 } } } end
  local function nom(id) return (ns.itemLabel(id):gsub("%[(.-)%]", "%1")) end
  local DORY, FLUX = 99100, 2880
  local sacs
  local function poser(s)
    sacs = s
    donnees({ hv = { [DORY] = prix(100000), [2841] = prix(1000), [3576] = prix(500), [2771] = prix(10), [2840] = prix(300), [FLUX] = prix(10) },
      recettes = {
        [99101] = { name = "Dory en bronze", output = DORY, profession = "Forge", reagents = { { id = 2841, qty = 8 }, { id = FLUX, qty = 4 } } },
        [2659] = { name = "Fonte du bronze", output = 2841, made_min = 2, profession = "Minage", reagents = { { id = 2840, qty = 1 }, { id = 3576, qty = 1 } } },
        [3304] = { name = "Fonte de l'étain", output = 3576, profession = "Minage", reagents = { { id = 2771, qty = 1 } } } },
      sacs = s })
    AzerothCommuneDB.chars[MOI].recipes = { Minage = { rank = 75, known = { [3304] = true, [2659] = true } },
      Forge = { rank = 100, known = { [99101] = true } } }
  end
  local faisable, requis = {}, {}
  C_TradeSkillUI = {
    GetRecipeInfo = function() return { learned = true } end,
    GetCraftableCount = function(k) return faisable[k] or 0 end,
    GetRecipeRequirements = function() return requis end,
  }
  C_Item.GetItemCount = function(id) return sacs[id] or 0 end
  local T, C = ns.texteToutFabriquer, ns.texteBouton -- la phrase (la bulle), le libellé du bouton d'action
  poser({ [2841] = 7, [2840] = 13, [3576] = 9, [2771] = 4 })
  local p = Composants.NouveauProjet({ name = "Dory", lines = { { id = DORY, qty = 4 } } })
  -- Aucune fenêtre de métier : d'abord les 4 barres d'étain (le bas de l'arbre), dans la fenêtre du Minage.
  local f = ns.prochaineDuProjet(p, nil)
  assert(f and f.cle == 3304 and f.etat == "ouvrir" and f.n == 4, "d'abord l'étain, fenêtre à ouvrir")
  assert(T(f) == "Ouvrir Minage : 4 × " .. nom(3576), T(f))
  assert(C(f) == "Ouvre Minage", C(f))
  -- Le Minage ouvert, le jeu confirme : on fabrique les 4.
  faisable[3304] = 4
  f = ns.prochaineDuProjet(p, "Minage")
  assert(f.cle == 3304 and f.etat == "pret" and f.n == 4 and T(f) == "Fabriquer 4 × " .. nom(3576), T(f))
  assert(C(f) == nom(3576) .. " ×4", C(f)) -- ce qu'il reste à faire, en objets
  -- Les 4 barres d'étain arrivent : le bronze, 13 fontes de 2 barres.
  poser({ [2841] = 7, [2840] = 13, [3576] = 13 })
  faisable[2659] = 13
  f = ns.prochaineDuProjet(p, "Minage")
  assert(f.cle == 2659 and f.etat == "pret" and f.n == 13 and T(f) == "Fabriquer 26 × " .. nom(2841), T(f))
  assert(f.id == 2841 and C(f) == nom(2841) .. " ×26", C(f)) -- f.id : la case cerclée ; 13 fontes de 2 barres
  -- Le bronze fondu : les Dory, mais le catalyseur manque (à acheter) ; rien n'est proposé.
  poser({ [2841] = 33 })
  f = ns.prochaineDuProjet(p, "Minage")
  assert(f.cle == 99101 and f.etat == "manque" and T(f) == "Il manque " .. nom(FLUX) .. " pour 4 × " .. nom(DORY), T(f))
  assert(C(f) == "Il manque " .. nom(FLUX), C(f))
  -- Acheté : la Forge à ouvrir ; ouverte sans enclume, le jeu le dit ; avec, on fabrique.
  poser({ [2841] = 33, [FLUX] = 16 })
  f = ns.prochaineDuProjet(p, "Minage")
  assert(f.etat == "ouvrir" and T(f) == "Ouvrir Forge : 4 × " .. nom(DORY), T(f))
  requis = { { name = "Enclume", met = false } }
  f = ns.prochaineDuProjet(p, "Forge")
  assert(f.cle == 99101 and f.etat == "manque" and T(f) == "Il manque Enclume pour 4 × " .. nom(DORY), T(f))
  assert(C(f) == "Il manque Enclume", C(f))
  requis, faisable[99101] = {}, 4
  f = ns.prochaineDuProjet(p, "Forge")
  assert(f.etat == "pret" and T(f) == "Fabriquer 4 × " .. nom(DORY), T(f))
  -- Les 4 Dory en sac : tout est fait.
  poser({ [DORY] = 4 })
  local fini
  f, fini = ns.prochaineDuProjet(p, "Forge")
  assert(f == nil and fini and T(f, fini) == "Tout est fabriqué", T(f, fini))
  assert(ns.projetFini(ns.projetArbre(p)), "fini : la ligne du projet le dit")
  -- Sacs vides : rien de proposé, la première fabrication dit ce qui lui manque.
  poser({})
  f = ns.prochaineDuProjet(p, "Minage")
  assert(f.cle == 3304 and f.etat == "manque" and T(f) == "Il manque " .. nom(2771) .. " pour 16 × " .. nom(3576), T(f))
  assert(not ns.projetFini(ns.projetArbre(p)), "pas fini")
  assert(C({ etat = "inconnue", recette = {} }) == "Recette inconnue : ?" and C({ etat = "manque", recette = {} }) == "Il manque un composant")
  assert(C({ etat = "pret", fois = 3, recette = { name = "Enchanter le plastron" } }) == "Enchanter le plastron ×3", "un enchantement : sa recette")
  assert(C(nil) == "Rien à fabriquer")
  -- Un projet vide : rien à fabriquer.
  f, fini = ns.prochaineDuProjet(Composants.NouveauProjet({ name = "Vide" }), nil)
  assert(f == nil and not fini and T(f, fini) == "Rien à fabriquer", T(f, fini))
  assert(not ns.projetFini(ns.projetArbre(Composants.NouveauProjet({ name = "Vide 2" }))), "vide : pas « fini »")
  -- En cours : l'avancement, en objets.
  assert(T(nil, nil, { nom = "Barre de bronze", per = 2, n = 13, fait = 2 }) == "Barre de bronze 4/26…")
  assert(C(nil, { nom = "Barre de bronze", per = 2, n = 13, fait = 2 }) == "Barre de bronze 4/26…")
  -- La barre en crans, un par fabrication ; au-delà de 20, une barre continue (les séparations ne se liraient plus).
  assert(ns.crans(13) == 13 and ns.crans(20) == 20 and ns.crans(21) == 0, "13 fontes : 13 crans ; 21 : aucun")
  -- Le remplissage : les fabrications finies, plus le cran en cours au rythme de l'incantation du jeu (UnitCastingInfo).
  local A, e, gt = ns.avancement, { cle = 2659, n = 13, fait = 4 }, GetTime
  local proche = function(a, b) return math.abs(a - b) < 1e-9 end
  assert(proche(A(e), 4 / 13), "sans incantation : 4 crans pleins")
  GetTime = function() return 10 end
  UnitCastingInfo = function() return "Fonte du bronze", "", nil, 9000, 11000, true, 7, false, 2659 end
  assert(proche(A(e), 4.5 / 13), "à mi-incantation : le 5e cran à moitié, " .. A(e) * 13)
  issecretvalue = function(v) return v == 9000 end
  assert(proche(A(e), 4 / 13), "début secret : le cran se remplit à la fin")
  issecretvalue = function(v) return v == 2659 end
  assert(proche(A(e), 4 / 13), "sort secret : idem")
  issecretvalue = nil
  UnitCastingInfo = function() return "Autre", "", nil, 9000, 11000, false, 7, false, 1234 end
  assert(proche(A(e), 4 / 13), "une autre incantation : pas la nôtre")
  UnitCastingInfo = function() return nil end
  assert(proche(A(e), 4 / 13), "incantation absente")
  e.fait = 13
  assert(A(e) == 1, "tout fait : pleine")
  GetTime, UnitCastingInfo = gt, nil
  C_TradeSkillUI, C_Item.GetItemCount = nil, nil
  commune.Conteneurs, AzerothCommuneDB.chars = realContainers, {}
end
print("Composants : la prochaine fabrication du projet affiché, le bouton d'action OK")

-- L'infobulle des objets (#16) : « Utilisé dans » (les projets dont l'arbre le demande) et « Fabriqué par » (mes persos qui
-- connaissent une recette qui le fabrique), rien pour un objet qui n'entre dans rien ; le cache suit les projets.
do
  local ALT = "Player-6942-00000A17"
  local function prix(pc) return { tiers = { { price = pc, qty = 999 } } } end
  donnees({ hv = { [2840] = prix(100), [3576] = prix(10), [2770] = prix(2), [2841] = prix(1000) },
    recettes = {
      [2659] = { name = "Fonte du bronze", output = 2841, made_min = 2, profession = "Minage", reagents = { { id = 2840, qty = 1 }, { id = 3576, qty = 1 } } },
      [2657] = { name = "Fonte du cuivre", output = 2840, profession = "Minage", reagents = { { id = 2770, qty = 1 } } } },
    persos = { [ALT] = { nom = "Alt Dupont", recipes = { Minage = { rank = 75, known = { [2659] = true } } } } } })
  AzerothCommuneDB.chars[MOI].recipes = { Minage = { rank = 75, known = { [2657] = true } } }
  local avant = ns.db().projets
  ns.db().projets = {} -- les projets des tests précédents rendus à la fin
  local p = Composants.NouveauProjet({ name = "Armure en bronze", lines = { { id = 2841, qty = 4 } } })
  local function texte(id) return table.concat(ns.lignesInfobulle(id), " | ") end
  assert(texte(2841):find("Utilisé dans : [^|]*Armure en bronze") and texte(2841):find("Fabriqué par : Alt$"), texte(2841))
  assert(texte(2770):find("Armure en bronze") and not texte(2770):find("Fabriqué par"), "le minerai : dans l'arbre, personne ne le fabrique")
  assert(texte(2840):find("Fabriqué par : Moi$"), texte(2840))
  assert(#ns.lignesInfobulle(99999) == 0, "un objet qui n'entre dans rien : aucune ligne")
  -- Le projet change (son nom, ses lignes) : le cache suit, par le signal des projets.
  Composants.Renommer(p, "Cuirasse")
  assert(texte(2841):find("Cuirasse") and not texte(2841):find("Armure en bronze"), texte(2841))
  Composants.Supprimer(p.id)
  assert(not texte(2770):find("Cuirasse"), "projet supprimé : plus dans l'infobulle")
  -- Au-delà de 3 projets : les 3 premiers, puis « +N ».
  for i = 1, 5 do Composants.NouveauProjet({ name = "P" .. i, lines = { { id = 2770, qty = 1 } } }) end
  assert(texte(2770) == "Utilisé dans : P1, P2, P3 +2", texte(2770))
  ns.db().projets = avant
  commune.Conteneurs, AzerothCommuneDB.chars = realContainers, {}
end
print("Composants : infobulle des objets OK")

-- La TOC : catégorie Métiers, le socle requis (rien d'autre), ses données propres ; jamais tests/ ni check.lua.
assert(TOC:find("\n## Title: Composants\n", 1, true) and TOC:find("\n## Category: Professions\n## Category-frFR: Métiers\n", 1, true), "titre, catégorie")
assert(TOC:find("\n## Notes: Chaque objet décomposé en ses composants, jusqu'aux matières premières : l'arbre, vos projets, ce qu'il reste à réunir.\n", 1, true), "notes")
assert(TOC:find("\n## Dependencies: AzerothCommune\n## SavedVariables: ComposantsDB\n", 1, true), "dépendances : le socle seul")
assert(not TOC:find("tests/", 1, true) and not TOC:find("check", 1, true), "ni tests ni check dans la TOC")
assert(SlashCmdList.COMPOSANTS and SLASH_COMPOSANTS1 == "/composants" and SLASH_COMPOSANTS2 == "/compo", "/composants, /compo")
-- Composants ne connaît pas Handshake (ni contrat, ni autre joueur) : c'est Handshake qui se branche sur l'emplacement du bloc.
for f in TOC:gmatch("([%w_]+)%.lua") do
  local code = io.open("Composants/" .. f .. ".lua"):read("*a"):gsub("%-%-[^\n]*", "")
  assert(not code:find("Handshake", 1, true) and not code:lower():find("contrat", 1, true), f .. ".lua parle de Handshake ou de contrats")
end
-- ComposantsDB : réglages par défaut, des projets, rien de relevé.
local d = ns.db()
assert(d.options.bags and d.options.bank and not d.options.alts and not d.options.unlearned and #d.projets > 0, "réglages par défaut")
aucunReleve("à la fin")
print("Composants : TOC, données propres OK")
