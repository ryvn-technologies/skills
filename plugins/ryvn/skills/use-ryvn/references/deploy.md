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

`ryvn update installation <name> -e <env>` (aliases `inst`, `si`) patches an installation
with a strategic merge patch and follows the general rules in
`references/configure.md` -> Updating Resources. A patch is required: `-p` for inline,
`--patch-file` for a file (`-` reads stdin). All merge logic runs server-side.

```bash
ryvn update installation my-app -e prod -p '{"spec": {"releaseChannel": "stable"}}'
ryvn update installation my-app -e prod --patch-file patch.yaml
cat patch.yaml | ryvn update si my-app -e prod --patch-file -
```

Some fields cannot be patched: `spec.name`, `spec.service`, `spec.environment`,
`spec.blueprint`, `spec.condition`, `spec.resources` and `spec.renamedFrom` are
rejected with a validation error naming the path, and nothing is written. To rename an
installation, or point it at a different service or environment, delete it and create
the one you want.

### Environment variables

`spec.env` merges by `key`; remove a variable with `$patch: delete`.

```yaml
# patch.yaml
spec:
  env:
    - key: API_URL
      value: "https://api.example.com"
    - key: OLD_VAR
      $patch: delete
```

### Config

`spec.config` is replaced wholesale. A patch never merges into it and never descends
into it, so a patch that omits `spec.config` leaves the stored config byte-identical —
including configs containing `{{ ... }}` template expressions.

To change one value in the config, read it, edit the file, and write the whole thing
back:

```bash
ryvn get installation my-app -e prod -o yaml > install.yaml   # whole resource
# edit spec.config inside install.yaml, then:
ryvn replace -f install.yaml
```

To work on the config on its own, read the raw string, edit it, and put it back into a
patch file:

```bash
ryvn get config --installation-id <id> > values.yaml
# edit values.yaml, then build patch.yaml with the edited file as spec.config:
{ printf 'spec:\n  config: |\n'; sed 's/^/    /' values.yaml; } > patch.yaml
ryvn update installation my-app -e prod --patch-file patch.yaml
```

`spec.config` in a patch must carry the config text itself. The file-reference form
(`config: [{path: ./values.yaml}]`) is rejected with a validation error naming the
path — the server cannot read files from your machine.

To send config in a patch, put it in a file and pass `--patch-file`; inline JSON
mangles multi-line config.

```yaml
# patch.yaml
spec:
  config: |
    replicaCount: 3
    resources:
      limits:
        cpu: "1"
```

### Secrets patching

Secrets can be created, updated, or deleted through the patch spec. Each secret item
requires a `name` and either a `value` (for create/update) or `$patch: delete` (for
removal). Omitting both `value` and `$patch: delete` returns a 400 error.

```yaml
# patch.yaml
spec:
  secrets:
    - name: DB_PASSWORD
      value: "new-password"
    - name: OLD_SECRET
      $patch: delete
```

## When to Use `update` vs `replace`

- **`update`** merges your patch into the existing resource, field by field, and
  replaces `spec.config` wholesale when the patch carries it. Use it to change
  individual fields while preserving everything else.
- **`replace -f`** overwrites the resource from the file: the file contents become the
  whole spec, including `spec.config`. Use it when you want the resource to exactly
  match your file.

For config edits, both paths write the full config, so pick whichever fits the file you
already have.

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
ryvn promote release --pipeline <pipeline-name> --source <channel> --target <channel>
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
| `--patch-file` | File path for YAML patch (use `-` for stdin); required transport for multi-line config |

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
