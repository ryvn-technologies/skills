# Platform Knowledge

Reference for Ryvn platform concepts, configuration formats, and common patterns. Load this reference when you need to understand service types, config field semantics, template variables, networking patterns, or Helm chart defaults.

---

## Service Types

Ryvn supports four service types. YAML manifests and the CLI use short names. The API returns versioned type identifiers.

| YAML / CLI name | API type | Description |
|---|---|---|
| `server` | `web-server.v1` | HTTP/HTTPS web applications with built-in load balancing, networking, and health monitoring |
| `job` | `job.v1` | One-off or scheduled tasks (Kubernetes CronJobs) |
| `helm-chart` | `helm-chart.v1` | Arbitrary Helm charts for custom Kubernetes workloads |
| `terraform` | `terraform.v1` | Infrastructure-as-code via Terraform modules |

In YAML manifests, always use the short name:

```yaml
kind: Service
metadata:
  name: my-api
spec:
  type: server
```

---

## Config Format

The `spec.config` field on a ServiceInstallation contains Helm values (for `server`, `job`, `helm-chart`) or Terraform variables in YAML format (for `terraform`).

**In YAML manifests** (used with `ryvn create -f` and `ryvn replace -f`), config must be a **YAML string** using a block scalar (`|`), not a structured object:

```yaml
kind: ServiceInstallation
metadata:
  name: my-api
spec:
  service: my-api
  environment: production
  networking:
    ports:
      - number: 8080
        public: true
  config: |
    replicaCount: 3
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
```

**In CLI patches** (`ryvn update`), `config` is a string and is replaced wholesale: the
patch value becomes the entire config, byte for byte. Send it from a file — inline JSON
mangles multi-line config.

```yaml
# patch.yaml
spec:
  config: |
    replicaCount: 3
```

```bash
ryvn update installation my-api -e prod --patch-file patch.yaml
```

### Config can also be file references

Config supports an array form where each item references a file in the repository:

```yaml
spec:
  config:
    - path: helm/values.yaml
    - path: helm/values-production.yaml
```

---

## Template Variables

Config values can use Go template syntax to reference dynamic values from the Ryvn platform. These work in both blueprint configs and installation configs.

### Environment

| Variable | Description |
|---|---|
| `{{ .ryvn.env.name }}` | Environment name (e.g., `production`) |
| `{{ .ryvn.env.state.public_domain.name }}` | Environment's public domain (e.g., `production.myorg.ryvn.run`) |
| `{{ .ryvn.env.state.cluster_name }}` | Kubernetes cluster name |
| `{{ .ryvn.env.config.<key> }}` | Environment config value |
| `{{ .ryvn.env.releaseChannel }}` | Environment's release channel |
| `{{ .ryvn.env.provider.type }}` | Cloud provider (`aws`, `gcp`, `azure`) |
| `{{ .ryvn.env.defaultNamespace }}` | Default Kubernetes namespace |

### Installation

| Variable | Description |
|---|---|
| `{{ .ryvn.installation.name }}` | Current installation name |
| `{{ (serviceInstallation "<name>").outputs.<key> }}` | Output from a service installation |
| `{{ (serviceInstallation "<name>").namespace }}` | Namespace of a service installation |
| `{{ (serviceInstallation "<name>").outputsSecret }}` | K8s secret name containing secret outputs |
| `{{ (blueprintInstallation "<name>").outputs.<key> }}` | Output from a blueprint installation |
| `{{ (blueprintInstallation "<name>").outputsSecret }}` | K8s secret name containing secret outputs |

Secret outputs (`isSecret: true`) are **not** available via `.outputs`. For env vars, use `valueFromOutput` (see below). For Helm chart values, use `.outputsSecret` to get the K8s secret name and reference keys via `secretKeyRef`:

```yaml
config: |
  env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: {{ (blueprintInstallation "database-stack").outputsSecret }}
          key: connection_string
```

### Cross-Installation References (`valueFromOutput`)

