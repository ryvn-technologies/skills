# Operate — Monitoring, Logs & Troubleshooting

Day-to-day operations reference for the Ryvn CLI.

---

## Health Snapshot

Start broad, then narrow down to the problem area.

```bash
# List all environments and their status
ryvn get environment

# List installations in a specific environment
ryvn get service-installation -e prod

# Detailed info for a single installation
ryvn describe installation <name> -e prod

# Check for pending or failed tasks
ryvn get installation-task <name> -e prod
```

---

## Logs

### Environment Provisioning Logs

View terraform provisioning logs for the most recent task of an environment.

```bash
ryvn logs environments <name>                # All provisioning logs
ryvn logs environments <name> --since 30m    # Last 30 minutes
ryvn logs environments <name> --follow       # Stream live
ryvn logs environments <name> -o json        # JSON output
```

Aliases: `environments`, `environment`, `env`

### Application Logs (Installation)

Log source is auto-detected by service type:
- **Terraform services** — shows task logs from the most recent deployment
- **Other services** (web-server, helm-chart, etc.) — shows application logs from Loki

```bash
# Recent logs
ryvn logs installations <name> -e <env>

# Last hour
ryvn logs installations <name> -e <env> --since 1h

# Stream live
ryvn logs installations <name> -e <env> --follow

# Search for errors
ryvn logs installations <name> -e <env> --search "connection refused" --level error

# Specific time window
ryvn logs installations <name> -e <env> --since 2026-02-27T10:00:00Z --until 2026-02-27T10:15:00Z

# Filter by pod and exclude noise
ryvn logs installations <name> -e <env> --pod my-api-abc123 --exclude "healthcheck"

# JSON output with level filter
ryvn logs installations <name> -e <env> --level error --since 1h -o json
```

Aliases: `installations`, `installation`, `inst`

### Log Flags Reference

| Flag | Short | Description |
|------|-------|-------------|
| `--environment` | `-e` | Target environment (installation logs only) |
| `--follow` | `-f` | Stream logs continuously |
| `--since` | | Time window start: duration (`30m`, `1h`) or ISO 8601 (`2026-02-27T10:00:00Z`). Omit to show all logs |
| `--until` | | Time window end: duration or ISO 8601 (default: now). Installation logs only |
| `--search` | `-s` | Server-side text search (substring match). Installation logs only |
| `--level` | | Filter by severity: `trace`, `debug`, `info`, `warn`, `error`, `fatal` (repeatable). Installation logs only |
| `--pod` | | Filter by specific pod name (repeatable). Installation logs only |
| `--container` | | Filter by container name (repeatable). Installation logs only |
| `--exclude` | | Exclude lines containing this text. Installation logs only |
| `--output` | `-o` | Output format (`json`) |
| `--timestamps` | | Show timestamps |
| `--prefix` | | Prefix each line with `[pod/POD_NAME/CONTAINER_NAME]`. Installation logs only |

---

## Task Operations

Tasks represent provisioning or deployment actions. Use `ryvn get installation-task` to find task IDs.

```bash
# Check task status
ryvn get installation-task <name> -e <env>

# Approve a pending task (e.g., Terraform plan)
ryvn task approve <task-uuid> --reason "reviewed plan"

# Cancel a running or pending task
ryvn task cancel <task-uuid> --reason "no longer needed"

# Retry a failed task
ryvn task retry <task-uuid> --reason "transient failure"
```

The `--reason` flag is optional but recommended for audit trails.

---

## Failure Triage

### Provisioning Failures

Environment failed to provision:

```bash
ryvn logs environments <name> --since 1h
ryvn describe environment <name> -o json
```

Common causes:
- GCP permissions insufficient
- Quota limits exceeded
- Network configuration errors

### Deployment Failures

Installation failed to deploy:

```bash
ryvn logs installations <name> -e <env> --level error --since 1h
ryvn describe installation <name> -e <env> -o json
ryvn get installation-task <name> -e <env>
```

Common causes:
- Version not found
- Configuration errors
- Resource limits exceeded
- Pending approval blocking progress

### Runtime Failures

Service is running but misbehaving:

```bash
ryvn logs installations <name> -e <env> --search "error" --since 30m
ryvn logs installations <name> -e <env> --level error --since 1h
```

Common causes:
- Connection failures to dependencies
- Misconfigured environment variables
- Resource exhaustion (CPU, memory)

---

## Recovery

After identifying the root cause:

```bash
# Fix configuration via patch
ryvn update installation <name> -e <env> -p '{"spec": {...}}'

# Retry a failed task
ryvn task retry <task-uuid> --reason "fixed configuration"

# Trigger a re-deploy (no patch = re-deploy with current settings)
ryvn update installation <name> -e <env>

# Verify recovery
ryvn describe installation <name> -e <env>
ryvn logs installations <name> -e <env> --since 5m
```

---

## Provisioner Daemon

For self-hosted provisioning, run the daemon that polls for and executes infrastructure tasks:

```bash
ryvn run provisioner \
  --environment staging \
  --poll-interval 30s
```

The daemon authenticates via either:
- **Flag-based credentials**: `--client-id` and `--client-secret`
- **File-based credentials**: `~/.ryvn/credentials.yaml` (default)

The daemon will continuously poll for pending provision/deprovision tasks, execute Terraform workflows, and report results back to the hub.

---

## Troubleshooting Quick Reference

| Symptom | Action |
|---------|--------|
| No logs appearing | Verify environment name and that the installation exists: `ryvn get service-installation -e <env>` |
| Logs seem truncated | Use `--since` with a wider window or specify an explicit time range with `--since` and `--until` |
| Task stuck in pending | Check if approval is required: `ryvn get installation-task <name> -e <env>`, then `ryvn task approve <uuid>` |
| Provisioner not picking up tasks | Verify service account credentials, network access, and that `--environment` matches the target |
| Installation not updating | Confirm the update was applied: `ryvn describe installation <name> -e <env>`, check for pending tasks |
