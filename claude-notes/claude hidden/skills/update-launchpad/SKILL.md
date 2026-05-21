---
name: update-launchpad
description: "Pull latest changes from the upstream launchpad repo into this team's copy. Handles upstream remote setup, protected files (teams/*.yml, teams/*.md, README.md, VERSION, CODEOWNERS, CHANGELOG.md), reviewable files (CLAUDE.md), and interactive conflict resolution. Use this skill whenever the user wants to update their launchpad copy, sync with upstream, pull latest launchpad changes, check for upstream updates, or says 'update launchpad', 'pull upstream', 'sync with upstream', 'get latest changes', or '/update-launchpad'. Also use when someone asks 'is my launchpad up to date?' or 'what's new in launchpad?'."
argument-hint: ""
---

# Update Launchpad

Sync this team's launchpad copy with the latest changes from the upstream launchpad repository. This protects team-specific files (`teams/*.yml`, `teams/*.md`, `README.md`, `VERSION`, `CODEOWNERS`, `CHANGELOG.md`) from being overwritten, offers to review changes to `CLAUDE.md`, and pulls in new skills, fixes, and improvements.

## Background

Team launchpad repos are created independently from the upstream repo — they do NOT share git history. This means `git merge` will never work (it fails with "unrelated histories"). Instead, this skill uses a **file-copy strategy**: checkout individual files from the upstream ref, skipping protected team files.

A `.last-upstream-sync` file in the repo root tracks the last synced upstream commit SHA, enabling meaningful "what's new" diffs on subsequent syncs. A `.upstream-version` file tracks the upstream version that was last synced, so teams can quickly see how far behind they are without fetching.

## Step 0: Upstream Guard

Check if this repo IS the upstream launchpad:

```bash
git remote get-url origin 2>/dev/null
```

If the origin URL is the upstream launchpad repo itself (not a team copy), **stop** and tell the user:

> This is the upstream launchpad repo — `/update-launchpad` is for syncing team copies with upstream. There's nothing to sync here since this IS the source.

Do not proceed.

## Step 1: Pre-flight Checks and Branch Setup

Check the working tree is clean:

```bash
git status --porcelain
```

If there is any output (uncommitted changes), **stop** and tell the user:

> Your working tree has uncommitted changes. Please commit or stash them before updating from upstream — this avoids mixing upstream changes with your local work.

Do not proceed until the tree is clean.

Switch to main and create a feature branch:

```bash
git checkout main
git pull
git checkout -b feature/sync-upstream-launchpad
```

All upstream sync work happens on this feature branch — never merge directly to main.

## Step 2: Check/Add Upstream Remote

Check if the `upstream` remote exists:

```bash
git remote get-url upstream 2>/dev/null
```

Three outcomes:

- **No upstream remote** — Ask the user for the upstream URL, then add it:
  ```bash
  git remote add upstream {upstream-url}
  ```

- **Upstream exists with the expected URL** — Continue.

- **Upstream exists with a different URL** — Use AskUserQuestion:
  - "Update to the correct upstream URL"
  - "Keep current URL"

## Step 3: Fetch Latest from Upstream

```bash
git fetch upstream main
```

If this fails (network error, auth issue), inform the user and stop.

## Step 4: Show What Changed

### Version Check

Compare the last-synced upstream version against the current upstream version:

```bash
last_synced_version=$(cat .upstream-version 2>/dev/null || echo "unknown")
upstream_version=$(git show upstream/main:VERSION 2>/dev/null || echo "unknown")
echo "LAST_SYNCED:$last_synced_version"
echo "UPSTREAM:$upstream_version"
```

Present this to the user:

> **Version check:** Last synced upstream version: **{last_synced_version}**, current upstream: **{upstream_version}**.

If both versions are the same, note: "You're up to date with the latest upstream release — checking for any other changes."

If `last_synced_version` is "unknown" (first sync), note: "This is your first sync — no previous upstream version recorded."

### Commit-level Diff

Determine the baseline for comparison. Check if `.last-upstream-sync` exists and contains a valid commit:

```bash
if [ -f .last-upstream-sync ]; then
  last_sync=$(cat .last-upstream-sync)
  if git cat-file -t "$last_sync" 2>/dev/null | grep -q commit; then
    echo "LAST_SYNC:$last_sync"
  else
    echo "LAST_SYNC:none"
  fi
else
  echo "LAST_SYNC:none"
fi
```

### If a previous sync exists (LAST_SYNC is a valid SHA)

Show what changed since the last sync:

1. **New commits:**
   ```bash
   git log --oneline $last_sync..upstream/main
   ```

2. **Changed files:**
   ```bash
   git diff --stat $last_sync..upstream/main
   ```

3. **New skills:**
   ```bash
   git diff --name-status $last_sync..upstream/main -- .claude/skills/
   ```

If there are no new commits, tell the user they're already up to date and clean up the feature branch.

### If no previous sync (first time)

Show what upstream contains and tell the user: "This is the first sync — all non-protected upstream files will be copied in."

### Confirm

Present the summary and use AskUserQuestion:
- "Proceed with sync"
- "Cancel"

