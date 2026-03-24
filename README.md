# Ryvn Skills

Agent skill for [Ryvn](https://ryvn.dev), following the [Agent Skills](https://agentskills.io) format.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/ryvn-technologies/skills/main/scripts/install.sh | bash
```

### Claude Code plugin marketplace

```
/plugin marketplace add ryvn-technologies/skills
/plugin install ryvn@ryvn-skills
```

## Skill surface

This repo ships one installable skill:

- [`use-ryvn`](plugins/ryvn/skills/use-ryvn/SKILL.md)

`use-ryvn` is route-first. Intent routing is defined in `SKILL.md`, and execution details are split into action-oriented references.

## Workflow coverage

`use-ryvn` covers:

- CLI installation and authentication
- Profile and service account management
- Environment provisioning and management
- Service installation deployment
- Blueprint and blueprint installation management
- Logs and monitoring
- Task approval and management
- Release channels and promotion pipelines
- GitOps synchronization
- Failure triage and recovery

## Repository structure

```text
skills/
├── plugins/ryvn/
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── hooks/
│   │   ├── hooks.json
│   │   └── auto-approve-cli.sh
│   └── skills/
│       └── use-ryvn/
│           ├── SKILL.md
│           └── references/
│               ├── setup.md
│               ├── deploy.md
│               ├── configure.md
│               └── operate.md
├── scripts/
│   └── install.sh
├── AGENTS.md
├── CLAUDE.md
└── README.md
```

## License

MIT