Use `valueFromOutput` on installation env vars to reference outputs from other installations. Prefer this over template functions — template functions render as plaintext, leaking secrets into manifests and logs. `valueFromOutput` routes secret outputs through the secrets system.

Exactly one of `serviceInstallation` or `blueprintInstallation` must be specified. `name` is required and supports dot notation (e.g., `bucket.name`).

```yaml
env:
  # Reference a service installation output
  - key: DATABASE_HOST
    valueFromOutput:
      serviceInstallation: postgres-rds
      name: endpoint

  # Reference a blueprint installation output
  - key: CACHE_HOST
    valueFromOutput:
      blueprintInstallation: cache-stack
      name: host

  # Secret output — automatically routed through secrets system
  - key: DATABASE_URL
    isSecret: true
    valueFromOutput:
      blueprintInstallation: database-stack
      name: connection_string
```

To concatenate an output with other values, set the output as a base env var and reference it via Kubernetes-native `$(VAR)` syntax:

```yaml
env:
  - key: DATABASE_HOST
    valueFromOutput:
      serviceInstallation: postgres-rds
      name: endpoint
  - key: DATABASE_URL
    value: "postgresql://$(DATABASE_HOST):5432/mydb"
```

### Release Images

| Variable | Description |
|---|---|
| `{{ .ryvn.release.images.app.repo }}` | Docker image repository |
| `{{ .ryvn.release.images.app.tag }}` | Docker image tag |

### Blueprint Inputs

Reference blueprint inputs using:

```
{{ input "<name>" }}
```

### Functions

**String**: `lower`, `upper`, `title`, `trim`, `contains`, `substring`, `default`

**Data formatting**: `toYaml`, `toJson`, `indent`, `nindent`, `join`

**Control flow**: `if`/`else if`/`else`/`end`, comparison (`eq`, `ne`, `lt`, `gt`, `le`, `ge`), boolean (`and`, `or`, `not`)

### Example: Template variables in config

```yaml
config: |
  resources:
    requests:
      cpu: {{ default "500m" .ryvn.env.config.cpu }}
      memory: {{ default "512Mi" .ryvn.env.config.memory }}
```

---

## Networking Patterns

Ryvn manages networking only in environments that Ryvn provisions. Check the environment first:

```bash
ryvn get environment <env> -o yaml
```

`spec.setup: pre-provisioned` means an existing cluster that the user connected to Ryvn. Ryvn manages no networking there, so ignore the rest of this section and follow what the cluster already uses for ingress or gateways.

In every other environment, an installation can be reachable on three networks:

| Network | Reachable from | Address |
|---|---|---|
| Private | Other installations in the environment | `<name>:<port>` in the same namespace, `<name>.<namespace>.svc.cluster.local:<port>` from another namespace |
| Internal | The VPC and connected networks | `https://<name>.internal.<environment domain>` |
| Public | The internet | `https://<name>.<environment domain>` |

`<name>` is the installation name for a `server`, and the Service name for a `helm-chart`. Ryvn creates the DNS records and TLS certificates for internal and public addresses. How the networks work: https://ryvn.ai/docs/networking/overview

### Check that native networking is enabled

Ports, domains, and Routes are Ryvn-native networking. An older environment may not have it enabled yet. Check once for each environment:

```bash
ryvn get installation ryvn-net -e <env>
```

A row with a `VERSION` means native networking is enabled.

