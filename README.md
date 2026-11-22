# Composants (nom provisoire)

Add-on WoW Forever, catégorie Métiers : chaque objet décomposé en ses composants, jusqu'aux matières premières ; l'arbre,
vos projets, ce qu'il reste à réunir. Glossaire : `CONTEXT.md`.

- **Requiert** le socle Azeroth Commune (`## Dependencies: AzerothCommune`) : toutes les données (recettes, sacs, banque,
  autres persos, prix de l'HV et des marchands) sont lues par lui.
- **Handshake facultatif** (`## OptionalDeps: Handshake`) : Composants sert seul. Quand Handshake est là, la fenêtre des
  projets montre aussi ses commandes (« Commander » sur un bloc, Ctrl+clic « j'apporte » sur une case, la barre des
  commandes et leur état) : Composants les dessine lui-même en appelant l'API publique de Handshake (global `Handshake`,
  voir le README de Handshake). Sans lui, rien de tout ça n'apparaît.
- **Pour le joueur** : `/composants` (ou `/compo`) ouvre la fenêtre ; `/composants <objet> [quantité] [tout]` l'ajoute au
  projet affiché ; `/composants demo [set|ceinture|hasard]` crée un projet d'essai ; Ctrl+clic droit sur un objet
  n'importe où le met au Brouillon (bouton « Brouillon » ; « + » en fait un projet, « Vider » le vide ; on n'y commande
  rien). Bouton de minicarte et options : ceux, communs, d'Azeroth Commune.
- **Données propres** : `ComposantsDB` (projets, Brouillon, projets mis dans les Besoins, options de calcul). Rien de relevé n'y est gardé (ADR 0002 de l'atelier).

## Fichiers

| Fichier | Rôle |
|---|---|
| `Donnees.lua` | accès au socle (recettes, inventaires, métiers, HV, noms d'objets), `ComposantsDB` |
| `Calcul.lua` | « acheter ou fabriquer » : le plan le moins cher d'un objet, choix entre recettes équivalentes, boucles écartées |
| `Projet.lua` | les projets (identité stable, lignes, choix de case, projet tenu, signal de changement), le Brouillon, les cases, les blocs, l'arbre |
| `Recherche.lua` | la barre de recherche d'objets (sur `AzerothCommune.ChercherObjets`) |
| `Fenetre.lua` | la fenêtre des projets, son dessin ; la barre des commandes de Handshake quand il est là ; Ctrl+clic droit ; `/composants` |
| `Besoins.lua` | les Besoins : les projets qu'on y met (case « dans les Besoins »), puis le Brouillon, sur un seul stock ; leur fenêtre |
| `API.lua` | le global `Composants` |

## API publique

Un seul global, `Composants`, disponible dès le chargement (un add-on qui s'en sert le déclare en `OptionalDeps` ou le
lit plus tard, à l'entrée en jeu). Seul ce qui suit est promis ; l'intérieur peut changer. Un projet `p` est une table
qu'on lit (`p.id` son identité stable, jamais redonnée ; `p.name`, `p.lines`, `p.choix`, `p.tenu`) et qu'on ne modifie
que par ces fonctions. Une ligne est un objet `{ id = itemID, qty = quantité }` ou une **fabrication**
`{ recette = sortID, fois = nombre de fois }` (la clé de la base des recettes du socle).

```lua
local C = Composants
-- Projets
local p = C.NouveauProjet({ name = "…", lines = { { id = 7963, qty = 1 } } }) -- t facultatif ; il devient le projet affiché
C.Projet(id)                 -- le projet d'identité id, nil s'il n'existe plus
C.Projets()                  -- la liste, dans son ordre
C.Renommer(p, "nom")
C.Supprimer(id)              -- le projet supprimé, ou nil
-- Lignes et choix de case : true, ou false et la raison
C.Ajouter(p, itemID, qty)    -- déjà là : sa quantité devient qty
C.Quantite(p, i, qty)        -- la ligne i
C.Retirer(p, i)
C.Choix(p, itemID, choix)    -- "fabriquer" (décomposer), "acheter" (tout fait), nil (le calcul des prix décide)
C.Peut(p, quoi)              -- quoi = "lignes" ou "choix" : true, ou false et la raison
-- Projet tenu : un autre add-on prend les lignes en donnant une raison ; ajouter, retirer, changer une quantité sont
-- refusés avec cette raison, telle quelle ; les choix de case restent libres. Le projet ne sait pas pourquoi il est tenu.
C.Tenir(p, raison, lignes)   -- lignes : les nouvelles (remises à jour à chaque appel, les choix restent), ou nil
-- Une ligne fabrication : sa case racine toujours fabriquée avec cette recette (ni stock, ni achat ; C.Choix(p, son objet,
-- "acheter") refuse) ; sans objet produit (un enchantement), seuls ses composants sont des cases. Dessous : libres.
C.Tenir(p, "Tranche 75 → 90", { { recette = 2659, fois = 5 }, { recette = 7420, fois = 3 } })
C.Tenir(p, nil)              -- lâché
-- L'arbre et les blocs : p = un projet, ou toute table { lines, choix } (la part d'une commande)
local res = C.Arbre(p, sansStock, apports)
-- sansStock = true : toutes les recettes, aucun stock déduit ; sinon les options de la fenêtre (sacs, banque…).
-- apports = { [itemID] = true } facultatif : ces cases (et ce qu'il y a dessous) sortent de l'arbre, n.apport = leur quantité.
-- res = { roots (le plan de chaque ligne), cases, caseDe (["T<i>"] ligne i, ["I<id>"] un objet), liens, total, incomplete,
--   blocs (un par métier : key, step, cases, deliver, qty, inputs, crafters, best), blocDe[métier], livraisons, market }
-- Signal et fenêtre
C.QuandChange(function(p, quoi) end) -- après chaque modification : "nouveau", "lignes", "choix", "nom", "tenu", "supprime"
C.Ouvrir(id)                 -- la fenêtre, sur le projet id (ou celui affiché)
C.Rafraichir()               -- la redessiner (ce qu'elle montre d'un autre add-on a changé)
```

## Développement

Lien symbolique de ce dossier dans `Interface/AddOns/` du jeu, `/reload` suffit. Vérifier, depuis le dossier des add-ons :
`luajit Composants/check.lua` (logique, bouchons de l'API WoW, Composants seul), puis `tools/sim.sh test Composants` et
`tools/sim.sh erreurs` dans l'atelier (`tests/`, jamais dans la TOC ; avec et sans Handshake dans les racines).
