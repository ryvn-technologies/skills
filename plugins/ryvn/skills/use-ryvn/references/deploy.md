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

This is the primary deployment flow for most services. For ad-hoc deployments outside this automated flow (e.g., deploying a specific version, rolling back, or deploying to an environment not tracking a channel), use `ryvn run command enforce-deploy` or `ryvn update installation` (see below).

## Service Installation Deployment

A service installation is an instance of a service deployed into a specific environment. Deployments create Terraform runs that apply infrastructure changes.

### Create an installation

```bash
ryvn create -f installation.yaml                   # Create from a YAML manifest
```

## Update Installations (Re-deploy)

The `update` command patches an existing installation. It can re-deploy with current settings or apply configuration changes.

### Re-deploy with current settings

```bash
ryvn update installation <name> -e <env>
```

Omitting a patch triggers a re-deploy using the installation's current configuration (status quo deployment).

### Update with inline patch

```bash
ryvn update installation <name> -e <env> -p '{"spec": {"version": "1.3.0"}}'
```

The `-p` flag accepts a JSON patch that is merged into the installation's existing spec.

### Update from file

```bash
ryvn update installation <name> -e <env> --patch-file patch.yaml
cat patch.yaml | ryvn update installation <name> -e <env> --patch-file -
```

Use `--patch-file` to supply the patch as a YAML file. Pass `-` to read from stdin, which is useful for piping from other commands or generating patches dynamically.

## When to Use `update` vs `replace`

- **`update -p`** performs a **deep merge**: it reads the current config, merges your patch on top, then writes the result. Good for changing individual fields while preserving everything else.
- **`replace -f`** performs a **full overwrite** of `spec.config`: the file contents become the entire config. Good for ensuring config exactly matches your file with no leftover keys from previous updates.

For Helm values changes, `replace -f` is generally more reliable because deep-merge can produce unexpected results when removing keys or restructuring nested values.

## Full Config Replacement

```bash
ryvn replace -f installation.yaml                  # Replace the entire spec.config
```

Unlike `update` (which merges), `replace` overwrites the full `spec.config` section with the contents of the YAML file. Use this when you want to ensure the installation's configuration exactly matches the file with no leftover fields from previous updates.

## Delete Installations

```bash
ryvn delete installation <name> -e <env>           # Delete a single installation
ryvn delete installation svc1 svc2 svc3 -e prod    # Delete multiple installations at once
ryvn delete installation <name> -e <env> --dry-run  # Preview what would be deleted
ryvn delete -f installation.yaml                   # Delete using a YAML manifest
```

Deleting an installation triggers a Terraform destroy run. Use `--dry-run` to preview the destroy plan before committing.

## Task Management

Deployments, updates, and deletes create **tasks** that track the lifecycle of Terraform runs. Some tasks (especially dry-runs) require explicit approval before they proceed.

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

The `ryvn run command` subcommand provides additional installation operations beyond deploy and update.

```bash
# Trigger a job execution
ryvn run command trigger-job -e <env> -i <name>

# Roll back to previous deployment
ryvn run command rollback -e <env> -i <name>

# Force deploy a specific version (bypasses channel)
ryvn run command enforce-deploy -e <env> -i <name> --version <version>

# Preview changes without applying (Terraform plan)
ryvn run command dry-run -e <env> -i <name>

# Task operations by installation (alternative to `ryvn task` with UUID)
ryvn run command retry-task -e <env> -i <name> --task-id <uuid>
ryvn run command cancel-task -e <env> -i <name> --task-id <uuid>
ryvn run command approve-task -e <env> -i <name> --task-id <uuid>
```

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
| `--dry-run` | Create a Terraform plan without applying |
| `--no-watch` | Return immediately without streaming status (commands auto-watch by default) |
| `--timeout` | Maximum time to wait for completion (default 10m) |
| `--poll-interval` | Status check interval, minimum 2s (default 5s) |
| `-o json` | Output in JSON format |
| `-p` | Inline JSON patch for update commands |
| `--patch-file` | File path for YAML patch (use `-` for stdin) |

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

After a dry-run or certain deployment types, the task waits for approval. Use `ryvn get installation-task <name> -e <env>` to find the task UUID, then `ryvn task approve <uuid> --reason "..."` to proceed.

### Dry-run shows unexpected changes

Inspect the current state of the installation with `ryvn describe installation <name> -e <env>` to compare what is deployed versus what the new version or config would change.

### Deployment timeout

Increase the timeout with `--timeout 20m`. If the deployment consistently times out, check the underlying infrastructure logs. The deployment may still be running -- use `ryvn get installation-task` to check its current status.

### Version not found

Verify the release channel has the version you are targeting. Use `ryvn get release` or `ryvn describe service <name>` to inspect available versions.

### Environment not provisioned

Installations cannot be deployed into an unprovisioned environment. Run `ryvn update environment <name>` to re-trigger provisioning, and wait for it to complete before deploying installations.
