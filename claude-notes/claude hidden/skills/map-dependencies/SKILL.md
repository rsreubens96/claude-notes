---
name: map-dependencies
description: "Discover service-to-service dependencies using observability tracing data, GitHub code search, and infrastructure/Helm configs. Use when users say 'map dependencies', 'find dependencies', 'service graph', 'what calls what', 'show me dependencies', or '/map-dependencies'."
argument-hint: "[team-name (optional)]"
---

# Map Dependencies

Discover service-to-service dependencies for a team by combining up to three data sources:

**Primary source (richest data, always start here):**
1. **Infrastructure/Helm configs** — Helm chart or IaC files contain `env` sections with all service URLs, database connections, message broker settings, and external API endpoints. This is typically the single best source of dependency information.

**Validation (confirms runtime traffic):**
2. **Observability tracing** — actual runtime traffic between services, confirming which dependencies carry real production load. Use for validation, not primary discovery.

**Supplementary (only when infra configs are insufficient):**
3. **GitHub code search** — hardcoded URLs, client imports, API references in source code. Only needed when infra configs are sparse or missing.

## Strategy: Infra-First with Smart Escalation

Infrastructure configs are almost always sufficient on their own. After scanning them, assess coverage:
- **If configs had rich `env` sections** (URLs, DB connections, broker settings visible) → Skip GitHub code search, go straight to observability validation.
- **If configs were minimal** (just deployment settings, no env vars) → Fall back to GitHub code search for those specific services.

This avoids wasting time on GitHub code search rate limits when infra configs already have everything.

## Step 1: Load Team Config

If `$ARGUMENTS` contains a team name, use it. Otherwise:

1. Check how many team configs exist in `teams/`.
2. If **only one** exists, use it automatically — no need to confirm with the user.
3. If **multiple** exist, use AskUserQuestion to present them as options (always include a "Different team" option so the minimum of 2 options is met).
4. If **none** exist, inform the user and suggest running `/team-setup` first.

Read `teams/{team-name}.yml` to get the team's `github_repos` list.

## Step 2: Discover Services from Infrastructure Configs

List the team's deployed services from your infrastructure config repository (e.g. a Helm/Argo state repo, Terraform state, or similar). The folder name used for the team may NOT match the team YAML name — try multiple strategies.

### 2a: Search by team name

Try environment folders with the team name:
```bash
gh api repos/{org}/{infra-repo}/contents/{env}/{team-name} --jq '.[].name'
```

Note: Some environments use `prod/` and others use `production/` — check both if applicable.

### 2b: Check org management repos

Your organisation's ops/team-management repo may be a reliable source of team-to-repo mappings:
```bash
gh api repos/{org}/ops/contents/teams/{team-name} --jq '.[].name'
```

This can reveal repos not listed in the team YAML and help confirm which infra folder name the team uses.

### 2c: Search by service/repo names

If the team name doesn't match an infra folder, search for service names derived from `github_repos`:
```bash
gh search code "{service-name}" --repo {org}/{infra-repo} --limit 5
```

This finds which infra team folder contains the service, even if it's under a different name.

### 2d: Check monorepos for sub-services

Some repos deploy **multiple services** under names that differ from the repo name. For any repo in `github_repos` that was NOT matched to an infra service by repo name:

1. **List the repo root** to check for multi-service indicators:
   ```bash
   gh api repos/{org}/{repo}/contents/ --jq '.[].name'
   ```

2. **If `docker-compose.yml` exists**, read it and extract service names from the `services:` keys.

3. **If no docker-compose**, check for multiple subdirectories containing `Dockerfile` or `docker/` folders — each is likely a separate deployable service.

4. **Search infra configs for each discovered sub-service name.**

5. **Record the repo-to-service mapping** — note that multiple infra services originate from one repo. Each sub-service gets its own entry in the dependency map with `repo:` pointing to the parent repo.

### 2e: Check for non-K8s deployments (Lambdas, etc.)

Not all services run on Kubernetes. Some teams deploy services as AWS Lambdas or other serverless platforms. For repos in `github_repos` that are NOT found in K8s infra configs, check whether they're actually deployed as serverless services:

```bash
gh api repos/{org}/{repo}/contents/ --jq '.[].name'
```

Look for these files at the repo root:
- `serverless.yml` or `serverless.ts` → Serverless Framework
- `template.yaml` or `template.yml` → AWS SAM
- `cdk.json` → AWS CDK
- `*.tf` files containing `aws_lambda_function` → Terraform

