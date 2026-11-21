# Composants — l'arbre de fabrication (nom provisoire)

Chaque objet décomposé en ses composants, jusqu'aux matières premières : l'arbre, mes projets, ce qu'il reste à réunir. Add-on solo : il ne sait rien des commandes ni des contrats ; Handshake s'y greffe quand les deux sont là. Né des grills du 20 et du 21/11/2026 (projets sortis de Handshake).

## Language

### Projets

**Projet**:
Ce que je veux faire fabriquer (des objets × quantités), avec son arbre, ses blocs et mes choix de case ; une seule page pour le suivre, et ses commandes quand Handshake est là.
_Avoid_: liste, suivi

**Brouillon**:
Le projet de passage, unique et toujours là, où atterrit tout Ctrl+clic droit sur un objet ; on le vide ou on en retire des lignes, et « + » en fait un vrai projet. Il n'est pas dans la liste des projets, et on n'y commande rien.
_Avoid_: projet temporaire, scratch

**Projet tenu**:
Un projet dont un autre add-on a pris les lignes (objets et quantités) en donnant une raison ; on ne peut plus les changer, la raison s'affiche telle quelle, et les choix de case restent libres. Le projet ne sait pas pourquoi il est tenu.
_Avoid_: projet verrouillé, projet figé

**Besoins**:
Les objets à réunir pour les projets qu'on y a mis (Brouillon compris, en dernier), toujours à jour de leurs choix de case, avec ce qu'on en a déjà (sacs, banque, autres personnages) ; une petite fenêtre à part pour suivre ce qu'il reste à acheter ou à récolter. C'est le seul endroit où le stock se partage entre projets : il va aux projets dans l'ordre où on les y a mis, alors que la page d'un projet l'estime comme s'il était seul.
_Avoid_: liste de courses, shopping

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

## Ambiguïtés relevées

- « Brouillon » désignait aussi, dans Handshake, un contrat préparé mais pas envoyé. Tranché le 20/11/2026 : le mot va au Brouillon des projets ; un tel contrat est **préparé**.
