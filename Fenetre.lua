-- Composants, la fenêtre (/composants) : la grande vue d'un projet, celle de ses phases Préparer, Fabriquer et Fini (la petite,
-- Réunir, est dans Besoins.lua ; une seule des deux visible, ns.montrerVue) ; le fil « Préparer › Réunir › Fabriquer » en
-- haut des deux. À gauche, la colonne des projets (le Brouillon en tête) ; le nom du projet en titre ; à droite, le fil, la ligne
-- d'ajout (Préparer seulement), son arbre par étages, et en bas un seul bouton d'action, qui suit la phase : « Lancer »,
-- la prochaine fabrication (Fabriquer.lua), « Clore ». En Fabriquer et Fini, l'arbre est en lecture seule. L'emplacement du
-- bloc (Composants.Emplacements, API.lua) : un autre add-on dessine dans chaque bloc et sur la ligne du projet, et un bloc
-- qu'il dit confié se réduit à une seule case ; Composants ne sait pas ce qu'il y dessine. Sans lui, rien de tout ça.
-- Colonne 0 : ce qu'on suit. Étage 1 : ce qu'il faut pour le fabriquer. Étage 2 : ce qu'il faut pour ces
-- composants, etc. Une seule case par objet : la barre de bronze du marteau et de la dague, c'est la même case,
-- rangée à l'étage le plus profond où elle sert.
-- Un objet est décomposé quand c'est moins cher d'après le dernier scan de l'HV ; « + » le décompose quand même,
-- « – » l'achète tout fait (clic encore = retour au calcul). Ce choix de case appartient au projet affiché.
-- Barre sous chaque case : vert = dans tes sacs, bleu = à ta banque, violet = chez tes autres persos,
-- orange = à fabriquer, gris = à acheter, rouge = ni prix ni recette (pas de légende : la bulle de la case le dit).
local _, ns = ...

local W, H_FEN = 720, 400 -- taille de départ et minimum (AzerothCommune.Fenetre) : le cas courant ; l'arbre se zoome pour tenir, la poignée pour un gros arbre
local COL_W, X0 = 180, 200 -- la colonne des projets, et le bord gauche de ce qui est à sa droite
local TOP_CONTENU = 30 -- le contenu commence sous la barre de titre du gabarit
-- Les tailles de l'arbre, passées à l'Arbre du socle (AzerothCommune.PlacerArbre) ; le haut (36) laisse la place
-- à la ligne du projet et au nom du premier artisan, l'écart entre deux bandes (28) à leur nom et à l'emplacement (haut de 16).
local NODE_W, NODE_H, TOP, MARGIN = 190, 42, 36, 10
local COLORS = {
  { 0.35, 0.80, 0.45 }, { 0.35, 0.60, 1.00 }, { 0.64, 0.21, 0.93 }, -- sacs, banque, autres persos (le violet épique du jeu)
  fabriquer = { 0.95, 0.65, 0.25 }, buy = { 0.60, 0.60, 0.62 }, none = { 0.90, 0.30, 0.30 }, target = { 1.00, 0.82, 0.00 },
  apport = { 0.30, 0.80, 0.85 },
}

local frame, arbre -- arbre : l'Arbre du socle (AzerothCommune.Arbre), sa toile qui défile
-- Le fournisseur des emplacements (API.lua), si ce projet en a : jamais un projet de passage (on n'y commande rien), qui ne
-- lui est donc jamais passé.
local function F(p) return not ns.estPassage(p) and ns.fournisseur or nil end
-- Appeler le fournisseur : une erreur chez lui ne casse pas la fenêtre (elle est signalée).
local function appel(fn, ...)
  local ok, r = pcall(fn, ...)
  if ok then return r end
  geterrorhandler()(r)
end
-- Demander au fournisseur (s'il est là pour p et a ce champ) : f[quoi](...) ; nil sans lui.
function ns.demander(p, quoi, ...)
  local f = F(p)
  if f and f[quoi] then return appel(f[quoi], ...) end
end
-- Le bloc (nil = le projet entier) est-il confié ?
local function confie(p, bloc) return ns.demander(p, "confie", p, bloc) and true or false end
-- Les blocs confiés de p, sur son arbre res : entier = le projet entier l'est ; confies = { [métier] = true }.
function ns.confies(p, res)
  local entier, confies = #res.roots > 0 and confie(p, nil), {}
  for _, grp in ipairs(res.blocs) do confies[grp.key] = confie(p, grp) or nil end
  return entier, confies
end
-- La part confiée (Besoins.lua) : les cases que le joueur n'a pas à réunir, { [case] = true } — tout l'arbre quand le
-- projet entier est confié, sinon les cases des blocs confiés et ce qui n'est fabriqué que pour eux (ns.reduire) ; sauf
-- ce que le joueur leur donne lui-même (aDonner), qui reste à réunir.
function ns.partConfiee(p, res)
  local entier, confies = ns.confies(p, res)
  local part = {}
  if entier then for _, n in ipairs(res.cases) do part[n] = true end
  else part = select(3, ns.reduire(res, confies)) end
  local donne = ns.demander(p, "aDonner", p) or {}
  -- Ce que le joueur donne, et ce qu'il lui faut pour le faire lui-même (sa case entière) : à réunir, comme les autres.
  local function rendre(n)
    if not part[n] then return end
    part[n] = nil
    for _, k in ipairs(n.children or {}) do rendre(k) end
  end
  for n in pairs(part) do if donne[n.id] then rendre(n) end end
  return part
end
-- Tout ce que le fournisseur a pris en charge pour p est-il arrivé ? Vrai sans lui (ou sans ce champ) ; une erreur chez
-- lui (signalée) : non.
function ns.closEmplacement(p)
  local f = F(p)
  if not (f and f.clos) then return true end
  return appel(f.clos, p) and true or false
end
-- Le projet affiché ; déclaré ici, avant toute fonction qui l'appelle (déclaré plus bas, une bulle d'étiquette de commande
-- appelait un « projet » global inexistant).
local function projet() return ns.projetCourant() end
-- Le fournisseur refuse-t-il Lancer ? Sa raison (« Lancer (<raison>) »), ou nil. Une erreur chez lui (signalée) : nil.
function ns.refusLancer(p)
  local r = ns.demander(p, "lancer", p)
  return type(r) == "string" and r or nil
end
-- Le fournisseur dit-il Fini lui-même ? true ou false (lui seul décide), nil (la règle de Composants : l'arbre plein et
-- clos ; aussi sans lui, sans ce champ, ou sur une erreur chez lui, signalée).
function ns.finiEmplacement(p)
  local r = ns.demander(p, "fini", p)
  if r == nil then return nil end
  return r and true or false
end
-- Les cases que le fournisseur dit fournies par un autre (nil sans lui) : elles sortent de l'arbre.
function ns.apportsEmplacement(p) return ns.demander(p, "apports", p) end
-- Couleur de chaque artisan, dans l'ordre de la liste (ton perso d'abord) ; rouge = personne ne sait le faire.
local CRAFTER_COLORS = { { 1.00, 0.82, 0.00 }, { 0.30, 0.80, 0.85 }, { 0.95, 0.65, 0.25 }, { 0.95, 0.45, 0.75 }, { 0.45, 0.85, 0.58 } }
-- Étiquettes des livraisons entre artisans : survol = la liste.
local orderTags = {}
local function bandName(b) return b == "reste" and "toi" or tostring(b) end
local function newOrderTag()
  local t = CreateFrame("Button", nil, arbre.toile, "TooltipBackdropTemplate") -- le fond des bulles du jeu, bord à la couleur du métier
  t:SetFrameLevel(arbre.toile:GetFrameLevel() + 5)
  t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t.text:SetPoint("LEFT", 6, 0)
  t.text:SetJustifyH("LEFT")
  t.text:SetWordWrap(false) -- tronquée au bord du dessin, par la fin (plus bas) ; la bulle dit tout
  t:SetScript("OnEnter", function(self)
    local o = self.order
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("Livraison : %s pour %s"):format(o.maker, bandName(o.client)))
    GameTooltip:AddLine(o.player and ("Par " .. o.player) or "Personne de ta liste n'a ce métier", 0.8, 0.8, 0.8)
    for _, id in ipairs(o.lines) do GameTooltip:AddLine(("%d× %s"):format(o.qty[id], ns.itemLabel(id)), 1, 1, 1) end
    GameTooltip:Show()
  end)
  t:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return t
