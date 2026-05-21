---
applyTo: "VERSION"
---

# VERSION File Change Verification

When the `VERSION` file is modified in a PR, always verify:

1. **README.md badge is updated (if present)** — Search for the line containing `img.shields.io/badge/version-` and confirm the version number matches the new VERSION exactly. If no badge exists in the README, no change is required.
2. **CHANGELOG.md has an entry for the new version** — Look for a section like `## [X.Y.Z] - YYYY-MM-DD` matching the new version
3. **VERSION file format is correct** — Must contain only a single semver string with no trailing newline (e.g., `1.5.0` followed immediately by EOF)

These files (VERSION, README.md if it has a badge, CHANGELOG.md) must stay synchronized. If any are missing or inconsistent, flag it in the review.
