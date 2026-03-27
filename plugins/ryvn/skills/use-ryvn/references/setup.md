# Ryvn CLI Setup and Authentication

## Installation

Install the Ryvn CLI using the install script:

```bash
curl -fsSL https://ryvn.ai/install.sh | bash
```

This detects your OS and architecture, downloads the latest release, and adds `ryvn` to your PATH.

To update to the latest version:

```bash
ryvn upgrade
```

Always upgrade before reporting bugs or requesting features to ensure you are on the latest version.

## Authentication

Ryvn uses a device authorization flow for interactive login. This opens a browser where you complete authentication, then the CLI receives credentials automatically.

```bash
ryvn auth login                           # Interactive device auth flow (default profile)
ryvn auth login --profile staging         # Login to a specific profile
```

To clear credentials:

```bash
ryvn auth logout                          # Logout from the active profile
ryvn auth logout --profile staging        # Logout from a specific profile
```

**Why device auth?** The device flow avoids storing passwords locally and works well in headless/SSH environments where the browser can be on a different machine. The CLI displays a URL and code; you authenticate in any browser.

## Profile Management

Profiles allow you to maintain multiple identities -- different orgs, environments, or service accounts -- and switch between them without re-authenticating each time.

### Creating profiles

```bash
ryvn auth create profile <name>                                            # Create a new empty profile
ryvn auth create profile staging --api-url https://api.staging.ryvn.dev    # Custom API endpoint
ryvn auth create profile ci --client-id <id> --client-secret <secret>      # Service account profile
ryvn auth create profile staging --from production                         # Copy settings from an existing profile
```

Use `--api-url` when targeting non-production environments. Use `--client-id`/`--client-secret` for CI/CD profiles that authenticate as service accounts instead of users.

### Listing and switching profiles

```bash
ryvn auth get profile                    # List all profiles (active profile shown with *)
ryvn auth use profile <name>              # Switch the active profile
```

The active profile determines which credentials and API endpoint the CLI uses for all commands. Switching profiles is instant and does not require re-authentication.

### Inspecting and removing profiles

```bash
ryvn auth describe profile <name>         # Show profile details including token expiry
ryvn auth delete profile <name>           # Remove a profile (cannot delete the active profile)
```

Before deleting, switch to a different profile with `ryvn auth use profile`. This prevents accidentally leaving the CLI in a broken state with no active profile.

## Service Accounts (CI/CD)

Service accounts are non-interactive identities intended for automation. They authenticate with client credentials instead of the browser-based device flow.

```bash
ryvn auth create service-user <name>      # Create a service account (outputs client ID and secret)
ryvn auth create service-user ci-bot --use  # Create and immediately configure the CLI to use it
ryvn auth get service-user                # List all service users in the current org
```

After creating a service account, store the client ID and secret securely. They are only displayed once. Use them either in a profile (`ryvn auth create profile ci --client-id <id> --client-secret <secret>`) or via environment variables.

## Organization Management

Organizations are the top-level scope in Ryvn. If you belong to multiple organizations, you can list and switch between them without changing profiles.

```bash
ryvn auth get org                         # List organizations you belong to
ryvn auth use org <name-or-id>            # Switch the active organization (accepts slug, name, or UUID)
ryvn auth status                          # Show current authentication status (profile, org, token expiry)
```

To target a specific organization for a single command without switching, use the `--org` flag:

```bash
ryvn get environment --org other-org      # List environments in a different org
```

Organization context is stored per-profile. Switching orgs updates the active profile's org setting.

## Configuration Files

Ryvn uses three configuration layers, from highest to lowest priority:

| File | Purpose |
|---|---|
| `.ryvn/settings.yaml` | Per-project local overrides (checked into repo or gitignored) |
| `~/.ryvn/credentials.yaml` | Profile management, credentials, and active profile selection |
| `~/.ryvn/config.yaml` | Legacy config file (auto-migrated to credentials.yaml on first use) |

You should not need to edit these files directly. Use the `ryvn auth` commands to manage configuration.

## Environment Variables

Environment variables override profile settings. Use these in CI/CD pipelines or when you need temporary overrides without modifying profiles.

```
RYVN_API_URL              # API endpoint (overrides profile's api-url)
RYVN_AUTH_URL             # Auth endpoint (rarely needed)
RYVN_CLIENT_ID            # Service account client ID
RYVN_CLIENT_SECRET        # Service account secret
RYVN_ENVIRONMENT          # Default environment for commands that accept one
RYVN_ORG_ID               # Organization override (slug, name, or UUID)
```

When `RYVN_CLIENT_ID` and `RYVN_CLIENT_SECRET` are both set, the CLI uses client credentials authentication regardless of the active profile. This is the recommended approach for CI/CD pipelines where you do not want to persist profiles on disk.

## Resource Discovery

After authenticating, verify your setup and explore available resources:

```bash
ryvn api-resources                        # List all supported resource types and their aliases
ryvn get service                          # List all services in the current org
ryvn get environment                      # List all environments
ryvn get blueprint                        # List all blueprints
```

`ryvn api-resources` is useful for discovering the short aliases (e.g., `svc` for `service`, `env` for `environment`) that save typing in day-to-day use.

## Troubleshooting

### `ryvn upgrade` fails

`ryvn upgrade` does not work with Homebrew installations. If the upgrade fails, uninstall the Homebrew version and reinstall using the install script:

```bash
brew uninstall ryvn
brew untap ryvn-technologies/tap  # optional cleanup
curl -fsSL https://ryvn.ai/install.sh | bash
```

After reinstalling, `ryvn upgrade` will work for future updates.

### CLI not found after installation

The `ryvn` binary must be on your PATH. Verify with `which ryvn`. If missing, add the directory containing the binary to your shell's PATH in `~/.zshrc` or `~/.bashrc`, then restart your shell.

### "not authenticated" errors

Run `ryvn auth login` to authenticate. If you are already logged in but see this error, your token may have expired -- re-run `ryvn auth login` to refresh it.

### Commands target the wrong org or environment

Run `ryvn auth status` to see the active profile and organization. To fix:

- **Wrong profile**: `ryvn auth use profile <name>` to switch profiles.
- **Wrong org**: `ryvn auth use org <name-or-id>` to switch organizations within the current profile.
- **Verify**: `ryvn auth describe profile <name>` to confirm the profile points to the correct API endpoint and org.

### Token expired

Tokens expire periodically. Re-run `ryvn auth login` (or `ryvn auth login --profile <name>` for a specific profile) to obtain a fresh token. For service accounts, tokens are refreshed automatically using the client credentials.

### Legacy config auto-migration

If you previously used `~/.ryvn/config.yaml`, the CLI automatically migrates your settings to the profile-based `~/.ryvn/credentials.yaml` on first use. The old file is preserved but no longer read. If migration produces unexpected results, delete `~/.ryvn/credentials.yaml` and re-run `ryvn auth login` to start fresh.
