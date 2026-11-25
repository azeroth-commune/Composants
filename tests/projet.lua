-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test Composants) : Composants chargé avec le socle Azeroth Commune dans
-- l'interface Forever simulée, avec ou sans Handshake selon les racines du simulateur. Les blocs viennent de la base des
-- recettes du socle (sa réserve, AzerothCommune/RecettesReserve.lua, générée, hors du repo : à copier dans un worktree).
local function tous(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        tous(c, ok, out)
    end
    return out
end
local function boutons(ok)
    return tous(ComposantsFrame, function(c) return c:GetObjectType() == "Button" and c:IsVisible() and ok(c:GetText() or "") end)
end
local function bouton(texte) return boutons(function(t) return t == texte end)[1] end
-- Les menus déroulants de la fenêtre (il n'y en a plus : la colonne des projets).
local function deroulant(nom)
    return tous(ComposantsFrame, function(c) return c.OverrideText ~= nil and c:IsVisible() and c:GetText() == nom end)[1]
end
-- La colonne des projets : ses entrées visibles, de haut en bas (une entrée porte son projet, c.p) ; l'entrée d'un nom ;
-- ouvrir(nom) = un clic dessus ; le menu de son clic droit (le vrai s'ouvre, puis est refermé), et y choisir une entrée.
local function entrees()
    local t = tous(ComposantsFrame, function(c) return c.p ~= nil and c.nom ~= nil and c:IsVisible() end)
    table.sort(t, function(a, b) return a:GetTop() > b:GetTop() end)
    return t
end
local function colonne(nom)
    for _, e in ipairs(entrees()) do if e.nom:GetText() == nom then return e end end
end
local function ouvrir(nom)
    local e = colonne(nom)
    assertNotNil(e, "« " .. nom .. " » dans la colonne")
    e:Click("LeftButton")
end
local function menuDe(nom)
    local e = colonne(nom)
    assertNotNil(e, "« " .. nom .. " » dans la colonne")
    local vrai, racine = MenuUtil.CreateContextMenu, nil
    MenuUtil.CreateContextMenu = function(owner, gen)
        racine = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultContextMenuMixin())
        gen(owner, racine)
        return vrai(owner, gen)
    end
    local ok, err = pcall(e.Click, e, "RightButton")
    MenuUtil.CreateContextMenu = vrai
    Menu.GetManager():CloseMenus()
    if not ok then error(err, 0) end
    local t = {}
    for _, d in racine:EnumerateElementDescriptions() do t[#t + 1] = d end
    return t
end
local function choisir(nom, entree)
    for _, d in ipairs(menuDe(nom)) do
        if MenuUtil.GetElementText(d) == entree then return d:Pick(MenuInputContext.MouseButton, "LeftButton") end
    end
    error("pas d'entrée « " .. entree .. " » au clic droit sur « " .. nom .. " »", 2)
end
-- Le nom du projet affiché en haut de la fenêtre.
local function affiche(nom)
    for _, r in ipairs({ ComposantsFrame:GetRegions() }) do
        if r.GetText and r:IsShown() and r:GetText() == nom then return true end
    end
    return false
end
-- Les cases dessinées : une par objet (c.node).
local function cases() return tous(ComposantsFrame, function(c) return c.node ~= nil and c:IsShown() end) end
local function projet() return ComposantsDB.projets[ComposantsDB.courant] end
-- Un bouton du fil « Préparer › Réunir › Fabriquer » d'une vue (son texte sans couleur), et la phase en cours qui s'y lit.
local function fil(f, nom)
    return tous(f, function(c)
        return c:GetObjectType() == "Button" and c:IsVisible() and ((c:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) == nom
    end)[1]
end
local function enCours(b) return (b:GetText() or ""):find("|cffa98fff", 1, true) ~= nil end -- lavande

-- Personne n'a de recette ici : « recettes pas apprises » cochée, toutes comptent et les blocs se dessinent. L'option est
-- rendue telle quelle, même si une vérification échoue.
local function sansRecettes(f)
    local avant = ComposantsDB.options.unlearned
    ComposantsDB.options.unlearned = true
    local ok, err = pcall(f)
    ComposantsDB.options.unlearned = avant
    ComposantsFrame:Hide()
    if ComposantsBesoinsFrame then ComposantsBesoinsFrame:Hide() end
    if not ok then error(err, 0) end
end

test("Composants se charge : son global, sa commande, ses données propres", function()
    assertType("table", Composants)
    assertType("function", Composants.Arbre)
    assertType("function", SlashCmdList.COMPOSANTS)
    assertType("table", ComposantsDB)
    for _, k in ipairs({ "recipes", "chars", "items", "market" }) do assertNil(ComposantsDB[k]) end
end)

-- Composants lit ses données par le socle : ses souscriptions sont datées de ce chargement, et les inventaires sont rangés
-- par GUID (repris de tests/releves.lua de Handshake, parti avec l'arbre, Handshake#39).
test("Composants souscrit à ses types de données ; mon perso par son GUID dans les inventaires", function()
    for _, t in ipairs({ "recettes connues", "base des recettes", "inventaires", "métiers et compétences", "marchands", "objets", "cours de l'HV" }) do
        assertType("number", AzerothCommuneDB.souscriptions[t])
        assertTrue(time() - AzerothCommuneDB.souscriptions[t] < 600, t)
    end
    local lib = AzerothCommune
    local d = lib:Lire("inventaires", "tous")
    if not d then SlashCmdList.AZEROTHCOMMUNE("") d = lib:Lire("inventaires", "tous") end -- /ac : relevé tout de suite
    assertNotNil(d, "inventaires relevés (Composants y souscrit)")
    local n = 0
    for cle in pairs(d.persos) do n = n + 1; assertTrue(cle:find("^Player%-") ~= nil, "clé " .. cle) end
    assertTrue(n > 0, "au moins mon perso")
    assertNotNil(d.persos[UnitGUID("player")], "mon perso sous mon GUID")
end)

test("projet de démo : l'arbre et ses blocs, la colonne passe d'un projet à l'autre", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    assertTrue(ComposantsFrame:IsShown())
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    assertTrue(#cases() > 5, "l'arbre dessiné (AzerothCommune/RecettesReserve.lua présent ?)")
    local etapes = tous(ComposantsFrame, function(c) return c.grp ~= nil and c:IsShown() end)
    assertTrue(#etapes > 1, "des blocs, un par métier")
    SlashCmdList.COMPOSANTS("demo set")
    assertTrue(affiche("Essai : set en thorium enchanté"))
    assertNil(deroulant("Projets"), "plus de menu « Projets »")
    ouvrir("Essai : ceintures multi-métiers")
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    ouvrir("Essai : set en thorium enchanté")
    assertTrue(affiche("Essai : set en thorium enchanté"))
end) end)

-- Valeur à l'HV (CONTEXT.md) : sur la ligne du projet, ce que valent à l'HV les objets fabriqués ; rien sans leur prix.
local function ligneProjet()
    for _, c in ipairs(tous(ComposantsFrame, function() return true end)) do
        for _, r in ipairs({ c:GetRegions() }) do
            local t = r:GetObjectType() == "FontString" and r:IsShown() and r:GetText()
            if t and t:find("^Projet · ") then return t end
        end
    end
end
test("valeur à l'HV : sur la ligne du projet, seulement quand ses objets ont un prix", function() sansRecettes(function()
    local avant, h = AzerothCommuneMarket, AzerothCommune.MaisonHV()
    local ok, err = pcall(function()
        AzerothCommuneMarket = { [h] = { scanned = "test", items = {} } }
        SlashCmdList.COMPOSANTS("demo ceinture")
        local t = ligneProjet()
        assertNotNil(t, "la ligne du projet")
        assertNil(t:find("vaut", 1, true), "sans prix : pas de valeur")
        AzerothCommuneMarket = { [h] = { scanned = "test", items = { [10721] = { min = 150000, qty = 1 }, [4264] = { min = 50000, qty = 1 } } } }
        Composants.Rafraichir()
        t = ligneProjet()
        assertNotNil(t:find("vaut .* à l'HV · "), t)
        assertTrue(t:find("rapporte", 1, true) ~= nil or t:find("coût incomplet", 1, true) ~= nil, t)
    end)
    AzerothCommuneMarket = avant
    if not ok then error(err, 0) end
end) end)

-- « + » et « – » : un choix de case du projet affiché, jamais d'un autre projet.
test("« + » et « – » : le choix de case appartient au projet affiché", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local autre = projet()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local p = projet()
    assertTrue(p ~= autre)
    local carte
    for _, c in ipairs(cases()) do if c.node.made > 0 and c.node.kind ~= "target" then carte = c break end end
    assertNotNil(carte, "une case fabriquée")
    local id = carte.node.id
    carte:Click() -- « – » : achetée toute faite
    assertEquals("acheter", p.choix[id])
    assertNil(autre.choix and autre.choix[id], "l'autre projet n'a pas ce choix")
    for _, c in ipairs(cases()) do if c.node.id == id then assertEquals(0, c.node.made, "achetée") end end
    for _, c in ipairs(cases()) do if c.node.id == id then c:Click() end end -- retour au calcul
    assertNil(p.choix and p.choix[id])
end) end)

-- Ctrl+clic droit sur un objet n'importe où dans le jeu : il entre dans le Brouillon, jamais dans le projet affiché.
local function ctrlClicDroit(lien)
    local ctrl, alt, maj, souris = IsControlKeyDown, IsAltKeyDown, IsShiftKeyDown, GetMouseButtonClicked
    IsControlKeyDown, IsAltKeyDown, IsShiftKeyDown = function() return true end, function() return false end, function() return false end
    GetMouseButtonClicked = function() return "RightButton" end
    local ok, err = pcall(HandleModifiedItemClick, lien)
    IsControlKeyDown, IsAltKeyDown, IsShiftKeyDown, GetMouseButtonClicked = ctrl, alt, maj, souris
    if not ok then error(err, 0) end
end
local BRONZE = "|cffffffff|Hitem:2841::::::::1:::::::::|h[Barre de bronze]|h|r"

test("Ctrl+clic droit sur un objet : il entre dans le Brouillon, pas dans le projet affiché", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local p = projet()
    local n = #p.lines
    ctrlClicDroit(BRONZE)
    local b = ComposantsDB.brouillon
    assertNotNil(b, "le Brouillon")
    assertEquals(n, #p.lines, "le projet affiché ne change pas")
    local q
    for i, l in ipairs(b.lines) do if l.id == 2841 then q = l end end
    assertNotNil(q, "la barre de bronze au Brouillon")
    q.qty = 5
    ctrlClicDroit(BRONZE)
    assertEquals(5, q.qty, "déjà là : sa quantité ne bouge pas")
    assertTrue(affiche("Brouillon"), "la fenêtre s'ouvre sur le Brouillon")
    choisir("Brouillon", "Vider le Brouillon")
    assertEquals(0, #b.lines, "vidé par le clic droit dans la colonne")
end) end)

test("le Brouillon : en tête de la colonne ; Lancer en fait un projet en Réunir, la petite vue seule", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local nb = #ComposantsDB.projets
    assertEquals("Brouillon", entrees()[1].nom:GetText(), "en tête de la colonne")
    ouvrir("Brouillon")
    choisir("Brouillon", "Vider le Brouillon")
    assertEquals(0, #ComposantsDB.brouillon.lines, "vidé")
    assertEquals("vide", colonne("Brouillon").phase:GetText())
    ctrlClicDroit(BRONZE)
    assertTrue(affiche("Brouillon"))
    assertEquals("1 ligne", colonne("Brouillon").phase:GetText())
    ouvrir("Essai : ceintures multi-métiers")
    assertTrue(not affiche("Brouillon"), "un projet choisi : on quitte le Brouillon")
    ouvrir("Brouillon")
    assertTrue(affiche("Brouillon"))
    bouton("Lancer"):Click()
    assertEquals(nb + 1, #ComposantsDB.projets, "un vrai projet")
    assertEquals(2841, projet().lines[1].id, "avec les lignes du Brouillon")
    assertEquals("Barre de bronze", projet().name, "nommé d'après sa première ligne")
    assertEquals("reunir", projet().phase, "en Réunir")
    assertEquals(0, #ComposantsDB.brouillon.lines, "le Brouillon vidé")
    assertTrue(ComposantsBesoinsFrame:IsShown(), "ses Besoins montrés")
    assertTrue(not ComposantsFrame:IsShown(), "la grande vue cachée")
end) end)

-- Lancer (CONTEXT.md) remplace « Mettre dans les Besoins » : le projet passe en Réunir, la petite vue (ses Besoins seuls)
-- prend le coin de la grande, le fil en haut des deux ; chaque projet ses Besoins. Un choix de case, ou Tenir sur un projet
-- lancé, le remet en Préparer.
local function lignesBesoins()
    local out = {}
    for _, c in ipairs(tous(ComposantsBesoinsFrame, function(c) return c.itemID ~= nil and c:IsShown() end)) do out[c.itemID] = c end
    return out
end
local function casesDe(p)
    local t = {}
    for _, n in ipairs(Composants.Arbre(p).cases) do t[n.id] = true end
    return t
end

test("Lancer : la petite vue au coin de la grande, le fil, les Besoins du seul projet affiché", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo set")
    local a = projet()
    assertNil(bouton("Mettre dans les Besoins"), "plus de « Mettre dans les Besoins »")
    assertTrue(enCours(fil(ComposantsFrame, "Préparer")), "le fil de la grande vue : Préparer")
    local x, y = ComposantsFrame:GetLeft(), ComposantsFrame:GetTop()
    bouton("Lancer"):Click()
    assertEquals("reunir", a.phase)
    assertTrue(ComposantsBesoinsFrame:IsShown() and not ComposantsFrame:IsShown(), "une seule vue : la petite")
    assertEquals(math.floor(x + 0.5), math.floor(ComposantsBesoinsFrame:GetLeft() + 0.5), "au coin de la grande")
    assertEquals(math.floor(y + 0.5), math.floor(ComposantsBesoinsFrame:GetTop() + 0.5))
    assertTrue(ComposantsBesoinsFrame.head:GetText():find(a.name, 1, true) ~= nil, "le projet affiché, nommé")
    assertTrue(enCours(fil(ComposantsBesoinsFrame, "Réunir")), "le fil de la petite vue : Réunir")
    assertTrue(not enCours(fil(ComposantsBesoinsFrame, "Préparer")))
    local deA = lignesBesoins()
    assertTrue(next(deA) ~= nil, "des objets à réunir")
    -- Un autre projet : retour à la grande vue par le fil, puis la ceinture, lancée : ses Besoins à elle.
    fil(ComposantsBesoinsFrame, "Préparer"):Click()
    assertTrue(ComposantsFrame:IsShown() and not ComposantsBesoinsFrame:IsShown(), "le fil : la grande vue")
    assertNil(a.phase, "Préparer")
    SlashCmdList.COMPOSANTS("demo ceinture")
    local b = projet()
    bouton("Lancer"):Click()
    assertTrue(ComposantsBesoinsFrame.head:GetText():find(b.name, 1, true) ~= nil)
    local cb, horsB = casesDe(b), false
    for id, l in pairs(lignesBesoins()) do
        if not (l.info or ""):find("^Pour fabriquer") then assertTrue(cb[id], "une ligne d'un autre projet : " .. id) end
    end
    for id in pairs(deA) do horsB = horsB or not cb[id] end
    assertTrue(horsB, "les Besoins du set n'y sont plus")
    -- Tenir sur un projet lancé (une tranche recalculée) : Préparer, la grande vue revient.
    Composants.Tenir(b, "tenu par le test", b.lines)
    Composants.Rafraichir()
    assertNil(b.phase, "tenu : Préparer")
    assertTrue(ComposantsFrame:IsShown() and not ComposantsBesoinsFrame:IsShown(), "la grande vue")
    Composants.Tenir(b, nil)
    -- Fabriquer : lecture seule, un clic sur une case ne change rien ; « Préparer » dans le fil, Lancer revient.
    fil(ComposantsFrame, "Fabriquer"):Click()
    assertEquals("fabriquer", b.phase)
    assertTrue(enCours(fil(ComposantsFrame, "Fabriquer")) and not bouton("Lancer"), "Fabriquer : pas de Lancer")
    local carte
    for _, c in ipairs(cases()) do if c.node.made > 0 and c.node.kind ~= "target" then carte = c break end end
    carte:Click()
    assertNil(b.choix and b.choix[carte.node.id], "Fabriquer : aucun choix de case")
    assertEquals("fabriquer", b.phase)
    fil(ComposantsFrame, "Préparer"):Click()
    assertNil(b.phase, "Préparer")
    assertNotNil(bouton("Lancer"))
end) end)

-- Réunir → Fabriquer tout seul quand tout est dans les sacs ; la banque dit où le trouver, elle ne suffit pas ; jamais de
-- retour tout seul ; Fini gardé après la vente ; le fil va partout ; « Clore » supprime. 4 barres d'étain à fondre (Fonte de
-- l'étain, réserve du socle) ; les sacs et la banque sont ceux du test, la vue recalculée par Composants.Rafraichir.
test("Réunir → Fabriquer quand tout est dans les sacs, pas à la banque ; Fini gardé ; le fil ; Clore", function() sansRecettes(function()
    local moi = UnitGUID("player")
    local sacs, banque = {}, { [2771] = 4 }
    local G = { Conteneurs = AzerothCommune.Conteneurs, GetItemCount = C_Item.GetItemCount, fiche = AzerothCommuneDB.chars[moi] }
    local function items(t) local out = {} for id, n in pairs(t) do out[#out + 1] = { id = id, count = n } end return { b = { items = out } } end
    AzerothCommune.Conteneurs = function(garder) return garder("Backpack") and items(sacs) or {} end
    C_Item.GetItemCount = function(id) return sacs[id] or 0 end
    AzerothCommuneDB.chars[moi] = setmetatable({}, { __index = function(_, k) if k == "bank" then return items(banque) end return G.fiche and G.fiche[k] end })
    -- La Fonte de l'étain : à apprendre, puis connue (une recette à apprendre retient en Réunir, comme un composant).
    local connue, cle = false, nil
    for k, r in pairs(AzerothCommune:Lire("base des recettes") or {}) do if r.output == 3576 then cle = k end end
    G.Lire = AzerothCommune.Lire
    AzerothCommune.Lire = function(self, t, ...)
        if t == "recettes connues" then return { persos = connue and { [moi] = { Minage = { known = { [cle] = 1 } } } } or {} } end
        return G.Lire(self, t, ...)
    end
    local p = Composants.NouveauProjet({ name = "Barres d'étain", lines = { { id = 3576, qty = 4 } } })
    local ok, err = pcall(function()
        Composants.Ouvrir(p.id)
        bouton("Lancer"):Click()
        local ligne = lignesBesoins()[2771]
        assertNotNil(ligne, "le minerai d'étain à réunir")
        assertTrue(ligne.text:GetText():find("banque 4", 1, true) ~= nil, "où le trouver : " .. ligne.text:GetText())
        assertEquals("0/4", ligne.count:GetText(), "rien dans les sacs")
        assertEquals("reunir", p.phase, "à la banque : on reste en Réunir")
        sacs, banque = { [2771] = 4 }, {}
        Composants.Rafraichir()
        assertEquals("reunir", p.phase, "dans les sacs, mais la recette à apprendre : on reste en Réunir")
        connue = true
        Composants.Rafraichir()
        assertEquals("fabriquer", p.phase, "dans les sacs, recette connue : Fabriquer tout seul")
        assertTrue(ComposantsFrame:IsShown() and not ComposantsBesoinsFrame:IsShown(), "la grande vue")
        assertTrue(enCours(fil(ComposantsFrame, "Fabriquer")))
        sacs, banque = {}, { [2771] = 4 }
        Composants.Rafraichir()
        assertEquals("fabriquer", p.phase, "rangé à la banque : pas de retour en Réunir")
        sacs, banque = { [3576] = 4 }, {}
        Composants.Rafraichir()
        assertEquals("fini", p.phase, "les barres fondues : Fini")
        assertTrue(ComposantsFrame.clore and ComposantsFrame.clore:IsVisible(), "« Clore »")
        assertEquals("Clore", ComposantsFrame.clore:GetText())
        sacs = {}
        Composants.Rafraichir()
        assertEquals("fini", p.phase, "les barres vendues : Fini gardé")
        assertTrue(ComposantsFrame.clore:IsVisible())
        -- Le fil : n'importe quelle phase, la vue suit.
        fil(ComposantsFrame, "Réunir"):Click()
        assertEquals("reunir", p.phase)
        assertTrue(ComposantsBesoinsFrame:IsShown() and not ComposantsFrame:IsShown())
        fil(ComposantsBesoinsFrame, "Fabriquer"):Click()
        assertEquals("fabriquer", p.phase)
        assertTrue(ComposantsFrame:IsShown() and not ComposantsBesoinsFrame:IsShown())
        fil(ComposantsFrame, "Préparer"):Click()
        assertNil(p.phase)
        -- De nouveau fabriquées, en Fabriquer : Fini, et « Clore » le supprime.
        sacs = { [3576] = 4 }
        fil(ComposantsFrame, "Fabriquer"):Click()
        assertEquals("fini", p.phase)
        ComposantsFrame.clore:Click()
        assertNil(Composants.Projet(p.id), "clos : supprimé")
    end)
    AzerothCommune.Conteneurs, C_Item.GetItemCount, AzerothCommuneDB.chars[moi] = G.Conteneurs, G.GetItemCount, G.fiche
    AzerothCommune.Lire = G.Lire
    if Composants.Projet(p.id) then Composants.Supprimer(p.id) end
    if not ok then error(err, 0) end
end) end)

-- La colonne des projets (#25) : le Brouillon en tête, puis chaque projet avec sa phase ; clic = l'ouvrir dans la vue de sa
-- phase ; clic droit = Renommer (un champ sur l'entrée) / Supprimer ; le Brouillon : Vider seulement.
test("la colonne : le Brouillon et les projets avec leur phase ; clic ouvre, clic droit Renommer / Supprimer", function() sansRecettes(function()
    local a = Composants.NouveauProjet({ name = "Colonne A", lines = { { id = 2841, qty = 2 } } })
    local b = Composants.NouveauProjet({ name = "Colonne B", lines = { { id = 2841, qty = 1 } } })
    local ok, err = pcall(function()
        a.phase = "fabriquer" -- (comme si elle avait été lancée et réunie)
        Composants.Ouvrir(b.id)
        local noms, rang = {}, {}
        for i, e in ipairs(entrees()) do noms[i] = e.nom:GetText(); rang[noms[i]] = i end
        assertEquals("Brouillon", noms[1], "le Brouillon en tête")
        assertTrue(rang["Colonne A"] and rang["Colonne B"] and rang["Colonne A"] < rang["Colonne B"], "les projets dans leur ordre")
        assertEquals("Fabriquer", colonne("Colonne A").phase:GetText())
        assertEquals("Préparer", colonne("Colonne B").phase:GetText())
        assertTrue(colonne("Colonne B").trait:IsShown() and not colonne("Colonne A").trait:IsShown(), "celui affiché se voit")
        -- Clic : la vue de sa phase.
        ouvrir("Colonne A")
        assertEquals(a, projet())
        assertTrue(ComposantsFrame:IsShown() and enCours(fil(ComposantsFrame, "Fabriquer")), "ouvert en Fabriquer")
        -- Clic droit sur un autre projet : Renommer, sur place.
        choisir("Colonne B", "Renommer")
        local champ = tous(ComposantsFrame, function(c) return c:GetObjectType() == "EditBox" and c:IsVisible() and c:GetText() == "Colonne B" end)[1]
        assertNotNil(champ, "le champ du nom, sur l'entrée")
        champ:SetText("Colonne B bis")
        champ:GetScript("OnEnterPressed")(champ)
        assertEquals("Colonne B bis", b.name)
        assertNotNil(colonne("Colonne B bis"), "renommé dans la colonne")
        assertTrue(not champ:IsShown(), "le champ refermé")
        assertEquals(a, projet(), "renommer n'ouvre pas")
        -- Supprimer un autre projet : celui affiché reste.
        choisir("Colonne B bis", "Supprimer")
        assertNil(Composants.Projet(b.id), "supprimé")
        assertNil(colonne("Colonne B bis"))
        assertEquals(a, projet(), "le projet affiché reste")
        -- Le Brouillon : ni Renommer, ni Supprimer.
        local textes = {}
        for _, d in ipairs(menuDe("Brouillon")) do textes[#textes + 1] = MenuUtil.GetElementText(d) end
        assertEquals("Vider le Brouillon", table.concat(textes, ", "))
    end)
    for _, p in ipairs({ a, b }) do if Composants.Projet(p.id) then Composants.Supprimer(p.id) end end
    if not ok then error(err, 0) end
end) end)

-- Un seul bouton d'action en bas, qui suit la phase (#25) ; en Fabriquer, l'arbre en lecture seule et pas de ligne d'ajout ;
-- plus d'options ni de légende dans la fenêtre (les options : la page Composants des réglages du socle).
local function actions()
    local t = {}
    for _, b in ipairs({ ComposantsFrame.lancerB, ComposantsFrame.clore, ComposantsToutFabriquer }) do
        if b and b:IsVisible() then t[#t + 1] = b end
    end
    return t
end
local function quantites()
    return tous(ComposantsFrame, function(c) return c:GetObjectType() == "EditBox" and c:IsVisible() and c:GetParent().node ~= nil end)
end
local function recherche()
    return tous(ComposantsFrame, function(c) return c:GetObjectType() == "EditBox" and c.recherche ~= nil end)[1]
end
test("un seul bouton d'action, selon la phase ; Fabriquer en lecture seule ; ni options ni légende", function() sansRecettes(function()
    local p = Composants.NouveauProjet({ name = "Lecture seule", lines = { { id = 2841, qty = 2 } } })
    local ok, err = pcall(function()
        Composants.Ouvrir(p.id)
        local acts = actions()
        assertEquals(1, #acts, "Préparer : un bouton d'action")
        assertEquals(ComposantsFrame.lancerB, acts[1])
        assertEquals("Lancer", acts[1]:GetText())
        assertTrue(recherche():IsVisible(), "Préparer : la ligne d'ajout")
        assertNil(bouton("Ajouter"), "plus de bouton « Ajouter »")
        assertTrue(#quantites() > 0, "Préparer : la quantité de la ligne se tape")
        local signes = 0
        for _, c in ipairs(cases()) do if (c.toggle:GetText() or "") ~= "" then signes = signes + 1 end end
        assertTrue(signes > 0, "Préparer : des « + » / « – »")
        fil(ComposantsFrame, "Fabriquer"):Click()
        assertEquals("fabriquer", p.phase)
        acts = actions()
        assertEquals(1, #acts, "Fabriquer : un bouton d'action")
        assertEquals(ComposantsToutFabriquer, acts[1], "la prochaine fabrication")
        assertTrue(not recherche():IsVisible(), "Fabriquer : pas de ligne d'ajout")
        assertEquals(0, #quantites(), "Fabriquer : pas de quantité à taper")
        for _, c in ipairs(cases()) do assertEquals("", c.toggle:GetText() or "", "Fabriquer : ni « + » ni « – »") end
        for _, c in ipairs(cases()) do
            if c.node.made > 0 and c.node.kind ~= "target" then
                c:Click()
                assertNil(p.choix and p.choix[c.node.id], "Fabriquer : un clic ne choisit rien")
            end
        end
        -- Plus d'options ni de légende dans la fenêtre.
        assertEquals(0, #tous(ComposantsFrame, function(c) return c:GetObjectType() == "CheckButton" end), "plus de cases à cocher")
        for _, r in ipairs({ ComposantsFrame:GetRegions() }) do
            local t = r.GetText and r:IsShown() and r:GetText()
            assertTrue(not (t == "à acheter" or t == "sans prix" or t == "autres persos"), "une légende : " .. tostring(t))
        end
    end)
    Composants.Supprimer(p.id)
    if not ok then error(err, 0) end
end) end)

test("les options du calcul : sur la page Composants des réglages fusionnés du socle", function()
    local r
    for _, x in ipairs(AzerothCommune.regroupes) do if x.nom == "Composants" then r = x end end
    assertNotNil(r, "Composants regroupé")
    assertType("function", r.reglages)
    local page = CreateFrame("Frame")
    local ancre = CreateFrame("Button", nil, page)
    ancre:SetSize(10, 10); ancre:SetPoint("TOPLEFT")
    r.reglages(page, ancre)
    local cases = tous(page, function(c) return c:GetObjectType() == "CheckButton" end)
    assertEquals(4, #cases, "sacs, banque, autres persos, recettes pas apprises")
    local cb
    for _, c in ipairs(cases) do if c.cle == "unlearned" then cb = c end end
    local avant = ComposantsDB.options.unlearned
    assertEquals(avant and true or false, cb:GetChecked() and true or false)
    cb:Click()
    assertEquals(not avant, ComposantsDB.options.unlearned and true or false, "cochée : l'option change")
    cb:Click()
    assertEquals(avant and true or false, ComposantsDB.options.unlearned and true or false)
end)

-- La Récolte (#18) : sur une ligne qui manque encore, la bascule « Achat » / « Récolte » ; l'état se lit sur le bouton.
test("Besoins : la bascule « Achat » / « Récolte » d'une ligne", function() sansRecettes(function()
    ComposantsDB.recolte = nil
    SlashCmdList.COMPOSANTS("demo set")
    bouton("Lancer"):Click()
    local ligne
    for _, c in pairs(lignesBesoins()) do if c.mode and c.mode:IsShown() then ligne = c break end end
    assertNotNil(ligne, "une ligne qui manque, avec sa bascule")
    local id = ligne.itemID
    assertEquals("Achat", ligne.mode:GetText(), "sans choix : à acheter")
    ligne.mode:Click()
    ligne = lignesBesoins()[id]
    assertEquals("Récolte", ligne.mode:GetText(), "un clic : à récolter")
    assertTrue(ComposantsDB.recolte[id], "noté pour tous les projets")
    assertTrue(ligne.count:GetText():find("à récolter", 1, true) ~= nil, "la ligne le dit, sans prix")
    ligne.mode:Click()
    assertEquals("Achat", lignesBesoins()[id].mode:GetText(), "de nouveau à acheter")
    assertNil(ComposantsDB.recolte[id])
end) end)

-- Fabrication (CONTEXT.md) : un projet tenu par un autre add-on (une tranche de montée de Maîtrise), aux lignes « recette ×
-- nombre de fois ». La fonte du bronze vient de la réserve du socle ; l'enchantement (sans objet produit, pas encore dans
-- la réserve) est ajouté aux recettes vues le temps du test.
test("projet tenu à lignes fabrication : la racine toujours fabriquée, l'enchantement par ses composants", function() sansRecettes(function()
    AzerothCommuneDB.recipes = AzerothCommuneDB.recipes or {}
    local avant = AzerothCommuneDB.recipes[7420]
    AzerothCommuneDB.recipes[7420] = { name = "Enchanter le plastron - Vie mineure", profession = "Enchantement", reagents = { { id = 10940, qty = 1 } } }
    local p = Composants.NouveauProjet({ name = "Tranche d'essai" })
    local ok, err = pcall(function()
        Composants.Tenir(p, "tenu par le test", { { recette = 2659, fois = 5 }, { recette = 7420, fois = 3 } })
        Composants.Ouvrir(p.id)
        assertTrue(affiche("Tranche d'essai"))
        local racines, de = {}, {}
        for _, c in ipairs(cases()) do
            if c.node.kind == "target" then racines[#racines + 1] = c end
            de[c.node.id] = c
        end
        assertEquals(1, #racines, "une seule case racine : la barre de bronze (l'enchantement n'en a pas)")
        local barre = racines[1]
        assertEquals(2841, barre.node.id)
        assertEquals(10, barre.node.made, "fabriquée : 5 fontes, 2 barres chacune")
        assertNotNil(de[10940], "la poussière de l'enchantement")
        assertEquals(0, #de[10940].node.parents, "sans case au-dessus")
        -- La racine : un clic ne la passe pas en « acheter », l'API refuse avec une raison.
        barre:Click()
        assertNil(p.choix and p.choix[2841], "clic sur la racine : aucun choix")
        local acheter, raison = Composants.Choix(p, 2841, "acheter")
        assertEquals(false, acheter)
        assertType("string", raison)
        -- Dessous, libre : la barre de cuivre achetée toute faite, puis retour au calcul.
        assertNotNil(de[2840], "la barre de cuivre sous le bronze")
        assertTrue(de[2840].node.made > 0, "témoin : le cuivre se fond")
        de[2840]:Click()
        assertEquals("acheter", p.choix and p.choix[2840])
        for _, c in ipairs(cases()) do if c.node.id == 2840 then c:Click() end end
        assertNil(p.choix and p.choix[2840])
        -- Les Besoins : la poussière à réunir.
        bouton("Lancer"):Click()
        assertNotNil(lignesBesoins()[10940], "la poussière dans les Besoins")
        -- La barre de bronze n'y paraît que par sa recette à apprendre (personne ne la connaît ici), jamais à réunir.
        local barreB = lignesBesoins()[2841]
        assertTrue(barreB == nil or (barreB.info or ""):find("^Pour fabriquer") ~= nil, "la barre de bronze, fabriquée : rien à réunir")
    end)
    AzerothCommuneDB.recipes[7420] = avant
    Composants.Tenir(p, nil)
    Composants.Supprimer(p.id)
    if not ok then error(err, 0) end
end) end)

test("la barre de recherche propose les objets de la recherche du socle", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local box = tous(ComposantsFrame, function(c) return c:GetObjectType() == "EditBox" and c.recherche ~= nil end)[1]
    assertNotNil(box, "barre de recherche")
    box:SetText("bronze")
    box:GetScript("OnTextChanged")(box, true)
    local attendus = AzerothCommune.ChercherObjets("bronze", 8)
    local montres = tous(ComposantsFrame, function(c)
        return c:GetObjectType() == "Button" and c:IsShown() and c.text ~= nil and math.floor(c:GetWidth() + 0.5) == 316
    end)
    assertEquals(#attendus, #montres)
    box:SetText("")
end) end)

-- Les Besoins défilent : une longue liste ne fait pas dépasser la fenêtre (retour de Virgile).
test("Besoins : la fenêtre plafonne sa hauteur et la liste défile", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo set")
    local p = projet()
    for id = 2840, 2880 do Composants.Ajouter(p, id, 3) end -- une quarantaine de lignes de plus
    bouton("Lancer"):Click()
    assertTrue(ComposantsBesoinsFrame:GetHeight() <= 520, "hauteur plafonnée : " .. ComposantsBesoinsFrame:GetHeight())
    local n = 0
    for _ in pairs(lignesBesoins()) do n = n + 1 end
    assertTrue(n > 15, "beaucoup de lignes : " .. n)
end) end)
