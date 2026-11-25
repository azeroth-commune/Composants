-- « Tout fabriquer » dans wow-ui-sim : le bouton sous la barre d'état de la fenêtre des projets (Fabriquer.lua).
-- ponytail: ce fichier passe après projet.lua exprès : au-delà de 5 s d'horloge simulée, le relevé du socle (scanAll) tourne
-- avec les données du simulateur et le test des Besoins de projet.lua ne trouve plus sa case ; le rendre robuste si un autre
-- test doit faire avancer l'horloge avant lui.
local function ecouler(s) -- horloge manuelle du simulateur : les minuteries programmées partent
    pcall(A_Admin.SetManualClock, GetTime())
    A_Admin.AdvanceTime(s)
end

-- « Tout fabriquer » : le bouton sous la barre d'état de la fenêtre des projets. 4 barres d'étain à fondre (Fonte de l'étain,
-- réserve du socle), 4 minerais en sac ; les sacs, le métier ouvert et les réponses de C_TradeSkillUI sont ceux du test.
test("Tout fabriquer : la prochaine fabrication du projet affiché, sa fenêtre, l'avancement, hors combat", function()
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
    local function texte(b, motif) assertTrue(b:GetText():find(motif) ~= nil, b:GetText() .. " ≠ " .. motif) end
    local function fonte(n) for _ = 1, n do FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "fonte", 3304) end end
    local ok, err = pcall(function()
        Composants.Ouvrir(p.id)
        ecouler(1)
        local b = ComposantsToutFabriquer
        assertNotNil(b, "le bouton Tout fabriquer")
        assertTrue(b:IsVisible(), "visible")
        assertTrue(b:GetTop() <= ComposantsFrame.status:GetBottom(), "sous la barre d'état")
        -- Aucune fenêtre de métier : la macro ouvre le Minage.
        texte(b, "^Ouvrir Minage : 4 × ")
        assertTrue(b:IsEnabled(), "Ouvrir : cliquable")
        assertEquals("macro", b:GetAttribute("type"))
        assertEquals("/cast Minage", b:GetAttribute("macrotext"))
        -- Le Minage ouvert : le même bouton fabrique les 4, d'un clic.
        metier = "Minage"
        ProfessionsFrame:Show()
        FireEvent("TRADE_SKILL_SHOW")
        ecouler(1)
        texte(b, "^Fabriquer 4 × ")
        assertNil(b:GetAttribute("type"), "plus de macro")
        b:Click("LeftButton")
        assertEquals(1, #lance)
        assertEquals(3304, lance[1][1]); assertEquals(4, lance[1][2])
        -- En cours : l'avancement, et pas de second clic.
        texte(b, " 0/4…$")
        assertTrue(not b:IsEnabled(), "en cours : grisé")
        b:Click("LeftButton")
        assertEquals(1, #lance, "pas de second lancement")
        fonte(2)
        ecouler(1)
        texte(b, " 2/4…$")
        -- Les 4 fondues : les barres dans les sacs, le bouton dit que tout est fait.
        sacs = { [3576] = 4 }
        fonte(2)
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        assertEquals("Tout est fabriqué", b:GetText())
        assertTrue(not b:IsEnabled(), "fini : grisé")
        -- Interrompue : le bouton revient à la fabrication.
        sacs = { [2771] = 4 }
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        b:Click("LeftButton")
        texte(b, " 0/4…$")
        FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "fonte", 3304)
        ecouler(1)
        texte(b, "^Fabriquer 4 × ")
        -- Combat : le bouton quitte la fenêtre juste avant le verrou ; rien d'écrit pendant ; tout revient à la sortie.
        FireEvent("PLAYER_REGEN_DISABLED")
        combat = true
        assertTrue(not b:IsShown(), "en combat : hors de la fenêtre")
        metier = nil
        ProfessionsFrame:Hide()
        FireEvent("TRADE_SKILL_CLOSE")
        ecouler(1)
        texte(b, "^Fabriquer 4 × ")
        assertNil(b:GetAttribute("type"), "en combat : aucun attribut écrit")
        combat = false
        FireEvent("PLAYER_REGEN_ENABLED")
        ecouler(1)
        assertTrue(b:IsVisible() and b:GetParent() == ComposantsFrame, "de retour dans la fenêtre")
        texte(b, "^Ouvrir Minage : 4 × ")
        assertEquals("/cast Minage", b:GetAttribute("macrotext"))
        -- Sans composants : rien de proposé.
        sacs = {}
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        texte(b, "^Il manque ")
        assertTrue(not b:IsEnabled(), "rien de possible : grisé")
        assertNil(b:GetAttribute("type"))
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

