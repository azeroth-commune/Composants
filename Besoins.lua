-- Composants, les Besoins (CONTEXT.md) : ce qu'il faut avoir dans les sacs pour fabriquer le projet affiché, la vue de sa
-- phase Réunir ; une petite fenêtre verticale, qui prend le coin de la grande (ns.montrerVue, Fenetre.lua), le fil en haut.
-- Chaque projet a ses Besoins et compte le stock comme s'il était seul. Une ligne avance quand l'objet arrive dans les sacs ;
-- ce qui est à la banque ou chez un autre perso dit où le trouver, sans compter comme réuni ; coche verte quand tout est
-- dans les sacs. Tout réuni : le projet passe tout seul en Fabriquer et la grande vue revient. En dessous, ce qu'apportent
-- les commandes Handshake (quand il est là), puis les recettes pas encore apprises. HV ouvert : clic sur une ligne = la
-- chercher à l'HV. Une ligne qui manque encore porte sa bascule « Achat » / « Récolte » ; ce qui reste à acheter devient, à
-- chaque ouverture de l'HV, la liste d'achats d'Auctionator « Besoins (Composants) » (#18), celle du projet affiché.
local _, ns = ...

-- L'arbre des Besoins de p : options de la fenêtre (ou opts), ses apports Handshake ; les sacs y comptent toujours, même
-- « Déduire mes sacs » décoché (réunir, c'est les avoir dans les sacs).
function ns.besoinsArbre(p, opts)
  local o = {}
  for k, v in pairs(opts or ns.db().options) do o[k] = v end
  o.bags = true
  return ns.projetArbre(p, o, ns.apportsHandshake(p))
end

-- Réuni (Phase, CONTEXT.md) : chaque ligne des Besoins est dans les sacs ; la banque et les autres persos ne comptent pas.
-- C'est la condition de Réunir → Fabriquer (ns.avancerPhase, Projet.lua). ponytail: les contrats Handshake clos s'y
-- ajouteront ici (Composants#26, #27).
local function reuni(p, res)
  if #p.lines == 0 then return false end
  for _, r in ipairs((ns.orderNeeds(res))) do if r.have[1] < r.required then return false end end
  return true
end
function ns.toutReuni(p, opts) return reuni(p, ns.besoinsArbre(p, opts)) end

-- La Récolte (CONTEXT.md) : les objets des Besoins que le joueur compte récolter plutôt qu'acheter, pour tous ses
-- projets : ComposantsDB.recolte = { [itemID] = true } ; sans choix, l'objet est à acheter.
local function recoltes()
  local d = ns.db()
  d.recolte = d.recolte or {}
  return d.recolte
end
function ns.estRecolte(id) return recoltes()[id] == true end
function ns.basculerRecolte(id)
  local t = recoltes()
  t[id] = (not t[id]) or nil
  ns.besoinsChanges()
end

-- Ce que les Besoins font acheter à l'HV : les lignes qui manquent encore (besoin − ce qu'on a), sauf la Récolte et ce
-- qu'un marchand vend. { { id, qty }, … } dans l'ordre des Besoins.
function ns.achatsHV(rows)
  local out = {}
  for _, r in ipairs(rows) do
    if r.need > 0 and r.how ~= "marchand" and not ns.estRecolte(r.id) then out[#out + 1] = { id = r.id, qty = r.need } end
  end
  return out
end

-- La liste d'achats d'Auctionator « Besoins (Composants) », réécrite à chaque ouverture de l'HV (son API remplace une
-- liste du même nom) : on la lance, l'HV ne montre que ces objets, avec la quantité qui manque. Recherche exacte par le
-- nom du client (en français). Sans Auctionator, rien. Une liste vide n'est pas créée, mais une ancienne est vidée.
-- Elle suit les Besoins du projet affiché (le Brouillon n'entre dans aucuns Besoins : rien). HV ouvert, elle suit aussi en
-- direct les modifications faites dans Composants (bascule, quantités, choix de case, autre projet affiché), seulement si
-- elle change : Auctionator déplie la liste à chaque réécriture. Pas sur les
-- changements de sacs : un achat en cours ne doit pas voir son écran sauter ; ils comptent à l'ouverture suivante.
ns.LISTE_AUCTIONATOR = "Besoins (Composants)"
local derniere -- la dernière liste écrite (ses termes joints)
function ns.pousserAuctionator(siChange)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.CreateShoppingList and api.ConvertToSearchString) then return end
  local termes = {}
  local p = #ns.db().projets > 0 and ns.projetCourant() -- (sans projet, pas d'appel qui en créerait un vide)
  local rows = p and not ns.estBrouillon(p) and ns.orderNeeds(ns.besoinsArbre(p)) or {}
  for _, a in ipairs(ns.achatsHV(rows)) do
    local it = ns.items()[a.id]
    local nom = (it and it.name) or C_Item.GetItemInfo(a.id)
    if nom then termes[#termes + 1] = api.ConvertToSearchString("Composants", { searchString = nom, isExact = true, quantity = a.qty }) end
  end
  local cle = table.concat(termes, "^")
  if siChange and cle == derniere then return #termes end
  if #termes == 0 and not pcall(api.GetShoppingListItems, "Composants", ns.LISTE_AUCTIONATOR) then return 0 end
  api.CreateShoppingList("Composants", ns.LISTE_AUCTIONATOR, termes)
  derniere = cle
  return #termes
end
function ns.besoinsChanges()
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
  local ok, err = pcall(ns.pousserAuctionator, true)
  if not ok then geterrorhandler()(err) end
end
ns.quandChange(function() ns.besoinsChanges() end) -- un projet modifié (Projet.lua, chargé avant)
do
  local f = CreateFrame("Frame")
  f:RegisterEvent("AUCTION_HOUSE_SHOW")
  f:SetScript("OnEvent", function()
    local ok, err = pcall(ns.pousserAuctionator)
    if not ok then geterrorhandler()(err) end
  end)
end

-- L'objet qui apprend une recette : « Plans : Claymore en mithril », « Formule : … », « Patron : … ».
-- ponytail: par le nom, faute de lien recette -> objet dans les données ; nil si jamais vu
local recipeItems = {}
function ns.recipeItem(name)
  if recipeItems[name] ~= nil then return recipeItems[name] or nil end
  local found = false
  for id, it in pairs(ns.items()) do
    local n = it.name
    if n and #n > #name and n:sub(-#name) == name and n:sub(1, #n - #name):find(":%s*$") then found = id break end
  end
  recipeItems[name] = found
  return found or nil
end

-- La liste des besoins : ce qui ne se fabrique pas dans l'arbre (acheté ou déjà en stock, même la part en stock d'une case
-- en partie fabriquée ; pas ce qu'une commande apporte), avec combien il en faut et combien on en a, une ligne par objet
-- (ligne du projet et composant d'une autre additionnés) ; puis les recettes pas apprises, une fois chacune.
function ns.orderNeeds(res)
  local rows, recipes, rowOf, seen = {}, {}, {}, {}
  for _, n in ipairs(res.cases) do
    local required = n.qty - n.made
    if required > 0 and (n.apport or 0) == 0 then
      local r = rowOf[n.id]
      if not r then
        r = { id = n.id, required = 0, have = { 0, 0, 0 }, need = 0, cost = 0 }
        rowOf[n.id], rows[#rows + 1] = r, r
      end
      r.required, r.need, r.cost = r.required + required, r.need + n.need, r.cost + (n.cost or 0)
      for i = 1, 3 do r.have[i] = r.have[i] + n.have[i] end
      r.unpriced, r.how = r.unpriced or n.unpriced, n.how or r.how
    end
    if n.made > 0 and n.unknown and n.recipe and not seen[n.recipe.name] then
      seen[n.recipe.name] = true
      recipes[#recipes + 1] = { name = n.recipe.name, item = ns.recipeItem(n.recipe.name), product = n.id }
    end
  end
  table.sort(rows, function(a, b)
    if (a.need > 0) ~= (b.need > 0) then return a.need > 0 end
    return a.id < b.id
  end)
  return rows, recipes
end

local W, ROW = 420, 28 -- 420 : la place de la bascule « Achat » / « Récolte »
local LARGE = W - 50 -- largeur d'une ligne, la barre de défilement à droite
local HAUT_MAX = 520 -- au-delà, la liste défile (retour de Virgile : elle dépassait de l'écran)
local COLORS = { { 0.35, 0.80, 0.45 }, { 0.35, 0.60, 1.00 }, { 0.66, 0.56, 1.00 } }
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local frame, rows, used = nil, {}, 0

-- Met le nom dans la recherche de l'HV et la lance. On ne change jamais d'onglet nous-mêmes : un onglet ouvert
-- par un addon bloque ensuite les clics du jeu (vu chez Mastercraft) ; hors de l'onglet Acheter, le nom attend.
local function ahSearch(id)
  local ah = AuctionHouseFrame
  local bar = ah and ah:IsShown() and ah.SearchBar
  if not bar then return print("Composants : ouvre l'hôtel des ventes, puis clique sur la ligne.") end
  local it = ns.items()[id]
  local name = (it and it.name) or C_Item.GetItemInfo(id)
  if not name then return end
  bar:SetSearchText(name)
  if ah.GetDisplayMode and AuctionHouseFrameDisplayMode and ah:GetDisplayMode() ~= AuctionHouseFrameDisplayMode.Buy then
    return print("Composants : « " .. name .. " » est dans la recherche ; reviens sur l'onglet Acheter et lance-la.")
  end
  bar:StartSearch()
end

local function newRow()
  local r = CreateFrame("Button", nil, frame.contenu)
  r:SetSize(LARGE, ROW)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.icon:SetPoint("TOPLEFT", 0, -2)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("TOPLEFT", 26, -4)
  r.text:SetPoint("RIGHT", -90, 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.count:SetPoint("TOPRIGHT", 0, -4)
  r.bg = r:CreateTexture(nil, "ARTWORK")
  r.bg:SetColorTexture(1, 1, 1, 0.08)
  r.bg:SetPoint("BOTTOMLEFT", 26, 4)
  r.bg:SetSize(LARGE - 26, 4)
  r.seg = {}
  for i = 1, 4 do r.seg[i] = r:CreateTexture(nil, "OVERLAY") end
  r:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    if self.info then GameTooltip:AddLine(self.info, 0.8, 0.8, 0.8, true) end
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then GameTooltip:AddLine("Clic : chercher à l'HV", 0.66, 0.56, 1) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- La bascule « Achat » / « Récolte » d'une ligne qui manque encore : l'état se lit sur le bouton, un clic le change.
  r.mode = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.mode:SetSize(70, 20)
  r.mode:SetPoint("TOPRIGHT", 0, -1)
  r.mode:SetScript("OnClick", function(b)
    ns.basculerRecolte(b:GetParent().itemID)
    ns.refreshNeeds()
    if b:IsMouseOver() then b:GetScript("OnEnter")(b) end
  end)
  r.mode:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if ns.estRecolte(b:GetParent().itemID) then
      GameTooltip:SetText("Tu le récoltes")
      GameTooltip:AddLine("Clic : l'acheter (il entre dans la liste d'Auctionator)", 0.66, 0.56, 1)
    else
      GameTooltip:SetText("Tu l'achètes")
      GameTooltip:AddLine("Clic : le récolter (il sort de la liste d'Auctionator)", 0.66, 0.56, 1)
    end
    GameTooltip:Show()
  end)
  r.mode:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self) if self.itemID then ahSearch(self.itemID) end end)
  return r
end

local function line(icon, text, count, itemID, info, have, required, missingColor)
  used = used + 1
  local r = rows[used] or newRow()
  rows[used] = r
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", 14, -frame.y)
  r.icon:SetTexture(icon)
  r.icon:SetShown(icon ~= nil)
  r.text:SetText(text)
  r.count:SetText(count or "")
  r.itemID, r.info = itemID, info
  r.mode:Hide()
  r.count:ClearAllPoints(); r.count:SetPoint("TOPRIGHT", 0, -4)
  r.text:SetPoint("RIGHT", -90, 0)
  local left, wmax = 26, LARGE - 26
  local parts = have and { have[1], have[2], have[3], math.max(0, required - have[1] - have[2] - have[3]) } or {}
  r.bg:SetShown(have ~= nil)
  for i = 1, 4 do
    local wpx = have and required > 0 and wmax * parts[i] / required or 0
    local seg = r.seg[i]
    if wpx >= 1 then
      local c = COLORS[i] or missingColor
      seg:SetColorTexture(c[1], c[2], c[3], 0.9)
      seg:ClearAllPoints()
      seg:SetPoint("BOTTOMLEFT", left, 4)
      seg:SetSize(wpx, 4)
      seg:Show()
      left = left + wpx
    else
      seg:Hide()
    end
  end
  r:Show()
  frame.y = frame.y + ROW
end

-- La bascule sur la ligne qui vient d'être posée.
local function bascule(recolte)
  local r = rows[used]
  r.mode:SetText(recolte and "Récolte" or "Achat")
  r.mode:Show()
  r.count:ClearAllPoints(); r.count:SetPoint("RIGHT", r.mode, "LEFT", -6, 0)
  r.text:SetPoint("RIGHT", -170, 0)
end

local function title(text)
  used = used + 1
  local r = rows[used] or newRow()
  rows[used] = r
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", 14, -frame.y)
  r.icon:Hide(); r.bg:Hide()
  for i = 1, 4 do r.seg[i]:Hide() end
  r.text:SetText("|cffffd100" .. text .. "|r")
  r.count:SetText("")
  r.itemID = nil
  r.mode:Hide()
  r.count:ClearAllPoints(); r.count:SetPoint("TOPRIGHT", 0, -4)
  r:Show()
  frame.y = frame.y + 22
end

-- Où trouver ce qui n'est pas dans les sacs : « banque 3 · autres persos 2 », en couleur de leur part de la barre.
local function ouTrouver(r)
  local t = {}
  if r.have[2] > 0 then t[#t + 1] = ("|cff5999ffbanque %d|r"):format(r.have[2]) end
  if r.have[3] > 0 then t[#t + 1] = ("|cffa98fffautres persos %d|r"):format(r.have[3]) end
  return #t > 0 and table.concat(t, " · ") or nil
end

function ns.refreshNeeds()
  if not (frame and frame:IsShown()) then return end
  local p = ns.projetCourant()
  -- La vue de Réunir seulement : un projet passé dans une autre phase (remis en Préparer, ou tout réuni : Fabriquer tout
  -- seul), la vue de sa phase prend la place.
  if ns.phase(p) ~= "reunir" then return ns.montrerVue() end
  local res = ns.besoinsArbre(p)
  if reuni(p, res) then
    ns.projetPhase(p, "fabriquer")
    return ns.montrerVue()
  end
  local list, recipes = ns.orderNeeds(res)
  used, frame.y = 0, 0
  frame.head:SetText("Besoins · " .. (p.name or "?"))
  frame.syncFil()

  title("Dans tes sacs")
  local done, buy = 0, 0
  for _, r in ipairs(list) do
    local complete = r.have[1] >= r.required
    if complete then done = done + 1 end
    local manque = r.need > 0 -- ni dans les sacs, ni à la banque, ni ailleurs : à acheter ou à récolter
    local recolte = manque and ns.estRecolte(r.id)
    local count = complete and (READY .. " " .. r.required) or ("%d/%d"):format(r.have[1], r.required)
    if recolte then
      count = "|cff88ccffà récolter|r  " .. count -- ni prix ni total : ce n'est pas de l'or à dépenser
    elseif manque then
      count = (r.unpriced and "|cffe64d4dsans prix|r  " or (ns.moneyShort(r.cost) .. "  ")) .. count
      buy = buy + (r.cost or 0)
    end
    local ou = not complete and ouTrouver(r)
    local info = ("Il en faut %d, %d dans tes sacs"):format(r.required, r.have[1])
    if ou then info = info .. "\nÀ prendre : " .. ou end
    if recolte then info = info .. ("\nReste %d à récolter"):format(r.need)
    elseif manque then info = info .. (r.unpriced and "\nNi prix ni recette" or ("\nReste %d à %s"):format(r.need, r.how == "marchand" and "acheter au marchand" or "acheter à l'HV")) end
    line(C_Item.GetItemIconByID(r.id), ns.itemLabel(r.id) .. (ou and ("  " .. ou) or ""), count, r.id, info, r.have, r.required,
      (recolte and { 0.53, 0.8, 1 }) or (r.unpriced and { 0.9, 0.3, 0.3 }) or { 0.6, 0.6, 0.62 })
    if manque then bascule(recolte) end
  end
  if #list == 0 then title("|cff999999Rien à réunir : tout se fabriquera avec ce que tu as.|r") end
  local brought = {}
  for _, n in ipairs(res.cases) do
    if (n.apport or 0) > 0 then brought[#brought + 1] = { id = n.id, qty = n.apport } end
  end
  table.sort(brought, function(a, b) return a.id < b.id end)
  if #brought > 0 then
    frame.y = frame.y + 6
    title("Tu apportes")
    for _, a in ipairs(brought) do
      local have = C_Item.GetItemCount and C_Item.GetItemCount(a.id) or 0
      line(C_Item.GetItemIconByID(a.id), ns.itemLabel(a.id), have >= a.qty and (READY .. " " .. a.qty) or ("%d/%d"):format(have, a.qty),
        a.id, "Dans tes sacs : " .. have, { math.min(have, a.qty), 0, 0 }, a.qty, { 0.30, 0.80, 0.85 })
    end
  end

  if #recipes > 0 then
    frame.y = frame.y + 6
    title("Recettes à apprendre")
    for _, r in ipairs(recipes) do
      local text = r.item and ns.itemLabel(r.item) or ("Recette : " .. r.name .. " |cff999999(objet jamais vu)|r")
      line(C_Item.GetItemIconByID(r.item or r.product), text, "à trouver", r.item or r.product, "Pour fabriquer " .. ns.itemLabel(r.product))
    end
  end
  for i = used + 1, #rows do rows[i]:Hide() end

  local foot = ("%d/%d dans les sacs"):format(done, #list)
  if buy > 0 then foot = foot .. " · à acheter : " .. ns.moneyShort(buy) end
  frame.foot:SetText(foot)
  frame.contenu:SetHeight(math.max(1, frame.y))
  frame:SetHeight(math.min(frame.y + 108, HAUT_MAX))
end

local function build()
  frame = ns.newWindow("ComposantsBesoinsFrame", "Besoins", W, 200)
  frame:ClearAllPoints()
  frame:SetPoint("TOPRIGHT", -60, -160) -- à côté, pas par-dessus la fenêtre des projets
  frame.title:SetText("")
  frame.head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.head:SetPoint("TOPLEFT", 14, -12)
  frame.syncFil = ns.fil(frame, 14, -38) -- le fil (Fenetre.lua), sous le nom du projet
  frame.head:SetPoint("RIGHT", -60, 0)
  frame.head:SetJustifyH("LEFT")
  frame.head:SetWordWrap(false)
  frame.foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.foot:SetPoint("BOTTOMLEFT", 14, 14)
  -- La liste défile au-delà de HAUT_MAX (molette ou barre).
  frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  frame.scroll:SetPoint("TOPLEFT", 0, -68)
  frame.scroll:SetPoint("BOTTOMRIGHT", -28, 34)
  frame.contenu = CreateFrame("Frame", nil, frame.scroll)
  frame.contenu:SetSize(LARGE + 14, 1)
  frame.scroll:SetScrollChild(frame.contenu)
  local pending
  frame:RegisterEvent("BAG_UPDATE_DELAYED")
  frame:SetScript("OnEvent", function()
    if pending or not frame:IsShown() then return end
    pending = true
    C_Timer.After(1, function() pending = false; ns.refreshNeeds() end)
  end)
  frame:SetScript("OnShow", function() ns.refreshNeeds() end)
end

-- La fenêtre des Besoins (faite au premier appel) ; ns.montrerVue (Fenetre.lua) la montre ou la cache.
function ns.besoinsFenetre()
  if not frame then build() end
  return frame
end
