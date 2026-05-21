# Launchpad

## Purpose

This repository is a central launchpad for cross-service engineering work. It is NOT a code repository — it's a configuration and planning hub that contains team metadata and Claude Code skills for team-level operations.

## Repository Structure

- `teams/{team-name}.yml` — Team configuration files (Jira, Confluence, GitHub, members, service dependencies)
- `plans/current/` — Active implementation plans (committed, shared)
- `plans/archive/` — Completed plans (moved here when done)
- `workspaces/` — Local clones of external repos for `/work-on` (git-ignored, never committed)
- `.claude/skills/team-setup/` — Skill for onboarding new teams
- `.claude/skills/map-dependencies/` — Skill for discovering service-to-service dependencies
- `.claude/skills/work-on/` — Skill for setting up workspaces in external repos
- `.claude/skills/update-launchpad/` — Skill for syncing with upstream launchpad changes
- `VERSION` — Current version (semver). Must be bumped with every change.
- `.upstream-version` — Last synced upstream version (written by `/update-launchpad`, team copies only)
- `CLAUDE.md` — This file (operating instructions)

## How This Works

### Team Configs

Each team has a YAML file in `teams/` with this schema:

```yaml
name: team-name
summary: What this team owns (1-2 sentences)

confluence_space: SPACEKEY
jira_project: PROJKEY

github_repos:
  - org/repo-one
  - org/repo-two

members:
  - github_username: alice
  - github_username: bob

# Optional — external teams and organisations this team depends on
external_dependencies:
  - name: data-engineering
    type: internal
    summary: Consumes our Kafka topics for data pipelines
    github_repos:
      - your-org/data-engineering-jobs
  - name: Stripe
    type: external
    summary: Provides payment gateway API

# Optional — populated by /map-dependencies
service_dependencies:
  - service: repo-one
    calls:
      - service: fraud-detection
        owner_team: risk
        protocol: http
      - service: payments-db
        protocol: database
    called_by:
      - service: checkout-api
        owner_team: checkout
        protocol: http
```

### Available Skills

- `/team-setup` — Interactively onboard a new team (collects and validates info, generates YAML)
- `/map-dependencies` — Discover service-to-service dependencies using observability data, GitHub code search, and infrastructure configs
- `/work-on` — Clone an external repo to a local workspace, explore it, and start making changes
- `/update-launchpad` — Pull latest changes from upstream launchpad, preserving team-specific files

### Available MCP Tools

Configure whichever of these are relevant to your organisation:

- **Jira** (`mcp__jira__*`) — Search issues, get details, query projects
- **Confluence** (`mcp__confluence__*`) — Search pages, get content, list spaces
- **GitHub** (`mcp__github__*`) — Search code/repos/users, get file contents, list PRs/issues
- **Observability** — Query traces and service dependency data (e.g. Honeycomb, Datadog)

## Planning Workflows

### Research a Team's Current Work

1. Read `teams/{team-name}.yml`
2. Use Jira MCP tools to search their project for active issues
3. Use Confluence MCP tools to find recent documentation
4. Use GitHub MCP tools to check recent PRs across their repos

### Plan Cross-Team Work

1. Identify all teams involved
2. Read each team's YAML config
3. Map service dependencies:
   a. Check each team's `service_dependencies` in their YAML config (if populated)
   b. If dependencies are not mapped, run `/map-dependencies` for each team
   c. Use your observability tool to verify dependencies are current (traffic in last 7 days)
4. Check for related work in each team's Jira project
5. Find shared documentation in Confluence

### Map Service Dependencies

1. Read `teams/{team-name}.yml` for the target team
2. Run `/map-dependencies` to discover dependencies via infrastructure configs, GitHub code search, and observability traces
3. Cross-reference discovered dependencies with other team configs
4. For each external dependency, identify the owning team
5. Update team YAML with discovered `service_dependencies`

### Make Changes to External Repos

1. Identify the target repo and the change needed
2. Run `/work-on org/repo` to clone to `workspaces/`, branch, and explore
3. Make changes, commit, push, and raise a PR as needed
4. Workspace persists for follow-up work — run `/work-on` again to continue

### Onboard a New Team

Run `/team-setup` to collect and validate team information.

## Organisation Context

### GitHub Orgs

Update this section with your organisation's GitHub structure. For example:

- **your-org** — Primary org for deployable services
- **your-org-internal** — Libraries, tooling, and non-deployable code

The `github_repos` field in team configs accepts any `org/repo` format within your GitHub Enterprise.

To discover team ownership, check:
- **Infrastructure/Helm configs** — Often organised by team name under environment folders
- **Dockerfile labels** — Many Dockerfiles include `LABEL maintainer="teamname@yourcompany.com"`
- **GitHub org teams** — Query via `gh api orgs/{org}/teams/{team-slug}/repos`

### Service Ownership Discovery

Adapt these patterns to your infrastructure:

- **Helm/Kubernetes configs** — Look for value files organised by environment and team
- **Dockerfile labels** — `LABEL maintainer` indicates team ownership
- **GitHub team membership** — `gh api orgs/{org}/teams/{team-slug}/repos`

### Artifact Registry

If your organisation uses an internal artifact registry, document how to check published versions here. For example:

