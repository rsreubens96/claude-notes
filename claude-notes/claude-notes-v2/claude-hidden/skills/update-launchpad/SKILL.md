---
name: update-launchpad
description: "Pull latest changes from the upstream launchpad repo into this team's copy. Handles upstream remote setup, protected files (teams/*.yml, teams/*.md, README.md, VERSION, CODEOWNERS, CHANGELOG.md), reviewable files (CLAUDE.md), and interactive conflict resolution. Use this skill whenever the user wants to update their launchpad copy, sync with upstream, pull latest launchpad changes, check for upstream updates, or says 'update launchpad', 'pull upstream', 'sync with upstream', 'get latest changes', or '/update-launchpad'. Also use when someone asks 'is my launchpad up to date?' or 'what's new in launchpad?'."
argument-hint: ""
---

# Update Launchpad

Sync this team's launchpad copy with the latest changes from the upstream launchpad repository. Protects team-specific files from being overwritten and pulls in new skills, fixes, and improvements.

## Background

Team launchpad repos are created independently from the upstream repo — they do NOT share git history. `git merge` will fail with "unrelated histories". Instead, this skill uses a **file-copy strategy**: checkout individual files from the upstream ref, skipping protected team files.

A `.last-upstream-sync` file tracks the last synced upstream commit SHA. A `.upstream-version` file tracks the upstream version last synced.

## Step 0: Upstream Guard

Check if this repo IS the upstream launchpad:

```bash
git remote get-url origin 2>/dev/null
```

If the origin URL is the upstream launchpad repo itself, stop and tell the user:

> This is the upstream launchpad repo — `/update-launchpad` is for syncing team copies with upstream. There's nothing to sync here since this IS the source.

## Step 1: Pre-flight Checks and Branch Setup

```bash
git status --porcelain
```

If there are uncommitted changes, stop and ask the user to commit or stash them first.

Then:

```bash
git checkout main
git pull
git checkout -b feature/sync-upstream-launchpad
```

All sync work happens on this feature branch.

## Step 2: Check/Add Upstream Remote

```bash
git remote get-url upstream 2>/dev/null
```

- **No upstream remote** — Ask the user for the upstream repo URL, then add it:
  ```bash
  git remote add upstream {upstream-url}
  ```
- **Upstream exists with expected URL** — Continue.
- **Upstream exists with different URL** — Use AskUserQuestion to update or keep.

## Step 3: Fetch Latest from Upstream

```bash
git fetch upstream main
```

If this fails, inform the user and stop.

## Step 4: Show What Changed

### Version Check

```bash
last_synced_version=$(cat .upstream-version 2>/dev/null || echo "unknown")
upstream_version=$(git show upstream/main:VERSION 2>/dev/null || echo "unknown")
```

Present the version comparison to the user.

### Commit-level Diff

Check for a previous sync marker:

```bash
if [ -f .last-upstream-sync ]; then
  last_sync=$(cat .last-upstream-sync)
  git cat-file -t "$last_sync" 2>/dev/null | grep -q commit && echo "LAST_SYNC:$last_sync" || echo "LAST_SYNC:none"
else
  echo "LAST_SYNC:none"
fi
```

**If a previous sync exists**, show new commits and changed files:
```bash
git log --oneline $last_sync..upstream/main
git diff --stat $last_sync..upstream/main
git diff --name-status $last_sync..upstream/main -- .claude/skills/
```

If no new commits, tell the user they're already up to date and clean up the branch.

**If first sync**, show total upstream commits and all upstream files.

Then use AskUserQuestion: "Proceed with sync" or "Cancel".

## Step 5: Identify Protected and Reviewable Files

**Always protected** (never overwritten):
- `teams/*.yml` — team configuration files
- `teams/*.md` — team-specific conventions
- `README.md` — team-customised readme
- `VERSION` — team-owned version number
- `CODEOWNERS` — team-specific code ownership
- `CHANGELOG.md` — team-specific changes

**Reviewable** (offer to merge):
- `CLAUDE.md` — upstream may add useful content but teams may have local customizations
- `.github/copilot-instructions.md`
- `.github/instructions/version-and-changelog.instructions.md`

## Step 6: Copy Files from Upstream

```bash
git ls-tree -r --name-only upstream/main
```

For each file:
1. **Protected** → Skip, tell user it was preserved
2. **Reviewable** → Set aside for Step 7
3. **Everything else** → Copy: `git checkout upstream/main -- <path>`
4. **`CODEOWNERS`** → Never copy, even if it doesn't exist locally
5. **`CHANGELOG.md`** → Never copy, even if it doesn't exist locally

Stage all changes: `git add -A`

## Step 7: Review Customisable Files

For each reviewable file that exists both locally and in upstream:

```bash
git diff HEAD:<file> upstream/main:<file>
```

Summarize changes in plain language. Use AskUserQuestion:
- "Take upstream version"
- "Keep my current version"
- "Show me the full diff first"

Copy and stage if the user takes the upstream version.

## Step 8: Update Sync Marker and Commit

```bash
git log -1 --format='%H' upstream/main > .last-upstream-sync
git show upstream/main:VERSION > .upstream-version
git add .last-upstream-sync .upstream-version
```

Check for staged changes. If none, tell the user they're already in sync and clean up the branch.

Otherwise commit:

```bash
git commit -m "feat: Sync with upstream launchpad ($last_synced_version → $upstream_version)"
```

## Step 9: Push and Create PR

```bash
git push -u origin feature/sync-upstream-launchpad

gh pr create --repo {org}/{repo} --base main --head feature/sync-upstream-launchpad \
  --title "feat: Sync with upstream launchpad ($last_synced_version → $upstream_version)" \
  --body "## Summary
- Syncs latest changes from upstream launchpad ($last_synced_version → $upstream_version)
- [list key changes]

## Protected files (local versions kept)
- [list protected files preserved]
"
```

## Step 10: Summary

Report:
- PR URL
- Version jump (or "first sync")
- Number of upstream commits synced
- Key files updated
- Protected files preserved
- New skills added (highlight these)

## Important Guidelines

- **Always use a feature branch** — never merge directly to main
- **Clean working tree required** — never proceed with uncommitted changes
- **Team files are sacred** — `teams/*.yml`, `README.md`, `VERSION`, `CODEOWNERS` must never be overwritten
- **CLAUDE.md and `.github/` files are reviewable** — show the diff and let the user decide
- **Never use git merge** — always use the file-copy strategy (`git checkout upstream/main -- <path>`)
- **Sync markers track state** — `.last-upstream-sync` and `.upstream-version` enable meaningful diffs
- **Show before syncing** — always present what's coming before copying files
- **AskUserQuestion** — always provide at least 2 options
- **Never force push**
- **Be conversational** — summarize what matters, don't dump raw git output
