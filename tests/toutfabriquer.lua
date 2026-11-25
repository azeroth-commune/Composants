-- La prochaine fabrication dans wow-ui-sim : le bouton d'action en bas de la grande vue, sa case cerclée (Fabriquer.lua).
-- ponytail: ce fichier passe après projet.lua exprès : au-delà de 5 s d'horloge simulée, le relevé du socle (scanAll) tourne
-- avec les données du simulateur et le test des Besoins de projet.lua ne trouve plus sa case ; le rendre robuste si un autre
-- test doit faire avancer l'horloge avant lui.
local function ecouler(s) -- horloge manuelle du simulateur : les minuteries programmées partent
    pcall(A_Admin.SetManualClock, GetTime())
    A_Admin.AdvanceTime(s)
end

-- Le bouton d'action en Fabriquer : la prochaine fabrication, sa case cerclée. 4 barres d'étain à fondre (Fonte de l'étain,
-- réserve du socle), 4 minerais en sac ; les sacs, le métier ouvert et les réponses de C_TradeSkillUI sont ceux du test.
test("le bouton d'action : la prochaine fabrication, une ou tout, sa fenêtre, l'avancement, hors combat", function()
    if not ProfessionsFrame then C_AddOns.LoadAddOn("Blizzard_Professions") end
    local T, garde, lance = C_TradeSkillUI, {}, {}
    local metier, combat, sacs = nil, false, { [2771] = 4 }
    local faux = {
        GetBaseProfessionInfo = function() return { professionName = metier or "", skillLevel = 1, maxSkillLevel = 75 } end,
        IsTradeSkillLinked = function() return false end,
        IsTradeSkillGuild = function() return false end,
        IsNPCCrafting = function() return false end,
        GetRecipeInfo = function(k) return { recipeID = k, learned = k == 3304 } end, -- le relevé du socle la note, comme en jeu
        GetCraftableCount = function(k) return k == 3304 and (sacs[2771] or 0) or 0 end,
        GetRecipeRequirements = function() return {} end,
        CraftRecipe = function(k, n) lance[#lance + 1] = { k, n } end,
    }
    for n, fn in pairs(faux) do garde[n], T[n] = T[n], fn end
    local G = { InCombatLockdown = InCombatLockdown, Conteneurs = AzerothCommune.Conteneurs, GetItemCount = C_Item.GetItemCount,
        unlearned = ComposantsDB.options.unlearned }
    InCombatLockdown = function() return combat end
    AzerothCommune.Conteneurs = function(garder)
        local items = {}
        for id, n in pairs(sacs) do items[#items + 1] = { id = id, count = n } end
        return garder("Backpack") and { b = { items = items } } or {}
    end
    C_Item.GetItemCount = function(id) return sacs[id] or 0 end
    ComposantsDB.options.unlearned = true
    -- Le relevé du socle (5 s après la connexion, puis chaque minute) tombe pendant le test et noterait ces faux sacs et ce
    -- faux métier sur la fiche du perso et dans ses lots : rendus tels quels.
    local function copie(t) if type(t) ~= "table" then return t end local c = {} for k, v in pairs(t) do c[k] = copie(v) end return c end
    local moi = UnitGUID("player")
    local fiche, lots = copie(AzerothCommuneDB.chars[moi]), copie(AzerothCommuneDB.lots)
    local p = Composants.NouveauProjet({ name = "Barres d'étain", lines = { { id = 3576, qty = 4 } } })
    local function fonte(n) for _ = 1, n do FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "fonte", 3304) end end
    -- La case d'un objet dans l'arbre, et une ligne de texte du dessin (la ligne du projet).
    local function caseDe(id)
        local function chercher(f)
            for _, c in ipairs({ f:GetChildren() }) do
                if c.node and c.node.id == id and c:IsShown() then return c end
                local r = chercher(c)
                if r then return r end
            end
        end
        return chercher(ComposantsFrame)
    end
    local function enBas(b) -- en bas à droite de la grande vue, sous l'arbre
        return b:GetParent() == ComposantsFrame and b:GetBottom() - ComposantsFrame:GetBottom() < 20
            and ComposantsFrame:GetRight() - b:GetRight() < 20
    end
    local function cerclee(c) return c.contour ~= nil and c.contour[1]:IsShown() end
    local function ligne(content, motif)
        for _, r in ipairs({ content:GetRegions() }) do
            if r.GetText and r:IsShown() and (r:GetText() or ""):find(motif) then return r end
        end
    end
    -- Le bouton du fil « Fabriquer » de la grande vue (la prochaine fabrication n'est proposée qu'en Fabriquer).
    local function filFabriquer()
        for _, c in ipairs({ ComposantsFrame:GetChildren() }) do
            if c:GetObjectType() == "Button" and ((c:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) == "Fabriquer" then return c end
        end
    end
    local ok, err = pcall(function()
        Composants.Ouvrir(p.id)
        ecouler(1)
        assertTrue(not (ComposantsToutFabriquer and ComposantsToutFabriquer:IsShown()), "en Préparer : pas de prochaine fabrication")
        filFabriquer():Click()
        ecouler(1)
        local b = ComposantsToutFabriquer
        assertNotNil(b, "le bouton de la prochaine fabrication")
        local barre = caseDe(3576)
        assertNotNil(barre, "la case Barre d'étain")
        assertTrue(b:IsVisible() and enBas(b), "visible, en bas de la grande vue")
        assertTrue(cerclee(barre), "la case de la prochaine fabrication se distingue : cerclée")
        local content, scroll = barre:GetParent(), barre:GetParent():GetParent()
        assertTrue(ComposantsFrame.status:GetBottom() - ComposantsFrame:GetBottom() < 20, "la barre d'état en bas")
        assertTrue(ComposantsFrame.status:GetRight() <= b:GetLeft(), "la barre d'état ne passe pas sous le bouton")
        -- Aucune fenêtre de métier : le bouton le dit, sa macro ouvre le Minage.
        assertEquals("Ouvre Minage", b:GetText())
        assertTrue(b:IsEnabled(), "Ouvre : cliquable")
        assertEquals("macro", b:GetAttribute("type"))
        assertEquals("/cast Minage", b:GetAttribute("macrotext"))
        -- Molette : le dessin zoome, le bouton reste en bas, la case reste cerclée.
        scroll:GetScript("OnMouseWheel")(scroll, 1)
        scroll:GetScript("OnMouseWheel")(scroll, 1)
        assertTrue(enBas(b) and cerclee(barre), "zoomé : le bouton en bas, la case cerclée")
        -- Le Minage ouvert : clic = une fabrication.
        metier = "Minage"
        ProfessionsFrame:Show()
        FireEvent("TRADE_SKILL_SHOW")
        ecouler(1)
        assertTrue(b:GetText():find(" ×4$") ~= nil, "la barre d'étain, 4 à faire : " .. b:GetText())
        assertNil(b:GetAttribute("type"), "plus de macro")
        b:Click("LeftButton")
        assertEquals(1, #lance)
        assertEquals(3304, lance[1][1]); assertEquals(1, lance[1][2], "clic : une")
        assertTrue(b:GetText():find(" 0/1…$") ~= nil, b:GetText())
        fonte(1)
        ecouler(1)
        assertTrue(b:GetText():find(" ×4$") ~= nil, "finie (le test ne change pas les sacs) : de nouveau prête, " .. b:GetText())
        -- Clic droit : tout ce que les sacs permettent.
        b:Click("RightButton")
        assertEquals(2, #lance)
        assertEquals(3304, lance[2][1]); assertEquals(4, lance[2][2], "clic droit : les 4")
        -- En cours : l'avancement sur le bouton et sur la case, et pas de second clic.
        assertTrue(b:GetText():find(" 0/4…$") ~= nil, b:GetText())
        assertTrue(not b:IsEnabled(), "en cours : grisé")
        b:Click("LeftButton")
        assertEquals(2, #lance, "pas de second lancement")
        fonte(2)
        ecouler(1)
        assertTrue(b:GetText():find(" 2/4…$") ~= nil, b:GetText())
        -- La barre de la case, pas une barre à lui : la part « à fabriquer » en 4 crans, 2 pleins (couleur du stock).
        assertNil(b.fill, "le bouton : son texte et son action, sans barre")
        local function rempli() return barre.cran:IsShown() and barre.cran:GetWidth() / barre.cranW or 0 end
        local w = rempli()
        assertTrue(w > 0.45 and w < 0.55, "2 crans sur 4 : " .. w * 4)
        local seps = 0
        for _, s in ipairs(barre.seps) do if s:IsShown() then seps = seps + 1 end end
        assertEquals(3, seps, "4 crans")
        local x = (barre.seps[2]:GetLeft() - barre.cran:GetLeft()) / barre.cranW
        assertTrue(x > 0.45 and x < 0.55, "la 2e séparation au milieu : " .. x)
        -- L'incantation du jeu à moitié : le 3e cran à moitié (2,5 sur 4), image après image.
        local uci, secret = UnitCastingInfo, issecretvalue
        local cast = function() local t = GetTime() * 1000 return "Fonte", "", nil, t - 1000, t + 1000, true, 7, false, 3304 end
        UnitCastingInfo = cast
        barre:GetScript("OnUpdate")(barre, 0.016)
        w = rempli()
        UnitCastingInfo = uci
        assertTrue(w > 0.6 and w < 0.65, "cran en cours à moitié : " .. w * 4)
        -- Secrète : le cran attend la fin de l'incantation, sans erreur.
        UnitCastingInfo, issecretvalue = cast, function() return true end
        local okSecret, errSecret = pcall(barre:GetScript("OnUpdate"), barre, 0.016)
        w = rempli()
        UnitCastingInfo, issecretvalue = uci, secret
        assertTrue(okSecret, tostring(errSecret))
        assertTrue(w > 0.45 and w < 0.55, "secrète : 2 crans pleins, " .. w * 4)
        -- Les 4 fondues : les barres dans les sacs, tout est fait ; ça se lit sur la ligne du projet.
        sacs = { [3576] = 4 }
        fonte(2)
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        assertTrue(not b:IsShown(), "fini : plus de prochaine fabrication")
        assertNotNil(ligne(content, "Tout est fabriqué"), "« Tout est fabriqué » sur la ligne du projet")
        assertEquals("fini", p.phase, "phase Fini")
        assertTrue(ComposantsFrame.clore:IsVisible() and not ComposantsFrame.lancerB:IsVisible(), "Fini : « Clore », seul")
        -- Fini est gardé (des barres vendues ne rouvrent rien) ; le fil ramène en Fabriquer, le bouton revient.
        sacs = { [2771] = 4 }
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        assertEquals("fini", p.phase, "Fini gardé")
        assertTrue(not b:IsShown(), "Fini : pas d'action")
        filFabriquer():Click()
        ecouler(1)
        assertTrue(b:IsShown() and enBas(b) and cerclee(caseDe(3576)), "de retour en bas, la case cerclée")
        assertTrue(not ComposantsFrame.clore:IsVisible(), "Fabriquer : pas de « Clore »")
        b:Click("RightButton")
        assertTrue(b:GetText():find(" 0/4…$") ~= nil, b:GetText())
        FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "fonte", 3304)
        ecouler(1)
        assertTrue(b:GetText():find(" ×4$") ~= nil, "interrompue : de nouveau prête, " .. b:GetText())
        -- Combat : le bouton quitte l'arbre juste avant le verrou ; rien d'écrit pendant, molette libre ; tout revient à la sortie.
        FireEvent("PLAYER_REGEN_DISABLED")
        combat = true
        assertTrue(not b:IsShown() and b:GetParent() == UIParent, "en combat : hors de la fenêtre")
        metier = nil
        ProfessionsFrame:Hide()
        FireEvent("TRADE_SKILL_CLOSE")
        ecouler(1)
        scroll:GetScript("OnMouseWheel")(scroll, -1)
        assertTrue(not b:IsShown(), "en combat : toujours hors de la fenêtre")
        assertNil(b:GetAttribute("type"), "en combat : aucun attribut écrit")
        combat = false
        FireEvent("PLAYER_REGEN_ENABLED")
        ecouler(1)
        barre = caseDe(3576)
        assertTrue(b:IsVisible() and enBas(b), "de retour en bas de la fenêtre")
        assertEquals("Ouvre Minage", b:GetText())
        assertEquals("/cast Minage", b:GetAttribute("macrotext"))
        -- Sans composants : le bouton dit ce qui manque, grisé.
        sacs = {}
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        assertTrue(b:GetText():find("^Il manque ") ~= nil, b:GetText())
        assertTrue(not b:IsEnabled(), "rien de possible : grisé")
        assertNil(b:GetAttribute("type"))
        assertTrue(not (ComposantsFrame.clore and ComposantsFrame.clore:IsShown()), "pas fini : rien à clore")
        assertNil(barre:GetScript("OnUpdate"), "hors fabrication : pas d'OnUpdate")
        -- Tout fabriqué : « Clore », le bouton d'action en bas, sans Maj ; le projet sort de la liste.
        sacs = { [3576] = 4 }
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        local clore = ComposantsFrame.clore
        assertTrue(clore and clore:IsVisible(), "fini : « Clore »")
        assertEquals("Clore", clore:GetText())
        assertTrue(enBas(clore), "à la place du bouton d'action")
        clore:Click("LeftButton")
        assertNil(Composants.Projet(p.id), "clos : le projet n'est plus là")
    end)
    for n in pairs(faux) do T[n] = garde[n] end
    InCombatLockdown, AzerothCommune.Conteneurs, C_Item.GetItemCount = G.InCombatLockdown, G.Conteneurs, G.GetItemCount
    ComposantsDB.options.unlearned = G.unlearned
    AzerothCommuneDB.chars[moi], AzerothCommuneDB.lots = fiche, lots
    Composants.Supprimer(p.id)
    ProfessionsFrame:Hide()
    if ComposantsFrame then ComposantsFrame:Hide() end
    if not ok then error(err, 0) end
end)

