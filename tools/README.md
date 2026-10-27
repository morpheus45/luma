# LLM local pour Omarchy

Deux scripts pour faire tourner un modèle de langage sur votre machine, sans saturer
l'ordinateur, et le brancher dans OmniRoute. Ils ne concernent pas l'application Luma.

## Ordre d'exécution

```bash
bash tools/llm-local-omarchy.sh                         # 1. installe le modèle local
OMNIROUTE_KEY=votre_cle bash tools/omniroute-local.sh   # 2. le branche dans OmniRoute
```

La clé OmniRoute se crée avec `omniroute keys add` (scope `manage`).

## 1. llm-local-omarchy.sh

Détecte la carte graphique (`ollama-cuda` / `ollama-rocm` / `ollama`) et la mémoire,
installe le modèle à la bonne taille, bride le service systemd (un cœur toujours libre,
priorité basse, un seul modèle en mémoire, déchargé après 2 min), crée la commande `ask`
et apprend à Claude Code à déléguer les tâches de masse au modèle local.

Pour forcer un modèle : `MODEL=qwen3:4b bash tools/llm-local-omarchy.sh`

## 2. omniroute-local.sh

Vérifie Ollama et OmniRoute, détecte une installation Docker, configure le provider
`ollama-local`, crée un combo `local-cheap`, puis teste une vraie requête de bout en bout.
Si une étape échoue, il affiche les manipulations à faire dans le tableau de bord et
sort en erreur.

Variables : `OMNIROUTE_KEY`, `OMNIROUTE_URL` (défaut `http://localhost:20128`), `MODEL`.

## Important

Le combo `local-cheap` est **séparé** de votre combo de codage, volontairement : un petit
modèle ne renvoie pas d'erreur sur une question difficile, il répond mal. Le local prend
les résumés, traductions, logs et messages de commit ; les modèles puissants gardent le code.
