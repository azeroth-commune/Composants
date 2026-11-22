-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test Composants) : Composants chargé avec le socle Azeroth Commune dans
-- l'interface Forever simulée, avec ou sans Handshake selon les racines du simulateur. Les blocs viennent de la base des
-- recettes du socle (sa réserve, AzerothCommune/RecettesClassic.lua, générée, hors du repo : à copier dans un worktree).
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
-- Le nom du projet affiché en haut de la fenêtre.
local function affiche(nom)
    return #tous(ComposantsFrame, function(c) return c:GetObjectType() == "EditBox" and c:GetText() == nom end) > 0
end
-- Les cases dessinées : une par objet (c.node).
local function cases() return tous(ComposantsFrame, function(c) return c.node ~= nil and c:IsShown() end) end
local function projet() return ComposantsDB.projets[ComposantsDB.courant] end

-- Personne n'a de recette ici : « recettes pas apprises » cochée, toutes comptent et les blocs se dessinent. L'option est
-- rendue telle quelle, même si une vérification échoue.
local function sansRecettes(f)
    local avant = ComposantsDB.options.unlearned
    ComposantsDB.options.unlearned = true
    local ok, err = pcall(f)
    ComposantsDB.options.unlearned = avant
    ComposantsFrame:Hide()
    if ComposantsBesoinsFrame then ComposantsBesoinsFrame:Hide() end
    if HandshakeContratsFrame then HandshakeContratsFrame:Hide() end
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

