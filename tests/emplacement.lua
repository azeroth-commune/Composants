-- L'emplacement du bloc (API.lua, Composants.Emplacements) : un autre add-on dessine dans les blocs de l'arbre et dit
-- lesquels sont confiés (réduits à une seule case). Ici un faux fournisseur, à la place de celui qui est chargé (Handshake,
-- s'il est dans les racines), remis à la fin de chaque test. Les blocs viennent de la réserve des recettes du socle.
local function tous(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        tous(c, ok, out)
    end
    return out
end
local function cases() return tous(ComposantsFrame, function(c) return c.node ~= nil and c:IsShown() end) end
local function projet() return ComposantsDB.projets[ComposantsDB.courant] end
local function blocsDessines() return tous(ComposantsFrame, function(c) return c.grp ~= nil and c:IsShown() end) end

-- f(appels) avec le faux fournisseur : appels[i] = { p, bloc, confie, zone } à chaque dessin ; confier = { [métier] = true }
-- (true = le projet entier) ; apports = { [itemID] = true }. Recettes pas apprises comptées (personne n'en a ici).
local function avecFaux(confier, apports, f)
    local appels = {}
    local faux = {
        confie = function(p, bloc) return confier[bloc and bloc.key or true] == true end,
        bloc = function(zone, p, bloc, confie)
            appels[#appels + 1] = { p = p, bloc = bloc, confie = confie, zone = zone }
            zone.faux = zone.faux or zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            zone.faux:SetPoint("LEFT", 4, 0)
            zone.faux:SetText((confie and "Confié · " or "Libre · ") .. (bloc and bloc.key or "tout"))
            if not confie then zone:SetWidth(zone.faux:GetStringWidth() + 8) end
        end,
        apports = function() return apports end,
    }
    local avant = Composants.Emplacements(faux)
    local unlearned = ComposantsDB.options.unlearned
    ComposantsDB.options.unlearned = true
    local ok, err = pcall(f, appels)
    ComposantsDB.options.unlearned = unlearned
    assertEquals(faux, Composants.Emplacements(avant), "le faux rendu, l'ancien remis")
    ComposantsFrame:Hide()
    if not ok then error(err, 0) end
end
local function dernier(appels, cle)
    for i = #appels, 1, -1 do
        local a = appels[i]
        if (a.bloc and a.bloc.key or true) == cle then return a end
    end
end

test("sans fournisseur : aucun emplacement, rien sur d'autres joueurs", function()
    avecFaux({}, nil, function()
        local faux = Composants.Emplacements(nil)
        SlashCmdList.COMPOSANTS("demo ceinture")
        assertTrue(#blocsDessines() > 0, "des blocs (AzerothCommune/RecettesReserve.lua présent ?)")
        for _, t in ipairs({ "Commander", "Préparer la demande", "Plus", "Importer une liste reçue" }) do
            assertEquals(0, #tous(ComposantsFrame, function(c) return c:IsVisible() and c.GetText and c:GetText() == t end), t)
        end
        assertEquals(0, #tous(ComposantsFrame, function(c) return c.emplacement and c:IsVisible() end), "aucune zone montrée")
        Composants.Emplacements(faux)
    end)
end)

test("le fournisseur dessine dans chaque bloc et sur la ligne du projet ; jamais sur le Brouillon", function()
    avecFaux({}, nil, function(appels)
        SlashCmdList.COMPOSANTS("demo ceinture")
        local p = projet()
        local blocs = Composants.Arbre(p).blocs
        assertTrue(#blocs > 1, "plusieurs blocs")
        for _, b in ipairs(blocs) do
            local a = dernier(appels, b.key)
            assertNotNil(a, "dessiné dans le bloc " .. b.key)
            assertEquals(p, a.p)
            assertTrue(a.confie == false and a.zone:IsShown(), "libre : une zone sur sa ligne de titre")
        end
        local tout = dernier(appels, true)
        assertTrue(tout ~= nil and tout.confie == false, "la ligne du projet entier")
        -- Le Brouillon, avec une ceinture (des blocs) : on n'y commande rien, le fournisseur n'en sait rien.
        local b = ComposantsDB.brouillon
        local deja = #b.lines
        Composants.Ajouter(b, 10721, 1)
        local n = #appels
        tous(ComposantsFrame, function(c) return c.p == b and c.nom ~= nil end)[1]:Click("LeftButton")
        local ok, err = pcall(function()
            assertTrue(#blocsDessines() > 0, "des blocs sur le Brouillon")
            for i = n + 1, #appels do assertTrue(appels[i].p ~= b, "rien demandé pour le Brouillon") end
            assertEquals(0, #tous(ComposantsFrame, function(c) return c.emplacement and c:IsVisible() end), "aucune zone")
        end)
        if #b.lines > deja then Composants.Retirer(b, #b.lines) end
        if not ok then error(err, 0) end
    end)
end)

test("un bloc confié se réduit à une seule case, dessinée par le fournisseur", function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    ComposantsDB.options.unlearned = true
    local blocs = Composants.Arbre(projet()).blocs
    ComposantsFrame:Hide()
    local cle = blocs[#blocs].key -- la première étape : ce qu'il livre entre dans un autre bloc
    local avant
    avecFaux({}, nil, function() SlashCmdList.COMPOSANTS(""); avant = #cases() end)
    avecFaux({ [cle] = true }, nil, function(appels)
        SlashCmdList.COMPOSANTS("")
        local a = dernier(appels, cle)
        assertTrue(a ~= nil and a.confie == true, "confié")
        assertTrue(a.zone:IsShown() and math.floor(a.zone:GetHeight() + 0.5) == 42, "la zone a la taille d'une case")
        assertTrue(#cases() < avant, ("ses cases sortent du dessin (%d → %d)"):format(avant, #cases()))
        for _, b in ipairs(blocs) do
            if b.key ~= cle then assertEquals(false, dernier(appels, b.key).confie, b.key .. " reste libre") end
        end
    end)
end)

test("le projet entier confié : une seule case ; ses apports sortent de l'arbre", function()
    avecFaux({ [true] = true }, nil, function(appels)
        SlashCmdList.COMPOSANTS("demo ceinture")
        assertEquals(0, #cases(), "plus aucune case")
        local a = dernier(appels, true)
        assertTrue(a ~= nil and a.confie and a.zone:IsShown(), "la case du projet")
    end)
    SlashCmdList.COMPOSANTS("demo ceinture")
    local id
    for _, c in ipairs(cases()) do if c.node.kind ~= "target" and c.node.made == 0 then id = c.node.id break end end
    ComposantsFrame:Hide()
    assertNotNil(id, "une case achetée")
    avecFaux({}, { [id] = true }, function()
        SlashCmdList.COMPOSANTS("")
        local n
        for _, c in ipairs(cases()) do if c.node.id == id then n = c.node end end
        assertTrue(n ~= nil and n.apport > 0 and n.need == 0, "la case fournie, hors de l'arbre")
    end)
end)

test("une erreur du fournisseur ne casse pas la fenêtre : elle est signalée, l'arbre est dessiné", function()
    local erreurs, geh = {}, geterrorhandler
    geterrorhandler = function() return function(e) erreurs[#erreurs + 1] = e end end
    local casse = function() error("fournisseur cassé") end
    local avant = Composants.Emplacements({ confie = casse, bloc = casse, apports = casse })
    local unlearned = ComposantsDB.options.unlearned
    ComposantsDB.options.unlearned = true
    local ok, err = pcall(function()
        SlashCmdList.COMPOSANTS("demo ceinture")
        assertTrue(#cases() > 0, "l'arbre est dessiné")
        assertTrue(#blocsDessines() > 0, "les blocs aussi")
        assertTrue(#erreurs > 0, "l'erreur est signalée")
    end)
    ComposantsDB.options.unlearned = unlearned
    geterrorhandler = geh
    Composants.Emplacements(avant)
    ComposantsFrame:Hide()
    if not ok then error(err, 0) end
end)
