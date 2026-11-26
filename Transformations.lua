-- Composants, les Transformations (CONTEXT.md) : ce que les matières des sacs du personnage connecté rapportent de plus
-- transformées, avec les recettes qu'il connaît, que vendues telles quelles. Rentable : vendre le bout de la chaîne (minerai
-- de cuivre → barre de cuivre → barre de bronze) rapporte plus que vendre la matière (une vente : ns.venteHV, comme la
-- Valeur à l'HV) ; les ingrédients en plus (charbon, sel, la barre d'étain du bronze) comptent à leur prix d'achat, même
-- s'ils sont dans les sacs ; sans prix pour un objet de la chaîne, rien pour cette matière ; pas de seuil.
-- Répartition gourmande, assumée : la matière au meilleur gain par unité d'abord, qui prend tout ce qu'elle peut des sacs
-- (ses ingrédients en plus aussi : tels quels, ou par une fonte d'une étape, le minerai d'étain pour la barre) ; ce qui
-- manque est à acheter (un Besoin du projet lancé). Le calcul rend une Fabrication par bout de chaîne : l'arbre du projet
-- y met les étapes d'avant (les fontes du cuivre et de l'étain sous celle du bronze), dans l'ordre.
local _, ns = ...
local lib = AzerothCommune

-- Les familles de transformations, liste fermée par métier et motif du nom de la recette : les fontes (toutes les barres),
-- les rouleaux d'étoffe, les peaux traitées. Pas les transmutations, poudres, silex, essences ni teintures.
-- ponytail: les noms du client français ; dans une autre langue, aucune transformation. Une liste d'IDs de recettes si ça arrive.
local FAMILLES = { Minage = "^Fonte", Couture = "^Rouleau", ["Travail du cuir"] = "traitée$" }

-- Les transformations que le personnage connecté connaît : { { cle, r } }, dans un ordre fixe.
local function connues()
  local t, recettes = {}, ns.recipes()
  for metier, p in pairs(ns.knownRecipes()[UnitGUID("player")] or {}) do
    for cle in pairs(p.known or {}) do
      local r = recettes[cle]
      local motif = r and FAMILLES[r.profession or metier]
      if motif and r.output and r.reagents and (r.name or ""):find(motif) then t[#t + 1] = { cle = cle, r = r } end
    end
  end
  table.sort(t, function(a, b) return tostring(a.cle) < tostring(b.cle) end)
  return t
end

local function qte(r, id) for _, rg in ipairs(r.reagents) do if rg.id == id then return rg.qty end end end
local function par(r) return math.max(1, r.made_min or 1) end

-- Le calcul, d'après les sacs et le dernier cours de l'HV : { lignes = { { recette, fois } }, gain (en cuivre, ce que ça
-- rapporte de plus que vendre les matières telles quelles) }.
function ns.calculTransformations()
  local market, T = ns.market(), connues()
  local res = { lignes = {}, gain = 0 }
  if not market or #T == 0 then return res end
  local marchands = lib:PrixMarchands()
  local function vente(id) return ns.venteHV(id, market) end
  local function achat(id) return lib:PrixAchat(id, 1, market.items, marchands) end
  -- Le prix d'achat des ingrédients en plus d'une fabrication (tout sauf id) ; nil si l'un n'a pas de prix.
  local function enPlus(r, id)
    local c = 0
    for _, rg in ipairs(r.reagents) do
      if rg.id ~= id then
        local pa = achat(rg.id)
        if not pa then return nil end
        c = c + pa * rg.qty
      end
    end
    return c
  end
  -- La meilleure chaîne pour une unité de id : sa valeur (le bout vendu, ingrédients en plus déduits) et ses recettes, de la
  -- première au bout ; vendu tel quel : sa vente et {}. nil sans prix.
  local function meilleure(id, vu)
    local best, chemin = vente(id), {}
    if not best then return nil end
    vu[id] = true
    for _, t in ipairs(T) do
      local a, o = qte(t.r, id), t.r.output
      if a and not vu[o] then
        local vo, suite = meilleure(o, vu)
        local c = vo and enPlus(t.r, id)
        local v = c and (vo * par(t.r) - c) / a
        if v and v > best then best, chemin = v, { t, unpack(suite) } end
      end
    end
    vu[id] = nil
    return best, chemin
  end

  -- Les sacs : { [id] = nombre }.
  local reste = {}
  for _, sac in pairs(ns.mesSacs() or {}) do
    for _, it in ipairs(sac.items or {}) do
      if it.id then reste[it.id] = (reste[it.id] or 0) + (it.count or 1) end
    end
  end
  -- Les matières : ce qui entre dans une transformation connue, sauf ce qu'un marchand vend (charbon, sel : jamais la
  -- matière d'une chaîne, seulement un ingrédient en plus) ; la meilleure au gain par unité d'abord.
  local matieres = {}
  for id in pairs(reste) do
    local entre = false
    for _, t in ipairs(T) do entre = entre or qte(t.r, id) ~= nil end
    local v, chemin
    if entre and not marchands[id] then v, chemin = meilleure(id, {}) end
    if v and #chemin > 0 then matieres[#matieres + 1] = { id = id, gain = v - vente(id), chemin = chemin } end
  end
  table.sort(matieres, function(a, b) if a.gain ~= b.gain then return a.gain > b.gain end return a.id < b.id end)

  -- Un ingrédient en plus, pris dans les sacs : tel quel, puis par une transformation connue d'une étape à un seul composant.
  local function prendre(id, n)
    local pris = math.min(reste[id] or 0, n)
    if pris > 0 then reste[id], n = reste[id] - pris, n - pris end
    for _, t in ipairs(T) do
      local rg = n > 0 and t.r.output == id and #t.r.reagents == 1 and t.r.reagents[1]
      local fois = rg and math.min(math.ceil(n / par(t.r)), math.floor((reste[rg.id] or 0) / rg.qty)) or 0
      if fois > 0 then reste[rg.id], n = reste[rg.id] - fois * rg.qty, n - fois * par(t.r) end
    end
  end
  local rang = {}
  for _, m in ipairs(matieres) do
    -- Les fabrications de chaque étape, sur tout ce qui reste de la matière.
    -- ponytail: ce qui reste d'un produit intermédiaire (3 barres pour une étape qui en prend 2) n'est ni vendu ni compté.
    local id, n, etapes = m.id, reste[m.id] or 0, {}
    for i, t in ipairs(m.chemin) do
      etapes[i] = math.floor(n / qte(t.r, id))
      id, n = t.r.output, etapes[i] * par(t.r)
    end
    if n > 0 then
      local premiere = etapes[1] * qte(m.chemin[1].r, m.id)
      reste[m.id] = reste[m.id] - premiere
      local gain = vente(id) * n - vente(m.id) * premiere
      id = m.id
      for i, t in ipairs(m.chemin) do
        gain = gain - enPlus(t.r, id) * etapes[i]
        for _, rg in ipairs(t.r.reagents) do if rg.id ~= id then prendre(rg.id, rg.qty * etapes[i]) end end
        id = t.r.output
      end
      res.gain = res.gain + gain
      local bout = m.chemin[#m.chemin]
      if not rang[bout.cle] then
        res.lignes[#res.lignes + 1] = { recette = bout.cle, fois = 0 }
        rang[bout.cle] = #res.lignes
      end
      local l = res.lignes[rang[bout.cle]]
      l.fois = l.fois + etapes[#etapes]
    end
  end
  res.gain = math.floor(res.gain + 0.5)
  return res
end
