---
name: work-on
description: "Clone an external GitHub repo into an isolated workspace, create a named branch, explore the codebase, and prepare for changes — all while keeping launchpad team context available. ALWAYS use this skill when the user wants to work on, fix, change, or make a PR for any repository. Trigger on phrases like 'work on [repo]', 'fix in [repo]', 'change in [repo]', 'make a PR for [repo]', 'can you fix [something] in [repo]', 'take a look at [repo]', or '/work-on'. This skill handles workspace isolation, branch naming conventions, dirty workspace detection, and structured repo exploration that direct cloning would miss."
argument-hint: "[org/repo] [description of change (optional)]"
---

# Work On

Set up a local workspace for an external repo so you can make changes from within launchpad, with full access to team context (configs, MCP tools, dependencies).

## Step 1: Check for Plan Files

Before asking questions, check for plan context in this order:

1. **Check IDE context first** — If the user has a file open (indicated by `ide_opened_file` in the conversation), read it. If it's a plan file, use it.
2. **Check `$ARGUMENTS`** — If `$ARGUMENTS` references a plan (e.g. "this plan", "the plan"), or contains a path to a plan file, read it.
3. **Search plan directories** — Search `plans/**/*plan*.md` and `workspaces/*plan*.md` for plan files.
4. If a plan provides the repo and description, skip Steps 2 and 3 below and proceed directly to workspace setup.

## Step 2: Identify Target Repo

If `$ARGUMENTS` contains an `org/repo`, use it. Otherwise:

### Disambiguating "this repo" inside a launchpad

If `$ARGUMENTS` is vague (e.g. "this", "this repo", "the launchpad") and you are running inside a team's launchpad copy (not the upstream launchpad), you must determine the correct target:

- **Changes to shared launchpad files** (`.claude/skills/`, `.gitignore`, `CODEOWNERS`, root `CLAUDE.md` sections that came from upstream, `README.md` template content) should target the **upstream repo** — that's where these files are maintained, and changes flow down to team copies via `/update-launchpad`.
- **Changes to team-specific files** (`teams/*.yml`, team-customised `CLAUDE.md` or `README.md` content) should target the **team's own launchpad repo**.

Use AskUserQuestion to confirm:
- "Upstream launchpad (your-org/launchpad)" — for shared skills, configs, and templates
- "This team's launchpad ({org}/{repo})" — for team-specific files

### Standard repo selection

1. Read all team configs from `teams/*.yml` to collect `github_repos` lists.
2. If only one team config exists, use its repos. If multiple exist, use AskUserQuestion to ask which team's repos to show.
3. Present the repos as options via AskUserQuestion.
4. Validate the repo exists: `gh api repos/{org}/{repo}`

## Step 3: Understand the Change

If a description was provided in `$ARGUMENTS` or a plan file, use it. Otherwise, use AskUserQuestion to ask:

> What change do you want to make? Briefly describe the goal.

Determine the change type for branch naming:
- Bug fix → `fix/{short-description}`
- New feature → `feature/{short-description}`
- Improvement/refactor → `improve/{short-description}`

Use AskUserQuestion with options:
- "Bug fix"
- "Feature"
- "Improvement"

## Step 4: Set Up Workspace

**IMPORTANT: Always clone to `workspaces/`.** Even if the target repo appears to be the current launchpad repo or a local folder, always clone it fresh into `workspaces/{repo-name}`. This ensures changes are isolated, on a proper branch, and can be pushed/PR'd independently. Never edit files directly in the launchpad repo when `/work-on` is invoked.

The `workspaces/` directory exists in the repo root (its contents are git-ignored).

### Workspace layout

Each repo has a **primary clone** at `workspaces/{repo-name}`. When parallel work is needed on the same repo, git worktrees are created alongside it:

```
workspaces/
  repo-name/                        # primary clone (main worktree)
  repo-name--fix-validation-bug/    # worktree for a second task
  repo-name--feature-retry-logic/   # worktree for a third task
```

Worktree directories use the naming convention `{repo-name}--{type}-{short-description}` (double-dash separator).

### Decision flow

Check if `workspaces/{repo-name}` already exists. If it does:

1. Run `git -C workspaces/{repo-name} status` to check state.
2. Run `git -C workspaces/{repo-name} branch --show-current` to check which branch you're on.
3. Also check for existing worktrees: `git -C workspaces/{repo-name} worktree list`

**If the working tree is clean**, use AskUserQuestion:
- "Reuse existing clone (pull latest from main)"
- "Fresh clone (delete and re-clone)"

**If there are uncommitted changes**, warn the user about the in-progress work and use AskUserQuestion:
- "Start parallel worktree (keep existing work untouched)" ← **recommended**
- "Continue on current branch (add to existing changes)"
- "Stash changes and start fresh from main"

