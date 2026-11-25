# Composants (nom provisoire)

Add-on WoW Forever, catégorie Métiers : chaque objet décomposé en ses composants, jusqu'aux matières premières ; l'arbre,
vos projets, ce qu'il reste à réunir. Glossaire : `CONTEXT.md`.

- **Requiert** le socle Azeroth Commune (`## Dependencies: AzerothCommune`) : toutes les données (recettes, sacs, banque,
  autres persos, prix de l'HV et des marchands) sont lues par lui.
- **Seul**, Composants ne montre rien qui concerne un autre joueur (ni contrat, ni artisan d'en face) et ne connaît pas
  Handshake. Il offre l'**emplacement du bloc** (`Composants.Emplacements`, plus bas) : un autre add-on y dessine dans
  chaque bloc de l'arbre et sur la ligne du projet, et un bloc qu'il dit confié se réduit à une seule case ; dans les
  Besoins, il ajoute ses lignes, et Réunir → Fabriquer et Fini attendent qu'il dise ce qu'il a pris en charge arrivé ; il
  peut refuser Lancer (« Lancer (<raison>) ») et dire lui-même quand le projet est Fini. Un
  bloc confié sort des Besoins, sauf ce que le joueur lui donne. Handshake s'y branche quand il est là (« Commander » un
  bloc, la case « Contrat n°12 · artisan · état », son panneau ; « Contrat n°12 · à recevoir » dans les Besoins).
- **Pour le joueur** : `/composants` (ou `/compo`) ouvre la fenêtre ; `/composants <objet> [quantité] [tout]` l'ajoute au
  projet affiché ; `/composants demo [set|ceinture|hasard]` crée un projet d'essai ; Ctrl+clic droit sur un objet
  n'importe où le met au Brouillon (en tête de la colonne des projets ; « Lancer » en fait un projet, clic droit « Vider le
  Brouillon » le vide ; on n'y commande rien). Bouton de minicarte et réglages : ceux, communs, d'Azeroth Commune ; les
  options du calcul (déduire les sacs, la banque, les autres persos ; compter les recettes pas apprises) sont sur la page
  Composants des réglages.
- **La grande vue** : à gauche, la colonne des projets, toujours visible (le Brouillon, puis chaque projet avec sa phase ;
  clic : l'ouvrir dans la vue de sa phase ; clic droit : Renommer, Supprimer) ; à droite, le nom du projet et le fil, la
  ligne d'ajout (recherche et quantité ; un objet déposé sur la recherche entre aussi), l'arbre, et en bas un seul bouton
  d'action qui suit la phase. Pas de légende : la bulle de chaque case dit d'où vient l'objet.
- **Phases** : un projet va de Préparer (l'arbre, les choix de case ; « Lancer ») à Réunir (ses Besoins seuls, dans la
  petite fenêtre qui prend le coin de la grande), puis Fabriquer tout seul quand tout est dans les sacs (la banque et les
  autres persos disent où le trouver) et ce que l'emplacement attend arrivé, puis Fini quand plus rien n'est à fabriquer (gardé ; « Clore » le supprime). Une
  seule vue à la fois ; le fil « Préparer › Réunir › Fabriquer » en haut des deux montre la phase et y va d'un clic. Changer
  une ligne ou un choix de case remet le projet en Préparer.
- **Fabriquer** : l'arbre en lecture seule (ni « + », ni quantités, ni choix de case : « Préparer » dans le fil pour
  changer) ; le bouton d'action nomme la prochaine fabrication du projet affiché (« Barre d'étain ×4 », du bas de l'arbre
  vers le haut), sa case cerclée de lavande. Clic : une fabrication ; clic droit : tout ce que les sacs permettent ;
  « Barre d'étain 2/4… » pendant (grisé, pas de second clic), puis la suivante d'elle-même. Sans la fenêtre du bon métier :
  « Ouvre Minage » (bouton sécurisé : la macro ouvre le métier) ; rien de possible : « Il manque … » ou « Recette
  inconnue : … », grisé, la phrase entière dans la bulle. C'est le seul endroit où l'on fabrique (plus de bouton sous la
  fenêtre de métier). Ses attributs ne changent que hors combat ; en combat il quitte la fenêtre et revient à la sortie.
  Fini : « Tout est fabriqué » s'ajoute à la ligne du projet, et le bouton devient « Clore ».
- **Infobulle des objets** : au survol d'un objet, « Utilisé dans : <projets> » s'il entre dans l'arbre d'un projet (Brouillon
  compris) et « Fabriqué par : <persos> » si l'un de vos persos connaît une recette qui le fabrique ; rien sinon.
- **Données propres** : `ComposantsDB` (projets et leur phase, Brouillon, objets en Récolte, options de calcul). Rien de relevé n'y est gardé (ADR 0002 de l'atelier).

## Fichiers

