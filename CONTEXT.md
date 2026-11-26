# Composants — l'arbre de fabrication (nom provisoire)

Chaque objet décomposé en ses composants, jusqu'aux matières premières : l'arbre, mes projets, ce qu'il reste à réunir. Add-on solo : il sert sans Handshake (ni contrat ni autre joueur) ; quand les deux sont là, Handshake dessine ses contrats dans deux emplacements que Composants lui offre (le bloc dans l'arbre, une ligne des Besoins). Né des grills du 20 et du 21/11/2026 (projets sortis de Handshake) ; circuit en phases au grill du 25/11/2026.

## Language

### Projets

**Projet**:
Une session de fabrication : ce que je fabrique maintenant (des objets × quantités, ou des fabrications), avec son arbre, ses blocs, mes choix de case, sa phase et ses propres Besoins, jamais mélangés à ceux d'un autre projet. Il naît du Brouillon (Lancer), d'une tranche de Maîtrise ou d'une demande reçue dans Handshake (la Réponse). Chaque projet compte le stock comme s'il était seul.
_Avoid_: liste, suivi, session (à l'écrit)

**Phase** (d'un projet):
Où en est le projet : **Préparer** (l'arbre, les choix de case, les contrats ; la grande vue), **Réunir** (ses Besoins seuls ; la petite vue), **Fabriquer** (l'arbre en lecture seule, qui se remplit ; la grande vue), **Fini**. Une seule vue de Composants est visible à la fois, celle de la phase du projet affiché ; la petite prend le coin de la grande. Le fil « Préparer › Réunir › Fabriquer » en haut des deux vues montre la phase et sert à changer à la main (commencer les barres pendant qu'un contrat attend, revenir changer un choix de case). Préparer → Réunir : Lancer. Réunir → Fabriquer : tout seul, quand tout est dans les sacs (la banque et les autres personnages disent où le trouver, ils ne comptent pas comme réuni) et les contrats clos ; jamais de retour en arrière tout seul. Tout changement de lignes (choix de case, recalcul d'une tranche) passe par Préparer. Fini : plus rien à fabriquer et les contrats clos, gardé dès lors (vendre les objets ne rouvre rien) ; « Clore » le supprime, sans archive.
_Avoid_: étape, état, statut

**Lancer**:
Le geste qui fait passer un projet de Préparer à Réunir, le seul bouton d'action de Préparer ; sur le Brouillon, il en fait un vrai projet (nommé d'après sa première ligne) et un Brouillon vide le remplace. Sur une Réponse, il attend que le contrat soit signé.
_Avoid_: valider, démarrer

**Fabrication** (ligne d'un projet):
Une ligne « recette × nombre de fois » au lieu de « objet × quantité » : sa case racine est toujours fabriquée (jamais achetée toute faite), et une recette sans objet produit (un enchantement) n'a pour cases que ses composants ; c'est ainsi qu'une tranche de montée tient son projet.
_Avoid_: craft, ligne forcée

**Transformation**:
Une recette qui change une matière de récolte en matière d'artisanat : les fontes (toutes les barres, bronze et acier compris), les rouleaux d'étoffe, les peaux traitées, et à la Forge les silex et pierres à aiguiser, les cailloux et la boucle en fer (les « Composants » et « Pierres d'arme » du jeu). Certaines demandent un ingrédient en plus (charbon, sel, la barre d'étain du bronze), qui devient un Besoin comme un autre. Les transmutations, avec leur temps de recharge, n'en sont pas. Transformer remplit un projet ordinaire de Fabrications ; ce n'est pas une sorte de projet.
_Avoid_: transfo (à l'écrit), raffinage, conversion

**Transformations** (l'entrée):
Le second projet de passage, unique et toujours là, sous le Brouillon dans la colonne des projets, qui porte ce qu'il rapporte (« Transformations · +3 po 12 ») : en Préparer, une Fabrication par transformation rentable des matières des sacs, avec les recettes que le personnage connaît, recalculée à chaque ouverture (une ligne retirée revient). Rentable : vendre le bout de la chaîne (minerai → barre → bronze) rapporte plus que vendre la matière telle quelle, ingrédients en plus comptés au prix d'achat ; sans prix, rien. Lancer en fait un vrai projet et une entrée vide le remplace, comme le Brouillon.
_Avoid_: projet de transfo, suggestions

**Prochaine fabrication** (d'un projet):
Ce qu'il faut fabriquer maintenant : dans l'ordre de l'arbre, du bas vers le haut (les barres avant l'armure), la première
fabrication que les composants des sacs permettent, faite d'un coup dans la fenêtre de son métier. En phase Fabriquer, elle
est cerclée d'or dans l'arbre et nommée par le seul bouton d'action, en bas (« Silex à aiguiser ×7 ») : clic = une, clic
droit = tout ce que les sacs permettent, puis on passe à la suivante ; sans la fenêtre du bon métier, le bouton le dit
(« Ouvre Forge »). C'est le seul endroit où l'on fabrique (plus de bouton sous la fenêtre de métier ni de panneau de Maîtrise).
Jamais deux recettes sur un clic.
_Avoid_: étape suivante, file de fabrication

**Brouillon**:
Le projet de passage, unique et toujours là, en tête de la colonne des projets, où atterrit tout Ctrl+clic droit sur un objet : la phase Préparer de ma prochaine session. On le vide ou on en retire des lignes ; Lancer en fait un vrai projet. On n'y commande rien, et il n'entre dans aucuns Besoins.
_Avoid_: projet temporaire, scratch

**Projet tenu**:
Un projet dont un autre add-on a pris les lignes (objets et quantités) en donnant une raison ; on ne peut plus les changer, la raison s'affiche telle quelle, et les choix de case restent libres. Le projet ne sait pas pourquoi il est tenu.
_Avoid_: projet verrouillé, projet figé

**Besoins**:
Ce qu'il faut avoir dans les sacs pour fabriquer un projet, la vue de sa phase Réunir (petite, verticale) : une ligne par objet (avancement, Achat ou Récolte, où le trouver : banque, autres personnages), les recettes à apprendre, et avec Handshake une ligne par contrat (à recevoir) ; ses apports sont des Besoins comme les autres. La liste d'achats d'Auctionator suit les Besoins du projet affiché. Un seul projet à la fois : pas de stock partagé entre projets (la réservation des matières est mise de côté).
_Avoid_: liste de courses, shopping

**Récolte**:
Un objet des Besoins que le joueur compte récolter plutôt qu'acheter ; il le décide dans les Besoins, une fois pour tous ses projets, et peut revenir sur ce choix d'un clic ; sans ce choix, l'objet est à acheter. Ce n'est pas un choix de case (qui appartient à un projet).
_Avoid_: farm, choix de récolte

**Valeur à l'HV** (d'un projet):
Ce que valent à l'HV les objets que le projet fabrique, ses objets de premier rang (la racine de chaque ligne), au prix le plus bas de l'HV × leur quantité ; avec un coût complet, ce que ça **rapporte** : la valeur moins la part de l'HV (5 %) et le dépôt, moins le coût. Sans prix pour l'un de ces objets, rien ; avec un coût incomplet, la valeur seule.
_Avoid_: bénéfice, marge, profit

### L'arbre

**Case**:
Un objet dans l'arbre d'un projet, une seule fois même s'il sert à plusieurs endroits : ce qu'il en faut, ce qu'on a en stock, ce qu'on fabrique ou achète (et, dans un contrat Handshake, ce qu'on apporte).
_Avoid_: nœud, node

**Bloc**:
Les cases fabriquées d'un même métier dans un projet, avec qui peut les faire ; avec Handshake, un bloc se commande d'un coup à un artisan : il devient un contrat et se réduit dans l'arbre à une seule case (« Contrat n°12 · artisan · état ») ; un contrat refusé, retiré, échu ou abandonné rend le bloc. Un bloc peut dépendre d'un autre (d'abord les barres, puis l'armure).
_Avoid_: groupe, bande

**Choix de case**:
Ce qu'on décide pour une case de l'arbre : la décomposer ou l'acheter toute faite ; sans choix, le calcul des prix décide. Un choix de case appartient à un projet, jamais à tout le joueur. Apporter une case n'est pas un choix de case : c'est un terme du contrat Handshake (voir Apport dans `../Handshake/CONTEXT.md`).
_Avoid_: force, choix forcé

### Montée

Montée, Route, Tranche : glossaire de Maîtrise (`../Maitrise/CONTEXT.md`).

### Entraide

**Compagnonnage**:
Une équipe de personnages qui s'aident à monter leurs métiers, formée à n'importe quel niveau ; distincte d'une Compagnie (voir `../Compagnie/CONTEXT.md`) : un personnage peut être dans les deux, et un Compagnonnage ne fait pas forcément l'aventure ensemble.
_Avoid_: compagnon (les mascottes du jeu), Compagnie de métiers, corporation, guilde

## Mis de côté

- Le **Compagnonnage** (22/11/2026) : à prix réels de l'HV, des routes de montée optimisées ensemble ne coûtent que 1 à 3 % de moins que les mêmes routes optimisées chacun de son côté ; ce qui coûte cher (barres, cuirs, étoffes) n'est produit par aucun métier d'artisanat du groupe, et l'Enchantement, seul preneur des verts des autres, ne pèse qu'environ 4 % du total. À reprendre si le partage de la récolte (minerai, cuir, étoffe) devient l'enjeu.

- La **réservation** des matières entre projets en cours et l'**archive** des projets finis (25/11/2026) : à reprendre quand plusieurs sessions se disputeront vraiment le même stock.

## Ambiguïtés relevées

- Un projet et une commande Handshake étaient presque la même chose (une commande de projet suivait le projet, on pouvait remélanger). Tranché le 25/11/2026 : deux mots seulement, **Projet** (Composants) et **Contrat** (Handshake) ; « commander » reste un verbe, qui crée un contrat.

- Les Besoins réunissaient plusieurs projets sur un seul stock, Brouillon en dernier. Tranché le 25/11/2026 : chaque projet a ses Besoins, un projet est une session.

- Monter ses métiers ensemble aurait pu être une deuxième sorte de Compagnie. Tranché le 22/11/2026 : c'est un **Compagnonnage**, un concept distinct ; la Compagnie reste l'équipe de l'aventure (un seul à la fois, dès le niveau 1, uniquement des quêtes).

- « Brouillon » désignait aussi, dans Handshake, un contrat préparé mais pas envoyé. Tranché le 20/11/2026 : le mot va au Brouillon des projets ; un tel contrat est **préparé**.