`Error: installation "ryvn-net" not found` means native networking is not enabled in this environment yet. Ryvn support can enable native networking on this environment. Until then, use [Ingress networking](#ingress-networking-deprecated).

### Choose the mechanism

When native networking is enabled:

| Installation | Use |
|---|---|
| `server`, new or with no `ingress` in its config | `spec.networking` ports |
| `helm-chart`, new or with no Ingress | A `Route` in the chart |
| Any installation that already uses an Ingress | Keep the Ingress. It is deprecated but still supported. Convert it only when the user asks. |

Do not add an Ingress to an installation that does not have one.

Before you change networking on an existing installation, check which mechanism it uses:

```bash
ryvn get installation <name> -e <env> -o yaml
```

`spec.networking.ports` means ports and domains. `ingress.enabled: true` inside `spec.config` means Ingress.

### Server: ports and domains

List the ports the app listens on under `spec.networking`, next to `spec.config`. Every port gets a private and an internal address. `public: true` adds a public address, and `domains` adds custom domains:

```yaml
spec:
  networking:
    ports:
      - number: 3000
        public: true
        domains:
          - app.example.com
```

When you patch `spec.networking`, ports merge by `number`. A port's `domains` list is replaced as a whole, so send every domain you want to keep.

- Every field, such as `name` for a second port and `protocol: http2` for gRPC: https://ryvn.ai/docs/iac/installations/server#networking
- Paths of one domain to different installations: https://ryvn.ai/docs/networking/overview#path-based-routing
- An app that terminates TLS itself: https://ryvn.ai/docs/networking/overview#tls-passthrough

### Helm chart: Route

Add a `Route` to the chart next to the Service it exposes, and read the hostname from the chart's values:

```yaml
# templates/route.yaml
apiVersion: networking.ryvn.app/v1alpha1
kind: Route
metadata:
  name: web
spec:
  exposure: [public]
  domains: [{{ .Values.route.host | quote }}]
  rules:
    - to: [{ name: web, port: http }]
```

Set the value in the installation config: `route.host: "web.{{ .ryvn.env.state.public_domain.name }}"`.

- `to` is a Service in the Route's namespace and one of its ports, by name or number.
- A public Route (`exposure: [public]`) takes a hostname in the public domain. An internal Route (`exposure: [internal]`) takes a hostname in the internal domain. To serve a Service on both networks, add one Route for each network.
- For a third-party chart, turn its Ingress off in the chart's values and add a Route with the `ryvn-routes` chart: https://ryvn.ai/docs/networking/routes#third-party-charts
- Path-based routing, TLS passthrough, external auth, and troubleshooting: https://ryvn.ai/docs/networking/routes

### Domains

Do not build domain strings by hand. Use the environment's domain variables, which resolve to the right domain for the environment:

- `{{ .ryvn.env.state.public_domain.name }}`: public domain, such as `production.acme-corp-xhnjr.ryvn.run`
- `{{ .ryvn.env.state.internal_domain.name }}`: internal domain, reachable from the VPC and connected networks

A custom domain needs DNS records at the user's DNS provider, and you cannot create them. Add the domain, run `ryvn describe installation <name> -e <env>`, and give the user the records listed under `DNS records`. What the records are and how to check them: https://ryvn.ai/docs/networking/domains-and-tls#create-the-dns-records

### Verify addresses

After a deploy, `ryvn describe installation <name> -e <env>` lists every internal and public address under `Endpoints` with its `State`: `Active`, `Pending`, or `Error`. `Reason` says what a `Pending` address waits for, or what to fix. With `-o json`, read `endpoints`.

### Ingress networking (deprecated)

Ingress is deprecated but still supported. Use it for an installation that already has an Ingress, and in an environment where native networking is not enabled yet.

For a `server`, set `ingress` in `spec.config`. For a `helm-chart`, set the chart's ingress values. Both take `enabled: true`, a class, its issuer annotation, `hosts`, and `tls`:

| className | Issuer annotation | Network |
|---|---|---|
| `external-nginx` | `cert-manager.io/cluster-issuer: external-issuer` | Public |
| `internal-nginx` | `cert-manager.io/cluster-issuer: internal-issuer` | Internal |

- Full example: https://ryvn.ai/docs/networking/migration-guides/ingress-networking#configure-an-ingress
- `className: nginx`, without the `external-` or `internal-` prefix, causes webhook admission errors.
- Many `nginx.ingress.kubernetes.io/*` annotations have no effect or are rejected. Check the annotation before you add it: https://ryvn.ai/docs/networking/migration-guides/ingress-networking#annotation-support
- To convert, move the hosts to `spec.networking` and remove `ingress` from the config (server), or turn the Ingress off and add a Route (Helm chart). A custom domain needs different DNS records after the conversion, so tell the user before you convert.

---

## Network policy

Network policy is in preview and isn't enabled by default. Contact Ryvn support to enable it. A network policy is a Kubernetes resource (`apiVersion: networking.ryvn.app/v1alpha1`, `kind: NetworkPolicy`, short name `rnp`) shipped in the service's Helm chart. It is NOT a Ryvn resource (never in Ryvn YAML or `ryvn create`) and NOT the built-in `networking.k8s.io` NetworkPolicy.

```yaml
apiVersion: networking.ryvn.app/v1alpha1
kind: NetworkPolicy
metadata:
  name: agent-egress
spec:
  podSelector:
    matchLabels:
      app: agent
  egress:
    - name: anthropic
      to:
        - domainNames: [api.anthropic.com]
      protocols:
        - tcp: { destinationPort: { number: 443 } }
```

These pass validation (`ACCEPTED=True`) but block traffic, so check them before applying:

- A policy only allows, and only outbound traffic. Once a policy selects a pod, the pod keeps only what its policies allow plus cluster DNS, workload identity, and the Kubernetes API.
- `networks` is only for addresses outside the cluster. For a pod or a Service in the cluster, use `pods` or `namespaces`.
- For `pods` and `namespaces`, `protocols` names the pod's container port, not the Service port.

Read the docs for the rest:

- Every `to` field and `protocols`: https://ryvn.ai/docs/networking/network-policy#rules
- Restrict a whole namespace by default with the `networking.ryvn.app/default-egress-policy` label: https://ryvn.ai/docs/networking/network-policy#namespace-posture
- Check a policy and test a connection with `ryvn connect <env>`: https://ryvn.ai/docs/networking/network-policy#check-a-policy
- Limitations on each cloud: https://ryvn.ai/docs/networking/network-policy#known-limitations

---

## Common Helm Chart Patterns

### Health Probes

For `server` type services, health probes are **disabled by default**:

```yaml
livenessEnabled: false    # default
readinessEnabled: false   # default
startupEnabled: false     # default
```

Enabling probes without a working health endpoint causes pods to crash-loop. Always verify the application exposes a health endpoint before enabling:

```yaml
config: |
  livenessEnabled: true
  livenessProbe:
    httpGet:
      path: /healthz
      port: 8080
  readinessEnabled: true
  readinessProbe:
    httpGet:
      path: /ready
      port: 8080
```

Default probe paths are `/` on port `http`. Override these if your application uses different paths or ports.

---

## Server Type Defaults

Key defaults for `server` type installations (Helm values):

| Field | Default | Notes |
|---|---|---|
| `replicaCount` | `1` | |
| `service.port` | `80` | Not used when `spec.networking.ports` is set |
| `service.type` | `ClusterIP` | |
| `ingress.enabled` | `false` | Deprecated. Use `spec.networking` for new installations |
| `livenessEnabled` | `false` | Enable only with a working health endpoint |
| `readinessEnabled` | `false` | Enable only with a working health endpoint |
| `startupEnabled` | `false` | |
| `autoscaling.enabled` | `false` | Managed via Ryvn API when enabled |
| `terminationGracePeriodSeconds` | `30` | |
| `preDeploy.enabled` | `false` | Set `preDeploy.run` to a command (e.g., `npm run db:migrate`) |
| `persistence.enabled` | `false` | PVC-based persistence |

---

## Job Type Defaults

Key defaults for `job` type installations (Helm values):

| Field | Default | Notes |
|---|---|---|
| `schedule` | `""` (empty) | Empty = manual-only, triggered via `ryvn command trigger-job`. Set a cron expression for scheduled execution. |
| `concurrencyPolicy` | `Forbid` | `Forbid`, `Allow`, or `Replace` |
| `backoffLimit` | `1` | |
| `restartPolicy` | `Never` | |
| `successfulJobsHistoryLimit` | `3` | |
| `failedJobsHistoryLimit` | `1` | |
| `ttlSecondsAfterFinished` | `null` | Set to auto-cleanup finished jobs |
