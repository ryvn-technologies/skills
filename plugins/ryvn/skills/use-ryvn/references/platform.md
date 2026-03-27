# Platform Knowledge

Reference for Ryvn platform concepts, configuration formats, and common patterns. Load this reference when you need to understand service types, config field semantics, template variables, networking patterns, or Helm chart defaults.

---

## Service Types

Ryvn supports four service types. YAML manifests and the CLI use short names. The API returns versioned type identifiers.

| YAML / CLI name | API type | Description |
|---|---|---|
| `server` | `web-server.v1` | HTTP/HTTPS web applications with built-in load balancing, ingress, and health monitoring |
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
  config: |
    replicaCount: 3
    ingress:
      enabled: true
      className: external-nginx
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
```

**In CLI patches** (`ryvn update -p`), the CLI accepts structured objects and handles the conversion internally. Both forms work:

```bash
# Structured object — CLI deep-merges into existing config
ryvn update installation my-api -e prod \
  -p '{"spec":{"config":{"replicaCount": 3}}}'

# String form — also works
ryvn update installation my-api -e prod \
  -p '{"spec":{"config":"replicaCount: 3\n"}}'
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
| `{{ .ryvn.installation.outputs.<key> }}` | Current installation's Terraform outputs |

### Cross-Installation References

Reference outputs from other installations using:

```
{{ .ryvn.installations.<name>.outputs.<key> }}
```

Installation names with hyphens are converted to underscores in templates. For example, `storage-service` becomes `storage_service`.

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

### Example: Cross-installation database wiring

```yaml
config: |
  env:
    - name: DATABASE_HOST
      value: {{ .ryvn.installations.postgres.outputs.host }}
    - name: DATABASE_PORT
      value: "{{ .ryvn.installations.postgres.outputs.port }}"
    - name: APP_DOMAIN
      value: {{ .ryvn.installation.name }}.{{ .ryvn.env.state.public_domain.name }}
  resources:
    requests:
      cpu: {{ default "500m" .ryvn.env.config.cpu }}
      memory: {{ default "512Mi" .ryvn.env.config.memory }}
```

---

## Networking Patterns

### Ingress Controllers

Each Ryvn environment has two NGINX ingress controllers:

| className | Issuer | Use for |
|---|---|---|
| `external-nginx` | `cert-manager.io/cluster-issuer: external-issuer` | Public internet-facing services |
| `internal-nginx` | `cert-manager.io/cluster-issuer: internal-issuer` | VPC-internal services |

Using `className: nginx` (without the `external-` or `internal-` prefix) causes webhook admission errors. Always use the full name.

### Domains

Each environment gets a default public domain in the format `{environment}.{org-slug}.ryvn.run`. Installation-level URLs follow the pattern `{installation-name}.{environment}.{org-slug}.ryvn.run`. Custom root domains replace the `ryvn.run` suffix when configured on the environment.

Rather than constructing domain strings manually, use the environment's domain output variables which resolve to the correct domain for the environment (whether default `ryvn.run` or custom):

- `{{ .ryvn.env.state.public_domain.name }}` — public domain (e.g., `production.acme-corp-xhnjr.ryvn.run`)
- `{{ .ryvn.env.state.internal_domain.name }}` — internal domain (VPC-only)

For installation-specific hostnames, prefix with the installation name:

```
{{ .ryvn.installation.name }}.{{ .ryvn.env.state.public_domain.name }}
```

### Full Ingress Example

```yaml
config: |
  ingress:
    enabled: true
    className: external-nginx
    annotations:
      cert-manager.io/cluster-issuer: external-issuer
    hosts:
      - host: {{ .ryvn.installation.name }}.{{ .ryvn.env.state.public_domain.name }}
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: {{ .ryvn.installation.name }}-tls
        hosts:
          - {{ .ryvn.installation.name }}.{{ .ryvn.env.state.public_domain.name }}
```

For services that should not be publicly accessible (e.g., internal databases, object storage), disable ingress entirely:

```yaml
config: |
  ingress:
    enabled: false
```

---

## Common Helm Chart Patterns

### CNPG Cluster Secrets

The `cnpg-cluster` Helm chart (CloudNativePG) creates a Kubernetes secret named `{installation-name}-app` containing the PostgreSQL connection string. For example, an installation named `cnpg-cluster` creates the secret `cnpg-cluster-app`.

Reference it from other installations using `secretKeyRef`:

```yaml
config: |
  env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: cnpg-cluster-app
          key: uri
```

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
| `service.port` | `80` | |
| `service.type` | `ClusterIP` | |
| `ingress.enabled` | `false` | Must enable explicitly for external access |
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
| `schedule` | `""` (empty) | Empty = manual-only, triggered via `ryvn run command trigger-job`. Set a cron expression for scheduled execution. |
| `concurrencyPolicy` | `Forbid` | `Forbid`, `Allow`, or `Replace` |
| `backoffLimit` | `1` | |
| `restartPolicy` | `Never` | |
| `successfulJobsHistoryLimit` | `3` | |
| `failedJobsHistoryLimit` | `1` | |
| `ttlSecondsAfterFinished` | `null` | Set to auto-cleanup finished jobs |