test("projet de démo : l'arbre et ses blocs, < et > passent d'un projet à l'autre", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    assertTrue(ComposantsFrame:IsShown())
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    assertTrue(#cases() > 5, "l'arbre dessiné (AzerothCommune/RecettesClassic.lua présent ?)")
    local etapes = tous(ComposantsFrame, function(c) return c.grp ~= nil and c:IsShown() end)
    assertTrue(#etapes > 1, "des blocs, un par métier")
    SlashCmdList.COMPOSANTS("demo set")
    assertTrue(affiche("Essai : set en thorium enchanté"))
    bouton("<"):Click()
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    bouton(">"):Click()
    assertTrue(affiche("Essai : set en thorium enchanté"))
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
    assertNotNil(bouton("Vider"))
end) end)

test("le Brouillon : son bouton, hors de « < » et « > », « + » en fait un projet", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local nb = #ComposantsDB.projets
    bouton("Brouillon"):Click()
    bouton("Vider"):Click()
    assertEquals(0, #ComposantsDB.brouillon.lines, "vidé")
    ctrlClicDroit(BRONZE)
    assertTrue(affiche("Brouillon"))
    for _ = 1, nb + 1 do
        bouton(">"):Click()
        assertTrue(not affiche("Brouillon"), "« > » passe par le Brouillon")
    end
    bouton("Brouillon"):Click()
    assertTrue(affiche("Brouillon"))
    bouton("+"):Click()
    assertEquals(nb + 1, #ComposantsDB.projets, "un vrai projet")
    assertEquals(2841, projet().lines[1].id, "avec les lignes du Brouillon")
    assertEquals(0, #ComposantsDB.brouillon.lines, "le Brouillon vidé")
    assertTrue(not affiche("Brouillon"), "le nouveau projet affiché")
end) end)

test("Besoins d'un projet : la petite fenêtre, ce qu'il reste à réunir", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    bouton("Besoins"):Click()
    assertTrue(ComposantsBesoinsFrame:IsShown())
    local lignes = tous(ComposantsBesoinsFrame, function(c) return c.itemID ~= nil and c:IsShown() end)
    assertTrue(#lignes > 0, "des objets à réunir")
    local envoyer = tous(ComposantsBesoinsFrame, function(c) return c.GetText and (c:GetText() or ""):find("Envoyer", 1, true) end)
    assertEquals(0, #envoyer, "plus de bouton « Envoyer » (décision du PRD)")
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

if not Handshake then
    test("Composants seul : aucun bouton de commande", function() sansRecettes(function()
        SlashCmdList.COMPOSANTS("demo ceinture")
        for _, t in ipairs({ "Commander", "Préparer la demande", "Importer", "En clair" }) do
            assertNil(bouton(t), t .. " affiché sans Handshake")
        end
        assertEquals(0, #boutons(function(t) return t:find("tout le projet", 1, true) ~= nil end), "pas de liste de commandes")
    end) end)
else
    -- Avec Handshake : Composants dessine « Commander », « J'apporte » et la barre des commandes par l'API de Handshake.
    local ARTISAN = "Bel Dupont"
    local function artisanConnu() -- son chuchotement : le jeu y joint son GUID (Handshake le retient)
        FireEvent("CHAT_MSG_WHISPER", "bonjour", ARTISAN, "", "", ARTISAN, "", 0, 0, "", 0, 1, "Player-1-0000BE11")
    end
    local function commandes() return boutons(function(t) return t:find(" · ", 1, true) ~= nil end) end

    test("avec Handshake : « Commander » un bloc ajoute une commande, son état se lit dans son contrat", function() sansRecettes(function()
        SlashCmdList.COMPOSANTS("demo ceinture")
        local p = projet()
        assertEquals(1, #commandes()) -- tout le projet
        local commander = boutons(function(t) return t == "Commander" end)
        assertTrue(#commander > 0, "« Commander » sur les blocs")
        commander[1]:Click()
        assertEquals(2, #Handshake.Commandes(p))
        local liste = commandes()
        assertEquals(2, #liste)
        assertTrue(liste[2]:GetText():find("pas envoyée", 1, true) ~= nil, liste[2]:GetText())
        artisanConnu()
        Handshake.Artisan(p, ARTISAN, 2)
        liste[2]:Click()
        bouton("Préparer la demande"):Click()
        assertTrue(HandshakeContratsFrame:IsShown(), "le brouillon s'ouvre dans les contrats")
        for _, c in ipairs(tous(HandshakeContratsFrame, function(c) return c.GetText and c:GetText() == "Envoyer la proposition" and c:IsShown() end)) do c:Click() end
        HandshakeContratsFrame:Hide()
        local texte = commandes()[2]:GetText()
        assertTrue(texte:find("demande envoyée", 1, true) ~= nil, texte)
        assertEquals("demande envoyée", Handshake.Commande(p, 2).etat)
    end) end)

    test("avec Handshake : rien à commander sur le Brouillon", function() sansRecettes(function()
        SlashCmdList.COMPOSANTS("demo ceinture")
        assertTrue(#boutons(function(t) return t == "Commander" end) > 0, "témoin : « Commander » sur un projet")
        bouton("Brouillon"):Click()
        bouton("Vider"):Click()
        ctrlClicDroit("|cffffffff|Hitem:10721::::::::1:::::::::|h[Ceinture]|h|r") -- un objet aux blocs nombreux
        assertTrue(affiche("Brouillon"))
        assertTrue(#tous(ComposantsFrame, function(c) return c.grp ~= nil and c:IsShown() end) > 0, "des blocs dessinés")
        for _, t in ipairs({ "Commander", "Préparer la demande", "Importer", "En clair" }) do
            assertNil(bouton(t), t .. " sur le Brouillon")
        end
        assertEquals(0, #commandes(), "pas de liste de commandes")
        assertNil(HandshakeDB.commandes and HandshakeDB.commandes[ComposantsDB.brouillon.id], "rien de rangé chez Handshake")
        bouton("Vider"):Click()
    end) end)

    test("avec Handshake : Ctrl+clic sur une case, « j'apporte » marque l'apport de la commande", function() sansRecettes(function()
        SlashCmdList.COMPOSANTS("demo ceinture")
        local p = projet()
        local carte
        for _, c in ipairs(cases()) do if c.node.kind ~= "target" then carte = c break end end
        local id = carte.node.id
        local ctrl = IsControlKeyDown
        IsControlKeyDown = function() return true end
        local ok, err = pcall(carte.Click, carte)
        IsControlKeyDown = ctrl
        assertTrue(ok, tostring(err))
        assertTrue(Handshake.Apports(p) ~= nil and Handshake.Apports(p)[id], "l'apport est un terme de la commande")
        assertNil(p.apports, "le projet ne garde aucun apport")
        local apportee
        for _, c in ipairs(cases()) do if c.node.id == id then apportee = c.node end end
        assertTrue(apportee.apport > 0, "la case est apportée dans l'arbre")
    end) end)
end
