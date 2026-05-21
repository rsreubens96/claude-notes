---
name: map-dependencies
description: "Discover service-to-service dependencies using observability tracing data, GitHub code search, and infrastructure/Helm configs. Use when users say 'map dependencies', 'find dependencies', 'service graph', 'what calls what', 'show me dependencies', or '/map-dependencies'."
argument-hint: "[team-name (optional)]"
---

# Map Dependencies

Discover service-to-service dependencies for a team by combining up to three data sources:

**Primary source (richest data, always start here):**
1. **Infrastructure/Helm configs** — Helm chart or IaC files contain `env` sections with all service URLs, database connections, message broker settings, and external API endpoints.

**Validation (confirms runtime traffic):**
2. **Observability tracing** — actual runtime traffic between services. Use for validation, not primary discovery.

**Supplementary (only when infra configs are insufficient):**
3. **GitHub code search** — hardcoded URLs, client imports, API references in source code.

## Strategy: Infra-First with Smart Escalation

After scanning infra configs, assess coverage:
- **Rich env sections found** → Skip GitHub code search, go straight to observability validation.
- **Minimal configs** → Fall back to GitHub code search for those specific services.

## Step 1: Load Team Config

If `$ARGUMENTS` contains a team name, use it. Otherwise:

1. Check how many team configs exist in `teams/`.
2. If **only one** exists, use it automatically.
3. If **multiple** exist, use AskUserQuestion to present them (always include a "Different team" option).
4. If **none** exist, suggest running `/team-setup` first.

Read `teams/{team-name}.yml` to get the team's `github_repos` list.

## Step 2: Discover Services from Infrastructure Configs

List the team's deployed services from your infrastructure config repository (Helm/Argo state, Terraform, or similar).

### 2a: Search by team name

```bash
gh api repos/{org}/{infra-repo}/contents/{env}/{team-name} --jq '.[].name'
```

Try multiple environment names (e.g. `prod/`, `production/`, `staging/`).

### 2b: Check org management repos

```bash
gh api repos/{org}/ops/contents/teams/{team-name} --jq '.[].name'
```

### 2c: Search by service/repo names

```bash
gh search code "{service-name}" --repo {org}/{infra-repo} --limit 5
```

### 2d: Check monorepos for sub-services

For repos not matched by name, check for multi-service indicators:
- `docker-compose.yml` — extract service names from `services:` keys
- Multiple subdirectories with `Dockerfile` — each is likely a separate deployable service

Search infra configs for each discovered sub-service name.

### 2e: Check for non-K8s deployments (Lambdas, etc.)

For repos not found in K8s infra, look for serverless indicators:
- `serverless.yml` / `serverless.ts` → Serverless Framework
- `template.yaml` → AWS SAM
- `cdk.json` → AWS CDK
- `*.tf` with `aws_lambda_function` → Terraform

Read the IaC config to extract env vars — same approach as Helm charts.

### 2f: Classify repos

- Not in infra, not a monorepo, not serverless → likely tooling/library, flag as "non-deployed"
- In infra but not in team's `github_repos` → flag as "missing from team config"

Present discovered services to the user and confirm before proceeding.

### 2g: Fetch service descriptions from READMEs

```bash
gh api repos/{org}/{repo}/readme --jq '.content' | base64 -d | head -20
```

Extract a one-line description per service (under 100 characters, explains what the service *does*).

## Step 3: Scan Infrastructure Configs for Service References

This is the **primary dependency discovery step**.

### 3a: Batch-read configs efficiently

```bash
for svc in service1 service2 service3; do
  echo "=== $svc ==="
  gh api repos/{org}/{infra-repo}/contents/{env}/{team-folder}/$svc/chart.yaml --jq '.content' | base64 -d
done
```

### 3b: Parse env config for dependencies

Look for:

- **HTTP service URLs** — env vars ending in `_URL`, `_URI`, `_BASE_URL`, `_DOMAIN`, or containing `Url`, `Uri`, `Service`
  - K8s internal: `http://{service-name}.{namespace}`
  - Internal DNS: `https://{service}.internal.yourcompany.com`

- **Database connections** — `DATABASE_URL`, `POSTGRES_SERVER`, `SQL_HOST`, `DATABASE_NAME`

- **Message broker config** — Kafka (`KAFKA_BROKERS`, `BOOTSTRAP_SERVERS`), SQS/SNS queue URLs, RabbitMQ broker URLs

  **CRITICAL — Trace event flows between services:**
  Don't just record "uses Kafka/SQS". Identify producers and consumers, match them via topic/queue names, and record as `called_by` entries with the appropriate protocol on the consumer side.

- **External/3rd party APIs** — any external service URLs or API keys

- **Object storage** — S3 bucket names, GCS buckets, Azure Blob config

