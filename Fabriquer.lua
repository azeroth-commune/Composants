-- Composants, la prochaine fabrication du projet affiché (CONTEXT.md) : en phase Fabriquer, le seul bouton d'action de la
-- grande vue, en bas, la nomme (« Silex à aiguiser ×7 ») et sa case est cerclée d'or dans l'arbre. Clic = une
-- fabrication, clic droit = tout ce que les sacs permettent (le jeu enchaîne lui-même, comme son « Créer tout ») ; sans la
-- fenêtre du bon métier, « Ouvre Forge » (un bouton sécurisé dont la macro lance le métier). Le compte avance comme dans
-- l'arbre : l'objet fabriqué arrive dans les sacs et l'arbre le déduit. C'est le seul endroit où l'on fabrique (plus de
-- bouton sous la fenêtre de métier). Jamais deux recettes sur un clic.
-- Forever, API moderne : C_TradeSkillUI.CraftRecipe(recette, nombre), l'appel même du bouton « Créer » du jeu
-- (Blizzard_ProfessionsTemplates/Blizzard_ProfessionsTransaction.lua:354) ; GetCraftableCount (combien les sacs en
-- permettent), GetRecipeInfo(...).learned, GetRecipeRequirements (outils, forge) ; le métier ouvert :
-- GetBaseProfessionInfo().professionName, comme le relevé du socle (AzerothCommune.lua:264).
local _, ns = ...

-- Le nom d'un objet sur un bouton : le lien du jeu (sa couleur), sans les crochets.
local function nom(id) return (ns.itemLabel(id):gsub("%[(.-)%]", "%1")) end