| Fichier | Rôle |
|---|---|
| `Donnees.lua` | accès au socle (recettes, inventaires, métiers, HV, noms d'objets), `ComposantsDB` |
| `Calcul.lua` | « acheter ou fabriquer » : le plan le moins cher d'un objet, choix entre recettes équivalentes, boucles écartées |
| `Projet.lua` | les projets (identité stable, lignes, choix de case, projet tenu, phases, signal de changement), le Brouillon et Lancer, les cases, les blocs, l'arbre |
| `Fenetre.lua` | la grande vue (Préparer, Fabriquer, Fini) : la colonne des projets, le nom et le fil, la ligne d'ajout, l'arbre (un bloc confié réduit à une case), le bouton d'action (Lancer, Clore) ; la vue de la phase ; les zones de l'emplacement du bloc ; les options du calcul dans les réglages du socle ; Ctrl+clic droit ; `/composants` |
| `Fabriquer.lua` | la prochaine fabrication du projet affiché : le bouton d'action en Fabriquer, sa case cerclée |
| `Infobulle.lua` | les lignes « Utilisé dans » / « Fabriqué par » dans l'infobulle des objets |
| `Besoins.lua` | les Besoins du projet affiché (Réunir) : réuni = dans les sacs (sans la part confiée) ; leur fenêtre, l'emplacement des Besoins, la bascule « Achat » / « Récolte », la liste d'achats d'Auctionator |
| `API.lua` | le global `Composants` |

## API publique

Un seul global, `Composants`, disponible dès le chargement (un add-on qui s'en sert le déclare en `OptionalDeps` ou le
lit plus tard, à l'entrée en jeu). Seul ce qui suit est promis ; l'intérieur peut changer. Un projet `p` est une table
qu'on lit (`p.id` son identité stable, jamais redonnée ; `p.name`, `p.lines`, `p.choix`, `p.tenu`, `p.phase` : nil =
Préparer, `"reunir"`, `"fabriquer"` ou `"fini"`) et qu'on ne modifie que par ces fonctions ; changer ses lignes ou un choix
de case (`Tenir` avec des lignes compris) le remet en Préparer. Une ligne est un objet `{ id = itemID, qty = quantité }` ou une **fabrication**
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
-- L'arbre et les blocs : p = un projet, ou toute table { lines, choix } (une part du projet)
local res = C.Arbre(p, sansStock, apports)
-- sansStock = true : toutes les recettes, aucun stock déduit ; sinon les options du calcul (réglages : sacs, banque…).
-- apports = { [itemID] = true } facultatif : ces cases (et ce qu'il y a dessous) sortent de l'arbre, n.apport = leur quantité.
-- res = { roots (le plan de chaque ligne), cases, caseDe (["T<i>"] ligne i, ["I<id>"] un objet), liens, total, incomplete,
--   valeur (Valeur à l'HV : ses objets au prix le plus bas, nil sans prix), rapporte (nil si coût incomplet),
--   blocs (un par métier : key, step, cases, deliver, qty, inputs, crafters, best), blocDe[métier], livraisons, market }
-- Signal et fenêtre
C.QuandChange(function(p, quoi) end) -- après chaque modification : "nouveau", "lignes", "choix", "nom", "tenu", "phase", "supprime"
C.Ouvrir(id)                 -- la fenêtre, sur le projet id (ou celui affiché), dans la vue de sa phase
C.Rafraichir()               -- la redessiner (ce qu'elle montre d'un autre add-on a changé)
-- L'emplacement du bloc : un autre add-on dessine dans les blocs de la grande vue (jamais sur le Brouillon). Un seul
-- fournisseur ; rend celui d'avant (nil le retire). bloc = un bloc de C.Arbre(p).blocs, ou nil = le projet entier.
local avant = C.Emplacements({
  confie = function(p, bloc) return vrai end,  -- confié : le bloc (nil : tout l'arbre) se réduit à une seule case
  bloc = function(zone, p, bloc, confie) end,  -- dessiner dans zone, un Frame posé par Composants à chaque dessin :
                                               --   confié, la case du bloc (190 × 42) ; sinon une bande haute de 16 sur
                                               --   sa ligne de titre (le projet : la ligne d'en-tête), dont on règle la largeur
  apports = function(p) return { [itemID] = true } end, -- les cases fournies par un autre : elles sortent de l'arbre
  -- L'emplacement des Besoins (facultatif) : un bloc confié sort des Besoins (ses cases et ce qui n'est fabriqué que pour
  -- lui), sauf ce que le joueur lui donne.
  besoins = function(zone, p) return hauteur end, -- ses lignes dans zone (sous celles des Besoins, large d'une ligne)
  clos = function(p) return vrai end,          -- tout ce qu'il a pris en charge est arrivé : Réunir → Fabriquer et Fini l'attendent
  aDonner = function(p) return { [itemID] = true } end, -- ce que le joueur donne à un bloc confié : des lignes des Besoins
  -- Les phases (facultatif)
  lancer = function(p) return raison end,      -- une chaîne : Lancer refusé, « Lancer (<raison>) » grisé, le fil reste en
                                               --   Préparer ; nil : permis
  fini = function(p) return vrai end,          -- nil : la règle de Composants (plus rien à fabriquer, et clos) ; true ou
                                               --   false : lui seul décide, sans l'arbre (true : Réunir ou Fabriquer → Fini)
})
```

## Développement

Lien symbolique de ce dossier dans `Interface/AddOns/` du jeu, `/reload` suffit. Vérifier, depuis le dossier des add-ons :
`luajit Composants/check.lua` (logique, bouchons de l'API WoW, Composants seul), puis `tools/sim.sh test Composants` et
`tools/sim.sh erreurs` dans l'atelier (`tests/`, jamais dans la TOC ; avec et sans Handshake dans les racines).
