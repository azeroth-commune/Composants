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
local NODE_W, NODE_H, GAP, TOP = 190, 42, 8, 36 -- le haut laisse la place à la ligne du projet et au nom du premier artisan
local RELAY = 10 -- place réservée à un lien qui traverse un étage
local BAND_GAP = 28 -- entre les rectangles de deux artisans (la place de leur nom et de l'emplacement, haut de 16)
local MARGIN = 10   -- à gauche et à droite : le rectangle d'un artisan dépasse ses cases de 6
local STEP = NODE_H + GAP
local COLORS = {
  { 0.35, 0.80, 0.45 }, { 0.35, 0.60, 1.00 }, { 0.64, 0.21, 0.93 }, -- sacs, banque, autres persos (le violet épique du jeu)
  fabriquer = { 0.95, 0.65, 0.25 }, buy = { 0.60, 0.60, 0.62 }, none = { 0.90, 0.30, 0.30 }, target = { 1.00, 0.82, 0.00 },
  apport = { 0.30, 0.80, 0.85 },
}

local frame, content, scroll
-- Le fournisseur des emplacements (API.lua), si ce projet en a : jamais le Brouillon (on n'y commande rien), qui ne lui est
-- donc jamais passé.
local function F(p) return not ns.estBrouillon(p) and ns.fournisseur or nil end
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
-- Vue du dessin : zoom (× l'échelle qui fait tout tenir en largeur) et décalage, en unités du dessin.
local view = { zoom = 1, x = 0, y = 0, fit = 1 }
local function applyView()
  if not content then return end
  view.zoom = math.max(0.25, math.min(3, view.zoom))
  content:SetScale(view.fit * view.zoom)
  content:ClearAllPoints()
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", view.x, view.y) -- décalage dans l'échelle du dessin
end
-- Couleur de chaque artisan, dans l'ordre de la liste (ton perso d'abord) ; rouge = personne ne sait le faire.
local CRAFTER_COLORS = { { 1.00, 0.82, 0.00 }, { 0.30, 0.80, 0.85 }, { 0.95, 0.65, 0.25 }, { 0.95, 0.45, 0.75 }, { 0.45, 0.85, 0.58 } }
local boxes = {}
-- Étiquettes des livraisons entre artisans : survol = la liste.
local orderTags = {}
local function bandName(b) return b == "reste" and "toi" or tostring(b) end
local function newOrderTag()
  local t = CreateFrame("Button", nil, content, "TooltipBackdropTemplate") -- le fond des bulles du jeu, bord à la couleur du métier
  t:SetFrameLevel(content:GetFrameLevel() + 5)
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
local cards, lines, labels = {}, {}, {}
-- Les zones de l'emplacement du bloc (API.lua) : des cadres vides que le fournisseur remplit à chaque dessin. Une bande
-- (haute de 16, sur une ligne de titre ; le fournisseur règle sa largeur) ou une case (à la place d'un bloc confié) :
-- jamais la même zone pour les deux.
local function newZone(case, parent)
  local z = CreateFrame("Frame", nil, parent or content, case and "InsetFrameTemplate" or nil) -- une case : le fond en retrait d'une case
  z:SetFrameLevel(content:GetFrameLevel() + 5)
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

---------------------------------------------------------------------------------------------------
-- Hauteurs. Chaque case (ou relais) vise le milieu de ses voisins, sans chevauchement (de gauche à droite, puis retour).
-- Un relais ne prend que la hauteur d'un lien. bands (facultatif) = clés de bande dans l'ordre, n.band sur chaque nœud :
-- chaque bande est placée seule (voisins de sa bande seulement), puis les bandes sont empilées, BAND_GAP entre elles.
-- Une bande tient donc dans un rectangle ; un lien d'une bande à l'autre ne passe qu'entre deux étages.
function ns.layoutGraph(g, bands)
  local last, up, down = g.cols - 1, g.up, g.down
  local function half(n) return n.kind == "relay" and RELAY / 2 or NODE_H / 2 end
  local function size(n) return n.kind == "relay" and RELAY or STEP end
  local function bandOf(n) -- (pas « bands and n.band or 1 » : la bande « personne » a la clé false)
    if bands then return n.band end
    return 1
  end
  local offset, any = 0, false
  for _, key in ipairs(bands or { 1 }) do
    local cols, members = {}, {}
    for c = 0, last do cols[c] = {} end
    for _, n in ipairs(g.all) do
      if bandOf(n) == key then table.insert(cols[n.col], n); members[#members + 1] = n end
    end
    if #members > 0 then
      local function aim(n, around, fallback)
        local s, k = 0, 0
        for _, v in ipairs(around) do
          if bandOf(v) == key then s, k = s + v.y + half(v), k + 1 end
        end
        if k == 0 then return fallback end
        return s / k - half(n)
      end
      local function place(col)
        table.sort(col, function(a, b) if a.w ~= b.w then return a.w < b.w end return a.key < b.key end)
        local prev
        for _, n in ipairs(col) do
          n.y = (prev and n.w < prev.y + size(prev)) and prev.y + size(prev) or n.w
          prev = n
        end
      end
      table.sort(cols[0], function(a, b) return (a.index or 0) < (b.index or 0) end)
      for i, n in ipairs(cols[0]) do n.w = (i - 1) * STEP end
      place(cols[0])
      for c = 1, last do
        for _, n in ipairs(cols[c]) do n.w = aim(n, up[n], 0) end
        place(cols[c])
      end
      for c = last - 1, 0, -1 do
        for _, n in ipairs(cols[c]) do n.w = aim(n, down[n], n.y) end
        place(cols[c])
      end
      local minY, maxY = math.huge, -math.huge
      for _, n in ipairs(members) do minY, maxY = math.min(minY, n.y), math.max(maxY, n.y + 2 * half(n)) end
      if any then offset = offset + BAND_GAP end
      for _, n in ipairs(members) do n.y = n.y - minY + offset end
      offset, any = offset + maxY - minY, true
    end
  end
  g.height = offset
end

-- Le dessin de l'arbre d'un projet (res = ns.projetArbre, Projet.lua), sans rien afficher (testé hors jeu dans check.lua).
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
  local parents = {}
  for _, n in ipairs(list) do parents[n] = {} end
  for _, e in ipairs(edges) do table.insert(parents[e.to], e.from) end
  local last = 0
  for _, n in ipairs(list) do n.col = n.kind == "target" and 0 or 1 end
  for _ = 1, #list do -- ponytail: relaxation O(n²), assez pour quelques dizaines de cases ; s'arrête sur une boucle
    local changed = false
    for _, n in ipairs(list) do
      if n.kind == "item" then
        local c = #parents[n] == 0 and 0 or 1
        for _, p in ipairs(parents[n]) do c = math.max(c, p.col + 1) end
        if c ~= n.col then n.col, changed = c, true end
      end
    end
    if not changed then break end
  end
  for _, n in ipairs(list) do last = math.max(last, n.col) end

  -- Un lien qui saute des étages passe par un relais dans chacun (pas de case, juste sa place) : les cases de ces
  -- étages s'écartent pour lui, et il ne passe jamais sous une case. e.path = départ, relais…, arrivée.
  local all, up, down = {}, {}, {}
  for _, n in ipairs(list) do all[#all + 1], up[n], down[n] = n, {}, {} end
  for _, e in ipairs(edges) do
    e.path = { e.from }
    for c = e.from.col + 1, e.to.col - 1 do
      local r = { key = "R" .. e.from.key .. ">" .. e.to.key .. ":" .. c, kind = "relay", col = c }
      all[#all + 1], up[r], down[r] = r, {}, {}
      e.path[#e.path + 1] = r
    end
    e.path[#e.path + 1] = e.to
    for i = 2, #e.path do
      table.insert(down[e.path[i - 1]], e.path[i]); table.insert(up[e.path[i]], e.path[i - 1])
    end
    e.first, e.last = e.path[2], e.path[#e.path - 1]
  end
  local g = { nodes = list, edges = edges, cols = last + 1, byKey = res.caseDe, all = all, up = up, down = down,
    groups = res.blocs, groupOf = res.blocDe, livraisons = res.livraisons }

  local blocOf = {}
  for _, grp in ipairs(res.blocs) do for _, n in ipairs(grp.cases) do blocOf[n] = grp.key end end
  local sorted = {}
  for _, n in ipairs(all) do sorted[#sorted + 1] = n end
  table.sort(sorted, function(x, y) return x.col < y.col end)
  for _, n in ipairs(sorted) do
    if blocOf[n] then n.band = blocOf[n]
    else
      n.band = "reste"
      for _, p in ipairs(up[n]) do if p.band ~= nil then n.band = p.band break end end
    end
  end
  local order = {}
  for i, grp in ipairs(g.groups) do
    grp.index, order[#order + 1] = i, grp.key
    local who = {}
    for _, c in ipairs(grp.crafters) do who[#who + 1] = ("%s %d (%d/%d)"):format(c.name, c.rank, c.known, #grp.recipes) end
    grp.label = ("Étape %d · %s%s · %s"):format(grp.step, grp.key, grp.level > 0 and (" · niv. " .. grp.level .. " requis") or "",
      #who > 0 and table.concat(who, ", ") or "personne de ta liste") .. (ns.texteTemps(grp) and (" · " .. ns.texteTemps(grp)) or "")
    grp.cards = {}
    for _, n in ipairs(list) do if n.band == grp.key then grp.cards[#grp.cards + 1] = n end end
  end
  order[#order + 1] = "reste"
  ns.layoutGraph(g, order)
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
  local c = CreateFrame("Button", nil, content, "InsetFrameTemplate")
  c:SetFrameLevel(content:GetFrameLevel() + 3) -- au-dessus des cadres d'artisans
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

-- Barre : sacs, banque, autres persos, à fabriquer, à acheter (rouge si sans prix). La case de la fabrication en cours
-- (le bouton d'action) : sa barre telle qu'au lancement, la part « à fabriquer » découpée en crans, un par fabrication.
-- ponytail: figée au lancement, sinon le stock qui arrive dans les sacs et le compte des fabrications avanceraient deux fois.
local function bar(c, n)
  local e = ns.fabricationEnCours and ns.fabricationEnCours()
  e = e and e.id == n.id and e or nil
  local parts = { n.have[1], n.have[2], n.have[3], n.made, n.need, n.apport, n.qty }
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
  c:SetScript("OnUpdate", e and peindreCran or nil)
end

local function subText(n)
  local s = (n.kind ~= "target" or lectureSeule()) and ("×" .. n.qty) or "" -- en Préparer, la ligne a son champ de quantité
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

local usedLines, usedLabels = 0, 0
local function segment(x1, y1, x2, y2, col, thick)
  usedLines = usedLines + 1
  local l = lines[usedLines] or content:CreateLine(nil, "BACKGROUND")
  lines[usedLines] = l
  l:SetThickness(thick)
  l:SetColorTexture(col[1], col[2], col[3], 0.45)
  l:SetStartPoint("TOPLEFT", content, x1, -y1)
  l:SetEndPoint("TOPLEFT", content, x2, -y2)
  l:Show()
end

-- Courbe en S entre deux cases (8 segments), quantité juste avant la case d'arrivée.
local function curve(x1, y1, x2, y2, col, qty, thick)
  local px, py = x1, y1
  for i = 1, 8 do
    local t = i / 8
    local s = t * t * (3 - 2 * t)
    local x, y = x1 + (x2 - x1) * t, y1 + (y2 - y1) * s
    segment(px, py, x, y, col, thick or 2)
    px, py = x, y
  end
  if not qty then return end -- tronçon avant un relais : la quantité n'est écrite qu'à l'arrivée
  usedLabels = usedLabels + 1
  local f = labels[usedLabels] or content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  labels[usedLabels] = f
  f:ClearAllPoints()
  f:SetPoint("RIGHT", content, "TOPLEFT", x2 - 3, -y2 + 6)
  f:SetText("×" .. qty)
  f:Show()
end

local headers = {}
-- Une durée en clair : « 45 s », « 2 min », « 1 h 05 ».
-- ponytail: la même que celle de Maîtrise (Fenetre.lua) ; au socle au troisième usage.
function ns.duree(s)
  s = math.floor(s + 0.5)
  if s < 60 then return s .. " s" end
  if s < 3600 then return math.floor(s / 60 + 0.5) .. " min" end
  return ("%d h %02d"):format(math.floor(s / 3600), math.floor(s % 3600 / 60))
end
-- Le temps de fabrication d'un bloc ou du projet (t.temps, t.tempsIncomplet, Projet.lua) : « 2 min », « au moins 2 min » si
-- une recette n'a pas de temps connu, « temps inconnu » si aucune ; nil s'il n'y a plus rien à fabriquer.
function ns.texteTemps(t)
  if (t.temps or 0) > 0 then return (t.tempsIncomplet and "au moins " or "") .. ns.duree(t.temps) end
  return t.tempsIncomplet and "temps inconnu" or nil
end

local function header(i, x, text)
  local h = headers[i] or content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  headers[i] = h
  h:ClearAllPoints()
  h:SetPoint("TOPLEFT", content, "TOPLEFT", MARGIN + x, 0)
  h:SetText(text)
  h:Show()
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

  -- Les étages s'étalent sur la largeur ; trop nombreux, le dessin rétrécit pour tenir (puis molette pour zoomer).
  local avail = scroll:GetWidth()
  if avail < 100 then avail = W - X0 - 14 end -- pas encore mis en page
  local spacing = g.cols > 1 and math.max(NODE_W + 44, (avail - NODE_W - 2 * MARGIN) / (g.cols - 1)) or 0
  local width = NODE_W + spacing * (g.cols - 1) + 2 * MARGIN
  view.fit = math.min(1, avail / width)
  content:SetSize(width, math.max(1, (g.height + TOP + 10)))
  applyView()

  for _, h in ipairs(headers) do h:Hide() end
  if #roots == 0 then
    header(1, 0, ns.estBrouillon(projet()) and "|cff999999Brouillon vide : Ctrl+clic droit sur un objet n'importe où l'y met ; Lancer en fait un projet.|r"
      or "|cff999999Cherche un objet (ou dépose-le sur la recherche) ; Ctrl+clic droit sur un objet le met au Brouillon.|r")
  else
    local o = projet()
    local cost = (total == 0 and not incomplete) and "rien à acheter" or (ns.moneyShort(total) .. (incomplete and " |cffe64d4d+ ?|r" or ""))
    local fini = ns.phase(o) == "fini" and " · |cff59cc73Tout est fabriqué|r" or "" -- la phase Fini
    -- Valeur à l'HV de ce qu'on fabrique, et ce que ça rapporte quand le coût est complet ; rien sans prix.
    local v = res.valeur and (" · vaut %s à l'HV · %s"):format(ns.moneyShort(res.valeur),
      res.rapporte and "rapporte " .. ns.moneySigned(res.rapporte) or "|cffe64d4dcoût incomplet|r") or ""
    local temps = ns.texteTemps(res)
    temps = temps and (" · " .. temps .. ((res.temps or 0) > 0 and " de fabrication" or "")) or ""
    header(1, 0, (ns.estBrouillon(o) and "Brouillon · " or "Projet · ") .. cost .. v .. temps .. fini)
  end
  -- L'emplacement du projet entier : une bande à la suite de cette ligne ; confié, la seule case de l'arbre.
  zoneProjet, caseProjet = zoneProjet or newZone(), caseProjet or newZone(true)
  local zp = entier and caseProjet or zoneProjet
  zoneProjet:Hide(); caseProjet:Hide()
  if f and #roots > 0 then
    zp:ClearAllPoints()
    if entier then zp:SetPoint("TOPLEFT", content, "TOPLEFT", MARGIN, -TOP)
    else zp:SetPoint("LEFT", headers[1], "RIGHT", 12, 0); zp:SetWidth(1) end
    zp:Show()
    appel(f.bloc, zp, p, nil, entier)
  end

  local x = function(n) return MARGIN + n.col * spacing end
  local caseDuBloc = {} -- la case d'un bloc confié : le fournisseur la dessine (plus bas), pas de case de Composants
  for _, grp in ipairs(g.groups or {}) do if confies[grp.key] and grp.case then caseDuBloc[grp.case] = grp end end
  for i, n in ipairs(g.nodes) do
    local c = cards[i] or newCard()
    cards[i] = c
    c.node = n
    c:ClearAllPoints()
    c:SetShown(not caseDuBloc[n])
    c:SetPoint("TOPLEFT", content, "TOPLEFT", x(n), -(n.y + TOP))
    local k = stateColor(n)
    c.accent:SetColorTexture(k[1], k[2], k[3], 0.9)
    c.icon:SetTexture(C_Item.GetItemIconByID(n.id))
    c.name:SetText(ns.itemLabel(n.id))
    c.sub:SetText((subText(n):gsub("^ ", "")))
    local target = n.kind == "target" and not lectureSeule() -- son champ de quantité, en Préparer seulement
    c.qty:SetShown(target); c.qty:SetEnabled(target and lignes())
    if target and not c.qty:HasFocus() then c.qty:SetText(n.qty) end
    c.sub:SetPoint("TOPLEFT", target and 80 or 40, -20)
    local t = toggleOf(n)
    local sign = lectureSeule() and "" or (n.made > 0 and "–") or (t and "+") or ""
    c.toggle:SetText(n.choix and ("|cffffd100" .. sign .. "|r") or sign)
    if n.choix then c:LockHighlight() else c:UnlockHighlight() end
    bar(c, n)
  end
  for i = #g.nodes + 1, #cards do cards[i]:Hide() end
  -- En Fabriquer, le bouton d'action en bas nomme la prochaine fabrication, sa case cerclée (Fabriquer.lua).
  ns.rafraichirToutFabriquer(function(id)
    for i = 1, #g.nodes do if cards[i].node.id == id then return cards[i] end end
  end)
  if #roots > 0 then -- un « Étage » que la ligne du projet recouvrirait est sauté (la case de l'étape dit déjà où l'on est)
    local libre = headers[1]:GetStringWidth() + 24 + (zoneProjet:IsShown() and zoneProjet:GetWidth() + 12 or 0)
    for c = 1, g.cols - 1 do if spacing * c >= libre then header(c + 1, spacing * c, "Étage " .. c) end end
  end

  -- Un rectangle par artisan : toutes ses cases (et ce qui n'est pas fabriqué sous elles), à sa couleur, son nom
  -- au-dessus (et « recette à apprendre »). Rouge : personne de ta liste ne sait le faire.
  local usedBoxes, boxOf, usedZones = 0, {}, 0
  for _, grp in ipairs(g.groups or {}) do
    local top, bottom, left, right = math.huge, -math.huge, math.huge, -math.huge
    for _, n in ipairs(grp.cards) do
      top, bottom = math.min(top, n.y), math.max(bottom, n.y + NODE_H)
      left, right = math.min(left, x(n)), math.max(right, x(n) + NODE_W)
    end
    usedBoxes = usedBoxes + 1
    local b = boxes[usedBoxes]
    if not b then
      b = CreateFrame("Frame", nil, content, "BackdropTemplate")
      b:SetFrameLevel(content:GetFrameLevel() + 1)
      b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      b.name:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 4, 2)
      -- Survol du nom : les recettes du métier, leur niveau requis, qui les connaît ; puis qui a le métier.
      b.hit = CreateFrame("Button", nil, b)
      b.hit:SetAllPoints(b.name)
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
      b.zone:SetPoint("LEFT", b.name, "RIGHT", 8, 0)
      boxes[usedBoxes] = b
    end
    local k = #grp.crafters > 0 and CRAFTER_COLORS[(grp.index - 1) % #CRAFTER_COLORS + 1] or COLORS.none
    boxOf[grp.key], b.color = b, k
    b:SetBackdropColor(k[1], k[2], k[3], 0.06)
    b:SetBackdropBorderColor(k[1], k[2], k[3], 0.7)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", content, "TOPLEFT", left - 6, -(top + TOP) + 6)
    b:SetSize(right - left + 12, bottom - top + 12)
    b.name:SetTextColor(k[1], k[2], k[3])
    b.name:SetText(grp.label)
    b.grp = grp
    b:Show()
    -- L'emplacement : une bande sur la ligne de titre ; confié, la case du bloc (à la place de la sienne).
    b.zone:SetShown(f ~= nil and not grp.case)
    if b.zone:IsShown() then b.zone:SetWidth(1); appel(f.bloc, b.zone, p, grp, false) end
    if f and grp.case then
      usedZones = usedZones + 1
      local z = zonesCase[usedZones] or newZone(true)
      zonesCase[usedZones] = z
      z:ClearAllPoints()
      z:SetPoint("TOPLEFT", content, "TOPLEFT", x(grp.case), -(grp.case.y + TOP))
      z:Show()
      appel(f.bloc, z, p, grp, true)
    end
  end
  for i = usedBoxes + 1, #boxes do boxes[i]:Hide() end
  for i = usedZones + 1, #zonesCase do zonesCase[i]:Hide() end

  -- Chaque courbe part et arrive à sa propre hauteur sur le bord de la case, dans l'ordre des cases d'en face :
  -- pas de croisement au départ, et les quantités ne se marchent pas dessus.
  -- ponytail: au-delà de 3 courbes sur un même bord, les quantités se rapprochent trop ; agrandir NODE_H si ça arrive
  local outs, ins, drawn = {}, {}, {}
  local livree = {}
  for _, e in ipairs(g.edges) do -- une livraison entre blocs : un seul lien (le premier), épais
    if not e.livraison or not livree[e.livraison] then drawn[#drawn + 1], livree[e.livraison or e] = e, true end
  end
  for _, e in ipairs(drawn) do
    outs[e.from] = outs[e.from] or {}
    ins[e.to] = ins[e.to] or {}
    table.insert(outs[e.from], e)
    table.insert(ins[e.to], e)
  end
  local function spread(map, field, other)
    for _, es in pairs(map) do
      table.sort(es, function(a, b)
        if a[other].y ~= b[other].y then return a[other].y < b[other].y end
        return a[other].key < b[other].key
      end)
      for i, e in ipairs(es) do e[field] = NODE_H * i / (#es + 1) end
    end
  end
  spread(outs, "dy1", "first")
  spread(ins, "dy2", "last")
  usedLines, usedLabels = 0, 0
  local usedTags = 0
  for _, e in ipairs(drawn) do
    local k = stateColor(e.to)
    local thick = e.livraison and 4 or 2
    if e.livraison then
      local grp = g.groupOf[e.livraison.maker]
      k = #grp.crafters > 0 and CRAFTER_COLORS[(grp.index - 1) % #CRAFTER_COLORS + 1] or COLORS.none
    end
    local px, py = x(e.from) + NODE_W, e.from.y + TOP + e.dy1
    for i = 2, #e.path - 1 do -- relais : on y entre, on traverse l'étage tout droit, on en ressort
      local r = e.path[i]
      local ry = r.y + TOP + RELAY / 2
      curve(px, py, x(r), ry, k, nil, thick)
      segment(x(r), ry, x(r) + NODE_W, ry, k, thick)
      px, py = x(r) + NODE_W, ry
    end
    local ex, ey = x(e.to), e.to.y + TOP + e.dy2
    curve(px, py, ex, ey, k, not e.livraison and e.qty or nil, thick)
  end
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
      t:SetPoint("LEFT", shelf[b] or (b.zone:IsShown() and b.zone or b.name), "RIGHT", 6, 0)
      shelf[b] = t
      t:Show()
      -- Jamais au-delà du bord droit visible (en unités du dessin) : tronquée, cachée s'il reste moins de 40.
      local l, cl = t:GetLeft(), content:GetLeft()
      local place = l and cl and scroll:GetWidth() / content:GetScale() - view.x - 4 - (l - cl)
      if place and t:GetWidth() > place then
        t:SetWidth(math.max(40, place)); t.text:SetWidth(math.max(40, place) - 12)
        t:SetShown(place >= 40)
      end
    end
  end
  for i = usedTags + 1, #orderTags do orderTags[i]:Hide() end
  for i = usedLines + 1, #lines do lines[i]:Hide() end
  for i = usedLabels + 1, #labels do labels[i]:Hide() end
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
-- plus aucun projet : le Brouillon (pas un projet vide créé pour rien). Signalé (QuandChange) : un autre add-on y range ce
-- qu'il doit.
local function supprimer(p)
  local affiche = projet()
  local _, i = ns.projet(p.id)
  if not i then return end
  ns.db().courant = i
  ns.supprimerProjet()
  if ns.estBrouillon(affiche) or #ns.db().projets == 0 then ns.ouvrirBrouillon()
  elseif affiche ~= p then ns.ouvrirProjet(affiche.id) end
  ns.montrerVue()
end

-- La colonne des projets (skill ui-addon : une colonne toujours visible, pas un menu déroulant) : le Brouillon en tête,
-- puis chaque projet avec sa phase, celui affiché surligné ; clic = l'ouvrir dans la vue de sa phase ; clic droit =
-- Renommer (un champ sur l'entrée : Entrée garde, Échap annule), Supprimer ; le Brouillon : Vider. Elle défile au-delà de
-- sa hauteur. Rend la fonction qui la met à jour.
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
      if ns.estBrouillon(self.p) then ns.ouvrirBrouillon() else ns.ouvrirProjet(self.p.id) end
      ns.montrerVue()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.nom:GetText())
      if self.p.tenu then GameTooltip:AddLine(self.p.tenu, 1, 0.82, 0, true) end
      GameTooltip:AddLine("Clic : l'ouvrir", 0.6, 0.6, 0.6)
      GameTooltip:AddLine(ns.estBrouillon(self.p) and "Clic droit : le vider" or "Clic droit : Renommer, Supprimer", 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    entrees[i] = b
    return b
  end
  return function()
    local tous, cur = { ns.brouillon() }, projet()
    for _, p in ipairs(ns.db().projets) do tous[#tous + 1] = p end
    for i, p in ipairs(tous) do
      local b = entrees[i] or entree(i)
      local brouillon = ns.estBrouillon(p)
      b.p = p
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 0, -((i - 1) * ENTREE_H + (i > 1 and 8 or 0))) -- le Brouillon un peu à part
      b.nom:SetFontObject(brouillon and "GameFontNormalSmall" or "GameFontHighlightSmall")
      b.nom:SetJustifyH("LEFT") -- (SetFontObject le remet au centre)
      b.nom:SetText(brouillon and "Brouillon" or (p.name or "?"))
      local n = #p.lines
      b.phase:SetText(brouillon and (n == 0 and "vide" or (n .. (n > 1 and " lignes" or " ligne"))) or PHASE_NOM[ns.phase(p)])
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
  local function surBrouillon() return ns.estBrouillon(projet()) end
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
  -- Brouillon, un vrai projet naît (le Brouillon se vide). Grisé sans ligne ; refusé par le fournisseur de l'emplacement :
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
      if surBrouillon() then GameTooltip:AddLine("Le Brouillon devient un projet, un Brouillon vide le remplace.", 0.6, 0.6, 0.6, true) end
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

  -- La zone de dessin : molette = zoom autour du curseur, glisser le fond = déplacer, clic du milieu = vue ajustée.
  scroll = CreateFrame("Frame", nil, frame)
  scroll:SetPoint("BOTTOMRIGHT", -14, 42)
  scroll:SetClipsChildren(true)

  -- Le projet affiché : son nom, le fil, la colonne ; la ligne d'ajout en Préparer ; le bouton d'action de la phase ; le
  -- dessin commence sous ce qui est montré.
  frame.syncProjet = function()
    local b, ph = surBrouillon(), ns.phase(projet())
    frame.title:SetText(b and "Brouillon" or projet().name or "")
    frame.syncFil()
    frame.syncColonne()
    for _, w in ipairs(ajout) do w:SetShown(ph == "preparer") end
    indiquer()
    local refus = ph == "preparer" and ns.refusLancer(projet())
    lancerB:SetText(refus and ("Lancer (%s)"):format(refus) or "Lancer")
    lancerB:SetWidth(math.max(140, lancerB:GetFontString():GetStringWidth() + 24))
    lancerB:SetShown(ph == "preparer")
    lancerB:SetEnabled(#projet().lines > 0 and not refus)
    clore:SetShown(ph == "fini")
    scroll:SetPoint("TOPLEFT", X0 - 4, -TOP_CONTENU - (ph == "preparer" and 58 or 28))
  end
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(W - X0 - 14, 1)
  local function cursor() -- le curseur dans la zone, vers la droite et vers le bas
    local cx, cy = GetCursorPosition()
    local es = scroll:GetEffectiveScale()
    return cx / es - scroll:GetLeft(), scroll:GetTop() - cy / es
  end
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, d)
    local mx, my = cursor()
    local s = view.fit * view.zoom
    local px, py = mx / s - view.x, my / s + view.y -- le point du dessin sous le curseur…
    view.zoom = view.zoom * (d > 0 and 1.15 or 1 / 1.15)
    applyView()
    s = view.fit * view.zoom
    view.x, view.y = mx / s - px, py - my / s -- …reste sous le curseur
    applyView()
  end)
  scroll:EnableMouse(true)
  local drag
  scroll:SetScript("OnMouseDown", function(_, button)
    if button == "MiddleButton" then view.zoom, view.x, view.y = 1, 0, 0; return applyView() end
    local mx, my = cursor()
    drag = { mx = mx, my = my, x = view.x, y = view.y }
  end)
  scroll:SetScript("OnMouseUp", function() drag = nil end)
  scroll:SetScript("OnUpdate", function()
    if not drag then return end
    if not IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("RightButton") then drag = nil return end
    local mx, my = cursor()
    local s = view.fit * view.zoom
    view.x, view.y = drag.x + (mx - drag.mx) / s, drag.y - (my - drag.my) / s -- le dessin suit la souris
    applyView()
  end)

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
