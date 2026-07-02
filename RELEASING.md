# Releasing

The installer pins to a tagged release and verifies the script against a published
checksum, so a few identifiers must move together on every release. Do them in one
commit, then tag.

## Steps

1. **Bump the version** in the `statusline.sh` header (the `vX.Y.Z` on line 3).
2. **Update `CHANGELOG.md`** — move the pending notes under a new `## [X.Y.Z] — YYYY-MM-DD`
   heading.
3. **Regenerate `checksums.txt`** so it matches the script you're about to tag:

   ```sh
   shasum -a 256 statusline.sh > checksums.txt   # macOS/BSD
   # or: sha256sum statusline.sh > checksums.txt  # GNU/Linux
   ```

4. **Bump the installer default** — set `REF` in `install.sh` to the new tag
   (`REF="${MOUNTAINLABS_STATUSLINE_REF:-vX.Y.Z}"`).
5. **Verify green:** `tests/run.sh && tests/lint.sh`.
6. **Commit, then tag** the same commit:

   ```sh
   git commit -am "release: vX.Y.Z"
   git tag vX.Y.Z
   git push && git push --tags
   ```

Because the tag, CHANGELOG entry, script header, and checksum all land in that one
commit, a user who installs `vX.Y.Z` fetches `statusline.sh@vX.Y.Z` and verifies it
against `checksums.txt@vX.Y.Z` — no drift between them.

## Why the checksum matters

`install.sh` fetches `statusline.sh` and `checksums.txt` from the same pinned ref and
aborts if the script's SHA-256 doesn't match. A stale or hand-edited `checksums.txt`
would falsely abort a good install, so always regenerate it with the command above
rather than editing it by hand.

## Not automated (yet)

Signing (GPG/sigstore) and GitHub Actions release publishing are possible follow-ups
(#0008 non-goals). Today the release is manual but the integrity check is real.
