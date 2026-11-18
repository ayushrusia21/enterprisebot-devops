# EB DevOps take-home

## Run and verify
Needs Docker, kind, kubectl, helm. Port 80 on the host must be free.

    ./setup.sh        # safe to run twice
    curl -s -H 'Host: demo.local' http://localhost/
    curl -si -H 'Host: demo.local' http://localhost/healthz
    kubectl -n demo get pods,svc,ingress

Expected: `GET /` returns `{"app": ..., "version": ..., "pod": ...}` and `/healthz` returns HTTP 200.

Change the identity at runtime (picked up from the mounted ConfigMap within about a minute, no restart):

    kubectl -n demo patch cm demo --type merge -p '{"data":{"APP_NAME":"changed","VERSION":"2.0.0"}}'

Part 4: `cd lab && ./scenario.sh up && ./scenario.sh verify`. See `lab/FINDINGS.md`.

## Resources and why
Requests 50m CPU / 64Mi, limits 200m CPU / 128Mi per pod. The service is stdlib Python and idles at roughly 20-30Mi, so 64Mi requested leaves headroom and a 128Mi limit gives about 4x slack before an OOM kill. CPU use is small and bursty, so a low request keeps scheduling cheap and the 200m limit stops a runaway loop. These are starting points. I did not load test them.

## Design notes
- The ConfigMap is injected as env (`envFrom`) and also mounted as files. The app prefers the file, so ConfigMap edits show in `GET /` without a pod restart. Env is the fallback. A checksum annotation rolls pods on `helm upgrade`.
- `setup.sh` applies ingress-nginx only on the first run, because its admission Jobs are immutable and a re-apply would fail. It also waits until the ingress route answers before finishing.
- Pods run non-root (uid 10001) with a read-only root filesystem and all capabilities dropped.

## Part 4 status
Seven chart problems fixed, one failure left (reporter). Full details, including what I could not resolve and why, are in `lab/FINDINGS.md`. My Mac and the kind node are arm64 and the lab image is amd64 only, which may be related. I did not prove that.

## Deliberately skipped (and the risk)
- No HPA, PodDisruptionBudget or anti-affinity: a node drain can take both replicas down at once.
- No NetworkPolicy: any pod in the cluster can reach the service.
- No TLS on the ingress: traffic is plain HTTP, fine locally only.
- No automated tests: regressions would only be caught by manual curl.
- Image tag fixed at 1.0.0 with IfNotPresent: rebuilding without a tag bump will not roll pods.

## Production-ready changes
Immutable image tags (digest or git SHA) pushed to a registry, TLS via cert-manager, HPA and PDB, NetworkPolicy, topology spread, structured logging and metrics, a real secrets flow, resource tuning from load tests, and Gateway API instead of ingress-nginx (see ANSWERS.md).

## How I used AI
I used Claude for most of this: drafting the service, Dockerfile, Helm chart, setup.sh, ANSWERS.md and this README, and suggesting diagnostic commands for Part 4. I ran everything myself on my own kind cluster and pasted the real output back.

Things that had to be corrected or were wrong along the way:
- The first setup.sh returned a 503 right after install, so a wait loop for the ingress route was added.
- For Part 4, some early fix suggestions were guesses from reading the YAML. I only kept fixes that the cluster output confirmed.
- A theory that the reporter failure was caused by the pod count was wrong: a clean namespace with one pod failed the same way.
- The reporter issue is still unresolved, and I say so in FINDINGS.md instead of guessing.

I can explain each file in this repo and each Part 4 fix.
