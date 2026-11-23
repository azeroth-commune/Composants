-- Composants, les Besoins (CONTEXT.md) : les objets à réunir pour les projets qu'on y a mis, puis le Brouillon, sur un
-- seul stock ; une petite fenêtre à garder ouverte pendant qu'on rassemble. Chaque ligne avance quand l'objet arrive dans
-- les sacs (ou la banque, les autres persos, selon les options) ; coche verte quand c'est complet. En dessous, ce
-- qu'apportent les commandes Handshake (quand il est là), puis les recettes pas encore apprises. HV ouvert : clic sur une
-- ligne = la chercher à l'HV.
local _, ns = ...

-- Les projets mis dans les Besoins : ComposantsDB.besoins = { identités }, dans l'ordre où on les y a mis (il décide à qui
-- va le stock). Le Brouillon n'y est jamais rangé : il y compte toujours, en dernier.
local function ids()
  local d = ns.db()
  d.besoins = d.besoins or {}
  return d.besoins
end
function ns.dansBesoins(p)
  for _, id in ipairs(ids()) do if id == p.id then return true end end
  return ns.estBrouillon(p)
end
function ns.besoinsMettre(p)
  if not ns.dansBesoins(p) then table.insert(ids(), p.id) end
end
function ns.besoinsRetirer(p)
  local t = ids()
  for i = #t, 1, -1 do if t[i] == p.id then table.remove(t, i) end end
end
-- Les projets des Besoins dans leur ordre, le Brouillon en dernier s'il a des lignes ; un projet supprimé en sort.
function ns.besoinsProjets()
  local t, out = ids(), {}
  for i = #t, 1, -1 do if not ns.projet(t[i]) then table.remove(t, i) end end
  for _, id in ipairs(t) do out[#out + 1] = ns.projet(id) end
  if #ns.brouillon().lines > 0 then out[#out + 1] = ns.brouillon() end
  return out
end
-- L'arbre des Besoins : les projets enchaînés sur un seul stock, chacun avec ses choix de case et ses apports Handshake.
function ns.besoinsArbre(opts)
  local projets, apports = ns.besoinsProjets(), {}
  for _, p in ipairs(projets) do apports[p] = ns.apportsHandshake(p) end
  return ns.arbreDe(projets, opts, apports)
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

-- La liste des besoins : ce qui ne se fabrique pas dans l'arbre (acheté ou déjà en stock ; pas ce qu'une commande
-- apporte), avec combien il en faut et combien on en a, une ligne par objet (ligne d'un projet et composant d'un autre
-- additionnés) ; puis les recettes pas apprises, une fois chacune.
function ns.orderNeeds(res)
  local rows, recipes, rowOf, seen = {}, {}, {}, {}
  for _, n in ipairs(res.cases) do
    local required = n.qty - n.made
    if required > 0 and (n.made == 0 or n.need > 0) and (n.apport or 0) == 0 then
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

local W, ROW = 380, 28
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
    if self.projet then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.projet.name or "?")
      GameTooltip:AddLine("Clic : retirer ce projet des Besoins", 0.66, 0.56, 1)
      GameTooltip:Show()
      return
    end
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    if self.info then GameTooltip:AddLine(self.info, 0.8, 0.8, 0.8, true) end
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then GameTooltip:AddLine("Clic : chercher à l'HV", 0.66, 0.56, 1) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self)
    if self.projet then -- un projet des Besoins : il en sort (le Brouillon n'a pas cette ligne cliquable)
      ns.besoinsRetirer(self.projet)
      ns.refreshNeeds()
      if ns.refreshCraftWindow then ns.refreshCraftWindow() end
    elseif self.itemID then ahSearch(self.itemID) end
  end)
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
  r.itemID, r.info, r.projet = itemID, info, nil
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
  r.itemID, r.projet = nil, nil
  r:Show()
  frame.y = frame.y + 22
end

function ns.refreshNeeds()
  if not (frame and frame:IsShown()) then return end
  local res = ns.besoinsArbre()
  local list, recipes = ns.orderNeeds(res)
  used, frame.y = 0, 0
  frame.head:SetText("Besoins")
  -- Les projets, dans l'ordre où le stock leur va ; clic sur l'un d'eux : il sort des Besoins (pas le Brouillon).
  for i, p in ipairs(res.projets) do
    title(("|cffbbbbbb%d. %s|r"):format(i, p.name or "?"))
    if not ns.estBrouillon(p) then rows[used].projet = p; rows[used].count:SetText("|cff888888retirer|r") end
  end
  if #res.projets == 0 then title("|cff999999« Mettre dans les Besoins » sur un projet ; le Brouillon y compte.|r") end
  frame.y = frame.y + 4

  title("À rassembler")
  local done, buy = 0, 0
  for _, r in ipairs(list) do
    local have = r.have[1] + r.have[2] + r.have[3]
    local complete = r.need == 0
    if complete then done = done + 1 end
    local count = complete and (READY .. " " .. r.required) or ("%d/%d"):format(have, r.required)
    if not complete then
      count = (r.unpriced and "|cffe64d4dsans prix|r  " or (ns.moneyShort(r.cost) .. "  ")) .. count
      buy = buy + (r.cost or 0)
    end
    local info = ("Il en faut %d : %d sacs, %d banque, %d autres persos"):format(r.required, r.have[1], r.have[2], r.have[3])
    if r.need > 0 then info = info .. (r.unpriced and "\nNi prix ni recette" or ("\nReste %d à %s"):format(r.need, r.how == "marchand" and "acheter au marchand" or "acheter à l'HV")) end
    line(C_Item.GetItemIconByID(r.id), ns.itemLabel(r.id), count, r.id, info, r.have, r.required, r.unpriced and { 0.9, 0.3, 0.3 } or { 0.6, 0.6, 0.62 })
  end
  if #list == 0 and #res.projets > 0 then title("|cff999999Rien : tout se fabriquera avec ce que tu as.|r") end
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

  local foot = ("%d/%d prêts"):format(done, #list)
  if buy > 0 then foot = foot .. " · à acheter : " .. ns.moneyShort(buy) end
  frame.foot:SetText(foot)
  frame.contenu:SetHeight(math.max(1, frame.y))
  frame:SetHeight(math.min(frame.y + 80, HAUT_MAX))
end

local function build()
  frame = ns.newWindow("ComposantsBesoinsFrame", "Besoins", W, 200)
  frame:ClearAllPoints()
  frame:SetPoint("TOPRIGHT", -60, -160) -- à côté, pas par-dessus la fenêtre des projets
  frame.title:SetText("")
  frame.head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.head:SetPoint("TOPLEFT", 14, -12)
  frame.head:SetPoint("RIGHT", -60, 0)
  frame.head:SetJustifyH("LEFT")
  frame.head:SetWordWrap(false)
  frame.foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.foot:SetPoint("BOTTOMLEFT", 14, 14)
  -- La liste défile au-delà de HAUT_MAX (molette ou barre).
  frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  frame.scroll:SetPoint("TOPLEFT", 0, -40)
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

function ns.toggleNeeds()
  if not frame then build() end
  frame:SetShown(not frame:IsShown())
end
-- Ouvre les Besoins (et les rafraîchit s'ils l'étaient déjà).
function ns.ouvrirBesoins()
  if not frame then build() end
  if frame:IsShown() then ns.refreshNeeds() else frame:Show() end
end
