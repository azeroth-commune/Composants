-- Composants, la barre de recherche d'objets de la fenêtre des projets (sur la recherche du socle, AzerothCommune.ChercherObjets).
-- ponytail: copie de celle de la commande à la main de Handshake (les deux add-ons ne se requièrent pas) ; deux add-ons
-- s'en servent, elle peut monter dans le socle à côté d'AzerothCommune.ChercherObjets (une issue à ouvrir là-bas).
local _, ns = ...

-- Un objet pris dans les sacs (au curseur) et déposé sur f : il est rendu à son sac et onObjet(id) le reçoit.
function ns.recevoirObjet(f, onObjet)
  local function depose()
    local kind, id = GetCursorInfo()
    if kind ~= "item" then return end
    ClearCursor()
    onObjet(id)
  end
  f:EnableMouse(true)
  f:SetScript("OnReceiveDrag", depose)
  f:HookScript("OnMouseUp", depose)
end

-- Barre de recherche avec suggestions (la recherche d'objets du socle, AzerothCommune#49) : flèches haut/bas, Entrée ou
-- Tab pour choisir, ou clic ; un objet déposé sur le champ l'ajoute aussitôt. onPick(id, quantité).
-- Maj+clic n'est pas pris : dans le jeu, il sépare une pile ou colle le lien dans la discussion.
-- w = largeur du champ (280 par défaut).
function ns.rechercheObjets(parent, qty, onPick, w)
  w = w or 280
  local name = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  name:SetSize(w, 22)
  name:SetAutoFocus(false)
  name.recherche = true
  local drop = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  drop:SetPoint("TOPLEFT", name, "BOTTOMLEFT", -6, -2)
  drop:SetSize(w + 40, 10)
  drop:SetFrameStrata("DIALOG")
  drop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  drop:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
  drop:SetBackdropBorderColor(0.66, 0.56, 1.00, 0.35)
  drop:Hide()
  local buttons, hits, sel = {}, {}, 1
  local function qtyValue() return math.max(1, tonumber(qty:GetText()) or 1) end
  local function pick(e)
    onPick(e.id, qtyValue())
    name:SetText("")
    name:ClearFocus()
    drop:Hide()
  end
  local function paint()
    for i, b in ipairs(buttons) do b.hl:SetShown(i == sel) end
  end
  for i = 1, 8 do
    local b = CreateFrame("Button", nil, drop)
    b:SetSize(w + 36, 20)
    b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(0.66, 0.56, 1.00, 0.18)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 4, 0)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 24, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function() sel = i; paint() end)
    b:SetScript("OnClick", function() if hits[i] then pick(hits[i]) end end)
    buttons[i] = b
  end
  local function update()
    hits, sel = ns.chercherObjets(name:GetText(), 8), 1
    for i, b in ipairs(buttons) do
      local e = hits[i]
      b:SetShown(e ~= nil)
      if e then
        b.icon:SetTexture(C_Item.GetItemIconByID(e.id))
        b.text:SetText(e.name .. (e.fabricable and "  |cffe6a640fabricable|r" or ""))
      end
    end
    drop:SetHeight(4 + 20 * #hits)
    drop:SetShown(#hits > 0)
    paint()
  end
  local function submit()
    if drop:IsShown() and hits[sel] then return pick(hits[sel]) end
    local id = ns.findItem(name:GetText() or "")
    if not id then return print("Composants : objet introuvable (nom exact, lien ou ID).") end
    pick({ id = id })
  end
  name:SetScript("OnTextChanged", function(_, userInput) if userInput then update() end end)
  name:SetScript("OnEditFocusLost", function() C_Timer.After(0.2, function() drop:Hide() end) end) -- laisse passer le clic
  name:SetScript("OnEscapePressed", function(self) drop:Hide(); self:ClearFocus() end)
  name:SetScript("OnEnterPressed", submit)
  name:SetScript("OnTabPressed", function() if hits[sel] then pick(hits[sel]) end end)
  name:SetScript("OnArrowPressed", function(_, key)
    if not drop:IsShown() then return end
    if key == "DOWN" then sel = math.min(#hits, sel + 1) elseif key == "UP" then sel = math.max(1, sel - 1) end
    paint()
  end)
  qty:SetScript("OnEnterPressed", submit)
  ns.recevoirObjet(name, function(id) onPick(id, qtyValue()) end)
  return name, submit
end
