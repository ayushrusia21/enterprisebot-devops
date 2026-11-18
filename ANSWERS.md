# Q1: Migrating ~40 Ingresses from ingress-nginx to Gateway API

**Approach: run both side by side, shift traffic gradually, remove the old path last.**

1. **Inventory first.** Export all 40 Ingresses and list every annotation in use (rewrites, auth, timeouts, body size, snippets, canary). Annotations are where the risk is, because many have no Gateway API equivalent.
2. **Pick a conformant implementation** (Envoy Gateway, Cilium, Traefik, NGINX Gateway Fabric). Install it next to ingress-nginx with its own LoadBalancer IP. Nothing changes for users yet.
3. **Translate in batches.** Start with low-risk internal services. Use ingress2gateway for a first draft, then review by hand. Create Gateway, HTTPRoute and policy objects.
4. **Test on the new IP** before any DNS change: send the same requests to both and compare status codes, headers and redirects.
5. **Shift traffic with low-TTL DNS** (or weighted DNS): 1%, 10%, 50%, 100% per batch, watching error rate and latency. Rollback is a DNS change.
6. **Decommission** ingress-nginx only after a quiet period. Keep the old Ingress objects in git until then.

**What I expect to break**
- Snippet and regex annotations, custom auth, and rewrite behaviour differences.
- Default timeouts, body size limits and header handling differing between controllers.
- TLS: cert-manager needs Gateway listener support, and secrets must be reachable across namespaces (ReferenceGrant).
- Source IP preservation, websockets and gRPC behaviour.
- Monitoring and alerts built on nginx metrics.
- Team habits: RBAC now splits Gateway (platform team) from routes (app teams).

**Risk call:** the biggest danger is a silent behaviour change on a few critical routes, so those go last and get explicit tests.
