# Ryvn Skills Plugin

Agent skill for [Ryvn](https://ryvn.dev), following the [Agent Skills](https://agentskills.io) format.

## Skill model

This plugin ships one Ryvn skill:

- `plugins/ryvn/skills/use-ryvn/SKILL.md`

`use-ryvn` is route-first. Routing rules and intent mapping live in `SKILL.md`.

## Reference loading pattern

1. Read `plugins/ryvn/skills/use-ryvn/SKILL.md`.
2. Choose the minimum reference set needed for the request.
3. For multi-step requests, load multiple references and compose one response.

References:

| Intent | Reference | Use for |
|---|---|---|
| Install, authenticate, configure profiles | `references/setup.md` | CLI installation, auth, profiles, service accounts, config files |
| Deploy environments or services | `references/deploy.md` | Environment provisioning, installation deployment, task approval, promotions |
| Manage resources and configuration | `references/configure.md` | Blueprints, connections, variable groups, release channels, GitOps sync |
| Monitor, debug, and recover | `references/operate.md` | Logs, task management, failure triage, provisioner daemon |

## Architecture

### CLI first

Use the Ryvn CLI for all operations.

- Command: `ryvn`
- Prefer `-o json` output where available.

### Configuration

- Primary config: `~/.ryvn/credentials.yaml` (profile-based)
- Legacy config: `~/.ryvn/config.yaml` (auto-migrated)
- Local overrides: `.ryvn/settings.yaml`

## Authoring guidance

When editing this plugin:

- Keep `SKILL.md` focused on routing, preflight, composition, and common operations.
- Keep references organized by information type (setup, deploy, configure, operate).
- Keep references action-oriented with reasoning. Explain why, not only what.
- Keep CLI behavior claims aligned with the Ryvn CLI source code.
- Bump `version` in `plugins/ryvn/.claude-plugin/plugin.json` in any PR that changes skill content.

## References

- https://code.claude.com/docs/en/skills
- https://code.claude.com/docs/en/plugins
- https://agentskills.io/specification
