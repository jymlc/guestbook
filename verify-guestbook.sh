#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C.UTF-8
root="$(pwd)"
evidence="$root/evidence"
mkdir -p "$evidence"
cd v1/guestbook

# The runner uses a local registry and an isolated kind cluster.
docker run -d --name guestbook-registry -p 5000:5000 registry:2
for attempt in {1..30}; do
  if curl -fsS http://127.0.0.1:5000/v2/ >/dev/null; then break; fi
  sleep 1
done
docker build -t guestbook:v1 .
docker tag guestbook:v1 localhost:5000/guestbook:v1
docker push localhost:5000/guestbook:v1
{
  printf 'Local Docker registry on GitHub Actions\n'
  printf '$ curl -fsS http://127.0.0.1:5000/v2/guestbook/tags/list\n'
  curl -fsS http://127.0.0.1:5000/v2/guestbook/tags/list
  printf '\n'
} | tee "$evidence/02-local-registry.txt"
kind load docker-image --name guestbook guestbook:v1

cp Dockerfile "$evidence/01-dockerfile.txt"
grep -E '<title>|<h1>' public/index.html > "$evidence/03-index-v1.txt"

{
  echo '$ kubectl apply -f hpa.yml'
  kubectl apply -f hpa.yml
  echo '$ kubectl get hpa guestbook'
  kubectl get hpa guestbook
} | tee "$evidence/04-hpa-created.txt"
awk '$1=="guestbook" && $6==0 { found=1 } END { exit !found }' "$evidence/04-hpa-created.txt"

kubectl apply -f deployment.yml
kubectl rollout status deployment/guestbook --timeout=180s
kubectl port-forward service/guestbook 13000:3000 > "$root/port-forward.log" 2>&1 &
forward=$!
trap 'kill "$forward" 2>/dev/null || true' EXIT
for attempt in {1..30}; do
  if curl -fsS http://127.0.0.1:13000/ | grep -Fq '<h1>Guestbook - v1</h1>'; then break; fi
  sleep 1
done
curl -fsS http://127.0.0.1:13000/ | grep -F '<h1>Guestbook - v1</h1>'
curl -fsS http://127.0.0.1:13000/rpush/guestbook/Hello | grep -F 'Hello'

kubectl run guestbook-load --image=busybox:1.37 --restart=Never --command -- sh -c \
  'for i in $(seq 1 12); do (while :; do wget -qO /dev/null http://guestbook:3000/hello; done) & done; wait'
kubectl wait --for=condition=Ready pod/guestbook-load --timeout=150s
scaled=false
for attempt in {1..42}; do
  replicas=$(kubectl get hpa guestbook -o jsonpath='{.status.currentReplicas}')
  ready=$(kubectl get deployment guestbook -o jsonpath='{.status.readyReplicas}')
  if [[ ${replicas:-0} -gt 1 && ${ready:-0} -gt 1 ]]; then scaled=true; break; fi
  sleep 5
done
{
  echo '$ kubectl get hpa guestbook'
  kubectl get hpa guestbook
  echo '$ kubectl get deployment guestbook'
  kubectl get deployment guestbook
} | tee "$evidence/05-hpa-scaled.txt"
[[ "$scaled" == true ]]
kubectl delete pod guestbook-load --wait=false
kubectl delete hpa guestbook

cp release-v2/index.html public/index.html
cp release-v2/deployment.yml deployment.yml
docker build -t guestbook:v2 .
docker tag guestbook:v2 localhost:5000/guestbook:v2
{
  echo '$ docker push localhost:5000/guestbook:v2'
  docker push localhost:5000/guestbook:v2
} | tee "$evidence/06-docker-push-v2.txt"
grep -Eq 'v2: digest: sha256:[[:xdigit:]]{64}' "$evidence/06-docker-push-v2.txt"
kind load docker-image --name guestbook guestbook:v2
{
  echo '$ kubectl apply -f deployment.yml'
  kubectl apply -f deployment.yml
  echo '$ kubectl rollout status deployment/guestbook'
  kubectl rollout status deployment/guestbook --timeout=180s
} | tee "$evidence/07-apply-v2.txt"

# A port-forward to a replaced pod must be re-established after rollout.
kill "$forward" 2>/dev/null || true
kubectl port-forward service/guestbook 13001:3000 > "$root/port-forward-v2.log" 2>&1 &
forward=$!
for attempt in {1..30}; do
  if curl -fsS http://127.0.0.1:13001/ | grep -Fq '<h1>Guestbook – v2</h1>'; then break; fi
  sleep 1
done
curl -fsS http://127.0.0.1:13001/ | grep -E '<title>|<h1>' > "$evidence/08-index-v2.txt"
grep -Fq '<h1>Guestbook – v2</h1>' "$evidence/08-index-v2.txt"
{
  echo '$ kubectl rollout history deployment/guestbook'
  kubectl rollout history deployment/guestbook
  echo '$ kubectl rollout history deployment/guestbook --revision=1'
  kubectl rollout history deployment/guestbook --revision=1
  echo '$ kubectl rollout history deployment/guestbook --revision=2'
  kubectl rollout history deployment/guestbook --revision=2
} | tee "$evidence/09-rollout-history.txt"
{
  echo '$ kubectl rollout undo deployment/guestbook --to-revision=1'
  kubectl rollout undo deployment/guestbook --to-revision=1
  kubectl rollout status deployment/guestbook --timeout=180s
  echo '$ kubectl get rs'
  kubectl get rs
} | tee "$evidence/10-replicasets-after-rollback.txt"
test "$(kubectl get deployment guestbook -o jsonpath='{.spec.template.spec.containers[0].image}')" = guestbook:v1
for file in "$evidence"/*.txt; do
  {
    printf '## %s\n\n' "$(basename "$file")"
    printf '\x60\x60\x60text\n'
    cat "$file"
    printf '\n\x60\x60\x60\n\n'
  } >> "$GITHUB_STEP_SUMMARY"
done
