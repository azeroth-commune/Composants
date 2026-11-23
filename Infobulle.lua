-- Composants, l'infobulle des objets (#16) : au survol d'un objet n'importe où, « Utilisé dans : <projets> » (les projets
-- dont l'arbre le demande, Brouillon compris) et « Fabriqué par : <persos> » (ceux de mes persos qui connaissent une
-- recette qui le fabrique). Rien pour un objet qui n'entre dans rien.
-- Forever n'a pas d'OnTooltipSetItem : une post-call des données d'infobulle, une fois
-- (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199 ; appelée avant le Show, ligne 298-300) ; data.id = l'objet
-- (TooltipUtil.lua:20).
local _, ns = ...

local MAX = 3 -- noms par ligne, puis « +N »
local function liste(noms)
  if #noms <= MAX then return table.concat(noms, ", ") end
  return table.concat(noms, ", ", 1, MAX) .. (" +%d"):format(#noms - MAX)
end

-- Le cache : utilise[id] = { noms de projets }, producteurs[id] = { clés de recettes }, persos, lignes[id] (déjà calculées).
-- Vidé à chaque changement d'un projet (le signal de Projet.lua), et refait au plus une fois par minute : la base des
-- recettes ne signale pas ses changements.
-- ponytail: 60 s faute de signal ; lib:Signaler("base des recettes") côté socle permettra de s'en passer.
local cache, fait = nil, 0
ns.quandChange(function() cache = nil end)

local function construire()
  local utilise, producteurs = {}, {}
  local d = ns.db()
  local projets = {}
  for _, p in ipairs(d.projets) do projets[#projets + 1] = p end
  if d.brouillon and #d.brouillon.lines > 0 then projets[#projets + 1] = d.brouillon end
  local opts = { unlearned = d.options.unlearned } -- l'arbre entier, sans stock déduit : ce que le projet demande
  for _, p in ipairs(projets) do
    local vu = {}
    for _, n in ipairs(ns.projetArbre(p, opts).cases) do
      if not vu[n.id] then
        vu[n.id] = true
        utilise[n.id] = utilise[n.id] or {}
        table.insert(utilise[n.id], p.name or "?")
      end
    end
  end
  for cle, r in pairs(ns.recipes()) do
    if r.output then
      producteurs[r.output] = producteurs[r.output] or {}
      table.insert(producteurs[r.output], cle)
    end
  end
  cache, fait = { utilise = utilise, producteurs = producteurs, persos = ns.knownRecipes(), lignes = {} }, GetTime()
end

-- Les lignes de l'infobulle d'un objet : { "Utilisé dans : …", "Fabriqué par : …" }, une seule ou aucune si inutile.
function ns.lignesInfobulle(id)
  if not cache or GetTime() - fait > 60 then construire() end
  local l = cache.lignes[id]
  if l then return l end
  l = {}
  if cache.utilise[id] then l[#l + 1] = "Utilisé dans : " .. liste(cache.utilise[id]) end
  local qui = {}
  for guid, metiers in pairs(cache.persos) do
    local sait = false
    for _, cle in ipairs(cache.producteurs[id] or {}) do
      for _, m in pairs(metiers) do sait = sait or (m.known and m.known[cle] ~= nil) end
    end
    if sait then qui[#qui + 1] = ns.prenom(guid) end
  end
  table.sort(qui)
  if #qui > 0 then l[#l + 1] = "Fabriqué par : " .. liste(qui) end
  cache.lignes[id] = l
  return l
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
    if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end -- pas les bulles de comparaison
    local id = data and data.id
    if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then return end
    for _, ligne in ipairs(ns.lignesInfobulle(id)) do tip:AddLine(ligne, 0.66, 0.56, 1, true) end
  end)
end
