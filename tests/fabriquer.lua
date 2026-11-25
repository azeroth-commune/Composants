-- Plus de bouton « Fabriquer » sous la fenêtre de métier du jeu (#25) : on fabrique par le bouton d'action de la grande vue
-- (tests/toutfabriquer.lua). La vraie fenêtre de métier Forever (Blizzard_Professions) chargée, un projet tenu d'une ligne
-- fabrication, le métier ouvert d'après le test.
local function ecouler(s) -- horloge manuelle du simulateur : les minuteries programmées partent
    pcall(A_Admin.SetManualClock, GetTime())
    A_Admin.AdvanceTime(s)
end

test("plus de bouton sous la fenêtre de métier", function()
    if not ProfessionsFrame then C_AddOns.LoadAddOn("Blizzard_Professions") end
    assertNotNil(ProfessionsFrame, "la fenêtre de métier du jeu")
    local recette = AzerothCommune:Lire("base des recettes")[2657] -- Fonte du cuivre (réserve du socle)
    assertNotNil(recette, "la réserve des recettes (AzerothCommune/RecettesReserve.lua) présente")
    local T, garde = C_TradeSkillUI, {}
    local faux = {
        GetBaseProfessionInfo = function() return { professionName = recette.profession, skillLevel = 1, maxSkillLevel = 75 } end,
        GetRecipeInfo = function(k) return { recipeID = k, learned = true, name = recette.name } end,
        GetCraftableCount = function() return 3 end,
    }
    for n, fn in pairs(faux) do garde[n], T[n] = T[n], fn end
    local p = Composants.NouveauProjet({ name = "Tranche d'essai" })
    local ok, err = pcall(function()
        Composants.Tenir(p, "Maîtrise : essai", { { recette = 2657, fois = 4 } })
        ProfessionsFrame:Show()
        FireEvent("TRADE_SKILL_SHOW")
        ecouler(1)
        assertNil(ComposantsFabriquer, "plus de bouton Fabriquer")
        local function sous(f)
            for _, c in ipairs({ f:GetChildren() }) do
                if c:IsVisible() and c.GetText and (c:GetText() or ""):find("^Fabriquer ") then return c end
                local r = sous(c)
                if r then return r end
            end
        end
        assertNil(sous(ProfessionsFrame), "rien de Composants dans la fenêtre de métier")
    end)
    for n in pairs(faux) do T[n] = garde[n] end
    Composants.Supprimer(p.id)
    ProfessionsFrame:Hide()
    if ComposantsFrame then ComposantsFrame:Hide() end
    if not ok then error(err, 0) end
end)