end
-- Les zones de l'emplacement du bloc (API.lua) : des cadres vides que le fournisseur remplit à chaque dessin. Une bande
-- (haute de 16, sur une ligne de titre ; le fournisseur règle sa largeur) ou une case (à la place d'un bloc confié) :
-- jamais la même zone pour les deux.
local function newZone(case, parent)
  local z = CreateFrame("Frame", nil, parent or arbre.toile, case and "InsetFrameTemplate" or nil) -- une case : le fond en retrait d'une case
  z:SetFrameLevel(arbre.toile:GetFrameLevel() + 5)
  z.emplacement = true
  if case then
    z:SetSize(NODE_W, NODE_H)
  else
    z:SetSize(1, 16)
  end
  return z
end
local zonesCase, zoneProjet, caseProjet = {}, nil, nil

local function opts() return ns.db().options end
-- Ce qui se modifie, la fenêtre le demande au projet (ns.projetPeut).
local function lignes() return (ns.projetPeut(projet(), "lignes")) end -- ajouter, retirer, changer une quantité
-- Fabriquer et Fini : l'arbre en lecture seule (ni « + », ni quantités, ni choix de case) ; « Préparer » dans le fil pour changer.
local function lectureSeule() return ns.phase(projet()) ~= "preparer" end

---------------------------------------------------------------------------------------------------
-- Le fil (CONTEXT.md, Phase) « Préparer › Réunir › Fabriquer », en haut des deux vues : la phase du projet affiché se lit
-- sur son bouton : texte doré, surligné, et non cliquable comme l'onglet choisi du jeu (Disable : le doré seul ne se voyait
-- pas assez en jeu) ; les autres en gris, clic = aller à cette phase (le Brouillon : lancé d'abord) et montrer sa vue.
-- Fini : les trois cliquables, et « › Fini » en vert au bout du fil. ns.fil(parent, x, y) le pose et rend la fonction qui
-- le met à jour.
local PHASES = {
  { "preparer", "Préparer", "l'arbre et les choix de case ; Lancer passe à Réunir" },
  { "reunir", "Réunir", "ses Besoins seuls ; tout dans les sacs, Fabriquer vient tout seul" },
  { "fabriquer", "Fabriquer", "l'arbre se remplit, la prochaine fabrication sur sa case" },
}
function ns.fil(parent, x, y)
  local bs = {}
  for i, ph in ipairs(PHASES) do
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(84, 20)
    if i == 1 then b:SetPoint("TOPLEFT", x, y) else
      local sep = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
      sep:SetPoint("LEFT", bs[i - 1], "RIGHT", 4, 0)
      sep:SetText("›")
      b:SetPoint("LEFT", sep, "RIGHT", 4, 0)
    end
    b:SetScript("OnClick", function()
      local ok, raison = ns.allerPhase(projet(), ph[1])
      if not ok then return print(("Composants : Lancer refusé (%s)."):format(raison or "?")) end
      ns.montrerVue()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(ph[2])
      GameTooltip:AddLine(ph[3], 1, 1, 1, true)
      if ns.phase(projet()) ~= ph[1] then GameTooltip:AddLine("Clic : y aller", 1, 0.82, 0) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetMotionScriptsWhileDisabled(true) -- la bulle aussi sur la phase en cours
    bs[i] = b
  end
  local fini = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fini:SetPoint("LEFT", bs[#bs], "RIGHT", 6, 0)
  fini:SetText("› |cff59cc73Fini|r")
  return function()
    local en = ns.phase(projet())
    for i, ph in ipairs(PHASES) do
      if ph[1] == en then bs[i]:SetText("|cffffd100" .. ph[2] .. "|r"); bs[i]:LockHighlight()
      else bs[i]:SetText("|cffbbbbbb" .. ph[2] .. "|r"); bs[i]:UnlockHighlight() end
      bs[i]:SetEnabled(ph[1] ~= en)
    end
    fini:SetShown(en == "fini")
  end
end

-- Le dessin de l'arbre d'un projet (res = ns.projetArbre, Projet.lua), sans rien afficher (testé hors jeu dans check.lua) ;
-- le placement (étages, relais, bandes empilées) est celui de l'Arbre du socle (AzerothCommune.PlacerArbre).
-- Étages : les lignes du projet en 0 (et les composants d'un enchantement, qui n'a pas de case), un objet juste à droite
-- de son parent le plus à droite. Bandes : un bloc = ses cases + ce qui n'est pas fabriqué sous elles (rattaché à son
-- premier parent), puis le reste (acheté ou en stock).
-- Chaque bloc reçoit sa couleur (index), son titre (label) et ses cases dessinées (cards).
-- confies (facultatif) = { [métier] = true } : ces blocs (confiés, l'emplacement du bloc) se réduisent à une seule case
-- (ns.reduire) ; grp.case = elle, à la place de leurs cases.
-- Un bloc confié : sa case la plus haute (une ligne du projet, sinon ce qu'il livre à un autre bloc) le représente ; ses
-- autres cases s'y fondent, et ce qui n'est pas fabriqué sous lui (la part de l'artisan) sort du dessin, sauf ce qu'un autre
-- y prend aussi. Les liens passent par elle, un seul par paire de cases, sans quantité quand plusieurs s'y fondent.
-- Rend les cases et les liens à dessiner (les mêmes tables quand rien n'est confié), et la part confiée : { [case] = true }
-- pour les cases des blocs confiés et ce qui sort du dessin avec eux (ns.partConfiee, les Besoins).
-- ponytail: une matière prise à la fois par un bloc confié et par un autre reste entière (la part de l'artisan n'en est
-- pas retranchée) ; à compter lien par lien si ça gêne.
function ns.reduire(res, confies)
  if not (confies and next(confies)) then return res.cases, res.liens, {} end
  local bloc, rep = {}, {}
  for _, grp in ipairs(res.blocs) do
    for _, n in ipairs(grp.cases) do bloc[n] = grp.key end
    if confies[grp.key] then
      for _, n in ipairs(grp.cases) do if not rep[grp.key] and (n.kind == "target" or grp.qty[n.id]) then rep[grp.key] = n end end
      rep[grp.key] = rep[grp.key] or grp.cases[1]
      grp.case = rep[grp.key]
    end
  end
  -- La bande d'une case pas fabriquée : celle de son premier parent (la règle du dessin, plus bas).
  local premier = {}
  for _, e in ipairs(res.liens) do premier[e.to] = premier[e.to] or e.from end
  local function bande(n, k)
    if bloc[n] ~= nil or k > #res.cases then return bloc[n] end
    return premier[n] and bande(premier[n], k + 1)
  end
  local vers = {} -- vers[n] = la case qui la dessine (elle-même, la case de son bloc confié), nil = sortie du dessin
  for _, n in ipairs(res.cases) do
    local b = bande(n, 0)
    if not rep[b] then vers[n] = n
    elseif bloc[n] then vers[n] = rep[b]
    else
      for _, e in ipairs(res.liens) do if e.to == n and bande(e.from, 0) ~= b then vers[n] = n end end
    end
  end
  local list, edges, vu, part = {}, {}, {}, {}
  for _, n in ipairs(res.cases) do
    if vers[n] == n then list[#list + 1] = n end
    if vers[n] ~= n or rep[bloc[n]] == n then part[n] = true end
  end
  for _, e in ipairs(res.liens) do
    local f, t = vers[e.from], vers[e.to]
    local k = f and t and f ~= t and (f.key .. ">" .. t.key)
    if k and not vu[k] then
      vu[k] = true
      edges[#edges + 1] = { from = f, to = t, livraison = e.livraison,
        qty = (f == e.from and t == e.to) and e.qty or nil }
    end
  end
  return list, edges, part
end

function ns.dessinArbre(res, confies)
  local list, edges = ns.reduire(res, confies)
  -- La bande de chaque case : son bloc ; une ligne fabrication finie reste dans son étape ; sinon celle de son premier
  -- parent (ce qui n'est pas fabriqué sous un bloc y est rattaché), le reste (acheté ou en stock) sans parent.
  local blocOf, premier, bandeDe = {}, {}, {}
  for _, grp in ipairs(res.blocs) do for _, n in ipairs(grp.cases) do blocOf[n] = grp.key end end
  for _, e in ipairs(edges) do premier[e.to] = premier[e.to] or e.from end
  local function bande(n, k)
    if bandeDe[n] == nil then
      if blocOf[n] then bandeDe[n] = blocOf[n]
      elseif n.faites and n.made == 0 and n.recipe and res.blocDe[n.recipe.profession] and not (confies and confies[n.recipe.profession]) then
        bandeDe[n] = n.recipe.profession
      elseif premier[n] and k <= #list then bandeDe[n] = bande(premier[n], k + 1)
      else bandeDe[n] = "reste" end
    end
    return bandeDe[n]
  end
  for _, n in ipairs(list) do n.band = bande(n, 0) end
  local bandes = {}
  for i, grp in ipairs(res.blocs) do
    grp.index = i
    local who = {}
    for _, c in ipairs(grp.crafters) do who[#who + 1] = ("%s %d (%d/%d)"):format(c.name, c.rank, c.known, #grp.recipes) end
    grp.labelSans = ("Étape %d · %s%s · %s"):format(grp.step, grp.key, grp.level > 0 and (" · niv. " .. grp.level .. " requis") or "",
      #who > 0 and table.concat(who, ", ") or "personne de ta liste") -- sans son temps (le compte à rebours le récrit)
    grp.label = grp.labelSans .. (ns.texteTemps(grp) and (" · " .. ns.texteTemps(grp)) or "")
    grp.cards = {}
    for _, n in ipairs(list) do if n.band == grp.key then grp.cards[#grp.cards + 1] = n end end
    -- Un rectangle par artisan, à sa couleur, dans l'ordre de la liste (ton perso d'abord) ; rouge = personne ne sait le faire.
    bandes[i] = { key = grp.key, title = grp.label, grp = grp,
      color = #grp.crafters > 0 and CRAFTER_COLORS[(i - 1) % #CRAFTER_COLORS + 1] or COLORS.none }
  end
  bandes[#bandes + 1] = { key = "reste" } -- sans rectangle ni titre
  -- Le placement (étages, relais, bandes empilées) : l'Arbre du socle. Une case du projet (sa ligne, kind « target ») en
  -- tête, à son rang.
  local g = AzerothCommune.PlacerArbre(list, edges, bandes, { largeur = NODE_W, hauteur = NODE_H, haut = TOP, marge = MARGIN })
  g.byKey, g.groups, g.groupOf, g.livraisons = res.caseDe, res.blocs, res.blocDe, res.livraisons
  return g
end

---------------------------------------------------------------------------------------------------
-- Dessin
local function stocked(n) return n.have[1] + n.have[2] + n.have[3] end

local function stateColor(n)
  if n.kind == "target" then return COLORS.target end
  if n.made > 0 then return COLORS.fabriquer end
  if n.apport > 0 and n.need == 0 then return COLORS.apport end
  if n.unpriced then return COLORS.none end
  if n.need == 0 then return COLORS[1] end
  return COLORS.buy
end

-- Maj+clic : la recette dans la fenêtre de métier du jeu. Seulement une fois la fenêtre chargée par le jeu
-- (Mastercraft fait pareil : l'ouvrir avant casse la fenêtre) et si ce perso-ci connaît la recette.
local function openRecipe(n)
  local key = n.recipeKey
  if type(key) ~= "number" then return print("Composants : pas de recette à ouvrir pour " .. ns.itemLabel(n.id) .. ".") end
  for _, prof in pairs(ns.knownRecipes()[UnitGUID("player")] or {}) do
    if prof.known and prof.known[key] then
      local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
      if not (loaded and loaded("Blizzard_Professions")) then return print("Composants : ouvre une fois ta fenêtre de métier, puis Maj+clic.") end
      return C_TradeSkillUI.OpenRecipe(key)
    end
  end
  local who = {}
  for k, metiers in pairs(ns.knownRecipes()) do
    for _, prof in pairs(metiers) do if prof.known and prof.known[key] then who[#who + 1] = ns.prenom(k) end end
  end
  print(("Composants : %s — %s."):format(n.recipe and n.recipe.name or "recette",
    #who > 0 and ("connue de " .. table.concat(who, ", ") .. ", pas de ce perso") or "aucun de tes persos ne la connaît"))
end

-- Ce que fait un clic sur la case : revenir au calcul si le choix était forcé, sinon forcer l'inverse.
local function toggleOf(n)
  if n.apport > 0 then return end -- fourni par un autre (l'emplacement du bloc) : hors de l'arbre
  if n.fabrication then return end -- une fabrication du projet : toujours fabriquée
  if n.choix then return "reset" end
  if n.made > 0 then return "acheter" end
  if n.craftable then return "fabriquer" end -- même en stock : « + » le fabrique au lieu de le prendre
end

local function newCard()
  -- Une case : le fond en retrait du jeu, le surlignage du jeu au survol, et tenu sur une case choisie à la main (n.choix).
  local c = CreateFrame("Button", nil, arbre.toile, "InsetFrameTemplate")
  c:SetFrameLevel(arbre.toile:GetFrameLevel() + 3) -- au-dessus des cadres d'artisans
  c:SetSize(NODE_W, NODE_H)
  c:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c.accent = c:CreateTexture(nil, "ARTWORK")
  c.accent:SetPoint("TOPLEFT", 1, -1)
  c.accent:SetPoint("BOTTOMLEFT", 1, 1)
  c.accent:SetWidth(3)
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetSize(26, 26)
  c.icon:SetPoint("TOPLEFT", 8, -5)
  c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.name:SetPoint("TOPLEFT", 40, -6)
  c.name:SetPoint("RIGHT", -20, 0)
  c.name:SetJustifyH("LEFT")
  c.name:SetWordWrap(false)
  c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  c.sub:SetPoint("TOPLEFT", 40, -20)
  c.sub:SetPoint("RIGHT", -6, 0)
  c.sub:SetJustifyH("LEFT")
  c.sub:SetWordWrap(false)
  -- Quantité commandée (cases de la colonne 0) : à taper, ou molette (Maj = par 10). Grisée si le projet
  -- ne permet pas de changer ses lignes (une réponse).
  c.qty = CreateFrame("EditBox", nil, c)
  c.qty:SetSize(36, 14); c.qty:SetPoint("TOPLEFT", 40, -19)
  c.qty:SetFontObject(GameFontHighlightSmall); c.qty:SetAutoFocus(false); c.qty:SetNumeric(true); c.qty:SetMaxLetters(4)
  c.qty:SetTextInsets(10, 2, 0, 0)
  local qbg = c.qty:CreateTexture(nil, "BACKGROUND"); qbg:SetAllPoints(); qbg:SetColorTexture(1, 1, 1, 0.08)
  local x = c.qty:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); x:SetPoint("LEFT", 2, 0); x:SetText("×")
  local function setQty(q)
    local n = c.node
    if not (n and n.kind == "target") then return end
    ns.projetQuantite(projet(), n.index, q)
    ns.refreshCraftWindow()
  end
  c.qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  c.qty:SetScript("OnEscapePressed", function(self) self.cancel = true; self:ClearFocus() end)
  c.qty:SetScript("OnEditFocusLost", function(self)
    if self.cancel then self.cancel = nil; return ns.refreshCraftWindow() end
    setQty(tonumber(self:GetText()))
  end)
  c.qty:SetScript("OnMouseWheel", function(self, d)
    local n = c.node
    if n and n.kind == "target" then setQty(math.max(1, n.qty + d * (IsShiftKeyDown() and 10 or 1))) end
  end)
  c.toggle = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge") -- doré : ton choix
  c.toggle:SetPoint("TOPRIGHT", -6, -2)
  c.barBg = c:CreateTexture(nil, "ARTWORK")
  c.barBg:SetColorTexture(1, 1, 1, 0.08)
  c.barBg:SetPoint("BOTTOMLEFT", 40, 5)
  c.barBg:SetSize(NODE_W - 48, 4)
  c.seg = {}
  for i = 1, 6 do c.seg[i] = c:CreateTexture(nil, "OVERLAY") end
  c:SetScript("OnEnter", function(self)
    local n = self.node
    if not n then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(n.id)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Il en faut %d"):format(n.qty), 1, 1, 1)
    if stocked(n) > 0 then GameTooltip:AddLine(("En stock : %d sacs, %d banque, %d autres persos"):format(n.have[1], n.have[2], n.have[3]), 0.35, 0.8, 0.45) end
    if n.made > 0 then
      GameTooltip:AddLine(("À fabriquer : %d — %s ×%d, %s"):format(n.made, n.recipe and n.recipe.name or "?", n.crafts, ns.money(n.madeCost)), 0.95, 0.65, 0.25)
      if n.who then GameTooltip:AddLine(("Par %s%s"):format(n.who, n.whoKnows and "" or " (a le métier, recette à apprendre)"), 1, 0.82, 0)
      elseif n.who == false then GameTooltip:AddLine("Personne de ta liste n'a ce métier", 0.9, 0.3, 0.3) end
      if n.unknown then GameTooltip:AddLine("Recette pas encore apprise", 0.9, 0.3, 0.3)
      elseif type(n.recipeKey) == "number" then GameTooltip:AddLine("Maj+clic : ouvrir la recette dans la fenêtre de métier", 0.6, 0.6, 0.6) end
      if n.buy then GameTooltip:AddLine("Acheter tout fait coûterait " .. ns.money(n.buy), 0.7, 0.7, 0.7) end
    end
    if n.need > 0 then
      GameTooltip:AddLine(n.unpriced and ("À trouver : %d — ni prix ni recette"):format(n.need)
        or ("À acheter : %d — %s, %s"):format(n.need, n.how == "marchand" and "marchand" or "HV", ns.money(n.cost)), 0.8, 0.8, 0.8)
    end
    if n.incomplete then GameTooltip:AddLine("Coût incomplet : un composant n'a ni prix ni recette (en rouge)", 0.9, 0.3, 0.3) end
    if n.partial then GameTooltip:AddLine("Pas assez en vente à l'HV : le reste est compté au dernier prix vu", 0.9, 0.6, 0.3) end
    local t = not lectureSeule() and toggleOf(n)
    if t == "reset" then GameTooltip:AddLine("Choix forcé à la main — clic : revenir au calcul des prix", 1, 0.82, 0)
    elseif t == "acheter" then GameTooltip:AddLine("Clic : l'acheter tout fait au lieu de le fabriquer", 0.6, 0.6, 0.6)
    elseif t == "fabriquer" then
      GameTooltip:AddLine(n.need == 0 and "Clic : le fabriquer au lieu de prendre ton stock" or "Clic : le décomposer (fabriquer) même si c'est plus cher", 0.6, 0.6, 0.6)
    end
    if n.apport > 0 then GameTooltip:AddLine(("Fourni : %d, hors de l'arbre"):format(n.apport), 0.3, 0.8, 0.85) end
    if n.kind == "target" and lignes() and not lectureSeule() then GameTooltip:AddLine("Clic droit : ne plus suivre", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  c:SetScript("OnClick", function(self, button)
    local n = self.node
    if IsShiftKeyDown() and button ~= "RightButton" then return openRecipe(n) end
    if lectureSeule() then return end
    if button == "RightButton" then
      if n.kind ~= "target" or not ns.projetRetirer(projet(), n.index) then return end
    else
      local t = toggleOf(n)
      if not t then return end
      ns.projetChoix(projet(), n.id, t ~= "reset" and t or nil)
    end
    ns.refreshCraftWindow()
    if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
  end)
  return c
end

-- Le cran en cours de la fabrication lancée, image après image (OnUpdate de la case, pendant la fabrication seulement) : les
-- fabrications finies et l'incantation du jeu, à la couleur du stock, sur la part « à fabriquer » (Fabriquer.lua).
local function peindreCran(c)
  local e = ns.fabricationEnCours()
  local x = e and c.cranW and ns.avancement(e) or 0
  c.cran:SetShown(x > 0)
  if x > 0 then c.cran:SetWidth(math.max(1, c.cranW * x)) end
end
local tic -- (plus bas, avec le dessin) : le compte à rebours récrit
-- OnUpdate de la case de la fabrication en cours (seulement elle, seulement pendant ; rien quand la fenêtre est cachée) :
-- le cran à chaque image, le compte à rebours une fois par seconde.
local function enCours(c, dt)
  peindreCran(c)
  c.acc = (c.acc or 0) + (dt or 0)
  if c.acc >= 1 then c.acc = 0; tic() end
end

-- Barre : sacs, banque, autres persos, à fabriquer, à acheter (rouge si sans prix). La case de la fabrication en cours
-- (le bouton d'action) : sa barre telle qu'au lancement, la part « à fabriquer » découpée en crans, un par fabrication.
-- ponytail: figée au lancement, sinon le stock qui arrive dans les sacs et le compte des fabrications avanceraient deux fois.
local function bar(c, n)
  local e = ns.fabricationEnCours and ns.fabricationEnCours()
  e = e and e.id == n.id and e or nil
  local fait = n.faites or 0 -- une ligne fabrication : ce qui est déjà fabriqué, en vert (toute verte une fois finie)
  local parts = { n.have[1] + fait, n.have[2], n.have[3], n.made, n.need, n.apport, n.qty + fait }
  if e then e.barre = e.barre or parts; parts = e.barre end
  local qty = parts[7]
  local tints = { COLORS[1], COLORS[2], COLORS[3], COLORS.fabriquer, n.unpriced and COLORS.none or COLORS.buy, COLORS.apport }
  local left, wmax = 40, NODE_W - 48
  for i = 1, 6 do
    local wpx = qty > 0 and wmax * parts[i] / qty or 0
    local seg = c.seg[i]
    if i == 4 then c.fab = left end
    if wpx >= 1 then
      local k = tints[i]
      seg:SetColorTexture(k[1], k[2], k[3], 0.9)
      seg:ClearAllPoints()
      seg:SetPoint("BOTTOMLEFT", left, 5)
      seg:SetSize(wpx, 4)
      seg:Show()
      left = left + wpx
    else
      seg:Hide()
    end
  end
  -- Les crans : séparations sur la part « à fabriquer », le remplissage par-dessus.
  local k = e and qty > 0 and ns.crans(e.n) or 0
  local cw = e and qty > 0 and wmax * e.per / qty or 0 -- un cran : les objets d'une fabrication
  c.cranW = e and cw * e.n or nil
  c.seps = c.seps or {}
  for i = 1, math.max(k - 1, #c.seps) do
    local s = c.seps[i]
    if i < k then
      if not s then
        s = c:CreateTexture(nil, "OVERLAY", nil, 7)
        s:SetColorTexture(0, 0, 0, 0.9); s:SetSize(1, 4)
        c.seps[i] = s
      end
      s:ClearAllPoints(); s:SetPoint("BOTTOMLEFT", c.fab + cw * i, 5); s:Show()
    elseif s then s:Hide() end
  end
  if not c.cran then
    c.cran = c:CreateTexture(nil, "OVERLAY", nil, 6)
    c.cran:SetColorTexture(COLORS[1][1], COLORS[1][2], COLORS[1][3], 0.9); c.cran:SetHeight(4)
  end
  c.cran:ClearAllPoints(); c.cran:SetPoint("BOTTOMLEFT", c.fab, 5)
  peindreCran(c)
  c.acc = 0
  c:SetScript("OnUpdate", e and enCours or nil)
end

local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t" -- la coche verte des Besoins
-- reste : la case de la fabrication en cours, ses secondes restantes (ns.resteEnCours) : son compte à rebours à la place
-- du détail (qui revient à la fin).
local function subText(n, reste)
  if reste then return (" |cffe6a640%d à fab.|r · |cffffffffreste %s|r"):format(n.made, ns.duree(reste, true)) end
  -- Une ligne fabrication finie : validée, avec ce qu'elle a fait ; entamée, ce qu'elle a fait avant ce qu'il reste.
  local faites = n.faites and ("|cff59cc73%d faite%s|r"):format(n.faites, n.faites > 1 and "s" or "")
  if faites and n.made == 0 then return (" %s %s"):format(READY, faites) end
  local s = (n.kind ~= "target" or lectureSeule()) and ("×" .. n.qty + (n.faites or 0)) or "" -- en Préparer, la ligne a son champ de quantité
  if faites then s = s .. " " .. faites end
  if stocked(n) > 0 then s = s .. (" |cff59cc73%d stock|r"):format(stocked(n)) end
  if n.made > 0 then s = s .. (n.unknown and " |cffe64d4d%d à fab.|r" or " |cffe6a640%d à fab.|r"):format(n.made) end
  if n.need > 0 then
    s = s .. (n.unpriced and (" |cffe64d4d%d sans prix|r"):format(n.need) or (" %d %s"):format(n.need, n.how == "marchand" and "marchand" or "HV"))
  end
  local cost = n.madeCost + n.cost
  if cost > 0 then s = s .. " · " .. ns.moneyShort(cost) end
  if n.apport > 0 then s = s .. (" |cff4dccd9%d fourni|r"):format(n.apport) end
  if n.incomplete then s = s .. " |cffe64d4d+ ?|r" end
  return s
end

local headers = {}
-- Une durée en clair : « 45 s », « 2 min », « 1 h 05 » ; vif (un compte à rebours) : les secondes sous 10 min, « 2 min 40 s ».
-- ponytail: la même que celle de Maîtrise (Fenetre.lua) ; au socle au troisième usage.
function ns.duree(s, vif)
  s = math.floor(s + 0.5)
  if s < 60 then return s .. " s" end
  if vif and s < 600 then return ("%d min %02d s"):format(math.floor(s / 60), s % 60) end
  if s < 3600 then return math.floor(s / 60 + 0.5) .. " min" end
  return ("%d h %02d"):format(math.floor(s / 3600), math.floor(s % 3600 / 60))
end
-- Le temps de fabrication d'un bloc ou du projet (t.temps, t.tempsIncomplet, Projet.lua) : « 2 min », « au moins 2 min » si
-- une recette n'a pas de temps connu, « temps inconnu » si aucune ; nil s'il n'y a plus rien à fabriquer. ecoule (pendant
-- une fabrication) : les secondes déjà passées sur l'incantation en cours, en moins, au format du compte à rebours.
function ns.texteTemps(t, ecoule)
  if (t.temps or 0) > 0 then
    return (t.tempsIncomplet and "au moins " or "") .. ns.duree(math.max(0, t.temps - (ecoule or 0)), ecoule ~= nil)
  end
  return t.tempsIncomplet and "temps inconnu" or nil
end

local function header(i, x, text)
  local h = headers[i] or arbre.toile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  headers[i] = h
  h:ClearAllPoints()
  h:SetPoint("TOPLEFT", arbre.toile, "TOPLEFT", MARGIN + x, 0)
  h:SetText(text)
  h:Show()
end

-- Le compte à rebours de la fabrication en cours (ns.resteEnCours) : sur sa case, sur la ligne de son étape et sur celle du
-- projet. vif = { case, bloc (le rectangle de son étape) }, posé par le dessin ; nil hors fabrication.
local vif, ligneProjet
tic = function()
  local e = vif and ns.fabricationEnCours()
  if not e then return end
  local reste, ecoule = ns.resteEnCours(e)
  if not reste then return end
  vif.case.sub:SetText((subText(vif.case.node, reste):gsub("^ ", "")))
  if ligneProjet then headers[1]:SetText(ligneProjet(ecoule)) end
  local b = vif.bloc
  if b then
    local t = ns.texteTemps(b.grp, ecoule)
    b.title:SetText(b.grp.labelSans .. (t and (" · " .. t) or ""))
  end
end

-- La fonction de case donnée à l'Arbre (AzerothCommune.Arbre) : crée la case la première fois (c = nil), la remplit.
local function remplirCase(n, c)
  c = c or newCard()
  c.node = n
  local k = stateColor(n)
  c.accent:SetColorTexture(k[1], k[2], k[3], 0.9)
  c.icon:SetTexture(C_Item.GetItemIconByID(n.id))
  c.name:SetText(ns.itemLabel(n.id))
  c.sub:SetText((subText(n):gsub("^ ", "")))
  local target = n.kind == "target" and not lectureSeule() -- son champ de quantité, en Préparer seulement
  c.qty:SetShown(target); c.qty:SetEnabled(target and lignes())
  if target and not c.qty:HasFocus() then -- une fabrication : son nombre de fois (ce que la saisie change), pas ses objets
    c.qty:SetText(n.fabrication and projet().lines[n.index].fois or n.qty)
  end
  c.sub:SetPoint("TOPLEFT", target and 80 or 40, -20)
  local t = toggleOf(n)
  local sign = lectureSeule() and "" or (n.made > 0 and "–") or (t and "+") or ""
  c.toggle:SetText(n.choix and ("|cffffd100" .. sign .. "|r") or sign)
  if n.choix then c:LockHighlight() else c:UnlockHighlight() end
  bar(c, n)
  return c
end

local function refresh()
  if not (frame and frame:IsShown()) then return end
  if ns.phase(projet()) == "reunir" then return ns.montrerVue() end -- la vue de Réunir, c'est la petite
  local res = ns.projetArbre(projet(), nil, ns.apportsEmplacement(projet()))
  ns.avancerPhase(projet(), res) -- Fabriquer → Fini, tout seul
  -- L'emplacement du bloc : les blocs confiés, chacun réduit à une case ; le projet entier confié, une seule case en tout.
  local p, f = projet(), F(projet())
  local entier, confies = ns.confies(p, res)
  local g = ns.dessinArbre(entier and { cases = {}, liens = {}, blocs = {}, livraisons = {}, caseDe = {} } or res, confies)
  if entier then g.height = NODE_H end
  local roots, market, total, incomplete = res.roots, res.market, res.total, res.incomplete
  frame.syncProjet()

  for _, h in ipairs(headers) do h:Hide() end
  if #roots == 0 then
    local vide = { brouillon = "Brouillon vide : Ctrl+clic droit sur un objet n'importe où l'y met ; Lancer en fait un projet.",
      transformations = "Rien de rentable à transformer dans tes sacs (tes recettes, le dernier cours de l'HV)." }
    header(1, 0, vide[ns.estPassage(projet())] and "|cff999999" .. vide[ns.estPassage(projet())] .. "|r"
      or "|cff999999Cherche un objet (ou dépose-le sur la recherche) ; Ctrl+clic droit sur un objet le met au Brouillon.|r")
  else
    local o = projet()
    local cost = (total == 0 and not incomplete) and "rien à acheter" or (ns.moneyShort(total) .. (incomplete and " |cffe64d4d+ ?|r" or ""))
    local fini = ns.phase(o) == "fini" and " · |cff59cc73Tout est fabriqué|r" or "" -- la phase Fini
    -- Valeur à l'HV de ce qu'on fabrique, et ce que ça rapporte quand le coût est complet ; rien sans prix.
    local v = res.valeur and (" · vaut %s à l'HV · %s"):format(ns.moneyShort(res.valeur),
      res.rapporte and "rapporte " .. ns.moneySigned(res.rapporte) or "|cffe64d4dcoût incomplet|r") or ""
    ligneProjet = function(ecoule) -- (le compte à rebours la récrit avec ecoule)
      local temps = ns.texteTemps(res, ecoule)
      temps = temps and (" · " .. temps .. ((res.temps or 0) > 0 and " de fabrication" or "")) or ""
      return (ns.estPassage(o) and o.name or "Projet") .. " · " .. cost .. v .. temps .. fini
    end
    header(1, 0, ligneProjet())
  end
  -- L'emplacement du projet entier : une bande à la suite de cette ligne ; confié, la seule case de l'arbre.
  zoneProjet, caseProjet = zoneProjet or newZone(), caseProjet or newZone(true)
  local zp = entier and caseProjet or zoneProjet
  zoneProjet:Hide(); caseProjet:Hide()
  if f and #roots > 0 then
    zp:ClearAllPoints()
    if entier then zp:SetPoint("TOPLEFT", arbre.toile, "TOPLEFT", MARGIN, -TOP)
    else zp:SetPoint("LEFT", headers[1], "RIGHT", 12, 0); zp:SetWidth(1) end
    zp:Show()
    appel(f.bloc, zp, p, nil, entier)
  end

  -- Les liens : à la couleur de leur case d'arrivée, la quantité juste avant elle ; une livraison entre blocs : un seul lien
  -- tracé (le premier), épais, à la couleur du métier qui fabrique.
  local livree = {}
  for _, e in ipairs(g.edges) do
    e.hidden = e.livraison and livree[e.livraison] or nil
    if e.livraison then livree[e.livraison] = true end
    e.color, e.thick, e.text = stateColor(e.to), e.livraison and 4 or 2, not e.livraison and e.qty and ("×" .. e.qty) or nil
    if e.livraison then
      local grp = g.groupOf[e.livraison.maker]
      e.color = #grp.crafters > 0 and CRAFTER_COLORS[(grp.index - 1) % #CRAFTER_COLORS + 1] or COLORS.none
    end
  end
  arbre:Dessiner(g) -- l'Arbre du socle : les cases (remplirCase), un rectangle par artisan, les liens
  local cards = arbre.cadres
  local caseDuBloc = {} -- la case d'un bloc confié : le fournisseur la dessine (plus bas), pas de case de Composants
  for _, grp in ipairs(g.groups or {}) do if confies[grp.key] and grp.case then caseDuBloc[grp.case] = grp end end
  for i, n in ipairs(g.nodes) do if caseDuBloc[n] then cards[i]:Hide() end end
  -- En Fabriquer, le bouton d'action en bas nomme la prochaine fabrication, sa case cerclée (Fabriquer.lua).
  local function carteDe(id)
    for i = 1, #g.nodes do if cards[i].node.id == id then return cards[i] end end
  end
  ns.rafraichirToutFabriquer(carteDe)

  -- Le rectangle de chaque artisan (dessiné par l'Arbre : toutes ses cases, à sa couleur, son nom au-dessus) : survol du
  -- nom = ses recettes ; l'emplacement du bloc sur sa ligne de titre.
  local boxOf, usedZones = {}, 0
  for _, b in ipairs(arbre.rectangles) do
    local grp = b:IsShown() and b.band.grp
    if grp then
      if not b.hit then
        -- Survol du nom : les recettes du métier, leur niveau requis, qui les connaît ; puis qui a le métier.
        b.hit = CreateFrame("Button", nil, b)
        b.hit:SetAllPoints(b.title)
        b.hit:SetScript("OnEnter", function(self)
          local grp = b.grp
          GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
          GameTooltip:AddLine(grp.key)
          for _, r in ipairs(grp.recipes) do
            GameTooltip:AddDoubleLine(r.name .. (r.level and (" |cff999999(" .. r.level .. ")|r") or ""),
              #r.known > 0 and table.concat(r.known, ", ") or "à apprendre", 1, 1, 1, #r.known > 0 and 0.35 or 0.9, #r.known > 0 and 0.8 or 0.3, #r.known > 0 and 0.45 or 0.3)
          end
          GameTooltip:AddLine(" ")
          if #grp.crafters == 0 then GameTooltip:AddLine("Personne de ta liste n'a ce métier", 0.9, 0.3, 0.3) end
          for _, c in ipairs(grp.crafters) do
            GameTooltip:AddLine(("%s : niveau %d, %d recette%s sur %d"):format(c.name, c.rank, c.known, c.known > 1 and "s" or "", #grp.recipes), 1, 0.82, 0)
          end
          GameTooltip:Show()
        end)
        b.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b.zone = newZone(false, b) -- l'emplacement du bloc, sur sa ligne de titre (caché avec lui)
        b.zone:SetPoint("LEFT", b.title, "RIGHT", 8, 0)
      end
      boxOf[grp.key], b.grp = b, grp
      -- L'emplacement : une bande sur la ligne de titre ; confié, la case du bloc (à la place de la sienne).
      b.zone:SetShown(f ~= nil and not grp.case)
      if b.zone:IsShown() then b.zone:SetWidth(1); appel(f.bloc, b.zone, p, grp, false) end
      if f and grp.case then
        usedZones = usedZones + 1
        local z = zonesCase[usedZones] or newZone(true)
        zonesCase[usedZones] = z
        z:ClearAllPoints()
        z:SetPoint("TOPLEFT", arbre.toile, "TOPLEFT", grp.case.x, -(grp.case.y + TOP))
        z:Show()
        appel(f.bloc, z, p, grp, true)
      end
    end
  end
  for i = usedZones + 1, #zonesCase do zonesCase[i]:Hide() end
  -- Une fabrication en cours dont la case est dessinée : son compte à rebours, tout de suite puis chaque seconde (tic).
  local e = ns.fabricationEnCours()
  local ce = e and e.id and #roots > 0 and carteDe(e.id)
  vif = ce and ce:IsShown() and { case = ce, bloc = boxOf[ce.node.band] } or nil
  tic()
  if #roots > 0 then -- un « Étage » que la ligne du projet recouvrirait est sauté (la case de l'étape dit déjà où l'on est)
    local libre = headers[1]:GetStringWidth() + 24 + (zoneProjet:IsShown() and zoneProjet:GetWidth() + 12 or 0)
    for c = 1, g.cols - 1 do if g.ecart * c >= libre then header(c + 1, g.ecart * c, "Étage " .. c) end end
  end

  local usedTags = 0
  -- Étiquettes des commandes : sur la ligne de titre du rectangle du métier qui fabrique, à la suite du titre (jamais
  -- sur une case ni sur le titre ; elles peuvent dépasser à droite du rectangle, la ligne de titre y est libre).
  local shelf = {}
  for _, o in ipairs(g.livraisons) do
    local b = boxOf[o.maker]
    if b then
      usedTags = usedTags + 1
      local t = orderTags[usedTags] or newOrderTag()
      orderTags[usedTags] = t
      t.order = o
      local first = o.lines[1]
      t.text:SetWidth(0)
      t.text:SetText(("pour %s · %d× %s%s"):format(bandName(o.client), o.qty[first], ns.itemLabel(first),
        #o.lines > 1 and (" +" .. (#o.lines - 1)) or ""))
      t:SetSize(t.text:GetStringWidth() + 12, 16)
      local k = b.color
      t:SetBackdropBorderColor(k[1], k[2], k[3], 0.9)
      t:ClearAllPoints()
      t:SetPoint("LEFT", shelf[b] or (b.zone:IsShown() and b.zone or b.title), "RIGHT", 6, 0)
      shelf[b] = t
      t:Show()
      -- Jamais au-delà du bord droit visible (en unités du dessin) : tronquée, cachée s'il reste moins de 40.
      local l, cl = t:GetLeft(), arbre.toile:GetLeft()
      local place = l and cl and arbre.zone:GetWidth() / arbre.toile:GetScale() - arbre.vue.x - 4 - (l - cl)
      if place and t:GetWidth() > place then
        t:SetWidth(math.max(40, place)); t.text:SetWidth(math.max(40, place) - 12)
        t:SetShown(place >= 40)
      end
    end
  end
  for i = usedTags + 1, #orderTags do orderTags[i]:Hide() end
  -- La barre d'état s'arrête au bouton d'action visible (sa largeur suit son libellé).
  local action = ComposantsToutFabriquer and ComposantsToutFabriquer:IsShown() and ComposantsToutFabriquer
    or frame.clore:IsShown() and frame.clore or frame.lancerB
  frame.status:SetPoint("RIGHT", action, "LEFT", -12, 0)

  frame.status:SetText(ns.texteHV(market) .. (lectureSeule() and " · lecture seule (« Préparer » pour changer)"
    or " · « + » décompose, « – » achète tout fait") .. " · molette : zoom, glisser : déplacer") -- coupée au bouton d'action
end
ns.refreshCraftWindow = refresh

-- Une seule vue visible (CONTEXT.md, Phase) : celle de la phase du projet affiché, après ce qui se fait tout seul
-- (ns.avancerPhase) ; Réunir = la petite (les Besoins), les autres = la grande. Celle qui s'ouvre prend le coin de celle qui
-- se ferme. Tout ce qui ouvre un projet ou change sa phase passe par ici.
function ns.montrerVue()
  if not frame then build() end
  local p = projet()
  ns.avancerPhase(p)
  local petite = ns.besoinsFenetre()
  local vue, autre = frame, petite
  if ns.phase(p) == "reunir" then vue, autre = petite, frame end
  if autre:IsShown() then
    local x, y = autre:GetLeft(), autre:GetTop()
    autre:Hide()
    if x and y then vue:ClearAllPoints(); vue:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y) end
  end
  if vue == frame then frame:Show(); refresh()
  elseif petite:IsShown() then ns.refreshNeeds()
  else petite:Show() end -- (son OnShow la remplit)
  ns.besoinsChanges() -- la liste d'Auctionator suit le projet affiché
end

---------------------------------------------------------------------------------------------------
local function track(id, qty)
  if not id then return end
  local ok, raison = ns.projetAjouter(projet(), id, qty)
  if not ok then return print("Composants : " .. raison .. " (le Brouillon pour un projet à toi).") end
  refresh()
end

-- La barre de recherche du socle (AzerothCommune#60 ; Composants souscrit aux deux types qu'elle lit) : l'objet choisi entre
-- dans le projet affiché.
local function searchBox(qty) return AzerothCommune.RechercheObjets(frame, qty, track) end

-- Supprimer un projet (clic droit dans la colonne, « Clore ») : le projet affiché le reste, sinon le suivant de la liste ;
-- plus aucun projet : le Brouillon (pas un projet vide créé pour rien) ; un projet de passage affiché le reste. Signalé (QuandChange) : un autre add-on y range ce
-- qu'il doit.
local function supprimer(p)
  local affiche = projet()
  local _, i = ns.projet(p.id)
  if not i then return end
  ns.db().courant = i
  ns.supprimerProjet()
  if ns.estPassage(affiche) then ns.ouvrirPassage(ns.estPassage(affiche))
  elseif #ns.db().projets == 0 then ns.ouvrirBrouillon()
  elseif affiche ~= p then ns.ouvrirProjet(affiche.id) end
  ns.montrerVue()
end

-- La colonne des projets (skill ui-addon : une colonne toujours visible, pas un menu déroulant) : les projets de passage en
-- tête (le Brouillon), puis chaque projet avec sa phase, celui affiché surligné ; clic = l'ouvrir dans la vue de sa phase ;
-- clic droit = Renommer (un champ sur l'entrée : Entrée garde, Échap annule), Supprimer ; le Brouillon : Vider ; un autre
-- projet de passage : rien. Elle défile au-delà de sa hauteur. Rend la fonction qui la met à jour.
local PHASE_NOM = { preparer = "Préparer", reunir = "Réunir", fabriquer = "Fabriquer", fini = "|cff59cc73Fini|r" }
local ENTREE_H = 34
local function colonne(parent)
  local col = CreateFrame("Frame", nil, parent, "InsetFrameTemplate") -- le fond en retrait du jeu, sous la barre de titre
  col:SetPoint("TOPLEFT", 10, -TOP_CONTENU)
  col:SetPoint("BOTTOMLEFT", 10, 10)
  col:SetWidth(COL_W)
  local sc = CreateFrame("ScrollFrame", nil, col, "UIPanelScrollFrameTemplate")
  sc:SetPoint("TOPLEFT", 4, -4)
  sc:SetPoint("BOTTOMRIGHT", -24, 4)
  local liste = CreateFrame("Frame", nil, sc)
  liste:SetSize(COL_W - 28, 1)
  sc:SetScrollChild(liste)
  local nomB = CreateFrame("EditBox", nil, liste, "InputBoxTemplate")
  nomB:SetHeight(20)
  nomB:SetAutoFocus(false)
  nomB:SetFrameLevel(liste:GetFrameLevel() + 5)
  nomB:Hide()
  local function fermer(self) self.p = nil; self:SetText(""); self:Hide() end
  nomB:SetScript("OnEnterPressed", function(self)
    local nom = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if self.p and nom ~= "" then ns.projetRenommer(self.p, nom) end
    fermer(self)
    refresh()
  end)
  nomB:SetScript("OnEscapePressed", fermer)
  nomB:SetScript("OnEditFocusLost", fermer)
  local function menu(b)
    local p = b.p
    if ns.estPassage(p) and not ns.estBrouillon(p) then return end -- (les autres passages : rien à y faire)
    MenuUtil.CreateContextMenu(b, function(_, root)
      if ns.estBrouillon(p) then
        root:CreateButton("Vider le Brouillon", function() ns.viderBrouillon(); ns.montrerVue() end)
        return
      end
      root:CreateButton("Renommer", function()
        nomB.p = p
        nomB:ClearAllPoints()
        nomB:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -1)
        nomB:SetPoint("RIGHT", b, "RIGHT", -2, 0)
        nomB:SetText(p.name or "")
        nomB:Show()
        nomB:SetFocus()
        nomB:HighlightText()
      end)
      root:CreateButton("Supprimer", function() supprimer(p) end)
    end)
  end
  local entrees = {}
  local function entree(i)
    local b = CreateFrame("Button", nil, liste)
    b:SetSize(COL_W - 28, ENTREE_H - 2)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Celui affiché : le surlignage du jeu, tenu, et un trait doré à gauche ; le survol, le même surlignage.
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.fond:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    b.fond:SetBlendMode("ADD")
    b.fond:SetVertexColor(1, 0.82, 0, 0.5)
    b.trait = b:CreateTexture(nil, "ARTWORK")
    b.trait:SetPoint("TOPLEFT"); b.trait:SetPoint("BOTTOMLEFT"); b.trait:SetWidth(2)
    b.trait:SetColorTexture(1, 0.82, 0, 0.9)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.nom = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.nom:SetPoint("TOPLEFT", 8, -4); b.nom:SetPoint("RIGHT", -4, 0)
    b.nom:SetJustifyH("LEFT"); b.nom:SetWordWrap(false)
    b.phase = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.phase:SetPoint("TOPLEFT", 8, -18); b.phase:SetPoint("RIGHT", -4, 0)
    b.phase:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self, souris)
      if souris == "RightButton" then return menu(self) end
      if ns.estPassage(self.p) then ns.ouvrirPassage(ns.estPassage(self.p)) else ns.ouvrirProjet(self.p.id) end
      ns.montrerVue()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.nom:GetText())
      if self.p.tenu then GameTooltip:AddLine(self.p.tenu, 1, 0.82, 0, true) end
      if ns.estPassage(self.p) == "transformations" then
        GameTooltip:AddLine("Les matières de tes sacs transformées avec tes recettes, quand ça rapporte plus que les vendre telles quelles (part de l'HV, dépôt et ingrédients en plus déduits).", 1, 1, 1, true)
      end
      GameTooltip:AddLine("Clic : l'ouvrir", 0.6, 0.6, 0.6)
      local droit = ns.estBrouillon(self.p) and "le vider" or not ns.estPassage(self.p) and "Renommer, Supprimer"
      if droit then GameTooltip:AddLine("Clic droit : " .. droit, 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    entrees[i] = b
    return b
  end
  return function()
    local tous, cur = ns.passages(), projet()
    local npassages = #tous
    for _, p in ipairs(ns.db().projets) do tous[#tous + 1] = p end
    for i, p in ipairs(tous) do
      local b = entrees[i] or entree(i)
      local passage = ns.estPassage(p)
      b.p = p
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 0, -((i - 1) * ENTREE_H + (i > npassages and 8 or 0))) -- les passages un peu à part
      b.nom:SetFontObject(passage and "GameFontNormalSmall" or "GameFontHighlightSmall")
      b.nom:SetJustifyH("LEFT") -- (SetFontObject le remet au centre)
      b.nom:SetText(p.name or "?")
      local n = #p.lines
      if passage == "transformations" then -- ce qu'elle rapporte, d'après les sacs et l'HV de maintenant (pas ses lignes d'avant)
        local c = ns.calculTransformations()
        n = #c.lignes
        b.nom:SetFontObject(n > 0 and "GameFontNormalSmall" or "GameFontDisableSmall")
        b.nom:SetJustifyH("LEFT")
        b.nom:SetText(p.name .. " · " .. (n > 0 and ns.moneySigned(c.gain) or "rien"))
      end
      b.phase:SetText(passage and (n == 0 and "vide" or (n .. (n > 1 and " lignes" or " ligne"))) or PHASE_NOM[ns.phase(p)])
      b.fond:SetShown(p == cur)
      b.trait:SetShown(p == cur)
      b:Show()
    end
    for i = #tous + 1, #entrees do entrees[i]:Hide() end
    liste:SetHeight(#tous * ENTREE_H + 8)
    if sc.ScrollBar then sc.ScrollBar:SetShown(liste:GetHeight() > sc:GetHeight()) end -- la barre seulement si ça déborde
  end
end

-- Les quatre options du calcul (déduire les sacs, la banque, les autres persos ; compter les recettes pas apprises) : dans la
-- page Composants des réglages fusionnés du socle (AzerothCommune.Regrouper, reglages), plus dans la fenêtre.
local OPTIONS = { { "bags", "Déduire mes sacs" }, { "bank", "Déduire ma banque" }, { "alts", "Déduire mes autres persos" },
  { "unlearned", "Compter les recettes pas encore apprises" } }
local casesOptions = {}
local function reglages(page, ancre)
  local titre = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titre:SetPoint("TOPLEFT", ancre, "BOTTOMLEFT", 0, -20)
  titre:SetText("Calcul de l'arbre")
  local prev = titre
  for _, o in ipairs(OPTIONS) do
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", prev == titre and -2 or 0, -6)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label:SetText(o[2])
    cb.cle = o[1]
    cb:SetChecked(opts()[o[1]])
    cb:SetScript("OnClick", function(self)
      opts()[o[1]] = self:GetChecked() and true or false
      refresh()
      ns.refreshNeeds()
    end)
    casesOptions[o[1]] = cb
    prev = cb
  end
end

local function build()
  frame = ns.newWindow("ComposantsFrame", "Composants", W, H_FEN) -- son titre : le nom du projet affiché (frame.syncProjet)
  local function button(text, w, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end
  local function surPassage() return ns.estPassage(projet()) end
  frame.syncColonne = colonne(frame)

  -- L'en-tête : le nom du projet dans la barre de titre, le fil dessous. On renomme par la colonne (clic droit).
  frame.syncFil = ns.fil(frame, X0, -TOP_CONTENU)

  -- Ligne d'ajout, en Préparer seulement : la recherche (taper un nom, ou y déposer un objet) et la quantité.
  local qty = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  qty:SetSize(40, 22)
  qty:SetAutoFocus(false)
  qty:SetNumeric(true)
  qty:SetText("1")
  local name = searchBox(qty)
  name:SetPoint("TOPLEFT", X0 + 6, -TOP_CONTENU - 28)
  local indice = name:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  indice:SetPoint("LEFT", 2, 0)
  indice:SetText("ajouter un objet… (ou le déposer ici)")
  local function indiquer() indice:SetShown((name:GetText() or "") == "" and not name:HasFocus()) end
  name:HookScript("OnTextChanged", indiquer)
  name:HookScript("OnEditFocusGained", indiquer)
  name:HookScript("OnEditFocusLost", indiquer)
  local fois = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  fois:SetPoint("LEFT", name, "RIGHT", 10, 0)
  fois:SetText("×")
  qty:SetPoint("LEFT", fois, "RIGHT", 8, 0)
  local ajout = { name, fois, qty }

  -- Le bouton d'action, en bas à droite : un seul visible, selon la phase. Lancer (Préparer) ; la prochaine fabrication
  -- (Fabriquer : Fabriquer.lua le pose au même endroit, frame.action) ; Clore (Fini).
  frame.action = CreateFrame("Frame", nil, frame)
  frame.action:SetSize(1, 24)
  frame.action:SetPoint("BOTTOMRIGHT", -28, 10) -- à gauche de la poignée
  -- Lancer (CONTEXT.md) : le projet passe à Réunir, la petite vue (ses Besoins) prend la place de la grande. Sur le
  -- Brouillon (un projet de passage), un vrai projet naît (le passage se vide). Grisé sans ligne ; refusé par le fournisseur de l'emplacement :
  -- grisé, « Lancer (<sa raison>) ».
  local lancerB = button("Lancer", 140, function()
    if not ns.lancer(projet()) then return end
    ns.montrerVue()
  end)
  lancerB:SetHeight(24)
  lancerB:SetPoint("BOTTOMRIGHT", frame.action)
  lancerB:SetMotionScriptsWhileDisabled(true)
  lancerB:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("Lancer")
    local refus = ns.refusLancer(projet())
    if #projet().lines == 0 then GameTooltip:AddLine("Rien à lancer : ajoute un objet", 0.9, 0.3, 0.3)
    elseif refus then GameTooltip:AddLine("Pas encore : " .. refus, 0.9, 0.3, 0.3, true)
    else
      GameTooltip:AddLine("Le projet passe à Réunir : ses Besoins seuls ; tout dans les sacs, Fabriquer vient tout seul.", 1, 1, 1, true)
      if surPassage() then GameTooltip:AddLine(projet().name .. " devient un projet, une entrée vide le remplace.", 0.6, 0.6, 0.6, true) end
    end
    GameTooltip:Show()
  end)
  lancerB:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.lancerB = lancerB
  -- Clore (Fini, CONTEXT.md) : tout est fabriqué, le projet sort de la liste, sans archive ni Maj (plus rien à perdre).
  local clore = button("Clore", 140, function() supprimer(projet()) end)
  clore:SetHeight(24)
  clore:SetPoint("BOTTOMRIGHT", frame.action)
  clore:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("Clore")
    GameTooltip:AddLine("Tout est fabriqué : le projet sort de la liste.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  clore:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.clore = clore

  -- La zone de dessin : l'Arbre du socle (molette = zoom autour du curseur, glisser le fond = déplacer, clic du milieu = vue
  -- ajustée) ; chaque case, Composants la crée et la remplit (remplirCase).
  arbre = AzerothCommune.Arbre(frame, { case = remplirCase })
  arbre.zone:SetPoint("BOTTOMRIGHT", -14, 42)

  -- Le projet affiché : son nom, le fil, la colonne ; la ligne d'ajout en Préparer ; le bouton d'action de la phase ; le
  -- dessin commence sous ce qui est montré.
  frame.syncProjet = function()
    local ph = ns.phase(projet())
    frame.title:SetText(projet().name or "")
    frame.syncFil()
    frame.syncColonne()
    -- Pas de ligne d'ajout sur l'entrée Transformations : recalculée à chaque ouverture, un objet ajouté y disparaîtrait.
    local ajoutable = ph == "preparer" and ns.estPassage(projet()) ~= "transformations"
    for _, w in ipairs(ajout) do w:SetShown(ajoutable) end
    indiquer()
    local refus = ph == "preparer" and ns.refusLancer(projet())
    lancerB:SetText(refus and ("Lancer (%s)"):format(refus) or "Lancer")
    lancerB:SetWidth(math.max(140, lancerB:GetFontString():GetStringWidth() + 24))
    lancerB:SetShown(ph == "preparer")
    lancerB:SetEnabled(#projet().lines > 0 and not refus)
    clore:SetShown(ph == "fini")
    arbre.zone:SetPoint("TOPLEFT", X0 - 4, -TOP_CONTENU - (ph == "preparer" and 58 or 28))
  end

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.status:SetPoint("BOTTOMLEFT", X0, 17)
  frame.status:SetJustifyH("LEFT")
  frame.status:SetWordWrap(false)

  -- Les sacs changent, un nom d'objet arrive du serveur : on recalcule, au plus une fois par seconde.
  local pending
  local function soon()
    if pending or not frame:IsShown() then return end
    pending = true
    C_Timer.After(1, function() pending = false; refresh() end)
  end
  frame:RegisterEvent("BAG_UPDATE_DELAYED")
  frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
  frame:SetScript("OnEvent", soon)
  frame:HookScript("OnShow", function() C_Timer.After(0, refresh) end) -- la largeur du défilement n'est connue qu'affichée
  -- Agrandie (la poignée du socle) : l'arbre se réétale sur la nouvelle largeur, au plus une fois par dixième de seconde.
  local retaille
  frame:HookScript("OnSizeChanged", function()
    if retaille then return end
    retaille = true
    C_Timer.After(0.1, function() retaille = false; refresh() end)
  end)
end

-- La fenêtre : l'objet id (facultatif) entre dans le projet affiché, puis la vue de sa phase.
function ns.openCraftWindow(id, qty)
  if not frame then build() end
  if id then track(id, qty or 1) end
  ns.montrerVue()
end
-- Bouton de minicarte et entrée des options communs d'Azeroth Commune : clic ou ligne du menu = cette fenêtre.
-- Ses réglages : les options du calcul, sur la page Composants des réglages fusionnés.
AzerothCommune.Regrouper({ nom = "Composants", dossier = "Composants", icone = "Interface\\Icons\\Trade_Engineering",
  ouvrir = function() ns.openCraftWindow() end, store = function() return ns.db() end, reglages = reglages })

-- Ctrl+clic droit sur un objet n'importe où dans le jeu (sacs, banque, lien du chat, butin, fenêtre de métier, HV) : il
-- entre dans le Brouillon, jamais dans le projet affiché, et la fenêtre s'ouvre sur le Brouillon. Un objet-recette (« Plans :
-- Claymore ») donne l'objet fabriqué. Les autres touches sont prises : Ctrl+clic = cabine d'essayage, Alt+clic =
-- Mastercraft, AuctionDB, Auctionator ; chez un marchand, Ctrl+clic droit est à BetterVendorPrice.
function ns.ctrlClicDroit(link)
  if (MerchantFrame and MerchantFrame:IsShown()) or type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return end
  local id = tonumber(link:match("item:(%d+)"))
  if not id then return end
  if select(6, C_Item.GetItemInfoInstant(id)) == 9 then -- recette : l'objet dont elle porte le nom
    local name = link:match("%[(.-)%]")
    local made = name and ns.findItem((name:gsub("^.-:%s*", "")))
    if not made then return print("Composants : je ne trouve pas l'objet que fabrique " .. link .. ".") end
    id = made
  end
  local b = ns.ouvrirBrouillon()
  local deja = false
  for _, l in ipairs(b.lines) do deja = deja or l.id == id end -- déjà dedans : sa quantité ne bouge pas
  if not deja then ns.projetAjouter(b, id, 1) end
  ns.openCraftWindow()
end
if HandleModifiedItemClick then
  hooksecurefunc("HandleModifiedItemClick", function(link)
    if IsControlKeyDown() and not IsAltKeyDown() and not IsShiftKeyDown() and GetMouseButtonClicked() == "RightButton" then
      ns.ctrlClicDroit(link)
    end
  end)
end

-- /composants (ou /compo) [<lien, nom ou ID d'objet> [quantité] [tout]] : l'objet entre dans le projet affiché ; « tout »
-- coche « recettes pas apprises » (réglages). /composants demo [set|ceinture|hasard] : un projet d'essai.
SLASH_COMPOSANTS1, SLASH_COMPOSANTS2 = "/composants", "/compo"
SlashCmdList.COMPOSANTS = function(args)
  args = args or ""
  if args:match("^%s*demo") then ns.demoProjet(args:match("^%s*demo%s+(%a+)")); return ns.openCraftWindow() end
  local all = args:find("%f[%w]tout%f[%W]") ~= nil
  args = args:gsub("%f[%w]tout%f[%W]", "")
  local qty = tonumber(args:match("%s(%d+)%s*$")) or 1
  local what = args:gsub("%s%d+%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
  local id = what ~= "" and ns.findItem(what)
  if all then
    opts().unlearned = true
    if casesOptions.unlearned then casesOptions.unlearned:SetChecked(true) end
  end
  ns.openCraftWindow(id, qty)
end
