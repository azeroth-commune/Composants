-- L'infobulle des objets (#16) dans wow-ui-sim : la vraie bulle du jeu (GameTooltip, chemin des données
-- d'infobulle de Forever, Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua) porte « Utilisé dans : <projet> » pour
-- un objet de l'arbre d'un projet, rien pour un objet qui n'entre dans rien. Le simulateur n'a pas les données d'infobulle
-- des objets (son SetItemByID appelle les post-calls avec des données sans id) : le test les donne au chemin Lua du jeu
-- (TooltipDataHandlerMixin:ProcessInfo, celui que suit SetItemByID dans le client), comme le client les donnerait.
local function lignes()
    local out = {}
    for i = 1, GameTooltip:NumLines() do
        local t = _G["GameTooltipTextLeft" .. i]
        out[#out + 1] = t and t:GetText() or ""
    end
    return table.concat(out, "\n")
end
local function bulle(id, sansDonnees)
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    if sansDonnees then GameTooltip:SetItemByID(id)
    else GameTooltip:ProcessInfo({ tooltipData = { type = Enum.TooltipDataType.Item, id = id, lines = { { leftText = "objet " .. id, type = 0 } } } }) end
    local t = lignes()
    GameTooltip:Hide()
    return t
end

test("Infobulle : « Utilisé dans » sur un objet d'un projet, rien sur un objet hors de tout projet", function()
    local p = Composants.NouveauProjet({ name = "Essai d'infobulle", lines = { { id = 2841, qty = 2 } } }) -- barre de bronze
    local ok, err = pcall(function()
        local t = bulle(2841)
        assertTrue(t:find("^objet 2841\n") ~= nil, "la bulle du jeu d'abord : " .. t)
        assertTrue(t:find("\nUtilisé dans : [^\n]*Essai d'infobulle") ~= nil, t)
        local autre = bulle(6948) -- la pierre de foyer : dans aucun arbre, aucune recette
        assertEquals("objet 6948", autre)
        -- Les données du simulateur (sans id) : aucune ligne, aucune erreur.
        assertTrue(bulle(2841, true):find("Utilisé dans") == nil, "sans id : rien")
    end)
    Composants.Supprimer(p.id)
    if ComposantsFrame then ComposantsFrame:Hide() end
    if not ok then error(err, 0) end
end)
