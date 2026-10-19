#!/usr/bin/env bash
# Vrai cluster Kubernetes local (kind) pour tester ce que le pipeline ne peut que simuler :
# Kyverno qui refuse un pod à l'admission, et les NetworkPolicies qui coupent un flux.
#
#   ./demo/cluster-kind.sh creer     # cluster + Kyverno + politiques + appli (3 à 5 min)
#   ./demo/cluster-kind.sh tester    # les 5 tests, à rejouer autant de fois que voulu
#   ./demo/cluster-kind.sh detruire  # supprime le cluster
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=kalipay
KYVERNO_VERSION=1.19.1
ok()  { printf '  \033[32mOK\033[0m      %s\n' "$*"; }
ko()  { printf '  \033[31mÉCHEC\033[0m   %s\n' "$*"; }
titre() { printf '\n\033[1m%s\033[0m\n' "$*"; }

creer() {
  titre "1. Cluster kind « $CLUSTER »"
  kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --wait 120s

  titre "2. Kyverno $KYVERNO_VERSION"
  kubectl apply --server-side -f "https://github.com/kyverno/kyverno/releases/download/v${KYVERNO_VERSION}/install.yaml" >/dev/null
  kubectl -n kyverno rollout status deployment --timeout=300s

  titre "3. Politiques d'admission (les mêmes que dans le pipeline)"
  # Le webhook de Kyverno met quelques secondes à répondre après le démarrage
  for _ in $(seq 30); do
    kubectl apply -f policies/kyverno/disallow-root.yaml -f policies/kyverno/require-limits.yaml 2>/dev/null && break
    sleep 5
  done
  kubectl wait --for=jsonpath='{.status.conditionStatus.ready}'=true validatingpolicy --all --timeout=120s

  titre "4. Image de l'appli construite localement et chargée dans le cluster"
  docker build -q -t comptes:local . >/dev/null
  kind load docker-image comptes:local --name "$CLUSTER"

  titre "5. Appli « comptes » avec ses NetworkPolicies"
  kubectl create namespace z3-horsprod --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f k8s/namespaces.yaml
  sed 's|image: ghcr.io/kalipay-demo/comptes@sha256:0\{64\}|image: comptes:local\n          imagePullPolicy: Never|' k8s/deployment.yaml | kubectl apply -f -
  kubectl apply -f k8s/service.yaml -f k8s/networkpolicies.yaml -f demo/clients.yaml
  kubectl -n z1-dmz rollout status deployment/comptes --timeout=180s
  kubectl wait --for=condition=Ready pod/backoffice -n z4-backoffice --timeout=120s
  kubectl wait --for=condition=Ready pod/recette -n z3-horsprod --timeout=120s
  titre "Cluster prêt. Lancer : ./demo/cluster-kind.sh tester"
}

tester() {
  local url=http://comptes.z1-dmz.svc.cluster.local:8080/health

  titre "Test 1 — Flux autorisé M12 : back-office (Z4) → comptes"
  if kubectl -n z4-backoffice exec backoffice -- curl -s -m 5 "$url" | grep -q ok; then ok "réponse reçue, le flux de la matrice passe"; else ko "le flux autorisé ne passe pas"; fi

  titre "Test 2 — Flux interdit M22 : recette (Z3) → comptes"
  if kubectl -n z3-horsprod exec recette -- curl -s -m 5 "$url" >/dev/null 2>&1; then ko "la recette joint la production"; else ok "connexion coupée par la NetworkPolicy (délai dépassé)"; fi

  titre "Test 3 — Conteneur root refusé à l'admission"
  if out=$(kubectl run pirate-root --image=comptes:local --image-pull-policy=Never --dry-run=server \
        --overrides='{"spec":{"containers":[{"name":"c","image":"comptes:local","securityContext":{"runAsUser":0,"privileged":true},"resources":{"limits":{"cpu":"100m","memory":"64Mi"}}}]}}' 2>&1); then
    ko "pod root accepté"; else ok "refusé par Kyverno :"; echo "$out" | grep -oE 'Chaque conteneur[^.]*\.|Aucun conteneur[^.]*\.' | sort -u | sed 's/^/          /'; fi

  titre "Test 4 — Pod sans limites de ressources refusé"
  if out=$(kubectl run sans-limites --image=comptes:local --image-pull-policy=Never --dry-run=server \
        --overrides='{"spec":{"securityContext":{"runAsNonRoot":true},"containers":[{"name":"c","image":"comptes:local","securityContext":{"runAsUser":65532,"allowPrivilegeEscalation":false}}]}}' 2>&1); then
    ko "pod sans limites accepté"; else ok "refusé par Kyverno :"; echo "$out" | grep -oE 'Chaque conteneur doit déclarer[^.]*\.' | sort -u | sed 's/^/          /'; fi

  titre "Test 5 — L'appli conforme tourne"
  kubectl -n z1-dmz get pods -l app=comptes -o custom-columns='POD:.metadata.name,ÉTAT:.status.phase,UTILISATEUR:.spec.securityContext.runAsUser'
}

case "${1:-}" in
  creer) creer ;;
  tester) tester ;;
  detruire) kind delete cluster --name "$CLUSTER" ;;
  *) echo "Usage : $0 {creer|tester|detruire}" >&2; exit 1 ;;
esac