If cancelled, clean up and stop.

## Step 5: Identify Protected and Reviewable Files

**Always protected** (never overwritten):
- `teams/*.yml` — team configuration files with team-specific data
- `teams/*.md` — team-specific conventions and documentation
- `README.md` — team repos typically customise the title and description
- `VERSION` — team-owned version number; upstream version is tracked separately in `.upstream-version`
- `CODEOWNERS` — team-specific code ownership; upstream CODEOWNERS points to the wrong team
- `CHANGELOG.md` — team-specific changes; teams track their own changes, not upstream history

**Reviewable** (offer to merge):
- `CLAUDE.md` — root project instructions; upstream may add useful content but teams may have local customizations
- `.github/copilot-instructions.md` — upstream Copilot review rules may assume upstream conventions
- `.github/instructions/version-and-changelog.instructions.md` — same reason as above

## Step 6: Copy Files from Upstream

Get the full list of files in upstream:

```bash
git ls-tree -r --name-only upstream/main
```

For each file, determine the action:

1. **Protected file that exists locally** — **Skip**. Tell the user it was preserved.
2. **Reviewable file that exists locally** — **Set aside for review** in Step 7. Don't copy yet.
3. **Everything else** (skills, configs, settings, new files) — **Copy from upstream:**
   ```bash
   git checkout upstream/main -- <path>
   ```
4. **`CODEOWNERS`** is **never** copied from upstream, even if it doesn't exist locally.
5. **`CHANGELOG.md`** is **never** copied from upstream, even if it doesn't exist locally.

After copying, stage all changes:

```bash
git add -A
```

Tell the user which files were updated and which were preserved.

## Step 7: Review Customisable Files

For each reviewable file (`CLAUDE.md`, `.github/copilot-instructions.md`, `.github/instructions/version-and-changelog.instructions.md`), if it exists locally AND in upstream, show the user what differs:

```bash
git diff HEAD:<file> upstream/main:<file>
```

Summarize the changes in plain language. Then use AskUserQuestion:

- "Take upstream version"
- "Keep my current version"
- "Show me the full diff first"

If the user takes the upstream version, copy it in and stage it.

If any reviewable file does not exist locally but upstream has one, copy it through and note it.

## Step 8: Update Sync Marker and Commit

Record the upstream commit SHA and version:

```bash
git log -1 --format='%H' upstream/main > .last-upstream-sync
git show upstream/main:VERSION > .upstream-version
git add .last-upstream-sync .upstream-version
```

Check if there are any staged changes:

```bash
git diff --cached --stat
```

If there are no changes, tell the user and clean up the feature branch.

Otherwise, commit:

```bash
# If versions are known and different:
git commit -m "feat: Sync with upstream launchpad ($last_synced_version → $upstream_version)"

# If versions are the same or unknown:
git commit -m "feat: Sync with upstream launchpad"
```

## Step 9: Push and Create PR

Push the feature branch and create a PR:

```bash
git push -u origin feature/sync-upstream-launchpad
```

```bash
gh pr create --repo {org}/{repo} --base main --head feature/sync-upstream-launchpad \
  --title "feat: Sync with upstream launchpad ($last_synced_version → $upstream_version)" \
  --body "## Summary
- Syncs latest changes from upstream launchpad ($last_synced_version → $upstream_version)
- [list key changes: updated skills, new files, etc.]

## Protected files (local versions kept)
- [list protected files that were preserved]
"
```

If `gh pr create` fails, provide the user with the push command and a link to create the PR manually.

## Step 10: Summary

Report to the user:

- PR URL
- Version jump (e.g. "1.0.0 → 1.3.0") — or "first sync" if no previous marker
- Number of upstream commits synced
- Files updated (list key changes, excluding protected files)
- Protected files preserved
- New skills added from upstream (if any — highlight these)

## Important Guidelines

- **Always use a feature branch** — never merge directly to main; always create `feature/sync-upstream-launchpad`, push, and create a PR
- **Clean working tree is required** — never merge onto uncommitted changes
- **Team files are sacred** — `teams/*.yml`, `README.md`, `VERSION`, and `CODEOWNERS` contain team-specific content that must never be overwritten by upstream
- **CLAUDE.md and `.github/` instruction files are reviewable** — always show the diff and let the user decide whether to take upstream's version or keep theirs
- **New files from upstream are welcome** — only existing local files are protected or reviewed
- **Never use git merge** — team repos have unrelated histories; always use the file-copy strategy (`git checkout upstream/main -- <path>`)
- **Sync markers track state** — `.last-upstream-sync` stores the last synced upstream commit SHA, `.upstream-version` stores the last synced upstream version string
- **Show before syncing** — always present what's coming before copying files so the user can make an informed decision
- **Use `--repo`, `--base`, `--head` with `gh pr create`** — explicit flags are more reliable than relying on git remote inference
- **AskUserQuestion** — always provide at least 2 options (the tool requires a minimum of 2)
- **Never force push** — this skill only performs safe operations
- **Be conversational** — don't overwhelm with git output, summarize what matters
