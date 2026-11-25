-- Composants, « Fabriquer » (#14) : un bouton sous la fenêtre de métier du jeu lance la prochaine fabrication d'un projet
-- tenu (une tranche de Maîtrise, une Réponse de Handshake…). Clic = une fabrication, clic droit = tout ce qu'il reste
-- (autant que les sacs le permettent : le jeu enchaîne lui-même, comme son « Créer tout »). Le compte avance comme dans la
-- fenêtre des projets : l'objet fabriqué arrive dans les sacs et l'arbre le déduit ; une ligne fabrication ne se décompte
-- pas (Maîtrise la recalcule), on passe à la suivante quand ses composants manquent.
-- Placé sous la fenêtre de métier, pas dans la fenêtre des projets : c'est là qu'on fabrique, et la fenêtre de métier du
-- jeu n'a pas de place libre en bas (Créer, Créer tout, le nombre) ni à droite de « Lien » (Mastercraft y met le sien).
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
-- "manque" (et le premier manque), "inconnue" (ce perso ne l'a pas apprise).
local function etatOuvert(f)
  local T = C_TradeSkillUI
  local info = T.GetRecipeInfo(f.cle)
  if not (info and info.learned) then f.etat = "inconnue" return f end
  local n = T.GetCraftableCount(f.cle) or 0
  if n > 0 then f.etat, f.n = "pret", math.min(n, f.fois) else f.etat, f.manque = "manque", manque(f) end
  return f
end

-- La prochaine fabrication des projets tenus (le projet affiché d'abord, puis dans l'ordre de la liste) pour le métier
-- ouvert : { p, cle, recette, id, fois (ce qu'il en reste), etat, n, manque }, ou nil s'il n'y a rien à fabriquer dans
-- aucun projet tenu. etat = "pret" (n = ce qu'on peut faire d'un coup, au plus fois), "manque", "inconnue" (ce perso ne
-- l'a pas apprise) ; "ailleurs" : rien pour ce métier, la prochaine est d'un autre (f.recette.profession).
-- La première prête l'emporte ; aucune prête : la première du métier, avec sa raison.
function ns.prochaineFabrication(metier)
  local d = ns.db()
  local moi = UnitGUID("player")
  local function mien(p) return p and p.tenu and (p.tenuPar == nil or p.tenuPar == moi) end -- pas la tranche d'un autre perso
  local courant = d.projets[d.courant or 0]
  local projets = { mien(courant) and courant or nil }
  for _, p in ipairs(d.projets) do if mien(p) and p ~= courant then projets[#projets + 1] = p end end
  local premiere, ailleurs
  for _, p in ipairs(projets) do
    for _, f in ipairs(aFabriquer(ns.projetArbre(p, nil, ns.apportsHandshake(p)))) do
      f.p = p
      if f.recette.profession ~= metier then
        ailleurs = ailleurs or f
      else
        if etatOuvert(f).etat == "pret" then return f end
        premiere = premiere or f
      end
    end
  end
  if premiere then return premiere end
  if ailleurs then ailleurs.etat = "ailleurs" return ailleurs end
end

-- « Tout fabriquer », sous la fenêtre des projets : la prochaine fabrication du projet p (celui affiché), tous métiers, dans
-- l'ordre de aFabriquer ; la première que les composants des sacs permettent. Fenêtre de son métier ouverte (metier) : le
-- jeu la confirme (etatOuvert) ; sinon etat = "ouvrir" (n = ce que les sacs permettent). Aucune : la première, etat =
-- "manque". Rien à fabriquer : nil, et fini = true quand les objets du projet sont tous là.
-- ponytail: l'arbre est recalculé ici, en plus du dessin de la fenêtre ; à partager si ça se sent.
function ns.prochaineDuProjet(p, metier)
  local res = ns.projetArbre(p, nil, ns.apportsHandshake(p))
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
  local fini = #res.roots > 0
  for _, c in ipairs(res.cases) do if c.kind == "target" and (c.need > 0 or c.made > 0) then fini = false end end
  return nil, fini
end

-- « 4 × Barre d'étain » : les objets que n fabrications donnent ; un enchantement, n × son nom.
local function combien(f, n)
  if f.id then return ("%d × %s"):format(n * math.max(1, f.recette.made_min or 1), nom(f.id)) end
  return ("%d × %s"):format(n, f.recette.name or "?")
end

-- Le libellé de « Tout fabriquer » : la prochaine action et son nombre, ou pourquoi rien ; e = la fabrication en cours.
function ns.texteToutFabriquer(f, fini, e)
  if e then return ("%s %d/%d…"):format(e.nom, e.fait * e.per, e.n * e.per) end
  if not f then return fini and "Tout est fabriqué" or "Rien à fabriquer" end
  if f.etat == "pret" then return "Fabriquer " .. combien(f, f.n) end
  if f.etat == "ouvrir" then return ("Ouvrir %s : %s"):format(f.recette.profession or "son métier", combien(f, f.n)) end
  if f.etat == "inconnue" then return "Recette inconnue : " .. (f.recette.name or "?") end
  if f.manque then return ("Il manque %s pour %s"):format(f.manque, combien(f, f.fois)) end
  return "Il manque de quoi faire " .. combien(f, f.fois)
end

-- « Ouvre la Forge », « Ouvre l'Alchimie », « Ouvre le Travail du cuir ».
local MASCULINS = { ["Travail du cuir"] = true, Secourisme = true, Minage = true, ["Dépeçage"] = true }
local function ouvre(metier)
  metier = metier or "fenêtre de son métier"
  local art = MASCULINS[metier] and "le " or ((metier:find("^[AEIOUH]") or metier:find("^É")) and "l'" or "la ")
  return "Ouvre " .. art .. metier
end

-- Le libellé du bouton : ce qu'il fera, ou pourquoi il ne peut pas.
function ns.texteFabriquer(f)
  local quoi = f.id and nom(f.id) or f.recette.name or "?"
  if f.etat == "pret" then return ("Fabriquer %s ×%d"):format(quoi, f.fois) end
  if f.etat == "manque" then return "Il manque " .. (f.manque or ("de quoi faire " .. quoi)) end
  if f.etat == "inconnue" then return "Recette inconnue : " .. (f.recette.name or quoi) end
  return ouvre(f.recette.profession)
end

---------------------------------------------------------------------------------------------------
-- Le bouton, fait à la première ouverture d'une fenêtre de métier (Blizzard_Professions se charge à la demande), enfant de
-- sa page de fabrication : il disparaît avec elle (autre onglet, fenêtre fermée).
local bouton, f
local function metierOuvert()
  local T = C_TradeSkillUI
  if not (T and T.GetBaseProfessionInfo) then return end
  if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
    or (T.IsNPCCrafting and T.IsNPCCrafting()) then return end -- le métier d'un autre
  local p = T.GetBaseProfessionInfo()
  return p and p.professionName ~= "" and p.professionName or nil
end

local function construire()
  local page = ProfessionsFrame.CraftingPage or ProfessionsFrame
  bouton = CreateFrame("Button", "ComposantsFabriquer", page, "UIPanelButtonTemplate")
  bouton:SetHeight(22)
  bouton:SetPoint("TOPLEFT", ProfessionsFrame, "BOTTOMLEFT", 4, -2)
  bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  bouton:SetMotionScriptsWhileDisabled(true) -- la bulle dit aussi pourquoi il est grisé
  bouton:SetScript("OnClick", function(_, souris)
    if not (f and f.etat == "pret") then return end
    C_TradeSkillUI.CraftRecipe(f.cle, souris == "RightButton" and f.n or 1)
  end)
  bouton:SetScript("OnEnter", function(self)
    if not f then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(f.p.name or "Projet")
    GameTooltip:AddLine(f.p.tenu, 0.66, 0.56, 1, true)
    if f.etat == "pret" then
      GameTooltip:AddLine(("Reste à fabriquer : %d"):format(f.fois), 1, 1, 1)
      GameTooltip:AddLine("Clic : une fabrication", 0.66, 0.56, 1)
      GameTooltip:AddLine(("Clic droit : tout (%d, ce que tes sacs permettent)"):format(f.n), 0.66, 0.56, 1)
    end
    GameTooltip:Show()
  end)
  bouton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function rafraichir()
  local metier = ProfessionsFrame and ProfessionsFrame:IsShown() and metierOuvert()
  f = metier and ns.prochaineFabrication(metier) or nil
  if not f then
    if bouton then bouton:Hide() end
    return
  end
  if not bouton then construire() end
  bouton:SetText(ns.texteFabriquer(f))
  bouton:SetWidth(bouton:GetTextWidth() + 30)
  bouton:SetEnabled(f.etat == "pret")
  bouton:Show()
end
ns.rafraichirFabriquer = rafraichir

---------------------------------------------------------------------------------------------------
-- « Tout fabriquer », sous la barre d'état de la fenêtre des projets : guider sans réfléchir, quoi fabriquer, combien, dans
-- quelle fenêtre. Un clic lance toute la prochaine fabrication du projet affiché (CraftRecipe(recette, n) : le jeu
-- enchaîne, comme son « Créer tout ») ; pendant ce temps le bouton montre l'avancement et ne prend pas de second clic ;
-- fini, il passe tout seul à la suivante. La fenêtre du métier fermée : « Ouvrir <métier> », car l'ouvrir est une action
-- protégée (CastSpell) : c'est un bouton sécurisé dont la macro lance le métier. Jamais deux recettes sur un clic.
-- Ses attributs ne s'écrivent que hors combat ; en combat il quitte la fenêtre (un enfant protégé la rendrait protégée :
-- ni fermée ni déplacée en combat) et y revient à la sortie.
local tf, tfFenetre, tfF, encours
local function enCombat() return InCombatLockdown and InCombatLockdown() end
local function enIncantation() return UnitCastingInfo and UnitCastingInfo("player") ~= nil end

local function rafraichirTout()
  if not (tf and tfFenetre:IsShown()) or enCombat() then return end -- en combat : refait à la sortie (PLAYER_REGEN_ENABLED)
  -- ponytail: fin sans événement (le jeu refuse sans incantation) : 3 s sans fonte ni incantation, la fabrication est finie.
  if encours and (encours.fait >= encours.n or (not enIncantation() and GetTime() - encours.t > 3)) then encours = nil end
  local f, fini = ns.prochaineDuProjet(ns.projetCourant(), ProfessionsFrame and ProfessionsFrame:IsShown() and metierOuvert() or nil)
  tfF = f
  local pret = f and f.etat == "pret" and not encours
  local ouvrir = f and f.etat == "ouvrir" and not encours
  tf:SetText(ns.texteToutFabriquer(f, fini, encours))
  tf:SetWidth(tf:GetTextWidth() + 30)
  tf:SetAttribute("type", ouvrir and "macro" or nil)
  tf:SetAttribute("macrotext", ouvrir and ("/cast " .. f.recette.profession) or nil)
  tf:SetEnabled((pret or ouvrir) and true or false)
end
ns.rafraichirToutFabriquer = rafraichirTout

local function lancer()
  local f = tfF
  if encours or not (f and f.etat == "pret") then return end -- en cours, ou « Ouvrir » (la macro s'en charge)
  encours = { cle = f.cle, nom = f.id and nom(f.id) or f.recette.name or "?", per = f.id and math.max(1, f.recette.made_min or 1) or 1,
    n = f.n, fait = 0, t = GetTime() }
  C_TradeSkillUI.CraftRecipe(f.cle, f.n)
  C_Timer.After(3.5, rafraichirTout)
  rafraichirTout()
end

-- Le bouton dans la fenêtre (fait hors combat seulement : un bouton sécurisé ne se crée ni ne s'ancre en combat).
local function placer()
  if not tfFenetre or enCombat() then return end
  if not tf then
    tf = CreateFrame("Button", "ComposantsToutFabriquer", tfFenetre, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    tf:SetHeight(22)
    tf:RegisterForClicks("AnyDown", "AnyUp") -- comme les boutons sécurisés de Be a Good Pal ; le second appel de lancer ne fait rien
    tf:SetAttribute("useOnKeyDown", GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") or false)
    tf:SetScript("PostClick", lancer)
  end
  tf:SetParent(tfFenetre)
  tf:ClearAllPoints()
  tf:SetPoint("BOTTOMLEFT", tfFenetre, "BOTTOMLEFT", 14, 8)
  tf:Show()
  rafraichirTout()
end
function ns.boutonToutFabriquer(fenetre) tfFenetre = fenetre; placer() end

-- Fenêtre de métier ouverte ou mise à jour, sacs changés (une fabrication finie), projet changé : au plus une fois par
-- image d'événements.
local prevu
local function bientot()
  if prevu then return end
  prevu = true
  C_Timer.After(0.2, function() prevu = false; rafraichir(); rafraichirTout() end)
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
  if e == "PLAYER_REGEN_ENABLED" then placer() end
  if encours and sort == encours.cle then -- l'avancement de « Tout fabriquer »
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
