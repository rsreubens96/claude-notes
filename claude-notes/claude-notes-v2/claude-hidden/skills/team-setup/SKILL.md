---
name: team-setup
description: "Onboard a new team into Launchpad by collecting and validating team information (Confluence space, Jira project, GitHub repos, members). Use when users say 'onboard team', 'add team', 'set up team', 'team setup', or '/team-setup'."
argument-hint: "[team-name (optional)]"
---

# Team Setup

Interactively onboard a new team into the Launchpad repository by collecting and validating their configuration.

## Step 1: Collect Team Name

If `$ARGUMENTS` contains a team name, use it. Otherwise, use AskUserQuestion to ask:

> What is your team's name?

Offer two options:
- Option 1: "List existing teams" — description: "Show team names already configured in this launchpad"
- Option 2: "Enter team name" — description: "Type your team name via 'Other' below"

If the user selects "List existing teams", list any existing files in `teams/` using the Glob tool and present those names.

Validation rules:
- Lowercase letters, numbers, hyphens only
- 3-50 characters
- No spaces or special characters

Check if `teams/{team-name}.yml` already exists. If it does, ask the user whether they want to update the existing config or choose a different name.

### Validate Team Name Against Infrastructure

After collecting the team name, verify it exists in your organisation's infrastructure. Adapt this to your company's approach — common options:

```bash
# Check GitHub org teams
gh api orgs/{your-org}/teams/{team-name} 2>/dev/null

# Or check an ops/team-management repo
gh api repos/{your-org}/ops/contents/teams/{team-name} 2>/dev/null
```

**Outcome handling:**
- If the team is found: confirm to the user and continue.
- If NOT found: inform the user, suggest similar names if possible, and ask if they want to proceed anyway.
- If validation tooling is unavailable: skip validation and inform the user.

## Step 2: Collect Team Summary

Use AskUserQuestion to ask for a brief description of what the team owns:
- Option 1: "Type a summary" — description: "Type a 1-2 sentence summary via 'Other' below"
- Option 2: "Skip for now"

## Step 3: Collect and Validate Confluence Space

Derive a likely space key from the team name (e.g. "platform-infra" → "PLATINFRA"). Use AskUserQuestion:
- Option 1: The derived key as a likely match
- Option 2: "Skip — add later"

If the user doesn't skip, validate using:
```
mcp__confluence__list_confluence_spaces with space_key set to the provided key
```

- If the space exists: confirm and continue
- If it doesn't exist: offer to retry or skip
- If skipped: omit `confluence_space` from the YAML

## Step 4: Collect and Validate Jira Project

Use AskUserQuestion with the same derived key from Step 3:
- Option 1: The same key used for Confluence
- Option 2: "Skip — add later"

If the user doesn't skip, validate using:
```
mcp__jira__search_jira_projects with query set to the provided key
```

- If the project exists: confirm and continue
- If it doesn't exist: offer to retry or skip

## Step 5: Collect and Validate GitHub Repositories

If your organisation has an ops/team-management repo, attempt to read the team's repo list from it first. Otherwise use AskUserQuestion to ask:

> What GitHub repositories does your team own? Provide them in org/repo format, separated by commas or newlines.

Parse the input (split by commas or newlines, trim whitespace, validate each entry contains exactly one `/`).

For each repo, validate using `gh api repos/{org}/{repo}`.

- If all repos exist: confirm and continue
- If any don't exist: list them, ask if the user wants to remove, correct, or proceed anyway

## Step 6: Collect and Validate Team Members

Ask for team members' GitHub usernames. If your organisation has a team-management repo, attempt to pre-populate from there. Otherwise use AskUserQuestion to ask:

> Who are the team members? Provide their GitHub usernames, separated by commas or newlines.

For each username, validate using `gh api users/{username}`.

- If all users are found: confirm and continue
- If any aren't found: list them, ask if the user wants to remove, correct, or proceed anyway

## Step 7: Collect External Dependencies (Optional)

Use AskUserQuestion:
- Option 1: "Yes, we have external dependencies to add"
- Option 2: "No, skip — I'll add them later if needed"

If yes, collect each dependency in a loop:

1. Ask type: "Internal team" or "External organisation (3rd party)"
2. Ask for name (or "Skip — no more dependencies")
3. Ask for a brief summary of the relationship
4. For internal teams only: optionally ask for relevant GitHub repos
5. Ask: "Add another dependency" or "Done — no more dependencies"

Each entry has:
- `name`: team or organisation name
- `type`: `internal` or `external`
- `summary`: description of the dependency relationship (omit if skipped)
- `github_repos`: list of relevant repos (internal only, omit if none provided)

## Step 8: Generate YAML Configuration

Write the team config file to `teams/{team-name}.yml`:

```yaml
name: {team-name}
summary: {team-summary}

confluence_space: {SPACEKEY}
jira_project: {PROJKEY}

github_repos:
  - {org/repo-1}
  - {org/repo-2}

members:
  - github_username: {username-1}
  - github_username: {username-2}

# Optional — external teams and organisations this team depends on
external_dependencies:
  - name: {team-or-org-name}
    type: internal
    summary: {description of dependency relationship}
    github_repos:
      - {org/repo}
  - name: {external-org-name}
    type: external
    summary: {description of dependency relationship}
```

Omit `confluence_space` or `jira_project` entirely if skipped. Omit `external_dependencies` if none were collected.

## Step 9: Customise README

Update `README.md` to reflect the team:
1. Replace the title with `# {Team Name} Launchpad`
2. Update the description line to reference the team name
3. Remove template "Getting Started" instructions that are no longer relevant

## Step 10: Remove Upstream CODEOWNERS

```bash
rm -f CODEOWNERS
```

The repo ships with a CODEOWNERS pointing to the upstream maintainer team. Remove it so it doesn't incorrectly assign reviews. The team can add their own later.

## Step 11: Confirm Success

Report to the user:
- The file path where the config was saved
- That the README was updated
- That CODEOWNERS was removed (if it existed)
- A summary of what was configured
- Remind them they can edit the YAML directly for future changes

## Important Guidelines

- Be conversational — don't overwhelm the user with technical details
- Validate after each piece of input, not all at the end
- Never block the user from completing setup due to validation failures — warn but allow proceeding
- If an MCP tool is unavailable, skip validation for that field and inform the user
- When using AskUserQuestion, always provide at least 2 options. An "Other" option for free-text input is added automatically.
