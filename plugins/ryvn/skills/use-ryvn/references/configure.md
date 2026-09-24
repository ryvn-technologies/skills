# Ryvn CLI Configuration and Resource Management

## Updating Resources

`ryvn update <kind> <name>` (alias `ryvn patch`) is one command for every kind: read the
current document with `ryvn get <kind> <name> -o yaml`, then send only the fields that
change as a strategic merge patch.

```bash
ryvn update maintenance-window weekend -p '{"spec": {"timeZone": "UTC"}}'
ryvn update maintenance-window weekend --patch-file patch.yaml --dry-run  # merged document, nothing written
cat patch.yaml | ryvn patch mw weekend --patch-file -                     # stdin; avoids shell quoting
```

- Wrap spec fields in `spec` and send only what changes; `-e <environment>` for
  environment-scoped kinds.
- Invalid fields are rejected and the error names every offending path — fix them all in
  one edit. If a kind is not supported, the error names the kinds that are.
- Lists with a merge key merge item by item; remove an item with `$patch: delete`
  (`spec.env: [{key: OLD_VAR, $patch: delete}]`). `spec.config` is replaced wholesale.

## Environment Management

Environments represent deployment targets (e.g., production, staging, development). Each environment can have its own configuration, release channel, and approval requirements.

```bash
ryvn get environment                               # List all environments
ryvn get environment production                    # Get specific environment
ryvn describe environment production               # Detailed info with status and settings
ryvn update environment prod -p '{"spec": {"displayName": "Production"}}'
ryvn update environment prod --patch-file patch.yaml
```

`ryvn update environment` is an exception to the rules above: it accepts
`spec.displayName`, `spec.description`, `spec.releaseChannel`, `spec.requireApproval`,
`spec.config`, and `metadata.labels`. Any other field in the patch is silently ignored
rather than rejected, so confirm the result with `ryvn get environment prod -o yaml`.

## Service Management

Services are the workloads running in your environments.

```bash
ryvn get service                                   # List all services
ryvn get service my-api                            # Get specific service
ryvn describe service my-api                       # Detailed info including deployments and config
```

## Blueprint Management

Blueprints are reusable templates that define infrastructure and service configurations. Blueprint installations are instances of a blueprint deployed into an environment.

```bash
ryvn get blueprint                                 # List all blueprints
ryvn get blueprint my-template                     # Get specific blueprint
ryvn describe blueprint my-template                # Detailed info including inputs and installations
ryvn get blueprint-installation -e prod --blueprint my-bp  # List installations for a blueprint in an environment
```

### Updating Blueprint Installations

`ryvn update blueprint-installation <name>` (aliases `bpi`, `blueprint-installations`)
follows the patch rules above; `-e <env>` is required.

```bash
ryvn update blueprint-installation my-stack -e prod -p '{"spec": {"inputs": [{"name": "cpu", "value": "2"}]}}'
ryvn update blueprint-installation my-stack -e prod -p '{"spec": {"inputs": [{"name": "cpu", "$patch": "delete"}]}}'
```

- `spec.inputs` merges by `name`: unlisted inputs survive; `$patch: delete` drops one.
- An input the installed blueprint version doesn't declare is stored and the response warns
  by name, but stays inactive until a version declaring it is installed.
- No `spec.blueprintVersion` or `spec.autoUpgradeEnabled`: use `ryvn set blueprint-version`
  and patch `spec.disableAutoUpgrade` instead.

`set`/`unset blueprint-input` below remain available as input shorthand.

### Blueprint Inputs

Blueprint inputs allow you to pass configuration values to a blueprint installation. Inputs can be simple values or file references (useful for secrets or structured data).

```bash
# Set a single input
ryvn set blueprint-input <name> -e <env> --name api_url --value https://api.example.com

# Set multiple inputs in one command
ryvn set blueprint-input <name> -e <env> --name a --value x --name b --value y

# Set an input from a file (useful for secret references or structured YAML)
ryvn set blueprint-input <name> -e <env> --name api_key --file secret-ref.yaml

# Batch set inputs from a YAML file
ryvn set blueprint-input <name> -e <env> -f inputs.yaml

# Batch set inputs from stdin
cat inputs.yaml | ryvn set blueprint-input <name> -e <env> -f -

# Remove specific inputs
ryvn unset blueprint-input <name> -e <env> --name api_url
ryvn unset blueprint-input <name> -e <env> --name a --name b
```

