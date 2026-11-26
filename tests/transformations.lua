-- Les Transformations dans wow-ui-sim (#37) : l'entrée sous le Brouillon, qui porte ce qu'elle rapporte ; l'ouvrir recalcule
-- (une ligne retirée revient) ; Lancer en fait un vrai projet « Transformations <date> » et une entrée vide prend sa place,
-- le Brouillon n'est pas touché. Les sacs, la recette connue (Fonte du fer, réserve du socle) et les cours de l'HV sont ceux
-- du test, rendus tels quels à la fin.
local function tous(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        tous(c, ok, out)
    end
    return out
end
local function bouton(texte)
    return tous(ComposantsFrame, function(c) return c:GetObjectType() == "Button" and c:IsVisible() and c:GetText() == texte end)[1]
end
-- La colonne des projets (aides de tests/projet.lua) : ses entrées visibles, de haut en bas ; l'entrée dont le nom commence par.
local function entrees()
    local t = tous(ComposantsFrame, function(c) return c.p ~= nil and c.nom ~= nil and c:IsVisible() end)
    table.sort(t, function(a, b) return a:GetTop() > b:GetTop() end)
    return t
end
local function colonne(debut)
    for _, e in ipairs(entrees()) do if (e.nom:GetText() or ""):sub(1, #debut) == debut then return e end end
end
local function ouvrir(debut)
    local e = colonne(debut)
    assertNotNil(e, "« " .. debut .. " » dans la colonne")
    e:Click("LeftButton")
end
local function affiche(nom) return ComposantsFrame.title:GetText() == nom end

test("l'entrée Transformations : sous le Brouillon, ce qu'elle rapporte ; ouverte, recalculée ; Lancer en fait un projet", function()
    local moi, maison = UnitGUID("player"), AzerothCommune.MaisonHV()
    local function copie(t) if type(t) ~= "table" then return t end local c = {} for k, v in pairs(t) do c[k] = copie(v) end return c end
    local G = { Conteneurs = AzerothCommune.Conteneurs, fiche = copie(AzerothCommuneDB.chars[moi]), hv = AzerothCommuneMarket[maison],
        brouillon = copie(ComposantsDB.brouillon), courant = ComposantsDB.courant }
    local sacs = { [2772] = 58 } -- 58 minerais de fer
    AzerothCommune.Conteneurs = function(garder)
        local items = {}
        for id, n in pairs(sacs) do items[#items + 1] = { id = id, count = n } end
        return garder("Backpack") and { b = { items = items } } or {}
    end
    AzerothCommuneDB.chars[moi] = AzerothCommuneDB.chars[moi] or {}
    AzerothCommuneDB.chars[moi].recipes = { Minage = { rank = 150, max = 150, known = { [3307] = "easy" } } }
    local function prix(pc) return { min = pc, qty = 999, tiers = { { price = pc, qty = 999 } } } end
    AzerothCommuneMarket[maison] = { scanned = "test", items = { [2772] = prix(100), [3575] = prix(2000) } }
    local lance
    local ok, err = pcall(function()
        ComposantsDB.brouillon = { id = 0, name = "Brouillon", lines = { { id = 2841, qty = 3 } } }
        SlashCmdList.COMPOSANTS("")
        -- Toujours là, sous le Brouillon, avec ce qu'elle rapporte.
        local e = entrees()
        assertEquals("Brouillon", e[1].nom:GetText(), "le Brouillon en tête")
        local libelle = e[2].nom:GetText() or ""
        assertTrue(libelle:find("^Transformations · ") ~= nil and libelle:find("+", 1, true) ~= nil, "ce qu'elle rapporte : " .. libelle)
        assertEquals("1 ligne", e[2].phase:GetText())
        -- Ouverte : une Fabrication « Fonte du fer ×58 », en Préparer.
        ouvrir("Transformations")
        assertTrue(affiche("Transformations"), "la fenêtre sur l'entrée")
        local t = ComposantsDB.transformations
        assertEquals(1, #t.lines)
        assertEquals(3307, t.lines[1].recette)
        assertEquals(58, t.lines[1].fois)
        -- Une ligne retirée (clic droit sur sa case) revient à la réouverture.
        local cible = tous(ComposantsFrame, function(c) return c.node ~= nil and c.node.kind == "target" and c:IsShown() end)[1]
        assertNotNil(cible, "la case de la ligne")
        cible:Click("RightButton")
        assertEquals(0, #t.lines, "retirée")
        ouvrir("Brouillon")
        ouvrir("Transformations")
        assertEquals(1, #t.lines, "revenue au recalcul")
        -- Lancer : un vrai projet « Transformations <date> », une entrée vide à sa place ; le Brouillon intact.
        local nb = #ComposantsDB.projets
        bouton("Lancer"):Click()
        assertEquals(nb + 1, #ComposantsDB.projets, "un vrai projet")
        lance = ComposantsDB.projets[#ComposantsDB.projets]
        assertEquals("Transformations " .. date("%d/%m"), lance.name)
        assertEquals(3307, lance.lines[1].recette)
        assertTrue(lance.phase ~= nil, "lancé (le minerai est dans les sacs : déjà en Fabriquer)")
        assertEquals(0, #t.lines, "une entrée vide la remplace")
        assertEquals(1, #ComposantsDB.brouillon.lines, "le Brouillon pas touché")
        assertEquals(2841, ComposantsDB.brouillon.lines[1].id)
        -- Les sacs vidés : « Transformations · rien », grisé.
        sacs = {}
        Composants.Ouvrir(lance.id)
        if not ComposantsFrame:IsShown() then ComposantsBesoinsFrame:Hide(); ouvrir("Brouillon") end
        libelle = colonne("Transformations").nom:GetText()
        assertEquals("Transformations · rien", libelle)
        local r, g, b = colonne("Transformations").nom:GetTextColor()
        assertTrue(math.abs(r - g) < 0.05 and math.abs(g - b) < 0.05, "grisé")
    end)
    if lance and Composants.Projet(lance.id) then Composants.Supprimer(lance.id) end
    ComposantsFrame:Hide()
    if ComposantsBesoinsFrame then ComposantsBesoinsFrame:Hide() end
    AzerothCommune.Conteneurs, AzerothCommuneDB.chars[moi], AzerothCommuneMarket[maison] = G.Conteneurs, G.fiche, G.hv
    ComposantsDB.brouillon, ComposantsDB.courant = G.brouillon, G.courant
    if not ok then error(err, 0) end
end)
