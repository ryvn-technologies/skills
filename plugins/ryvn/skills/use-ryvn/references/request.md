# Request

How to find Ryvn documentation, schemas, and context beyond these skill references.

## Official documentation

Primary sources for authoritative Ryvn information:

- **LLM summary**: `https://ryvn.ai/docs/llms.txt`
- **Full LLM docs**: `https://ryvn.ai/docs/llms-full.txt`
- **Direct doc pages**: `https://ryvn.ai/docs/<path>`

Fetch official docs first for product behavior questions.

Common doc paths:

| Topic | Path |
|---|---|
| Quickstart | `quickstart` |
| How Ryvn works | `how-ryvn-works` |
| Environments | `guides/environments` |
| Services | `guides/services` |
| Installations | `guides/installations` |
| Ryvn agent | `guides/ryvn-agent` |
| Provisioning (GCP) | `provision/google-cloud` |
| Provisioning (AWS) | `provision/aws` |
| Provisioning (Azure) | `provision/azure` |
| Deploy from GitHub | `deploy/deploy-from-github` |
| Deploy from registry | `deploy/deploy-from-registry` |
| Service type comparison | `deploy/service-types/comparison` |
| Environment variables | `configure/environment-variables` |
| Blueprints | `configure/blueprints` |
| Previews | `configure/previews` |
| Release channels | `configure/release-channels` |
| Maintenance windows | `configure/maintenance-windows` |
| Health checks | `configure/health-checks` |
| Scaling | `configure/scaling` |
| Rollbacks | `configure/rollbacks` |
| Infrastructure as code | `configure/infrastructure-as-code` |
| Logs | `observability/logs` |
| Metrics | `observability/metrics` |
| Notifications | `observability/notifications` |
| Custom domains | `networking/custom-domains` |
| TLS certificates | `networking/tls-certificates` |
| Deployment approvals | `guides/deployment-approvals` |
| Drift protection | `guides/drift-protection` |
| CLI | `experimental/cli` |
| Agent skills | `experimental/agent-skills` |
| Docs MCP | `experimental/docs-mcp` |
| FAQ | `support/faq` |


## GitOps reference

Full resource specs and field-level documentation for YAML manifests. Use these when you need exact field names, types, defaults, or valid values for a resource kind.

Base path: `https://ryvn.ai/docs/iac/<path>`

| Resource | Path |
|---|---|
| Overview | `iac/overview` |
| Server service | `iac/services/server` |
| Job service | `iac/services/job` |
| Helm chart service | `iac/services/helm-chart` |
| Terraform service | `iac/services/terraform` |
| AWS environment | `iac/environments/aws` |
| GCP environment | `iac/environments/gcp` |
| Azure environment | `iac/environments/azure` |
| Server installation | `iac/installations/server` |
| Job installation | `iac/installations/job` |
| Helm chart installation | `iac/installations/helm-chart` |
| Terraform installation | `iac/installations/terraform` |
| Blueprint installation | `iac/installations/blueprint` |
| Template functions | `iac/installations/template-functions` |
| Blueprint | `iac/blueprint` |
| Preview | `iac/preview` |
| Release channel | `iac/release` |
| Maintenance window | `iac/maintenance-window` |
| Promotion pipeline | `iac/promotion-pipeline` |


## YAML schema

Ryvn publishes a JSON Schema for IDE validation and autocomplete of YAML resource files:

**URL**: `https://api.ryvn.app/v1/schemas/resources.json`

Add this directive to the top of any Ryvn YAML file for editor autocomplete and validation:

```yaml
# yaml-language-server: $schema=https://api.ryvn.app/v1/schemas/resources.json
```

The schema covers all resource kinds (Service, Environment, Blueprint, ServiceInstallation, BlueprintInstallation, Preview, PromotionPipeline, ReleaseChannel, MaintenanceWindow) and uses the `kind` field as a discriminator for automatic type detection.

When the user is working with Ryvn YAML files, suggest adding the schema directive. For VS Code, the user can also configure project-wide schema association in `.vscode/settings.json`:

```json
{
  "yaml.schemas": {
    "https://api.ryvn.app/v1/schemas/resources.json": "**/*.{yaml,yml}"
  }
}
```


## MCP documentation search

The `search_ryvn` MCP tool provides semantic search across all Ryvn documentation. Use it when the skill references and doc pages don't cover the user's question.

Available as `mcp__ryvn-docs__search_ryvn` or `mcp__ryvn__search_ryvn`.

If the MCP tool is not available, instruct the user to add the Ryvn docs MCP server to their `.mcp.json`:

```json
{
  "mcpServers": {
    "ryvn": {
      "type": "http",
      "url": "https://ryvn.ai/docs/mcp"
    }
  }
}
```

Use MCP search when:
- The skill references don't cover the user's question
- You need field-level detail for a specific resource type
- The user asks about a feature not in the routing table


## API reference

REST API for programmatic access (currently covers secrets management):

- **Base URL**: `https://api.ryvn.app`
- **Auth**: OAuth 2.0 client credentials via `https://auth.ryvn.app/oauth/v2/token`
- **API docs**: `https://ryvn.ai/docs/api-reference/introduction`
