-- « Tout fabriquer » dans wow-ui-sim : la prochaine fabrication sur sa case de l'arbre (Fabriquer.lua).
-- ponytail: ce fichier passe après projet.lua exprès : au-delà de 5 s d'horloge simulée, le relevé du socle (scanAll) tourne
-- avec les données du simulateur et le test des Besoins de projet.lua ne trouve plus sa case ; le rendre robuste si un autre
-- test doit faire avancer l'horloge avant lui.
local function ecouler(s) -- horloge manuelle du simulateur : les minuteries programmées partent
    pcall(A_Admin.SetManualClock, GetTime())
    A_Admin.AdvanceTime(s)
end

-- « Tout fabriquer » : l'action sur la case de la prochaine fabrication. 4 barres d'étain à fondre (Fonte de l'étain,
-- réserve du socle), 4 minerais en sac ; les sacs, le métier ouvert et les réponses de C_TradeSkillUI sont ceux du test.
test("Tout fabriquer : la prochaine fabrication sur sa case, sa fenêtre, l'avancement, hors combat", function()
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
    local function caseDe(id, b)
        for _, c in ipairs({ b:GetParent():GetParent():GetChildren() }) do
            if c.node and c.node.id == id and c:IsShown() then return c end
        end
    end
    local function dans(b, c) -- le bouton tient dans la case, à toute échelle
        return b:GetLeft() >= c:GetLeft() - 0.5 and b:GetRight() <= c:GetRight() + 0.5
            and b:GetTop() <= c:GetTop() + 0.5 and b:GetBottom() >= c:GetBottom() - 0.5
    end
    local function ligne(content, motif)
        for _, r in ipairs({ content:GetRegions() }) do
            if r.GetText and r:IsShown() and (r:GetText() or ""):find(motif) then return r end
        end
    end
    local ok, err = pcall(function()
        Composants.Ouvrir(p.id)
        ecouler(1)
        local b = ComposantsToutFabriquer
        assertNotNil(b, "le bouton de la prochaine fabrication")
        local barre = caseDe(3576, b)
        assertNotNil(barre, "la case Barre d'étain")
        assertEquals(barre, b:GetParent(), "sur la case de la prochaine fabrication")
        assertTrue(b:IsVisible() and dans(b, barre), "visible, dans la case")
        assertTrue(b.contour[1]:IsShown(), "la case se distingue : contour")
        local content, scroll = barre:GetParent(), barre:GetParent():GetParent()
        assertTrue(ComposantsFrame.status:GetBottom() - ComposantsFrame:GetBottom() < 20, "plus de bouton en bas : la barre d'état à sa place")
        -- Aucune fenêtre de métier : la macro ouvre le Minage.
        assertEquals("Ouvrir Minage", b:GetText())
        assertTrue(b:IsEnabled(), "Ouvrir : cliquable")
        assertEquals("macro", b:GetAttribute("type"))
        assertEquals("/cast Minage", b:GetAttribute("macrotext"))
        -- Molette et glisser : le bouton suit la case (enfant de la case, dans le dessin qui défile).
        scroll:GetScript("OnMouseWheel")(scroll, 1)
        scroll:GetScript("OnMouseWheel")(scroll, 1)
        assertTrue(dans(b, barre), "zoomé : toujours dans la case")
        -- Le Minage ouvert : le même bouton fabrique les 4, d'un clic.
        metier = "Minage"
        ProfessionsFrame:Show()
        FireEvent("TRADE_SKILL_SHOW")
        ecouler(1)
        assertEquals("Fabriquer 4", b:GetText())
        assertNil(b:GetAttribute("type"), "plus de macro")
        b:Click("LeftButton")
        assertEquals(1, #lance)
        assertEquals(3304, lance[1][1]); assertEquals(4, lance[1][2])
        -- En cours : l'avancement sur la case, sa barre, et pas de second clic.
        assertEquals("0/4…", b:GetText())
        assertTrue(not b:IsEnabled(), "en cours : grisé")
        b:Click("LeftButton")
        assertEquals(1, #lance, "pas de second lancement")
        fonte(2)
        ecouler(1)
        assertEquals("2/4…", b:GetText())
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
        assertTrue(not b:IsShown(), "fini : plus d'action")
        assertNotNil(ligne(content, "Tout est fabriqué"), "« Tout est fabriqué » sur la ligne du projet")
        -- Interrompue : le bouton revient à la fabrication.
        sacs = { [2771] = 4 }
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        assertTrue(b:IsShown() and b:GetParent() == caseDe(3576, b), "de retour sur la case")
        b:Click("LeftButton")
        assertEquals("0/4…", b:GetText())
        FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "fonte", 3304)
        ecouler(1)
        assertEquals("Fabriquer 4", b:GetText())
        -- Combat : le bouton quitte l'arbre juste avant le verrou ; rien d'écrit pendant, molette libre ; tout revient à la sortie.
        FireEvent("PLAYER_REGEN_DISABLED")
        combat = true
        assertTrue(not b:IsShown() and b:GetParent() == UIParent, "en combat : hors de l'arbre")
        metier = nil
        ProfessionsFrame:Hide()
        FireEvent("TRADE_SKILL_CLOSE")
        ecouler(1)
        scroll:GetScript("OnMouseWheel")(scroll, -1)
        assertTrue(not b:IsShown(), "en combat : toujours hors de l'arbre")
        assertNil(b:GetAttribute("type"), "en combat : aucun attribut écrit")
        combat = false
        FireEvent("PLAYER_REGEN_ENABLED")
        ecouler(1)
        barre = caseDe(3576, b)
        assertTrue(b:IsVisible() and b:GetParent() == barre and dans(b, barre), "de retour sur la case")
        assertEquals("Ouvrir Minage", b:GetText())
        assertEquals("/cast Minage", b:GetAttribute("macrotext"))
        -- Sans composants : la case dit ce qui manque, grisée.
        sacs = {}
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        assertTrue(b:GetText():find("^Il manque ") ~= nil, b:GetText())
        assertTrue(not b:IsEnabled(), "rien de possible : grisé")
        assertNil(b:GetAttribute("type"))
        assertTrue(not (ComposantsFrame.clore and ComposantsFrame.clore:IsShown()), "pas fini : rien à clore")
        assertNil(barre:GetScript("OnUpdate"), "hors fabrication : pas d'OnUpdate")
        -- Tout fabriqué : « Clore le projet » sur la ligne du projet, sans Maj ; le projet sort de la liste.
        sacs = { [3576] = 4 }
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        local clore = ComposantsFrame.clore
        assertTrue(clore and clore:IsVisible(), "fini : « Clore le projet »")
        assertEquals("Clore le projet", clore:GetText())
        assertTrue(clore:GetLeft() > ligne(content, "Tout est fabriqué"):GetRight(), "au bout de la ligne du projet")
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

