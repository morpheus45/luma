#!/usr/bin/env bash
# omniroute-local.sh — branche le modèle local dans OmniRoute : diagnostic, configuration, test réel.
# Usage : OMNIROUTE_KEY=votre_cle bash omniroute-local.sh
set -uo pipefail
OR=${OMNIROUTE_URL:-http://localhost:20128}; K=${OMNIROUTE_KEY:-}
export no_proxy=localhost,127.0.0.1 NO_PROXY=localhost,127.0.0.1  # jamais de proxy en local
T=$(mktemp); trap 'rm -f "$T"' EXIT
ok(){ echo "✓ $1"; }; ko(){ echo "✗ $1"; }

# 1. Le modèle local parle-t-il bien le protocole OpenAI ?
m=${MODEL:-$(curl -sf --max-time 5 http://localhost:11434/v1/models | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)}
[ -n "$m" ] || { ko "Ollama muet sur le port 11434 — lancez d'abord llm-local-omarchy.sh"; exit 1; }
ok "modèle local détecté : $m"

# 2. OmniRoute répond-il ?
[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$OR")" = 000 ] \
  && { ko "OmniRoute injoignable sur $OR — lancez : omniroute"; exit 1; }
ok "OmniRoute joignable sur $OR"

# 3. Dans Docker, « localhost » ne désigne pas votre machine
base=http://localhost:11434/v1
if docker ps --format '{{.Image}}{{.Names}}' 2>/dev/null | grep -qi omniroute; then
  base=http://host.docker.internal:11434/v1
  ko "OmniRoute tourne dans Docker → Base URL à saisir : $base"
  ko "  (conteneur à relancer avec --add-host=host.docker.internal:host-gateway)"
fi

# 4. Le provider intégré existe-t-il dans votre version ?
p=$(omniroute providers list 2>/dev/null | grep -io 'ollama[a-z-]*' | head -1)
if [ -n "$p" ]; then ok "provider intégré présent : $p"
else p=ollama-local; ko "provider ollama introuvable ici → voir les étapes manuelles en fin de script"; fi

# 5. Déclaration du modèle + combo « local-cheap » (API officielle, scope manage)
if [ -n "$K" ]; then
  post(){ c=$(curl -s -o "$T" -w '%{http_code}' --max-time 15 -X POST "$OR$1" \
    -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d "$2")
    case $c in 20*) ok "$1 → HTTP $c";; *) ko "$1 → HTTP $c : $(head -c 160 "$T")";; esac; }
  post /api/provider-models "{\"provider\":\"$p\",\"modelId\":\"$m\",\"modelName\":\"$m\"}"
  post /api/combos "{\"name\":\"local-cheap\",\"strategy\":\"priority\",\"models\":[{\"model\":\"$p/$m\"}]}"
else
  ko "OMNIROUTE_KEY absent → étape API ignorée (créez une clé : omniroute keys add)"
fi

# 6. Test de bout en bout : une vraie requête traversant OmniRoute
echo "— test réel via OmniRoute —"
for id in "$p/$m" "ollama/$m" "ollamalocal/$m" "$m"; do
  r=$(curl -s --max-time 90 "$OR/v1/chat/completions" -H "Authorization: Bearer ${K:-x}" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$id\",\"messages\":[{\"role\":\"user\",\"content\":\"Réponds uniquement: OK\"}]}")
  if echo "$r" | grep -q '"content"'; then
    ok "OmniRoute → modèle local fonctionnel. Identifiant à utiliser : $id"; exit 0
  fi
done
ko "aucune route n'a abouti. Dernière réponse : $(echo "$r" | head -c 200)"
cat <<EOS

À faire une fois dans le tableau de bord ($OR/dashboard/providers) :
 1. Providers → chercher « ollama » → l'activer, Base URL = $base (pas de clé API)
 2. S'il n'y figure pas : Providers → Add OpenAI Compatible
    Prefix = ollamalocal · API Type = Chat Completions · Base URL = $base
 3. Available Models → ajouter le modèle : $m
 4. Combos → Create New → nom « local-cheap » → stratégie Priority → modèle local en premier
EOS
exit 1
