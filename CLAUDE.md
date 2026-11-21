# Composants (nom provisoire)

Add-on solo d'artisanat : l'arbre de fabrication, les projets, le Brouillon et les Besoins. Ne requiert pas Handshake (ni l'inverse) ; peut contenir le code qui s'y branche quand Handshake est chargé. Repo `azeroth-commune/Composants` (privé pour l'instant). Espace de travail parent : `../` (outils, recherche, captures — pas dans ce repo).
Déploiement : lien symbolique depuis le dossier AddOns du jeu, `/reload` suffit. Requiert le socle Azeroth Commune (ADR 0002).
Vérifier : `luajit Composants/check.lua` depuis le dossier des add-ons, puis `tools/sim.sh test Composants` dans l'atelier (`tests/`, jamais dans la TOC).

## Agent skills

### Issue tracker

GitHub Issues de `azeroth-commune/Composants`, toujours avec `-R azeroth-commune/Composants` ; PR externes : non. See `docs/agents/issue-tracker.md`.

### Triage labels

Labels par défaut (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix) + `prd`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : `CONTEXT.md` + `docs/adr/` à la racine, créés au besoin. See `docs/agents/domain.md`.
