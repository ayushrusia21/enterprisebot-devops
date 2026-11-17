#!/usr/bin/env bash
# One-command, idempotent setup: kind cluster + ingress-nginx + image + helm release.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=demo
NS=demo
RELEASE=demo
IMAGE=demo-service
TAG=1.0.0
INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml"

for bin in docker kind kubectl helm; do
  command -v "$bin" >/dev/null || { echo "missing required tool: $bin" >&2; exit 1; }
done

echo "==> kind cluster '$CLUSTER'"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "cluster exists, reusing"
else
  kind create cluster --name "$CLUSTER" --config kind-config.yaml --wait 120s
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

echo "==> ingress-nginx"
# Only apply on first run: its admission Jobs are immutable, so re-applying fails.
if ! kubectl -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
  kubectl apply -f "$INGRESS_MANIFEST"
fi
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s
kubectl -n ingress-nginx wait --for=condition=complete job/ingress-nginx-admission-create --timeout=120s || true
kubectl -n ingress-nginx wait --for=condition=complete job/ingress-nginx-admission-patch --timeout=120s || true

echo "==> build and load image $IMAGE:$TAG"
docker build -t "$IMAGE:$TAG" service/
kind load docker-image "$IMAGE:$TAG" --name "$CLUSTER"

echo "==> helm release '$RELEASE' in namespace '$NS'"
helm upgrade --install "$RELEASE" chart/ \
  --namespace "$NS" --create-namespace \
  --set image.repository="$IMAGE" --set image.tag="$TAG" \
  --wait --timeout 180s

echo "==> waiting for ingress route"
for i in $(seq 1 30); do
  if curl -fs -o /dev/null -H 'Host: demo.local' http://localhost/healthz; then
    echo "route is live"; break
  fi
  sleep 2
done

echo
echo "Done. Verify with:"
echo "  curl -s -H 'Host: demo.local' http://localhost/"
echo "  curl -si -H 'Host: demo.local' http://localhost/healthz"