### Blueprint Exclusions

Blueprint exclusions control auto-update behavior. When a blueprint is updated, all installations are normally updated automatically. Excluding an installation prevents it from receiving automatic updates, giving you manual control over when that installation is updated.

```bash
ryvn set blueprint-exclusion <name> -e <env> --installation redis-cache    # Disable auto-updates
ryvn unset blueprint-exclusion <name> -e <env> --installation redis-cache  # Re-enable auto-updates
```

### Unlink Blueprint Installation

Unlinking detaches an installation from its blueprint entirely. The resources remain but are no longer managed by the blueprint. This is irreversible.

```bash
ryvn unlink blueprint-installation --id <uuid>
```

## Connections

Connections represent external integrations configured at the org level. They provide credentials and configuration for third-party services.

```bash
ryvn get connection                                # List all connections
ryvn get connection --type infisical              # Filter by type: Infisical (secrets management)
ryvn get connection --type temporal               # Filter by type: Temporal (workflow orchestration)
```

Supported connection types: `infisical` (secrets management), `temporal` (workflow orchestration).

## Variable Groups

Variable groups are collections of environment variables and secrets that can be shared across services.

```bash
ryvn get variable-group                            # List all variable groups
```

## Release Channels

Release channels control which version of a service is deployed to each environment. They define the progression path for releases (e.g., dev -> staging -> production).

When a new release is pushed to a channel, all installations subscribed to that channel automatically deploy the new version. This is the primary mechanism for continuous deployment via CI/CD — see deploy.md for the GitHub Actions flow.

```bash
ryvn get release-channel                           # List all release channels
ryvn get release-channel stable -o yaml            # Read the current document
ryvn update release-channel stable -p '{"spec": {"isDefault": true}}'   # Make it the org default
```

## Promotion Pipelines

Promotion pipelines define the rules and stages for promoting releases across environments.

```bash
ryvn get promotion-pipeline                        # List all promotion pipelines
ryvn update promotion-pipeline <name> -p '...'     # Update pipeline configuration
```

## Maintenance Windows

Maintenance windows define scheduled periods during which deployments and updates are permitted.

```bash
ryvn get maintenance-window                        # List all maintenance windows
ryvn get maintenance-window weekend -o yaml        # Read the current document
ryvn update maintenance-window weekend -p '{"spec": {"timeZone": "UTC"}}'
ryvn update maintenance-window weekend --patch-file patch.yaml --dry-run   # Preview the merged document
```

A patch replaces `spec.intervals` wholesale, so send the full list when changing it:

```yaml
spec:
  intervals:
    - "Sat 00:00 - Mon 06:00"
```

## Previews

Preview deployments are ephemeral environments created for testing changes before they reach permanent environments.

```bash
ryvn get preview                                   # List all preview deployments
```

## GitOps Sync

The sync command triggers a reconciliation between your git repository and the Ryvn platform. This is useful when you want to force an immediate sync rather than waiting for the next automatic cycle.

```bash
ryvn sync import --all                             # Trigger full org sync, return immediately
ryvn sync import --all --wait                      # Trigger sync and wait for completion
ryvn sync import --all --wait --timeout 20m        # Wait longer than the 10m default
```

`--wait` (`-w`) is what makes the command block; `--timeout` (default 10m) and
`--poll-interval` (default 5s) only apply while waiting. Without `--wait` the command
returns as soon as the sync is queued.

## Workload Identity (keyless CI)

Workload issuers and federation bindings let CI jobs exchange a provider-issued OIDC token for a Ryvn credential — no static `RYVN_CLIENT_ID`/`RYVN_CLIENT_SECRET` on the workload. Issuers describe who can sign tokens; bindings map a token claim pin to a service user.

### Issuers

