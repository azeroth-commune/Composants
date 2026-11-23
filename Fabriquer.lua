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

-- La prochaine fabrication des projets tenus (le projet affiché d'abord, puis dans l'ordre de la liste) pour le métier
-- ouvert : { p, cle, recette, id, fois (ce qu'il en reste), etat, n, manque }, ou nil s'il n'y a rien à fabriquer dans
-- aucun projet tenu. etat = "pret" (n = ce qu'on peut faire d'un coup, au plus fois), "manque", "inconnue" (ce perso ne
-- l'a pas apprise) ; "ailleurs" : rien pour ce métier, la prochaine est d'un autre (f.recette.profession).
-- La première prête l'emporte ; aucune prête : la première du métier, avec sa raison.
function ns.prochaineFabrication(metier)
  local T, d = C_TradeSkillUI, ns.db()
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
        local info = T.GetRecipeInfo(f.cle)
        if not (info and info.learned) then
          f.etat = "inconnue"
        else
          local n = T.GetCraftableCount(f.cle) or 0
          if n > 0 then f.etat, f.n = "pret", math.min(n, f.fois) return f end
          f.etat, f.manque = "manque", manque(f)
        end
        premiere = premiere or f
      end
    end
  end
  if premiere then return premiere end
  if ailleurs then ailleurs.etat = "ailleurs" return ailleurs end
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

-- Fenêtre de métier ouverte ou mise à jour, sacs changés (une fabrication finie), projet changé : au plus une fois par
-- image d'événements.
local prevu
local function bientot()
  if prevu then return end
  prevu = true
  C_Timer.After(0.2, function() prevu = false; rafraichir() end)
end
local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE", "BAG_UPDATE_DELAYED" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", bientot)
ns.quandChange(bientot)
