#!/usr/bin/env bash
# llm-local.sh — LLM local bridé pour Omarchy (Arch Linux). Relançable sans risque.
# Usage : bash llm-local.sh          (ou MODEL=qwen3:4b bash llm-local.sh)
set -euo pipefail
command -v pacman >/dev/null || { echo "Ce script est pour Arch/Omarchy (pacman absent)."; exit 1; }

# 1. Carte graphique -> bon paquet (les 3 sont dans le dépôt officiel "extra")
case "$(lspci 2>/dev/null | grep -iE 'vga|3d controller|display' || true)" in
  *NVIDIA*)                pkg=ollama-cuda ;;
  *AMD*|*ATI*|*Radeon*)    pkg=ollama-rocm ;;
  *)                       pkg=ollama ;;
esac

# 2. RAM -> taille de modèle (poids réels du registre Ollama)
ram=$(free -g | awk '/^Mem:/{print $2}')
if   [ "$ram" -ge 24 ]; then m=qwen2.5-coder:7b    # 4,7 Go
elif [ "$ram" -ge 12 ]; then m=qwen2.5-coder:3b    # 1,9 Go
else                         m=qwen2.5-coder:1.5b  # 1,0 Go
fi
model=${MODEL:-$m}
echo "→ RAM ${ram} Go · paquet $pkg · modèle $model"

# 3. Installation
sudo pacman -S --needed --noconfirm "$pkg"

# 4. Bridage : laisse toujours 1 cœur libre, priorité basse, 1 seul modèle en RAM
cores=$(nproc); quota=$(( (cores > 1 ? cores - 1 : 1) * 100 ))
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/bridage.conf >/dev/null <<EOF
[Service]
CPUQuota=${quota}%
Nice=10
IOSchedulingClass=idle
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_KEEP_ALIVE=2m"
Environment="OLLAMA_CONTEXT_LENGTH=8192"
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now ollama
sleep 2

# 5. Téléchargement du modèle + commande "ask"
ollama pull "$model"
sudo tee /usr/local/bin/ask >/dev/null <<EOF
#!/usr/bin/env bash
# ask "ta question"   |   cat fichier.txt | ask "résume en 5 points"
p="\$*"
# ajoute l'entrée seulement si un pipe ou un fichier est fourni (jamais de blocage)
if [ -p /dev/stdin ] || [ -f /dev/stdin ]; then p="\$p
\$(cat)"; fi
exec ollama run $model "\$p"
EOF
sudo chmod +x /usr/local/bin/ask

# 6. Vérification réelle
s=$SECONDS
r=$(ask "Réponds uniquement par le mot: OK" | tr -d '\n')
echo "✓ Réponse « $r » en $((SECONDS - s)) s · RAM du service : $(systemctl show -p MemoryCurrent --value ollama | awk '{printf "%d Mo", $1/1048576}')"
echo "✓ Prêt. Tapez :  ask \"ta question\""

# 7. Apprend à Claude Code à déléguer les tâches de masse au modèle local
mkdir -p ~/.claude/skills/llm-local
cat > ~/.claude/skills/llm-local/SKILL.md <<'EOS'
---
name: llm-local
description: Déléguer au LLM local (commande `ask`) les tâches volumineuses et peu complexes pour économiser des tokens — résumer un fichier, un log ou une longue sortie de commande, traduire, reformuler, rédiger un message de commit, trier une longue liste. À utiliser dès qu'une sortie volumineuse doit être condensée avant d'entrer dans le contexte.
---
Un modèle local tourne sur cette machine (Ollama, service bridé) : gratuit, illimité, aucune donnée ne sort.

Utilisation : `ask "consigne"` ou `commande | ask "consigne"`.

À déléguer : résumés, extractions, traductions, reformulations, messages de commit, tri de longues listes.
À NE PAS déléguer : architecture, débogage, écriture de code de production, décisions — ce modèle est petit et se trompe.
Toujours relire une sortie du modèle local avant de s'en servir pour modifier du code.
EOS
echo "✓ Claude Code délèguera les tâches de masse au modèle local"
