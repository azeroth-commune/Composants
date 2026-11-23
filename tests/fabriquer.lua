-- « Fabriquer » (#14) dans wow-ui-sim : la vraie fenêtre de métier Forever (Blizzard_Professions) chargée, un projet tenu
-- d'une ligne fabrication ; les réponses de C_TradeSkillUI (métier ouvert, recette apprise, combien en faire) sont celles
-- du test, le simulateur n'ayant pas de métier ; le bouton sous la fenêtre lance CraftRecipe au clic.
local function ecouler(s) -- horloge manuelle du simulateur : les minuteries programmées partent
    pcall(A_Admin.SetManualClock, GetTime())
    A_Admin.AdvanceTime(s)
end

test("Fabriquer : le bouton sous la fenêtre de métier lance la prochaine fabrication du projet tenu", function()
    if not ProfessionsFrame then C_AddOns.LoadAddOn("Blizzard_Professions") end
    assertNotNil(ProfessionsFrame, "la fenêtre de métier du jeu")
    local recette = AzerothCommune:Lire("base des recettes")[2657] -- Fonte du cuivre (réserve du socle)
    assertNotNil(recette, "la réserve des recettes (AzerothCommune/RecettesClassic.lua) présente")
    local T, garde, lance = C_TradeSkillUI, {}, {}
    local faux = {
        GetBaseProfessionInfo = function() return { professionName = recette.profession, skillLevel = 1, maxSkillLevel = 75 } end,
        IsTradeSkillLinked = function() return false end,
        IsTradeSkillGuild = function() return false end,
        IsNPCCrafting = function() return false end,
        GetRecipeInfo = function(k) return { recipeID = k, learned = k == 2657, name = recette.name } end,
        GetCraftableCount = function(k) return k == 2657 and 3 or 0 end,
        GetRecipeRequirements = function() return {} end,
        CraftRecipe = function(k, n) lance[#lance + 1] = { k, n } end,
    }
    for n, fn in pairs(faux) do garde[n], T[n] = T[n], fn end
    local p = Composants.NouveauProjet({ name = "Tranche d'essai" })
    local ok, err = pcall(function()
        Composants.Tenir(p, "Maîtrise : essai", { { recette = 2657, fois = 4 } })
        ProfessionsFrame:Show()
        FireEvent("TRADE_SKILL_SHOW")
        ecouler(1)
        local b = ComposantsFabriquer
        assertNotNil(b, "le bouton Fabriquer")
        assertTrue(b:IsVisible(), "visible sous la fenêtre de métier")
        assertTrue(b:IsEnabled(), "prêt")
        assertTrue(b:GetText():find("^Fabriquer .+ ×4$") ~= nil, b:GetText())
        b:Click("LeftButton")
        b:Click("RightButton")
        assertEquals(2, #lance)
        assertEquals(2657, lance[1][1]); assertEquals(1, lance[1][2])
        assertEquals(3, lance[2][2]) -- tout : ce que les sacs permettent (3), pas les 4 qui restent
        -- La recette oubliée : le bouton le dit, grisé, et ne lance rien.
        T.GetRecipeInfo = function(k) return { recipeID = k, learned = false } end
        FireEvent("BAG_UPDATE_DELAYED")
        ecouler(1)
        assertTrue(b:GetText():find("^Recette inconnue") ~= nil, b:GetText())
        assertTrue(not b:IsEnabled(), "grisé")
        b:Click("LeftButton")
        assertEquals(2, #lance)
        -- Projet lâché : plus de bouton.
        Composants.Tenir(p, nil)
        ecouler(1)
        assertTrue(not b:IsShown(), "plus rien à fabriquer : caché")
    end)
    for n in pairs(faux) do T[n] = garde[n] end
    Composants.Supprimer(p.id)
    ProfessionsFrame:Hide()
    if ComposantsFrame then ComposantsFrame:Hide() end
    if not ok then error(err, 0) end
end)
