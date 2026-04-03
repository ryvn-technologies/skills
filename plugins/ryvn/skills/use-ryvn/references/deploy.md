# Ryvn CLI Deploy Reference

Deploying with Ryvn involves two resource types: **environments** (infrastructure) and **service installations** (applications running in those environments). Environments must be provisioned before installations can be deployed into them.

## Environment Provisioning

Environments represent infrastructure targets (e.g., a GCP project, a Kubernetes cluster). Provisioning creates the underlying infrastructure; deprovisioning tears it down.

### Create and provision from YAML

```bash
ryvn create -f environment.yaml                    # Create environment from a YAML manifest
```

Creating an environment automatically kicks off provisioning.

### Delete an environment

```bash
ryvn delete environment <name>                     # Deprovision infrastructure and delete the environment
```

Deleting an environment tears down all cloud resources and removes the environment. Installations in the environment should be deleted first.

## GitHub Actions CI/CD Flow

When you create a service linked to a GitHub repository, Ryvn can auto-create a pull request with a GitHub Actions workflow file. **You must merge that PR before CI can build releases.**

After the PR is merged, the automated flow is:

1. Push to main (or configured branch)
2. GitHub Actions builds the container image and creates a release in Ryvn
3. The release is pushed to the service's release channel
4. Installations subscribed to that channel automatically deploy the new release

This is the primary deployment flow for most services. For ad-hoc deployments outside this automated flow (e.g., redeploying with current config, deploying a specific version, or rolling back), use `ryvn command redeploy`, `ryvn command enforce-deploy`, or `ryvn command rollback` (see Installation Commands below).

## Service Installation Deployment

A service installation is an instance of a service deployed into a specific environment. Deployments create Terraform runs that apply infrastructure changes.

### Create an installation

```bash
ryvn create -f installation.yaml                   # Create from a YAML manifest
```

## Update Installations

The `update` command patches an existing installation by applying configuration changes. A patch is required — use `-p` (inline) or `--patch-file` (file) to specify what to update. All merge logic runs server-side.

### Update with inline patch

```bash
ryvn update installation <name> -e <env> -p '{"spec": {"releaseChannel": "stable"}}'
```

The `-p` flag accepts a JSON patch that is deep-merged into the installation's existing spec using the strategic merge strategy by default.

### Update from file

```bash
ryvn update installation <name> -e <env> --patch-file patch.yaml
cat patch.yaml | ryvn update installation <name> -e <env> --patch-file -
```

Use `--patch-file` to supply the patch as a YAML file. Pass `-` to read from stdin, which is useful for piping from other commands or generating patches dynamically.

### Patch strategies (--type flag)

The `--type` flag controls how the patch is merged with the existing installation config. Strategies only affect `spec.config` — other fields like `releaseChannel`, `branch`, `env`, and `secrets` are always applied directly regardless of strategy.

| Strategy | Flag | Behavior |
|---|---|---|
| Strategic (default) | `--type strategic` | kubectl-style deep merge. Objects are recursively merged. Arrays with known merge keys (`env` by `key`, `secrets` by `name`) are merged by key. Other arrays are replaced wholesale. Use `$patch: delete` to remove items. |
| JSON Merge Patch | `--type merge` | RFC 7386. Deep merges objects, replaces arrays wholesale. Set a field to `null` to delete it from the config. |
| JSON Patch | `--type json` | RFC 6902. Provide an array of explicit operations (`add`, `remove`, `replace`, `move`, `copy`, `test`) for precise surgical edits. |

#### Strategic merge (default)

```bash
# Deep-merge config — existing keys are preserved, new keys are added
ryvn update installation my-app -e prod -p '{"spec": {"config": {"replicaCount": 3}}}'

# Add/update environment variables by key
ryvn update installation my-app -e prod --patch-file patch.yaml
# patch.yaml:
#   spec:
#     env:
#       - key: API_URL
#         value: "https://api.example.com"
#       - key: OLD_VAR
#         $patch: delete
```

#### JSON Merge Patch (RFC 7386)

```bash
# Set a field to null to delete it from config
ryvn update installation my-app -e prod --type merge -p '{"spec": {"config": {"legacyMode": null}}}'
```

#### JSON Patch (RFC 6902)

```bash
# Precise operations — add, remove, replace with explicit paths
ryvn update installation my-app -e prod --type json -p '{"spec": {"config": [{"op": "replace", "path": "/replicaCount", "value": 5}, {"op": "remove", "path": "/legacyMode"}]}}'
```

### Secrets patching

Secrets can be created, updated, or deleted through the patch spec. Each secret item requires a `name` and either a `value` (for create/update) or `$patch: delete` (for removal). Omitting both `value` and `$patch: delete` returns a 400 error.

```yaml
# patch.yaml
spec:
  secrets:
    - name: DB_PASSWORD
      value: "new-password"
    - name: OLD_SECRET
      $patch: delete
```

```bash
ryvn update installation my-app -e prod --patch-file patch.yaml
```

## When to Use `update` vs `replace`

