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

Check if `teams/{team-name}.yml` already exists using the Glob tool. If it does, ask the user whether they want to update the existing config or choose a different name.

### Validate Team Name Against Infrastructure

After collecting the team name, verify it exists in your organisation's infrastructure. The exact approach depends on how your company manages team and repository ownership — common patterns include:

- A GitHub org management repo (e.g. `your-org/ops-github`) with a `teams/` folder
- An infrastructure-as-code repo with team definitions
- GitHub org teams queryable via `gh api orgs/{org}/teams/{team-slug}`

Try to look the team up using whatever approach is configured for your organisation:

```bash
gh api orgs/{your-org}/teams/{team-name} 2>/dev/null
```

**Outcome handling:**
- If the team is found: confirm to the user and continue.
- If the team is NOT found: inform the user, list any similar names if possible, and ask if they want to proceed anyway or try a different name.
- If validation tooling is unavailable: skip validation and inform the user.

## Step 2: Collect Team Summary

Use AskUserQuestion to ask for a brief description of what the team owns. Offer:
- Option 1: "Type a summary" — description: "Type a 1-2 sentence summary via 'Other' below"
- Option 2: "Skip for now"

## Step 3: Collect and Validate Confluence Space

Use AskUserQuestion with smart defaults based on the team name. Derive a likely space key by uppercasing the team name or using an abbreviation (e.g. "platform-infra" → "PLATINFRA"). Offer:
- Option 1: The derived key as a likely match
- Option 2: "Skip — add later"

The user can pick the suggestion, skip, or type their own key via "Other".

If the user doesn't skip, validate using:

```
mcp__confluence__list_confluence_spaces with space_key set to the provided key
```

- If the space exists: confirm to the user and continue
- If it doesn't exist: inform the user, offer to retry with a different key or skip
- If skipped: omit `confluence_space` from the YAML

## Step 4: Collect and Validate Jira Project

Use AskUserQuestion with the same derived key from Step 3 (Confluence and Jira keys are often the same). Offer:
- Option 1: The same key used for Confluence, or the derived abbreviation
- Option 2: "Skip — add later"

The user can pick the suggestion, skip, or type their own key via "Other".

If the user doesn't skip, validate using:

```
mcp__jira__search_jira_projects with query set to the provided key
```

- If the project exists: confirm to the user and continue
- If it doesn't exist: inform the user, offer to retry or skip
- If skipped: omit `jira_project` from the YAML

## Step 5: Collect and Validate GitHub Repositories

Ask the user for the repositories this team owns. If your organisation has an ops/team-management repo, attempt to read the team's repo list from it first and present it as a default.

If no repos are pre-discovered, use AskUserQuestion to ask:

> What GitHub repositories does your team own? Provide them in org/repo format, separated by commas or newlines.

Parse the input:
- Split by commas or newlines
- Trim whitespace
- Validate each entry contains exactly one `/`

For each repo, validate using `gh api repos/{org}/{repo}` (or `mcp__github__get_file_contents` as fallback).

- If all repos exist: confirm and continue
- If any don't exist: list the invalid repos, ask if the user wants to remove them, correct them, or proceed anyway (repos might not be created yet)

## Step 6: Collect and Validate Team Members

Ask the user for the team's GitHub usernames. If your organisation has a team-management repo or GitHub org teams, attempt to pre-populate the member list from there.

If no members are pre-discovered, use AskUserQuestion to ask:

> Who are the team members? Provide their GitHub usernames, separated by commas or newlines.

Parse the input:
- Split by commas or newlines
- Trim whitespace

For each username, validate using `gh api users/{username}` (or `mcp__github__search_users` as fallback).

- If all users are found: confirm and continue
- If any aren't found: list the invalid usernames, ask if the user wants to remove them, correct them, or proceed anyway

## Step 7: Collect External Dependencies (Optional)

Ask the user whether their team has external dependencies — either internal teams they need to be aware of or external third-party organisations they integrate with. Make clear this step is optional and can be skipped or added later by editing the YAML directly.

Use AskUserQuestion with:
- Option 1: "Yes, we have external dependencies to add"
- Option 2: "No, skip — I'll add them later if needed"

If the user selects "Yes", collect each dependency in a loop:

For each dependency:

1. Ask what type it is. Use AskUserQuestion with:
   - Option 1: "Internal team"
   - Option 2: "External organisation (3rd party)"

   Set `type` to `"internal"` or `"external"` accordingly.

2. Ask for the dependency name (team name or company/service name) via free-text ("Other" in AskUserQuestion). Use AskUserQuestion with:
   - Option 1: "Type the name"
   - Option 2: "Skip — no more dependencies"

   If the user selects "Skip", stop collecting dependencies and proceed.

3. Ask for a brief summary describing the nature of the dependency (e.g. "Consumes our Kafka topics for data pipelines", "Provides credit check API"). Use AskUserQuestion with:
   - Option 1: "Type a summary" — description: "Type a summary via 'Other' below"
   - Option 2: "Skip summary"

4. **For internal teams only** — optionally ask for relevant GitHub repositories owned by that team. Use AskUserQuestion with:
   - Option 1: "Add GitHub repos for this dependency"
   - Option 2: "Skip — no repos to add"

   If adding repos, ask for them in `org/repo` format (comma or newline separated).

5. After capturing the dependency, ask: Use AskUserQuestion with:
   - Option 1: "Add another dependency"
   - Option 2: "Done — no more dependencies"

Build up a list of dependencies. Each entry has:
- `name`: team or organisation name
- `type`: `internal` or `external`
- `summary`: description of the dependency relationship (omit if skipped)
- `github_repos`: list of relevant repos (internal only, omit if none provided)

## Step 8: Generate YAML Configuration

Write the team config file to `teams/{team-name}.yml` using the Write tool.

Use this format:

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

If `confluence_space` or `jira_project` was skipped, omit the field entirely rather than writing `null`.

If `github_repos` or `members` is empty, write an empty list: `github_repos: []`

If no external dependencies were collected, omit the `external_dependencies` field entirely.

For each external dependency entry:
- Omit `summary` if the user skipped it
- Omit `github_repos` if none were provided (or if `type` is `external`)

## Step 9: Customise README

Update `README.md` to reflect the team that was just onboarded. Use the Edit tool to make these changes:

1. **Replace the title** — Change `# Launchpad` to `# {Team Name} Launchpad` (title-cased team name)
2. **Replace the description line** — Update the description to reference the team name
3. **Remove the "Getting Started" section** — Delete template instructions that are no longer relevant once the team is set up

## Step 10: Remove Upstream CODEOWNERS

The repository ships with a `CODEOWNERS` file pointing to the upstream maintainer team, not this team. Remove it so it doesn't incorrectly assign code reviews:

```bash
rm -f CODEOWNERS
```

If the file did not exist (already removed), silently continue. Do not generate a new CODEOWNERS — the team can add their own later if they wish.

## Step 11: Confirm Success

Report to the user:
- The file path where the config was saved
- That the README was updated to reflect the team
- That the upstream `CODEOWNERS` file was removed (if it existed)
- A summary of what was configured, including any external dependencies added
- Remind them they can edit the YAML file directly for future changes

## Important Guidelines

- Be conversational — don't overwhelm the user with technical details
- Validate after each piece of input, not all at the end
- Never block the user from completing setup due to validation failures — warn but allow proceeding
- If an MCP tool is unavailable, skip validation for that field and inform the user
- When using AskUserQuestion, always provide at least 2 options — the tool requires a minimum of 2. An "Other" option for free-text input is added automatically by the tool, so don't include one yourself.
