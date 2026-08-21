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

`update` returns as soon as the server accepts the patch: it prints the patch result
(resource type, name, and whether it was created, updated, or unchanged) and exits. It
does not print a task UUID and does not watch the resulting rollout, and it takes none
of the task flags (`--reason`, `--no-watch`, `--timeout`, `--poll-interval`); passing
one fails with `unknown flag`. Its relevant command-local flags are `-p/--patch`,
`--patch-file`, `-e/--environment`, `--dry-run`, and `-o`. To follow what the patch
triggered, poll `ryvn get installation-task <name> -e <env>`.

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

The `--reason` flag documents why the action was taken; it exists on `ryvn task approve|cancel|retry` and on `ryvn command *`, not on `update`, `create`, `replace`, or `delete`.

You can always obtain task UUIDs from `ryvn get installation-task <name> -e <env>`. When a
task-creating `ryvn command` watches by default, its first status line also includes the
UUID. With `--no-watch`, it returns a valid monitoring command before discovering the
task, so it does not print the UUID. `ryvn command unpin` creates no task. The
sync-backed verbs (`create`, `replace`, `update`, `delete`) print the resource that
changed, not a task UUID.

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

# Dry run (helm diff or terraform plan) without applying
ryvn command dry-run -e <env> -i <name>

# Rollout restart workloads without changing version or config
ryvn command restart -e <env> -i <name>            # web-server: auto-selects its Deployment
ryvn command restart -e <env> -i <name> --all      # every workload in the installation
ryvn command restart -e <env> -i <name> --deployment api --statefulset db

# Pin to a release version, optionally with a configuration revision
ryvn command pin -e <env> -i <name> --version <version>
ryvn command pin -e <env> -i <name> --version <version> --config-version <revision>

# Remove the pin and resume release-channel updates (no task is created)
ryvn command unpin -e <env> -i <name>
```

Command types: `rollback`, `enforce-deploy`, `trigger-job`, `dry-run`, `restart`, `pin`,
and `unpin` (plus the `redeploy installation` subcommand above).

**When to use `redeploy` vs `update`**: Use `ryvn command redeploy installation` when you want to re-trigger a deployment without changing any configuration (e.g., to pick up external changes like variable groups, secrets, or to retry after a transient failure). Use `ryvn update installation` when you need to change the installation's config, release channel, env vars, or secrets.

For task operations (approve, cancel, retry), use `ryvn task` with the task UUID (see Task Management above).

Task-creating command operations (`rollback`, `enforce-deploy`, `trigger-job`, `dry-run`,
`restart`, `pin`, and `redeploy installation`) auto-watch until the task completes. Use
`--no-watch` to return a monitoring command immediately, `--timeout`/`--poll-interval`
to tune the wait, and `--reason` to annotate the action. `unpin` accepts `--reason` but
creates no task and returns after removing the pin. `ryvn task approve|cancel|retry`
accepts `--reason`; `ryvn sync import` uses `--wait` with `--timeout` and
`--poll-interval`. The sync-backed verbs (`create`, `replace`, `update`, `delete`) do not
accept these task-control flags and return as soon as the API accepts the change.

## Promotion

Promotion copies a release version from one channel to another, enabling staged rollouts (e.g., dev to staging to production).

```bash
ryvn promote release --pipeline <pipeline-name> --source <channel> --target <channel>
```

## Deploy Flags Reference

Flags are command-local. Some command groups register shared flags, but those flags are
meaningful only for the operations listed below. Check command help before composing them.

| Flag | Where it works | Description |
|---|---|---|
| `-e` / `--environment` | most installation-scoped commands | Target environment (required for installation-scoped resources) |
| `-o json` | commands whose help lists `--output` | Output in JSON format |
| `-p` / `--patch` | `ryvn update` | Inline patch (JSON or YAML) |
| `--patch-file` | `ryvn update` | File path for a patch (use `-` for stdin); required transport for multi-line config |
| `--dry-run` | `ryvn update <kind> <name>` only (not the `update environment\|service\|variable-group` subcommands) | Merge and validate without writing, printing the merged document |
| `-i` / `--installation` | positional `ryvn command <type>` operations | Target installation; `redeploy installation` takes the name positionally |
| `--version` | `ryvn command enforce-deploy`, `dry-run`, `pin` | Release version to deploy |
| `--config-version` | `ryvn command pin` | Configuration revision to hold |
| `--disable-approvals` | `ryvn command dry-run` | Create a preview that cannot be applied |
| `--reason` | `ryvn command` operations, `ryvn task approve\|cancel\|retry` | Audit annotation for the action |
| `--no-watch` | task-creating `ryvn command` operations | Return a monitoring command instead of watching; `unpin` is already immediate |
| `--timeout` | task-creating `ryvn command` operations (default 10m), `ryvn sync import --wait` (default 10m) | Maximum time to wait for completion |
| `--poll-interval` | task-creating `ryvn command` operations, `ryvn sync import --wait` (default 5s) | Status check interval |
| `--all`, `--deployment`, `--statefulset`, `--daemonset` | `ryvn command restart` | Workload selection |
| `--force` | `ryvn delete installation\|environment` | Skip the uninstall task and delete immediately (orphans cloud resources). On macOS, the confirmation code appears in a native dialog and requires an interactive terminal, so it cannot be used from CI, SSH, or an agent |

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

When a task-creating `ryvn command` stops watching, increase its wait with `--timeout 20m`; the timeout only bounds the CLI's watch, so the task keeps running -- use `ryvn get installation-task <name> -e <env>` to check its current status. `unpin` and the sync-backed verbs do not watch, so there is nothing to time out.

### Version not found

Verify the release channel has the version you are targeting. Use `ryvn get release -s <service>` (`-b <blueprint>` for blueprint releases) or `ryvn describe service <name>` to inspect available versions.

### Environment not provisioned

Installations cannot be deployed into an unprovisioned environment. Patching the environment's config re-triggers provisioning -- `ryvn update environment <name> -p '{"spec": {"config": ...}}'` (a patch is required; `ryvn update environment <name>` on its own is an error) -- then wait for it to complete before deploying installations. Track it with `ryvn logs environments <name> --follow`.