If found, read the IaC config to extract dependencies — Lambda env vars contain the same service URLs, DB connections, and API endpoints as K8s Helm charts.

Lambda services should be included in the dependency map with `environment: lambda`.

### 2f: Classify repos as deployed vs non-deployed

Cross-reference discovered infra services, monorepo sub-services, and Lambda services with the team's `github_repos` list:
- Repos that don't appear in infra, aren't monorepos with sub-services, and aren't Lambda services are likely tooling, libraries, or config repos → flag as "non-deployed"
- Services in infra that DON'T appear in the team's `github_repos` → flag as "missing from team config" and suggest adding them

Present the discovered services to the user and ask them to confirm.

For large teams (15+ services), ask whether to map all services or focus on a subset.

### 2g: Fetch service descriptions from READMEs

For each confirmed service that has a known repo, fetch a one-line description:

```bash
gh api repos/{org}/{repo}/readme --jq '.content' | base64 -d | head -20
```

Extract a one-line description from each README. If the README is missing or unhelpful, infer a description from the service name, its infra config, and its language/framework. Keep descriptions to one concise sentence (under 100 characters) that explains what the service *does*, not how it's built.

## Step 3: Scan Infrastructure Configs for Service References

This is the **primary dependency discovery step**. Helm chart or IaC env sections typically contain every HTTP URL, database connection, message broker, and external API the service talks to.

### 3a: Batch-read chart/config files efficiently

For large teams, use shell loops to batch API calls:

```bash
for svc in service1 service2 service3; do
  echo "=== $svc ==="
  gh api repos/{org}/{infra-repo}/contents/{env}/{team-folder}/$svc/chart.yaml --jq '.content' | base64 -d
done
```

### 3b: Parse env config for dependencies

Look in the environment config section for:

- **HTTP service URLs** — Look for env vars ending in `_URL`, `_URI`, `_BASE_URL`, `_DOMAIN`, or containing `Url`, `Uri`, `Service`. Parse the hostname to identify the target service.
  - K8s internal: `http://{service-name}.{namespace}` → extract service and namespace
  - Internal DNS: `https://{service}.internal.yourcompany.com` → extract service name

- **Database connections** — Look for:
  - `POSTGRES_SERVER`, `SQL_HOST`, `DATABASE_SERVER`, `DATABASE_URL` → database host
  - `DATABASE_NAME`, `POSTGRES_DATABASE_NAME` → logical database name

- **Message broker configuration** — Look for:
  - Kafka: `KAFKA_BROKERS`, `BOOTSTRAP_SERVERS`, consumer/producer group IDs
  - SQS/SNS: queue URLs, topic ARNs
  - RabbitMQ/AMQP: broker URLs

  **CRITICAL — Trace event flows between services, not just "uses messaging":**
  Don't just record that a service "uses Kafka". Trace the actual event flow to capture `called_by` relationships:
  1. Identify which services are **producers** (write to topics/queues)
  2. Identify which services are **consumers** (read from topics/queues)
  3. Match producers to consumers using topic/queue name patterns
  4. Record each messaging connection as a `called_by` entry on the consumer with the appropriate protocol

- **External/3rd party services** — Look for any external API URLs or SDK keys (Stripe, Salesforce, Twilio, auth providers, etc.)

- **Object storage** — Look for S3 bucket names, GCS bucket names, Azure Blob config

### 3c: Assess infra config coverage

After scanning all configs, assess whether GitHub code search is needed:
- If most services had rich env sections with URLs → **Skip Step 4** (code search), go to Step 5 (observability)
- If some services had minimal configs → Run Step 4 only for those specific services

### 3d: Identify inbound caller signals

While scanning configs, also extract indicators that a service **receives** inbound traffic:

- **Ingress config** — indicates the service is externally routable
- **WAF / rate-limit config** — indicates the service handles HTTP traffic from outside the cluster
- **Self-referencing URL** — `APPLICATION_URL`, `BASE_URL` env vars pointing to the service itself
- **OAuth/OIDC config** — indicates the service authenticates external callers

For services with these signals, infer the primary caller from the service's purpose. Record inbound signals for each service — they will be used in observability validation and `called_by` compilation.

## Step 4: Search GitHub Code for Service References (Conditional)

**Only run this step if infra configs were insufficient for some services.**

**IMPORTANT — GitHub code search rate limits:** The code search API has a strict rate limit (~30 requests per minute). Do NOT launch parallel agents searching multiple repos simultaneously. Instead:

