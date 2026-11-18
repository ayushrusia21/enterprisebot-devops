# Findings: Part 4 debug lab

Seven chart problems fixed (the brief says six, so one of mine may be a side effect of another or of my environment). One failure remains, the reporter, and I could not resolve it. Details at the end.

## Defect 1: Job restartPolicy invalid
**Symptom:**

    Error: Job.batch "migrate" is invalid: spec.template.spec.restartPolicy: Required value: valid values: "OnFailure", "Never"

**Cause:** `restartPolicy: Always` in migrate-job.yaml. Jobs only allow OnFailure or Never, so Helm install failed before the Job was created.
**Fix:** changed to OnFailure (the Job should retry on failure, bounded by backoffLimit).
**How I found it:** read the Helm error from `./scenario.sh up`, then grepped the template.

## Defect 2: runAsNonRoot with a non-numeric image user
**Symptom:** every pod stuck in CreateContainerConfigError. `kubectl describe pod` showed:

    Error: container has runAsNonRoot and image has non-numeric user (nonroot), cannot verify user is non-root

**Cause:** the image user is the name "nonroot", and Kubernetes cannot verify a name is non-root.
**Fix:** added `runAsUser: 65532` next to `runAsNonRoot: true` in all workload templates, keeping the hardening. I also deleted the old migrate Job once, because a Job's pod template is immutable (upgrade failed with "field is immutable").
**How I found it:** `get all` showed one shared status on every pod, so I described one pod and read the Events.

## Defect 3: worker needs a writable cache directory
**Symptom:** worker in CrashLoopBackOff. `kubectl logs deploy/worker`:

    FATAL: worker could not initialise its cache: mkdir /var/cache/app: read-only file system

**Cause:** readOnlyRootFilesystem is true and there is no writable path for /var/cache/app.
**Fix:** mounted an emptyDir at /var/cache/app. This keeps the read-only root filesystem instead of disabling it.
**How I found it:** logs of the crash-looping pod.

## Defect 4: app listens on 8081, chart assumes 8080
**Symptom:** pods Running but not Ready. Probe event:

    Readiness probe failed: Get "http://10.244.0.17:8080/healthz": dial tcp 10.244.0.17:8080: connect: connection refused

Log line: `listening on :8081 (image default is 8081; set PORT to override)`
**Cause:** the image defaults to 8081, but probes, Services and common.port use 8080.
**Fix:** set env PORT from .Values.common.port in every Deployment.
**How I found it:** describe showed connection refused, logs showed the real listen port.

## Defect 5: RoleBinding bound to the wrong ServiceAccount
**Symptom:** verify printed "FAIL ServiceAccount debug-lab/reporter cannot list pods". Reporter log:

    pods is forbidden: User "system:serviceaccount:debug-lab:reporter" cannot list resource "pods" in API group "" in the namespace "debug-lab"

**Cause:** the RoleBinding subject was `default`, not `reporter`.
**Fix:** subject name changed to reporter in rbac.yaml. Verify then passed this check.
**How I found it:** reporter logs, then `kubectl get rolebinding reporter-read -o yaml`.

## Defect 6: gateway BACKEND_URL points at the wrong namespace
**Symptom:** gateway not Ready. Log:

    readiness failed: backend not reachable: GET http://backend.default.svc:8080/healthz: ... no such host

**Cause:** BACKEND_URL used backend.default.svc, but the backend is in debug-lab.
**Fix:** changed it to http://backend.debug-lab.svc:8080 in values.yaml. Gateway /status then returned "backend":"ok".
**How I found it:** gateway logs.

## Defect 7: metrics CPU above the LimitRange maximum
**Symptom:** metrics had no pod. ReplicaSet events:

    Error creating: pods "metrics-5fbdd57d89-wkr2p" is forbidden: maximum cpu usage per Container is 1, but limit is 4

**Cause:** metrics asked for requests 2 and limits 4 CPU, but the namespace LimitRange caps a container at 1.
**Fix:** set requests 50m and limits 200m, matching the other workloads.
**How I found it:** the Deployment showed FailedCreate, and `describe rs` showed the admission message.

## Not resolved: reporter /report returns "unexpected end of JSON input"
**Symptom:** reporter never becomes Ready. Log:

    pod list failed: parse pod list: unexpected end of JSON input

**What I ruled out:** RBAC is correct (`kubectl auth can-i` passes, and the API returned HTTP 200 with a full body of about 109 KB for the reporter ServiceAccount). A reporter pod in a fresh namespace with one pod fails the same way, so it is not pod count or this chart's wiring.
**Environment caveat:** my Mac and the kind node are arm64 and the image is amd64 only (`crictl inspecti` shows amd64, and the process list showed /usr/bin/qemu-x86_64). The failure may be an emulation artifact, but I did not prove that.
**Also noted:** on my machine `./scenario.sh verify` lost the first lines of its probe pod output, so it reported backend and gateway as failing while manual probes with the same wget commands passed.
**Dead end:** an ephemeral debug container could not read the app process (Permission denied).
**Next I would try:** run the lab on a native amd64 machine, and check whether the reporter reads the API response with a size limit.