### Handling each choice

**Reuse existing clone (clean workspace):**
```
git -C workspaces/{repo-name} checkout main
git -C workspaces/{repo-name} pull
git -C workspaces/{repo-name} checkout -b {type}/{short-description}
```

**Fresh clone:**
```
rm -rf workspaces/{repo-name}
gh repo clone {org}/{repo} workspaces/{repo-name}
git -C workspaces/{repo-name} checkout -b {type}/{short-description}
```

**Start parallel worktree (dirty workspace):**
```
# Fetch latest main in the primary clone
git -C workspaces/{repo-name} fetch origin main

# Create a worktree branching from origin/main
git -C workspaces/{repo-name} worktree add ../{repo-name}--{type}-{short-description} -b {type}/{short-description} origin/main
```

After creating the worktree, use the worktree path (`workspaces/{repo-name}--{type}-{short-description}/`) for all subsequent file operations, git commands, and exploration in this session. The primary clone remains untouched.

**Continue on current branch (dirty workspace):**
```
# The new work will be on the same branch as existing changes
# Warn the user: new branch won't be based on main
current_branch=$(git -C workspaces/{repo-name} branch --show-current)
```
No new branch is created — work continues on the current branch. Only offer this when the new task is closely related to the in-progress work.

**Stash changes and start fresh from main (dirty workspace):**
```
git -C workspaces/{repo-name} stash push --include-untracked
git -C workspaces/{repo-name} checkout main
git -C workspaces/{repo-name} pull
git -C workspaces/{repo-name} checkout -b {type}/{short-description}
```
Note: the stash is preserved. Remind the user they can recover it with `git stash pop` later.

### First-time clone (no existing workspace)

```
gh repo clone {org}/{repo} workspaces/{repo-name}
git -C workspaces/{repo-name} checkout -b {type}/{short-description}
```

### Worktree cleanup

Worktrees persist across sessions so users can `/work-on` the same repo again to continue. When a worktree's branch has been merged (PR closed), it can be cleaned up:
```
git -C workspaces/{repo-name} worktree remove ../{repo-name}--{type}-{short-description}
```
Only clean up worktrees when the user explicitly asks, or when listing worktrees reveals stale entries (branches already merged).

## Step 5: Explore the Target Repo

Read key files using absolute paths under `workspaces/{repo-name}/`:

1. **CLAUDE.md** — If it exists, read it and follow its conventions for all subsequent work in this repo.
2. **README.md** — Understand what the project does and how it's structured.
3. **Build/test setup** — Check for and read whichever exists:
   - `Makefile`
   - `package.json` (scripts section)
   - `pyproject.toml`
   - `build.gradle.kts`
   - `go.mod`
   - `Dockerfile`
4. **Source files relevant to the change** — Based on the user's description, find and read the files that need modifying.

Report to the user:
- What conventions the repo follows (from CLAUDE.md/README)
- How to build and test
- Which files are relevant to the change
- Any dependencies or related services found in launchpad's `teams/*.yml`

The workspace is now ready. Continue working based on the user's instructions.

## Important Guidelines

- **Follow the target repo's conventions** — If it has a CLAUDE.md, those rules apply to all work in the workspace. If it has linting/formatting configs, use them.
- **Use absolute paths** — All file operations use `workspaces/{repo-name}/` paths. Claude Code's Read, Write, Edit, Glob, and Grep tools all work with absolute paths.
- **Launchpad context is always available** — You can read `teams/*.yml` at any time to check team ownership, service dependencies, Jira/Confluence references, or member lists.
- **Be conversational** — Don't overwhelm the user with technical details. Report what matters.
- **Workspace persists** — Users can `/work-on` the same repo again to continue where they left off. Don't delete the workspace unless the user asks.
- **Git operations use the workspace directory** — Use `git -C workspaces/{repo-name}` for commits, pushes, etc.
- **MCP fallbacks** — If an MCP tool is unavailable, skip that step and inform the user.
- **AskUserQuestion** — Always provide at least 2 options (the tool requires a minimum of 2). An "Other" option for free-text input is added automatically.
- **Always clone, never work in-place** — Even if the target repo is the launchpad repo itself, clone it to `workspaces/`. This ensures proper branch isolation and clean PRs. Never edit launchpad files directly when `/work-on` is invoked.
- **Upstream vs team launchpad** — When working on shared launchpad files, always target the upstream repo, not the team's copy. Changes to shared files in a team copy will be overwritten by the next `/update-launchpad`. Ask the user if the target is ambiguous.
- **Prefer `gh` CLI** — Use `gh` for all GitHub operations (clone, PR creation, API calls).
