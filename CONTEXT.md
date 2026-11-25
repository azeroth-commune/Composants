# Composants — l'arbre de fabrication (nom provisoire)

Chaque objet décomposé en ses composants, jusqu'aux matières premières : l'arbre, mes projets, ce qu'il reste à réunir. Add-on solo : il sert sans Handshake ; quand les deux sont là, les commandes de Handshake apparaissent dans ses projets. Né des grills du 20 et du 21/11/2026 (projets sortis de Handshake).

## Language

### Projets

**Projet**:
Ce que je veux faire fabriquer (des objets × quantités), avec son arbre, ses blocs et mes choix de case ; une seule page pour le suivre, et ses commandes quand Handshake est là.
_Avoid_: liste, suivi

**Fabrication** (ligne d'un projet):
Une ligne « recette × nombre de fois » au lieu de « objet × quantité » : sa case racine est toujours fabriquée (jamais achetée toute faite), et une recette sans objet produit (un enchantement) n'a pour cases que ses composants ; c'est ainsi qu'une tranche de montée tient son projet.
_Avoid_: craft, ligne forcée

**Brouillon**:
Le projet de passage, unique et toujours là, où atterrit tout Ctrl+clic droit sur un objet ; on le vide ou on en retire des lignes, et « + » en fait un vrai projet. Il n'est pas dans la liste des projets, et on n'y commande rien.
_Avoid_: projet temporaire, scratch

**Projet tenu**:
Un projet dont un autre add-on a pris les lignes (objets et quantités) en donnant une raison ; on ne peut plus les changer, la raison s'affiche telle quelle, et les choix de case restent libres. Le projet ne sait pas pourquoi il est tenu.
_Avoid_: projet verrouillé, projet figé

**Besoins**:
Les objets à réunir pour les projets qu'on y a mis (Brouillon compris, en dernier), toujours à jour de leurs choix de case, avec ce qu'on en a déjà (sacs, banque, autres personnages) ; une petite fenêtre à part pour suivre ce qu'il reste à acheter ou à récolter. C'est le seul endroit où le stock se partage entre projets : il va aux projets dans l'ordre où on les y a mis, alors que la page d'un projet l'estime comme s'il était seul.
_Avoid_: liste de courses, shopping

**Récolte**:
Un objet des Besoins que le joueur compte récolter plutôt qu'acheter ; il le décide dans les Besoins, une fois pour tous ses projets, et peut revenir sur ce choix d'un clic ; sans ce choix, l'objet est à acheter. Ce n'est pas un choix de case (qui appartient à un projet).
_Avoid_: farm, choix de récolte

**Valeur à l'HV** (d'un projet):
Ce que valent à l'HV les objets que le projet fabrique, ses objets de premier rang (la racine de chaque ligne), au prix le plus bas de l'HV × leur quantité ; avec un coût complet, ce que ça **rapporte** : la valeur moins la part de l'HV (5 %) et le dépôt, moins le coût. Sans prix pour l'un de ces objets, rien ; avec un coût incomplet, la valeur seule.
_Avoid_: bénéfice, marge, profit

### L'arbre

**Case**:
Un objet dans l'arbre d'un projet, une seule fois même s'il sert à plusieurs endroits : ce qu'il en faut, ce qu'on a en stock, ce qu'on fabrique ou achète (et, dans une commande Handshake, ce qu'on apporte).
_Avoid_: nœud, node

**Bloc**:
Les cases fabriquées d'un même métier dans un projet, avec qui peut les faire ; avec Handshake, un bloc se commande d'un coup à un artisan. Un bloc peut dépendre d'un autre (d'abord les barres, puis l'armure).
_Avoid_: groupe, bande

**Choix de case**:
Ce qu'on décide pour une case de l'arbre : la décomposer ou l'acheter toute faite ; sans choix, le calcul des prix décide. Un choix de case appartient à un projet, jamais à tout le joueur. Apporter une case n'est pas un choix de case : c'est un terme de la commande Handshake (voir Apport dans `../Handshake/CONTEXT.md`).
_Avoid_: force, choix forcé

### Montée

Montée, Route, Tranche : glossaire de Maîtrise (`../Maitrise/CONTEXT.md`).

### Entraide

**Compagnonnage**:
Une équipe de personnages qui s'aident à monter leurs métiers, formée à n'importe quel niveau ; distincte d'une Compagnie (voir `../Compagnie/CONTEXT.md`) : un personnage peut être dans les deux, et un Compagnonnage ne fait pas forcément l'aventure ensemble.
_Avoid_: compagnon (les mascottes du jeu), Compagnie de métiers, corporation, guilde

## Mis de côté

- Le **Compagnonnage** (22/11/2026) : à prix réels de l'HV, des routes de montée optimisées ensemble ne coûtent que 1 à 3 % de moins que les mêmes routes optimisées chacun de son côté ; ce qui coûte cher (barres, cuirs, étoffes) n'est produit par aucun métier d'artisanat du groupe, et l'Enchantement, seul preneur des verts des autres, ne pèse qu'environ 4 % du total. À reprendre si le partage de la récolte (minerai, cuir, étoffe) devient l'enjeu.

## Ambiguïtés relevées

- Monter ses métiers ensemble aurait pu être une deuxième sorte de Compagnie. Tranché le 22/11/2026 : c'est un **Compagnonnage**, un concept distinct ; la Compagnie reste l'équipe de l'aventure (un seul à la fois, dès le niveau 1, uniquement des quêtes).

- « Brouillon » désignait aussi, dans Handshake, un contrat préparé mais pas envoyé. Tranché le 20/11/2026 : le mot va au Brouillon des projets ; un tel contrat est **préparé**.