1. **Prefer the contents API for key files first** — reading `pyproject.toml`, `go.mod`, `build.gradle.kts`, `package.json`, and `.env.example` via `gh api repos/{org}/{repo}/contents/{path}` uses a different (higher) rate limit.
2. **Then use code search sequentially** with short pauses between queries.
3. **If rate limited**, fall back to the contents API to browse source directories and read specific files directly.

### 4a: Read dependency manifest files first (no rate limit issues)

For each repo, check the language via `gh api repos/{org}/{repo} --jq '.language'`, then read the appropriate dependency file:

**Python:** `pyproject.toml` or `requirements.txt` — look for `httpx`, `requests`, `aiohttp`, database drivers, cloud SDKs, message queue clients

**Go:** `go.mod` — look for database drivers, cloud SDKs, HTTP frameworks, message queue clients

**Kotlin/Java:** `build.gradle.kts` — look for database libs, Kafka/messaging clients, HTTP clients

**.NET/C#:** `*.csproj` — look for database drivers, cloud SDKs, messaging clients

**TypeScript:** `package.json` — look for HTTP clients, database drivers, cloud SDKs, messaging clients

Also read `.env.example` if it exists — these often document all external service URLs.

### 4b: Targeted code search (rate-limit aware)

Run searches **sequentially** with 2-3 second pauses between them. Search for:
- Internal service URL patterns (e.g. `.internal`, `.svc.cluster.local`, `api.yourcompany.com`)
- HTTP client instantiations
- Message broker/queue client patterns
- Database driver usage

For each match, extract:
- The target service or resource name
- The file where it was found
- The type of dependency (http-client, kafka-producer, kafka-consumer, sqs-consumer, database, etc.)

## Step 5: Query Observability for Runtime Dependencies

If observability MCP tools are available (e.g. Honeycomb, Datadog), query for actual traffic patterns to **validate** infra findings. This step confirms which dependencies carry real traffic but rarely discovers new ones. If observability MCP is not available, skip this step and note it in the output.

### 5a: Find the service's dataset/traces

Observability datasets are typically named after the service. Use whatever naming convention your organisation follows (e.g. `{service-name}.{namespace}`, `{service-name}`, or `{env}-{service-name}`).

### 5b: Query downstream dependencies (outbound calls)

Query for client-side spans to see what the service calls. Break down by target host/address to get a clean service-level aggregate.

Filter to the last 7 days to capture steady-state traffic.

### 5c: Query async dependencies (messaging)

Query for messaging spans to see which topics/queues the service produces to or consumes from.

### 5d: Validate inbound traffic (server spans)

For services identified as externally callable in Step 3d, confirm they receive active inbound traffic by querying server-side spans.

### 5e: Compare observability results with infra findings

For each validated service:
- **Present in both infra and observability** → Confirmed active dependency
- **In infra but NOT observability** → May be unused, async, or not traced. Flag for review.
- **In observability but NOT infra** → May be via a shared library or sidecar. Investigate.

## Step 6: Cross-Reference and Deduplicate

Merge results from all sources:

1. **Deduplicate** — The same dependency may appear in multiple sources. Merge into a single entry noting which sources confirmed it.
2. **Identify owner teams** — For each dependency, check if any other team's `github_repos` or YAML config contains that service.
3. **Flag discrepancies** — If a dependency appears in code/config but NOT in observability, it may be unused or async.
4. **Flag inactive dependencies** — If a dependency exists in code but evidence suggests it's disabled, mark with `active: false`.
5. **Classify protocols** — Categorise each dependency: `http`, `grpc`, `kafka`, `sqs`, `sns`, `database`, `cache`, `s3`, `external`, `amqp`.
6. **Build `called_by` from all sources** — For each service, compile inbound relationships from:
   a. Infra ingress/naming inference (Step 3d) — primary source for external callers
   b. Messaging producer→consumer flows (Step 3b) — record on the consumer side
   c. Other teams' YAML `calls` sections — read all files in `teams/` and check cross-references
   d. Observability server span validation (Step 5d) — confirms active inbound traffic

   Every service with an ingress or public endpoint MUST have at least one `called_by` entry. If the caller cannot be determined, add a `called_by` entry with `service: unknown`.

## Step 7: Present Results

For large teams, present a **high-level summary first** rather than per-service tables. Group by cross-team dependency:

```
## Cross-Team Dependencies (External)

### Team: payments
| Dependency | Description | Protocol | Used By |
|---|---|---|---|
| payment-gateway | Processes card payments | http | checkout-api, mobile-api |

### Team: auth
| Dependency | Description | Protocol | Used By |
|---|---|---|---|
| identity-service | Manages user identity and tokens | http | checkout-api, dashboard-api |
```

Then show:
- **Inbound Dependencies (who calls us)** — services that call this team's services
- Internal (intra-team) dependencies, databases, messaging, external/3rd-party in separate sections

Ask the user to review and confirm before saving.

## Step 8: Update Team YAML

Add or update the `service_dependencies` section in `teams/{team-name}.yml`:

```yaml
service_dependencies:
  - service: payment-api
    description: Processes card and bank transfer payments
    environment: production
    repo: org/payment-api
    calls:
      - service: fraud-service
        owner_team: risk
        protocol: http
      - service: payments-db
        protocol: database
      - service: legacy-gateway
        protocol: http
        description: Present in code but feature-flagged off
        active: false
      - service: transaction-events
        protocol: kafka
    called_by:
      - service: checkout-api
        owner_team: checkout
        protocol: http

  - service: checkout-api
    description: Handles customer checkout flow
    environment: production
    repo: org/checkout-api
    calls:
      - service: payment-api
        protocol: http
    called_by:
      - service: web-frontend
        protocol: http
        description: Customer-facing web app
```

Schema notes:
- `description` — one-line summary of what the service does (on top-level entries) or context about the relationship (on dependency entries)
- `environment` — where this service is deployed (production, staging, etc.)
- `repo` — the GitHub repo this service comes from
- `active` — set to `false` for dependencies that exist in code but are disabled at runtime
- Separate top-level service entries with a blank line for readability

If the team YAML already has a `service_dependencies` section, show a diff of what changed and ask the user whether to merge or replace.

## Step 9: Summary

Report to the user:
- How many services were analysed (deployed vs non-deployed)
- How many dependencies were discovered (by source)
- Which dependencies are cross-team (these are the ones that matter most for planning)
- Any services missing observability tracing (suggest adding instrumentation)
- The file path where results were saved
- Suggest re-running periodically to catch new dependencies as services evolve

## Important Guidelines

- **Infra configs are the gold mine** — env sections contain nearly all dependency information. Start here, and only escalate to GitHub code search if configs are sparse
- **Batch infra reads with shell loops** — For teams with many services, use `for svc in ...; do ... done` to read multiple configs in one command
- **Observability validates, infra discovers** — Position observability as confirmation of infra findings, not primary discovery
- **Trace messaging event flows, not just "uses Kafka/SQS"** — The most common mistake is listing a message broker as a generic dependency without tracing which services are connected via specific topics/queues. Match producers to consumers. Record these as `called_by` entries with the appropriate protocol on the consumer side
- **Focus observability on critical services** — For large teams, validate 3-5 high-traffic services rather than querying all of them
- **Prefer `gh` CLI over MCP GitHub tools** — It's faster and more reliable for file listing and code search
- **Filter out infrastructure services** — monitoring, alerting, and platform services are not team-owned services
- **Respect GitHub code search rate limits** — Only use code search when infra configs are insufficient. Run sequentially with pauses, never in parallel
- **Use 7-day time range for observability** — Captures steady-state traffic, not transient spikes
- **Don't block on observability** — If the MCP server isn't connected or a dataset doesn't exist, note it and move on
- **Flag but don't discard mismatches** — A dependency in code but not observability might be a feature flag, dead code, or async path. Mark with `active: false` if evidence suggests it's disabled
- **For large teams (15+ services), ask about scope** — Offer "all services", "core services only", or "pick specific" options before starting
- **Don't assume all services are K8s** — Some teams deploy Lambdas or other serverless services. Check unaccounted repos for IaC files and read their env configs
- **Present cross-team summary first** — Group by external team, not per-service. This is more useful for planning
- **Add a one-line description to every service** — Fetch from README first, infer from name/config if README is missing
- **Be conversational** — Present findings incrementally, don't dump everything at the end
- **Check monorepos for sub-services** — If a repo name isn't found in infra configs, inspect the repo for docker-compose or multiple Dockerfiles
- **Always map `called_by` for externally-facing services** — If a service has ingress or a public endpoint, it MUST have `called_by` entries
- **Never block the user** — If a source is unavailable, skip it and note what was missed