```bash
ryvn get workload-issuer                                     # registered issuers
ryvn get workload-issuer <issuer-id>                         # one issuer's full record
ryvn get workload-issuer-preset                              # provider catalog (github, gitlab-com, gcp, kubernetes, cursor, custom)
ryvn describe workload-issuer <issuer-url>                   # fetch JWKS URL + algorithms from the issuer's discovery doc
ryvn create workload-issuer --preset github                  # prefill a known provider, then print provider setup steps + job snippet
ryvn create workload-issuer <issuer-url> --jwks-url <url> --subject-keys sub --algorithms RS256
ryvn create workload-issuer <issuer-url> --jwks-static-file jwks.json   # issuer without a public JWKS endpoint
ryvn set workload-issuer <issuer-url> --enabled=false        # upsert by issuer URL; disabling stops its bindings working
ryvn delete workload-issuer <issuer-id>                      # refuses while bindings exist; --delete-bindings cascades
```

Useful flags on `create`/`set`: `--preset`, `--display-name`, `--jwks-url` (exclusive with `--jwks-static-file`), `--algorithms`, `--subject-keys`, `--run-claim`, `--max-token-age` (seconds), `--allow-token-reuse`, `--enabled`.

### Bindings

```bash
ryvn get workload-binding                                    # list bindings (id argument shows one as JSON)
ryvn create workload-binding --issuer <issuer-id> --subject-key repository_id --subject-value 123456 \
  --new-service-user ci-release                             # creates a dedicated service user with no default grants
ryvn create workload-binding --from-token $TOKEN --new-service-user ci-release   # decode a real token to prefill pin + policy
ryvn describe workload-binding <binding-id>                  # record + recent denial tail
ryvn describe workload-binding <binding-id> --from-token $TOKEN         # dry-run the policy against real claims
ryvn describe workload-binding <binding-id> --claims '{"repository_id":"123"}' --policy 'claims.repository_owner_id == "42"'
ryvn set workload-binding <binding-id> --policy 'claims.repository_owner_id == "42"'   # also --service-user, --subject-*, --enabled, --clear-policy
ryvn get workload-denials                                    # org-wide denial tail (incl. subject_not_registered rows)
ryvn delete workload-binding <binding-id>
```

`create` upserts on (issuer, subject-key, subject-value, service-user); exactly one of `--service-user` or `--new-service-user` is required. `create` and `set` also accept `--policy-file`; the `describe` dry-run takes the claims input (`--claims`, `--claims-file`, or `--from-token`) plus an optional `--policy` override.

### Service-user federation view

```bash
ryvn describe federation-credential <service-user>           # credential status, bindings, last exchange
ryvn delete federation-credential <service-user>             # revoke the machine key + credential now; bindings fail closed until re-enrolled
```

### Job-side token sources

The CLI picks up a workload token automatically: operator-set sources first (any of `RYVN_OIDC_TOKEN`/`RYVN_OIDC_TOKEN_FILE`/`RYVN_OIDC_TOKEN_ENV` — they're one tier, and setting more than one is an ambiguity error; `RYVN_OIDC_TOKEN_ENV` is the GitLab `id_tokens` shape), then ambient platform detection (GitHub Actions env, GCP metadata, Cursor agent socket, a Kubernetes projected token file). The GitHub source stays eligible whenever the Actions env is present — a job that granted `id-token: write` opted in, so it outranks static credentials and any other probe the host happens to expose (the GCE metadata server on GKE-hosted runners, a stray Cursor socket). The other ambient sources stay dormant when client credentials or a stored login exist; several detected sources without `RYVN_OIDC_SOURCE` is an error — set it to the intended one. `RYVN_SERVICE_USER`/`RYVN_BINDING_ID` select a target when more than one binding matches; `ryvn auth status` shows the source, issuer, and the binding the hub resolved (not just the requested selector).

## Troubleshooting

### Blueprint input not taking effect

Verify the input name exactly matches the blueprint's expected inputs. Use `ryvn describe blueprint <name>` to see the list of accepted inputs. Input names are case-sensitive. An input the installed version does not declare is stored but stays inactive, and setting it returns a warning naming it; it takes effect once a version that declares it is installed.

### Connection not found

Check the type filter matches an existing connection type. Use `ryvn get connection` without filters to list all connections and verify the connection exists in the current org.

### Sync failure

Check git repository connectivity and YAML syntax. Run `ryvn sync import --all` without `--wait` to see immediate errors. Common causes include invalid YAML in committed config files, missing repository access, or authentication issues with the git provider.

### Patch rejected

The error names every invalid path. Compare them against `ryvn get <kind> <name> -o yaml`, and check the patch wraps spec fields in `spec`. See Updating Resources above.
