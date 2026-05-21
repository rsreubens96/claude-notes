# Launchpad Repository Instructions

## What is this repository?

Launchpad is a configuration and planning hub for cross-service engineering work. It is **not an application code repository**. The primary file types are:

- YAML team configuration files (`teams/{team-name}.yml`)
- Markdown documentation (`CLAUDE.md`, `README.md`, plan files)
- Claude Code skill definitions (`.claude/skills/*/`)
- A `VERSION` file (plain text, single semver string)
- A `CHANGELOG.md` following Keep a Changelog format

## Versioning Requirements

**Every PR must bump the `VERSION` file.** This is a strict requirement. When reviewing PRs, verify:

1. **VERSION file is modified** — It must contain a single semver string with no trailing newline (e.g., `1.5.0`)
2. **README.md version badge matches (if present)** — Search for `img.shields.io/badge/version-` and ensure the version matches VERSION. If no badge exists, no change is required.
3. **CHANGELOG.md has a new entry** — The CHANGELOG must include a section for the new version with the change documented

**Semver bump rules:**
- **Patch** (1.0.0 → 1.0.1) — Bug fixes, minor config changes, permission updates
- **Minor** (1.0.0 → 1.1.0) — New skills, new team configs, new features
- **Major** (1.0.0 → 2.0.0) — Breaking changes to CLAUDE.md conventions, skill interfaces, or team YAML schema

## Pull Request Requirements

When reviewing PRs, check that:

1. **One PR maps to exactly one ticket** — Never combine multiple tickets in a single PR
2. **Commit messages follow a consistent format** — e.g. `{TICKET} - {type}: {description}`
3. **Branch names use the correct prefix:**
   - Bug fix: `fix/{short-description}`
   - New feature: `feature/{short-description}`
   - Improvement/refactor: `improve/{short-description}`
4. **No force pushes** — Only safe git operations (`git push`, never `--force` or `--force-with-lease`)

## Team YAML Schema

Team configuration files at `teams/{team-name}.yml` must follow this schema:

**Required fields:**
- `name` — Team identifier (kebab-case)
- `summary` — What the team owns (1-2 sentences)
- `github_repos` — List of `org/repo` strings
- `members` — List of objects with `github_username` field

**Optional fields:**
- `confluence_space` — Confluence space key
- `jira_project` — Jira project key
- `external_dependencies` — External teams and third-party services this team depends on
- `service_dependencies` — Service-to-service dependency graph (populated by `/map-dependencies` skill)

## Skill Structure Conventions

Claude Code skills are stored under `.claude/skills/{skill-name}/`. When reviewing changes to skills:

- **Eval definitions** must go under `.claude/skills/{skill-name}/evals/` (never top-level)
- Files: `evals.json`, `trigger-eval-set.json` (committed)
- Run output: `iteration-*/`, `optimization-log.txt` (gitignored)

## Files That Should Never Be Committed

- `workspaces/` — Local clones of external repos (entire directory is gitignored)
- `.DS_Store` files
- Skill eval run output (iteration directories and logs)

## Common Review Issues

Based on previous PRs, watch for:

- VERSION file has a trailing newline (should be removed — file should contain only the version string)
- README badge doesn't match VERSION after a bump (if a badge is present)
- CHANGELOG link references are missing (Keep a Changelog format uses `[1.0.0]: https://github.com/...` at the bottom)
- Team YAML files missing required fields
- Skill eval files created at the top level instead of under the skill's `evals/` folder
