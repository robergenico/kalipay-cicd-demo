#!/usr/bin/env bash
# Introduit volontairement une faille pour montrer quel contrôle du pipeline la bloque.
#
#   ./demo/casser.sh <scenario>
#
# Puis : git checkout -b demo/<scenario> && git commit -am "demo" && git push, et ouvrir une PR.
# Pour revenir à l'état sain : git checkout -- . && git clean -fd app k8s infra
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  secret)
    # La clé est assemblée ici pour que ce script ne contienne pas lui-même de secret.
    prefixe="kp_""live_"
    cle="$(python3 -c 'import secrets, string; print("".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))')"
    printf 'PARTNER_API_KEY = "%s%s"\n' "$prefixe" "$cle" > app/config.py
    echo "→ Clé d'API partenaire en dur dans app/config.py. Attendu : échec du job « Secrets (gitleaks) »."
    ;;
  pan)
    cat >> app/main.py <<'PY'


@app.get("/api/debug/carte/<card_number>")
def debug_carte(card_number: str):
    return jsonify(card_number=card_number)
PY
    echo "→ Un numéro de carte manipulé hors du périmètre carte. Attendu : échec du job « Code (Semgrep) »."
    ;;
  cve)
    echo "pyyaml==5.3.1" >> app/requirements.txt
    echo "→ Dépendance avec une CVE critique (CVE-2020-14343). Attendu : échec du job « Dépendances (Trivy) »."
    ;;
  iac)
    cat > infra/terraform/ouverture_temporaire.tf <<'TF'
# « Ouverture temporaire » pendant un incident : le cas typique du risque R1
resource "aws_security_group" "debug" {
  name        = "debug-temporaire"
  description = "Ouverture temporaire pendant incident"
  ingress {
    description = "SSH depuis partout"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
TF
    echo "→ SSH ouvert à Internet. Attendu : échec du job « Infra en code (Checkov) »."
    ;;
  flux)
    cat >> k8s/networkpolicies.yaml <<'K8S'
---
# Un développeur ouvre l'accès depuis la recette pour « tester plus vite »
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: comptes-depuis-recette
  namespace: z1-dmz
  annotations:
    kalipay.fr/flux: M1
spec:
  podSelector:
    matchLabels:
      app: comptes
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: z3-horsprod
      ports:
        - protocol: TCP
          port: 8080
K8S
    echo "→ Flux Z3 → production, interdit par M22. Attendu : échec du job « Matrice de flux (Conftest) »."
    ;;
  root)
    sed -i 's/runAsUser: 65532/runAsUser: 0/; s/runAsNonRoot: true/runAsNonRoot: false/; s/allowPrivilegeEscalation: false/allowPrivilegeEscalation: true/' k8s/deployment.yaml
    echo "→ Conteneur root avec élévation de droits. Attendu : échec des jobs « Admission (Kyverno) » et « Infra en code (Checkov) »."
    ;;
  *)
    echo "Usage : $0 {secret|pan|cve|iac|flux|root}" >&2
    exit 1
    ;;
esac