### 3c: Assess coverage

If configs are rich → skip Step 4, go to Step 5. If sparse for some services → run Step 4 only for those.

### 3d: Identify inbound caller signals

Look for:
- Ingress config → service is externally routable
- WAF/rate-limit config → handles external HTTP traffic
- `APPLICATION_URL` / `BASE_URL` self-referencing env vars
- OAuth/OIDC config → authenticates external callers

Record these signals for Step 5d and `called_by` compilation.

## Step 4: Search GitHub Code for Service References (Conditional)

**Only run if infra configs were insufficient for some services.**

**IMPORTANT — rate limits:** GitHub code search has a strict rate limit (~30 req/min). Run searches **sequentially** with 2-3 second pauses. Never in parallel.

### 4a: Read dependency manifests first (no rate limit)

Check the repo language and read:
- Python: `pyproject.toml` / `requirements.txt`
- Go: `go.mod`
- Kotlin/Java: `build.gradle.kts`
- .NET: `*.csproj`
- TypeScript: `package.json`
- Also check `.env.example` for documented service URLs

### 4b: Targeted code search

Search sequentially for:
- Internal service URL patterns
- HTTP client instantiations
- Message broker/queue client patterns
- Database driver usage

## Step 5: Query Observability for Runtime Dependencies

If observability MCP tools are available, validate infra findings against real traffic. Skip if unavailable.

### 5a: Find service datasets

Use your observability tool's naming convention (e.g. `{service-name}.{namespace}`, `{env}-{service-name}`).

### 5b: Query downstream dependencies (outbound calls)

Query client-side spans, breaking down by target host/address. Use a 7-day time range.

### 5c: Query async dependencies (messaging)

Query for messaging spans to see which topics/queues the service produces to or consumes from.

### 5d: Validate inbound traffic (server spans)

For services identified in Step 3d, confirm active inbound traffic via server-side spans.

### 5e: Compare results

- In both infra and observability → confirmed active dependency
- In infra but NOT observability → may be unused/async/untraced. Flag for review.
- In observability but NOT infra → may be via shared library. Investigate.

## Step 6: Cross-Reference and Deduplicate

1. **Deduplicate** — same dependency from multiple sources → merge into one entry
2. **Identify owner teams** — check other teams' `github_repos` in `teams/*.yml`
3. **Flag discrepancies** — code but no observability → possibly dead code or async
4. **Flag inactive** — mark with `active: false` if disabled at runtime
5. **Classify protocols** — `http`, `grpc`, `kafka`, `sqs`, `sns`, `database`, `cache`, `s3`, `external`, `amqp`
6. **Build `called_by`** from all sources: infra ingress signals, messaging flows, other teams' YAML, observability server spans

Every service with public ingress/endpoint MUST have at least one `called_by` entry.

## Step 7: Present Results

Present a **high-level summary first**, grouped by cross-team dependency:

```
## Cross-Team Dependencies (External)

### Team: auth
| Dependency | Description | Protocol | Used By |
|---|---|---|---|
| identity-service | Manages user identity | http | checkout-api, mobile-api |
```

Then show inbound dependencies, databases, messaging, external/3rd-party separately.

Ask the user to review and confirm before saving.

## Step 8: Update Team YAML

Add or update `service_dependencies` in `teams/{team-name}.yml`:

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
        active: false
      - service: transaction-events
        protocol: kafka
    called_by:
      - service: checkout-api
        owner_team: checkout
        protocol: http
```

If `service_dependencies` already exists, show a diff and ask whether to merge or replace.

## Step 9: Summary

Report:
- Services analysed (deployed vs non-deployed)
- Dependencies discovered (by source)
- Cross-team dependencies (most important for planning)
- Services missing observability tracing
- File path where results were saved

## Important Guidelines

- **Infra configs are the gold mine** — start here, escalate to code search only if needed
- **Batch infra reads** — use shell loops to read multiple configs in one command
- **Observability validates, infra discovers** — not the other way around
- **Trace messaging flows end-to-end** — match producers to consumers via topic/queue names; record as `called_by` entries
- **Focus observability on critical services** — validate 3-5 high-traffic services for large teams
- **Prefer `gh` CLI** — faster and more reliable than MCP GitHub tools for file listing and search
- **Respect code search rate limits** — sequential only, never parallel
- **Use 7-day time range** for observability — captures steady-state traffic
- **Don't block on observability** — if unavailable, note it and move on
- **Flag but don't discard mismatches** — mark uncertain deps with `active: false`
- **Check monorepos for sub-services** — inspect for docker-compose or multiple Dockerfiles
- **Always map `called_by` for externally-facing services** — if a service has ingress, it must have `called_by` entries
- **Be conversational** — present findings incrementally
- **Never block the user** — if a source is unavailable, skip and note what was missed