- **Maven metadata** — `curl https://your-registry/{group}/{artifact}/maven-metadata.xml`
- **Docker images** — `curl https://your-registry/docker/{image}/`

## Conventions

### Jira

- **Code changes require the right issue type** — Use the issue type appropriate for code changes (e.g. Story with acceptance criteria). Use Tasks for non-code work.
- **Create the ticket before committing** — Many repos use `{TICKET} - {type}: {description}` commit message format, so the ticket must exist first.
- **Confirm epic assignment with the user** — Don't assume the epic from plan files or other sources. Always ask.
- **Always include a description** — Jira may block transitions if the description is empty. Always provide a meaningful description when creating tickets.
- **Use real newlines in Jira text fields** — Never use `\n` escape sequences in `description` or `acceptance_criteria` strings. The MCP tool requires actual newline characters.
- **Workflow transitions may require intermediate steps** — Some Jira statuses can't be reached directly. If a transition fails, check available transitions first.

### Pull Requests

- **Always include a "Why" in the PR description** — Every PR description must explain *why* the change was made, not just what was changed.
- **Each PR links to exactly one ticket** — Don't combine multiple tickets into a single PR. One PR = one ticket.
- **Never force push** — Only safe git operations.
- **Prefer `gh` CLI for GitHub operations** — Use `gh pr create`, `gh pr view`, etc.
- **Reply to PR review comments after fixing** — When a code review comment is addressed, post a reply on the original comment explaining what was done.

### Branching

- **Branch naming convention**:
  - Bug fix → `fix/{short-description}`
  - New feature → `feature/{short-description}`
  - Improvement/refactor → `improve/{short-description}`

## Tooling Preferences

- **Opening workspaces in an IDE** — When the user asks to open a workspace in an IDE, use `which idea || which idea1` for IntelliJ and `which code` for VS Code to check what's available. Run the appropriate command with `workspaces/{repo-name}` as the path.
- **Do not chain Bash commands** — Use simple, single commands rather than chained commands. If a command needs a specific working directory, use flags like `git -C /path` instead of `cd`.

## Skill Evals

- **Keep eval definitions and output under the skill's own `evals/` folder** — Each skill stores its eval definitions and run output in `.claude/skills/{skill-name}/evals/`. Definitions are committed; run output is git-ignored.

## Versioning

This repo uses a `VERSION` file in the root directory containing a single semver string (e.g. `1.0.0`). **Every PR must bump the version and add a `CHANGELOG.md` entry** under a new `## [x.y.z] - YYYY-MM-DD` heading. Use standard semver rules:

- **Patch** (1.0.0 → 1.0.1) — Bug fixes, minor config changes, permission updates
- **Minor** (1.0.0 → 1.1.0) — New skills, new team configs, new features
- **Major** (1.0.0 → 2.0.0) — Breaking changes to CLAUDE.md conventions, skill interfaces, or team YAML schema

**In team copies, VERSION is team-owned** — teams bump it for their own changes just like upstream does. The upstream version is tracked separately in `.upstream-version`.

## Team Copy Customisations

Team copies can customise their launchpad while maintaining clean upstream syncs using protected files that are never overwritten during `/update-launchpad`.

### Protected Files

The following files are **never overwritten** during `/update-launchpad`:

- `teams/*.yml` — Team configurations
- `teams/*.md` — Team-specific conventions and documentation
- `README.md` — Team-specific readme
- `CODEOWNERS` — Team code ownership
- `CHANGELOG.md` — Team-specific changes
- `VERSION` — Team version (upstream version tracked in `.upstream-version`)

### Team Documentation Pattern

Create `teams/{team-name}.md` to document team-specific conventions that supplement or override upstream CLAUDE.md. Reference it at the top of your CLAUDE.md:

```markdown
**Team-specific conventions:** See [teams/my-team.md](teams/my-team.md) for team overrides.
```

### Changelog Approach

**Team copies** should track only their own changes in `CHANGELOG.md` and link to the upstream changelog for upstream changes.

## Operating Principles

1. **Team-level context** — This repo operates at team level, not individual repo level
2. **Read team configs first** — Always read relevant YAML before planning work
3. **Validate against live services** — Use MCP tools to verify references are current
4. **Cross-service awareness** — Consider dependencies between services when planning
5. **Keep configs simple** — YAML files are the source of truth, no complex tooling
6. **Do not chain Bash commands** — Use simple, single commands. Chained commands may not match permission patterns in settings.json.

## Parallel Work (Batch)

When spawning background worktree agents:

- **Broad permissions in settings.json are required** — Background agents inherit permissions from `.claude/settings.json`. Ensure `Bash(git:*)`, `Bash(gh:*)` wildcards are present so agents can run quality checks, commit, push, and create PRs autonomously.
- **Each worker creates its own ticket** — Workers can use MCP tools to create tickets. Tickets must have descriptions and acceptance criteria for development stories.
- **Worktree isolation** — Each worker gets an isolated copy of the repo.
- **External repos (`workspaces/`) — do NOT use `isolation: "worktree"`** — Instead, have each agent create its own `git worktree` within the target repo (e.g. `git worktree add /tmp/worker-1 feature/branch`).
- **Do not chain Bash commands** — Critical for background agents since they rely entirely on permission patterns.