- **`update`** deep-merges your patch into the existing config. Use it for changing individual fields while preserving everything else. Choose a strategy with `--type` based on how you want config merged (strategic for most cases, merge for null-deletion, json for surgical precision).
- **`replace -f`** performs a **full overwrite** of `spec.config`: the file contents become the entire config. Use it when you want the config to exactly match your file with no leftover keys from previous updates.

For Helm values changes, `replace -f` is generally more reliable because deep-merge can produce unexpected results when removing keys or restructuring nested values. Alternatively, use `--type merge` with null values to remove specific keys while preserving the rest.

## Full Config Replacement

```bash
ryvn replace -f installation.yaml                  # Replace the entire spec.config
```

Unlike `update` (which merges), `replace` overwrites the full `spec.config` section with the contents of the YAML file. Use this when you want to ensure the installation's configuration exactly matches the file with no leftover fields from previous updates.

## Delete Installations

```bash
ryvn delete installation <name> -e <env>           # Delete a single installation
ryvn delete installation svc1 svc2 svc3 -e prod    # Delete multiple installations at once
ryvn delete -f installation.yaml                   # Delete using a YAML manifest
```

Deleting an installation triggers an uninstall task (Terraform destroy or Helm uninstall). In environments with approval required, the task must be approved before proceeding.

## Task Management

Deployments, updates, and deletes create **tasks** that track the lifecycle of Terraform runs. Some tasks require explicit approval before they proceed.

### Check task status

```bash
ryvn get installation-task <name> -e <env>          # List tasks for an installation
```

### Approve, cancel, or retry tasks

```bash
ryvn task approve <uuid> --reason "reviewed plan"
ryvn task cancel <uuid> --reason "no longer needed"
ryvn task retry <uuid> --reason "transient failure"
```

The `--reason` flag documents why the action was taken. Task UUIDs are displayed in the output of deploy, update, and delete commands, and in `ryvn get installation-task` output.

## Installation Commands

The `ryvn command` verb provides installation operations beyond config updates.

```bash
# Redeploy with current config and latest release version (no config changes)
ryvn command redeploy installation <name> -e <env>
ryvn command redeploy installation <name> -e <env> --reason "pick up variable group changes"

# Trigger a job execution
ryvn command trigger-job -e <env> -i <name>

# Roll back to previous deployment
ryvn command rollback -e <env> -i <name>

# Force deploy a specific version (bypasses channel)
ryvn command enforce-deploy -e <env> -i <name> --version <version>
```

**When to use `redeploy` vs `update`**: Use `ryvn command redeploy installation` when you want to re-trigger a deployment without changing any configuration (e.g., to pick up external changes like variable groups, secrets, or to retry after a transient failure). Use `ryvn update installation` when you need to change the installation's config, release channel, env vars, or secrets.

For task operations (approve, cancel, retry), use `ryvn task` with the task UUID (see Task Management above).

All commands auto-watch task progress by default. Use `--no-watch` to return immediately. Use `--reason` to annotate the action for audit trails.

## Promotion

Promotion copies a release version from one channel to another, enabling staged rollouts (e.g., dev to staging to production).

```bash
ryvn promote releases --pipeline <pipeline-name> --source <channel> --target <channel>
```

## Deploy Flags Reference

| Flag | Description |
|---|---|
| `-e` / `--environment` | Target environment (required for installation commands) |
| `-v` / `--version` | Release version to deploy |
| `--no-watch` | Return immediately without streaming status (commands auto-watch by default) |
| `--timeout` | Maximum time to wait for completion (default 10m) |
| `--poll-interval` | Status check interval, minimum 2s (default 5s) |
| `-o json` | Output in JSON format |
| `-p` | Inline JSON patch for update commands |
| `--patch-file` | File path for YAML patch (use `-` for stdin) |
| `--type` | Patch strategy for installation updates: `strategic` (default), `merge`, or `json` |

## YAML Resource Format

Ryvn uses Kubernetes-style YAML manifests with `kind`, `metadata`, and `spec` fields. Multiple resources can be defined in a single file separated by `---`.

```yaml
kind: Environment
metadata:
  name: staging
spec:
  # environment-specific fields
---
kind: ServiceInstallation
metadata:
  name: my-api
spec:
  service: my-api-service
  environment: production
  config:
    # service configuration
```

Use `ryvn create -f` to create resources from manifests, `ryvn replace -f` to overwrite their config, and `ryvn delete -f` to remove them.

## Troubleshooting

### Task pending approval

Some deployment types require approval before proceeding. Use `ryvn get installation-task <name> -e <env>` to find the task UUID, then `ryvn task approve <uuid> --reason "..."` to proceed.

### Unexpected changes after deploy

Inspect the current state of the installation with `ryvn describe installation <name> -e <env>` to compare what is deployed versus what the new version or config would change.

### Deployment timeout

Increase the timeout with `--timeout 20m`. If the deployment consistently times out, check the underlying infrastructure logs. The deployment may still be running -- use `ryvn get installation-task` to check its current status.

### Version not found

Verify the release channel has the version you are targeting. Use `ryvn get release` or `ryvn describe service <name>` to inspect available versions.

### Environment not provisioned

Installations cannot be deployed into an unprovisioned environment. Run `ryvn update environment <name>` to re-trigger provisioning, and wait for it to complete before deploying installations.