-- Ce qu'il reste à fabriquer dans l'arbre d'un projet : { cle (la recette), recette, id (l'objet, nil pour un
-- enchantement), fois }, du bas vers le haut (une case vient après les cases fabriquées qu'il lui faut), puis dans l'ordre
-- de l'arbre.
local function aFabriquer(res)
  local niveau = {}
  local function niv(n)
    if not niveau[n] then
      niveau[n] = 1 -- boucle : coupée
      local m = 1
      for _, c in ipairs(n.children) do if c.made > 0 then m = math.max(m, niv(c) + 1) end end
      niveau[n] = m
    end
    return niveau[n]
  end
  local out = {}
  for i, n in ipairs(res.cases) do
    if n.made > 0 and type(n.recipeKey) == "number" then
      out[#out + 1] = { cle = n.recipeKey, recette = n.recipe, id = n.id, fois = n.crafts, niv = niv(n), rang = i }
    end
  end
  for i, r in ipairs(res.roots) do -- un enchantement : pas de case, seulement ses composants
    if r.fabrication and not r.id and type(r.recipeKey) == "number" then
      local m = 1
      for _, part in ipairs(r.parts) do
        local c = res.caseDe["I" .. part.id]
        if c and c.made > 0 then m = math.max(m, niv(c) + 1) end
      end
      out[#out + 1] = { cle = r.recipeKey, recette = r.recipe, fois = r.crafts, niv = m, rang = #res.cases + i }
    end
  end
  table.sort(out, function(a, b) if a.niv ~= b.niv then return a.niv < b.niv end return a.rang < b.rang end)
  return out
end

-- Pourquoi une recette apprise ne se fait pas : le premier composant qui manque dans les sacs (un objet), sinon le premier
-- outil ou lieu requis absent (un nom), sinon nil.
local function manque(f)
  for _, rg in ipairs(f.recette.reagents or {}) do
    if rg.id and C_Item.GetItemCount(rg.id) < rg.qty then return nom(rg.id) end
  end
  local T = C_TradeSkillUI
  local ok, req = pcall(T.GetRecipeRequirements, f.cle)
  for _, r in ipairs(ok and type(req) == "table" and req or {}) do
    if type(r) == "table" and r.met == false and r.name then return r.name end
  end
end

-- Combien de fois les sacs permettent une fabrication (au plus f.fois) : ses composants seulement ; les outils et la
-- forge, le jeu le dit une fois sa fenêtre ouverte.
local function possible(f)
  local n = f.fois
  for _, rg in ipairs(f.recette.reagents or {}) do
    if rg.id then n = math.min(n, math.floor(C_Item.GetItemCount(rg.id) / rg.qty)) end
  end
  return n
end

-- L'état d'une fabrication, la fenêtre de son métier ouverte : "pret" (n = ce qu'on peut faire d'un coup, au plus fois),
-- "atelier" (f.atelier : l'atelier ou l'outil que le jeu dit absent, GetRecipeRequirements, son nom tel quel ; le jeu
-- refuserait), "manque" (et le premier manque), "inconnue" (ce perso ne l'a pas apprise). Le jeu ne dit rien : rien de deviné.
local function etatOuvert(f)
  local T = C_TradeSkillUI
  local info = T.GetRecipeInfo(f.cle)
  if not (info and info.learned) then f.etat = "inconnue" return f end
  local ok, req = pcall(T.GetRecipeRequirements, f.cle)
  for _, r in ipairs(ok and type(req) == "table" and req or {}) do
    if type(r) == "table" and r.met == false and r.name then f.etat, f.atelier = "atelier", r.name return f end
  end
  local n = T.GetCraftableCount(f.cle) or 0
  if n > 0 then f.etat, f.n = "pret", math.min(n, f.fois) else f.etat, f.manque = "manque", manque(f) end
  return f
end

-- La prochaine fabrication du projet p (celui affiché), tous métiers, dans
-- l'ordre de aFabriquer ; la première que les composants des sacs permettent. Fenêtre de son métier ouverte (metier) : le
-- jeu la confirme (etatOuvert) ; sinon etat = "ouvrir" (n = ce que les sacs permettent). Aucune : la première, etat =
-- "manque". Rien à fabriquer : nil, et fini = true quand les objets du projet sont tous là.
-- ponytail: l'arbre est recalculé ici, en plus du dessin de la fenêtre ; à partager si ça se sent.
function ns.prochaineDuProjet(p, metier)
  local res = ns.projetArbre(p, nil, ns.apportsEmplacement(p))
  -- Une recette pas apprise dont le patron est dans les sacs : l'apprendre d'abord (etat = "apprendre", f.patron l'objet ;
  -- le bouton l'utilise). Apprise, le patron quitte les sacs et l'étape passe d'elle-même.
  -- ponytail: pas pour un enchantement sans case (racine sans objet) ; il reste « Recette inconnue ».
  for _, n in ipairs(res.cases) do
    local patron = n.made > 0 and n.unknown and n.recipe and ns.patronEnSac(n.recipe)
    if patron then return { etat = "apprendre", patron = patron, recette = n.recipe, id = n.id, p = p } end
  end
  local liste = aFabriquer(res)
  for _, f in ipairs(liste) do
    f.p = p
    local n = possible(f)
    if n > 0 then
      if f.recette.profession == metier then return etatOuvert(f) end
      f.etat, f.n = "ouvrir", n
      return f
    end
  end
  local f = liste[1]
  if f then f.p, f.etat, f.manque = p, "manque", manque(f) return f end
  return nil, ns.projetFini(res)
end

-- Les objets du projet sont tous là (rien à acheter ni à fabriquer pour eux) : « Tout est fabriqué » sur sa ligne.
function ns.projetFini(res)
  if #res.roots == 0 then return false end
  for _, c in ipairs(res.cases) do if c.kind == "target" and (c.need > 0 or c.made > 0) then return false end end
  return true
end

-- « 4 × Barre d'étain » : les objets que n fabrications donnent ; un enchantement, n × son nom.
local function combien(f, n)
  if f.id then return ("%d × %s"):format(n * math.max(1, f.recette.made_min or 1), nom(f.id)) end
  return ("%d × %s"):format(n, f.recette.name or "?")
end

-- La phrase de la bulle du bouton d'action : la prochaine action et son nombre, ou pourquoi rien ; e = la fabrication en cours.
function ns.texteToutFabriquer(f, fini, e)
  if e then return ("%s %d/%d…"):format(e.nom, e.fait * e.per, e.n * e.per) end
  if not f then return fini and "Tout est fabriqué" or "Rien à fabriquer" end
  if f.etat == "apprendre" then return ("Apprendre %s avec %s"):format(f.recette.name or "?", nom(f.patron)) end
  if f.etat == "pret" then return "Fabriquer " .. combien(f, f.n) end
  if f.etat == "ouvrir" then return ("Ouvrir %s : %s"):format(f.recette.profession or "son métier", combien(f, f.n)) end
  if f.etat == "inconnue" then return "Recette inconnue : " .. (f.recette.name or "?") end
  if f.etat == "atelier" then return ("Requiert %s pour fabriquer %s : approche-toi de l'atelier (ou prends l'outil)"):format(f.atelier, combien(f, f.n or f.fois)) end
  if f.manque then return ("Il manque %s pour %s"):format(f.manque, combien(f, f.fois)) end
  return "Il manque de quoi faire " .. combien(f, f.fois)
end

-- Le libellé du bouton d'action : la prochaine fabrication et ce qu'il en reste à faire (« Silex à aiguiser ×7 », en
-- objets), « Ouvre Forge », ou pourquoi rien ; e = la fabrication en cours (« Barre de bronze 2/4… »). La phrase entière
-- va dans sa bulle (texteToutFabriquer).
function ns.texteBouton(f, e)
  if e then return ("%s %d/%d…"):format(e.nom, e.fait * e.per, e.n * e.per) end
  if not f then return "Rien à fabriquer" end
  if f.etat == "apprendre" then return "Apprendre : " .. (f.recette.name or "?") end
  if f.etat == "ouvrir" then return "Ouvre " .. (f.recette.profession or "son métier") end
  if f.etat == "inconnue" then return "Recette inconnue : " .. (f.recette.name or "?") end
  if f.etat == "atelier" then return "Requiert : " .. f.atelier end
  if f.etat == "manque" then return "Il manque " .. (f.manque or "un composant") end
  local per = f.id and math.max(1, f.recette.made_min or 1) or 1
  return ("%s ×%d"):format(f.id and nom(f.id) or f.recette.name or "?", f.fois * per)
end

local function metierOuvert()
  local T = C_TradeSkillUI
  if not (T and T.GetBaseProfessionInfo) then return end
  if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
    or (T.IsNPCCrafting and T.IsNPCCrafting()) then return end -- le métier d'un autre
  local p = T.GetBaseProfessionInfo()
  return p and p.professionName ~= "" and p.professionName or nil
end

---------------------------------------------------------------------------------------------------
-- Le bouton d'action en Fabriquer (frame.action de Fenetre.lua, en bas de la grande vue) : guider sans réfléchir, quoi
-- fabriquer, combien, dans quelle fenêtre ; la case de la prochaine fabrication cerclée d'or. Pendant une
-- fabrication, le bouton compte (« Barre de bronze 2/4… », grisé) et ne prend pas de second clic, la barre de la case
-- avance cran par cran (Fenetre.lua) ; finie, il passe tout seul à la suivante. La fenêtre du métier fermée :
-- « Ouvre <métier> », car l'ouvrir est une action protégée (CastSpell) : c'est un bouton sécurisé dont la macro lance le
-- métier. Ses attributs ne s'écrivent que hors combat ; en combat il quitte la fenêtre (un enfant protégé la rendrait
-- protégée : ni fermée ni déplacée en combat) et y revient à la sortie.
local tf, tfF, encours
local function enCombat() return InCombatLockdown and InCombatLockdown() end
local function enIncantation() return UnitCastingInfo and UnitCastingInfo("player") ~= nil end
local OR = { 1.00, 0.82, 0.00 } -- le doré des textes du jeu

-- La part « à fabriquer » de la barre de la case en crans, un par fabrication. ponytail: au-delà de 20, sur les 142 px de
-- la barre, les séparations ne se lisent plus (moins de 7 px par cran) : une barre continue.
function ns.crans(n) return n <= 20 and n or 0 end

-- La part faite (0 à 1) de l'incantation en cours de la fabrication e, lue comme la barre d'incantation du jeu
-- (UnitCastingInfo : début et fin en ms). Secrète, absente ou une autre : 0, le cran se remplit d'un coup à la fin
-- (UNIT_SPELLCAST_SUCCEEDED). Aucune opération sur une valeur secrète : issecretvalue d'abord.
local function partEnCours(e)
  if not UnitCastingInfo then return 0 end
  local _, _, _, debut, fin, _, _, _, sort = UnitCastingInfo("player")
  local secret = issecretvalue and (issecretvalue(debut) or issecretvalue(fin) or issecretvalue(sort))
  if not secret and type(debut) == "number" and type(fin) == "number" and sort == e.cle and fin > debut then
    return math.min(1, math.max(0, (GetTime() * 1000 - debut) / (fin - debut)))
  end
  return 0
end

-- Le remplissage (0 à 1) : les fabrications finies, plus la part de l'incantation en cours.
function ns.avancement(e) return math.min(1, (e.fait + partEnCours(e)) / e.n) end

-- Le compte à rebours de la fabrication en cours (la case, l'étape et la ligne du projet, chaque seconde, Fenetre.lua) :
-- ce qu'il lui reste (fabrications restantes × cast, moins la part faite de l'incantation en cours) et ce qui est déjà
-- écoulé de l'incantation en cours, en secondes ; nil sans temps connu (recette sans cast).
-- ponytail: même source que la barre ; incantation secrète, le compte tombe d'un cast à chaque fabrication finie.
function ns.resteEnCours(e)
  if not (e and e.cast) then return nil end
  local part = partEnCours(e)
  return math.max(0, e.n - e.fait - part) * e.cast, part * e.cast
end

-- La fabrication lancée par le bouton d'action, nil une fois finie : { id, cle, n fabrications, per objets chacune, fait,
-- cast (secondes, nil si inconnu) }.
-- La case de son objet en dessine l'avancement (Fenetre.lua, sa barre).
function ns.fabricationEnCours()
  -- ponytail: fin sans événement (le jeu refuse sans incantation) : 3 s sans fonte ni incantation, la fabrication est finie.
  if encours and (encours.fait >= encours.n or (not enIncantation() and GetTime() - encours.t > 3)) then encours = nil end
  return encours
end

local function lancer(_, souris)
  local f = tfF
  if encours or not (f and f.etat == "pret") then return end -- en cours, ou « Ouvre » (la macro s'en charge)
  local n = souris == "RightButton" and f.n or 1 -- clic : une ; clic droit : tout ce que les sacs permettent
  encours = { cle = f.cle, id = f.id, nom = f.id and nom(f.id) or f.recette.name or "?",
    per = f.id and math.max(1, f.recette.made_min or 1) or 1, n = n, fait = 0, t = GetTime(), cast = f.recette.cast }
  C_TradeSkillUI.CraftRecipe(f.cle, n)
  C_Timer.After(3.5, ns.refreshCraftWindow)
  ns.refreshCraftWindow()
end

local function construireTout(parent) -- hors combat seulement : un bouton sécurisé ne se crée ni ne s'ancre en combat
  tf = CreateFrame("Button", "ComposantsToutFabriquer", parent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
  local t = tf:GetFontString()
  t:ClearAllPoints(); t:SetPoint("LEFT", 8, 0); t:SetPoint("RIGHT", -8, 0); t:SetWordWrap(false)
  -- les deux sens, selon ActionButtonUseKeyDown ; lancer ne part qu'une fois (encours)
  tf:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
  tf:SetAttribute("useOnKeyDown", GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") or false)
  tf:SetMotionScriptsWhileDisabled(true) -- la bulle dit aussi pourquoi il est grisé
  tf:SetScript("PostClick", lancer)
  tf:SetScript("OnEnter", function(self)
    if not tfF then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("Prochaine fabrication du projet", OR[1], OR[2], OR[3])
    GameTooltip:AddLine(ns.texteToutFabriquer(tfF, nil, encours), 1, 1, 1, true)
    if tfF.etat == "ouvrir" and not encours then GameTooltip:AddLine("Clic : ouvre la fenêtre du métier", 0.6, 0.6, 0.6, true)
    elseif tfF.etat == "apprendre" and not encours then GameTooltip:AddLine("Clic : utilise le patron", 0.6, 0.6, 0.6, true)
    elseif tfF.etat == "pret" and not encours then
      GameTooltip:AddLine("Clic : une fabrication", 0.6, 0.6, 0.6)
      GameTooltip:AddLine(("Clic droit : tout ce que tes sacs permettent (%d)"):format(tfF.n), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
  end)
  tf:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Le cercle doré sur la case de la prochaine fabrication (gris si rien n'est possible) : ses textures à elle, dans le
-- dessin ; une seule case cerclée à la fois.
local cerclee
local function cercler(c, k, a)
  if cerclee and cerclee ~= c then for i = 1, 4 do cerclee.contour[i]:Hide() end end
  cerclee = c
  if not c then return end
  if not c.contour then
    c.contour = {}
    for i = 1, 4 do c.contour[i] = c:CreateTexture(nil, "OVERLAY", nil, 7) end
  end
  local b = c.contour
  for i = 1, 4 do b[i]:ClearAllPoints(); b[i]:SetColorTexture(k[1], k[2], k[3], a); b[i]:Show() end
  b[1]:SetPoint("TOPLEFT", c, 0, 0); b[1]:SetPoint("TOPRIGHT", c, 0, 0); b[1]:SetHeight(2)
  b[2]:SetPoint("BOTTOMLEFT", c, 0, 0); b[2]:SetPoint("BOTTOMRIGHT", c, 0, 0); b[2]:SetHeight(2)
  b[3]:SetPoint("TOPLEFT", c, 0, 0); b[3]:SetPoint("BOTTOMLEFT", c, 0, 0); b[3]:SetWidth(2)
  b[4]:SetPoint("TOPRIGHT", c, 0, 0); b[4]:SetPoint("BOTTOMRIGHT", c, 0, 0); b[4]:SetWidth(2)
end
ns.cerclee = function() return cerclee end -- (lu par les tests)

-- Appelé à la fin de chaque dessin de l'arbre (Fenetre.lua) : carteDe(id) = la case affichée de cet objet. Seulement en
-- phase Fabriquer (CONTEXT.md, Prochaine fabrication) : en Préparer on choisit encore ses cases, en Fini c'est « Clore ».
function ns.rafraichirToutFabriquer(carteDe)
  if enCombat() then return end -- en combat : refait à la sortie (PLAYER_REGEN_ENABLED)
  ns.fabricationEnCours()
  local p, fenetre = ns.projetCourant(), ComposantsFrame
  local enFabriquer = ns.phase(p) == "fabriquer"
  local f = enFabriquer and ns.prochaineDuProjet(p, ProfessionsFrame and ProfessionsFrame:IsShown() and metierOuvert() or nil) or nil
  tfF = f
  local id = encours and encours.id or f and f.id
  local case = id and carteDe(id)
  if not (enFabriquer and fenetre and fenetre.action) then
    if tf then tf:Hide() end
    cercler(nil)
    return
  end
  if not tf then construireTout(fenetre) end
  local ouvrir = f and f.etat == "ouvrir" and not encours
  local apprendre = f and f.etat == "apprendre" and not encours -- utiliser un objet est protégé : la macro du bouton sécurisé
  local actif = encours or ouvrir or apprendre or (f and f.etat == "pret")
  tf:SetText(ns.texteBouton(f, encours))
  tf:SetAttribute("type", (ouvrir or apprendre) and "macro" or nil)
  tf:SetAttribute("macrotext", ouvrir and ("/cast " .. f.recette.profession) or apprendre and ("/use item:" .. f.patron) or nil)
  tf:SetEnabled((actif and not encours) and true or false)
  tf:SetDisabledFontObject(encours and GameFontHighlight or GameFontDisable) -- l'avancement se lit, en blanc
  tf:SetParent(fenetre)
  tf:ClearAllPoints()
  tf:SetPoint("BOTTOMRIGHT", fenetre.action)
  tf:SetSize(math.min(340, math.max(140, tf:GetTextWidth() + 30)), 24)
  tf:Show()
  if case then cercler(case, actif and OR or { 0.6, 0.6, 0.62 }, actif and 0.95 or 0.5) else cercler(nil) end
end

-- Fenêtre de métier ouverte ou mise à jour, sacs changés (une fabrication finie), projet changé : au plus une fois par
-- image d'événements.
local prevu
local function bientot()
  if prevu then return end
  prevu = true
  C_Timer.After(0.2, function() prevu = false; ns.refreshCraftWindow() end)
end
local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE", "BAG_UPDATE_DELAYED",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do ev:RegisterEvent(e) end
for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_STOP" }) do
  ev:RegisterUnitEvent(e, "player")
end
ev:SetScript("OnEvent", function(_, e, _, _, sort)
  if e == "PLAYER_REGEN_DISABLED" then -- juste avant le verrou du combat : encore permis
    if tf then tf:Hide(); tf:ClearAllPoints(); tf:SetParent(UIParent) end
    return
  end
  -- Une fabrication réussie compte pour son projet, lancée d'ici ou par « Créer » du jeu (ns.compterFabrication, Projet.lua).
  if e == "UNIT_SPELLCAST_SUCCEEDED" then ns.compterFabrication(sort) end
  if encours and sort == encours.cle then -- l'avancement de la fabrication lancée
    if e == "UNIT_SPELLCAST_SUCCEEDED" then
      encours.fait, encours.t = encours.fait + 1, GetTime()
      C_Timer.After(3.5, bientot)
    elseif e ~= "UNIT_SPELLCAST_STOP" then
      encours = nil -- interrompue, refusée
    end
  end
  bientot()
end)
ns.quandChange(bientot)
