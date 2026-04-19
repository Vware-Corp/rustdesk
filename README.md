## Upstream tag mirror (with custom patch)

This repository contains a GitHub Actions workflow that **mirrors the latest upstream version tag** into this repo, after applying a custom patch, and then **force-pushes the same tag name** here.

Workflow file: `./.github/workflows/sync-upstream-tags.yml`

### How it works

- **Schedule**: runs weekly (and can be run manually with `workflow_dispatch`).
- **Tag selection**:
  - Reads all upstream tags, filters them with a **fixed regex in the workflow** (semver-style like `1.4.6`, `1.2.3-2`), and selects the **highest** tag using `sort -V`.
  - Compares it to the **highest local** tag matching the same regex.
  - Proceeds only if the upstream tag is strictly higher and not already present locally.
- **Mirroring**:
  - Fetches the upstream tag commit.
  - Downloads a patch from a **GitLab project snippet** (API raw URL) using **`GITLAB_TOKEN`** in the `PRIVATE-TOKEN` header, then applies it with `git apply`.
  - Creates one commit if the patch changed anything.
  - Creates the tag with the **same name** as upstream pointing at the patched commit.
  - **Force-pushes** that tag to this GitHub repo.

### Required GitHub secrets

Create these in **GitHub → Settings → Secrets and variables → Actions → Secrets**:

- **`UPSTREAM_URL`**: Upstream git remote URL. For private upstream you can embed credentials in the URL.
- **`GITLAB_TOKEN`**: GitLab **project access token** (same project as the snippet). Used only as `PRIVATE-TOKEN` when downloading the snippet — **not** embedded in the URL.
- **`PATCH_SNIPPET_URL`**: GitLab API raw URL **without** token, for example:  
  `https://gitlab.com/api/v4/projects/<PROJECT_ID>/snippets/<SNIPPET_ID>/raw`  
  (Numeric `PROJECT_ID` or URL-encoded path like `group%2Fproject`.)
- **`GIT_USER_NAME`**: Git author/committer name for the patch commit.
- **`GIT_USER_EMAIL`**: Git author/committer email for the patch commit.

The version-tag filter is defined in `.github/workflows/sync-upstream-tags.yml` (`^[0-9]+(\.[0-9]+){2}(-[0-9]+)?$`). Repository variables are not used for it.

### Creating / updating the patch

Create a patch that applies cleanly on top of the upstream tag you expect:

```bash
git fetch --tags upstream
git checkout --detach <upstream-tag>
# make your changes...
git add -A
git diff --cached --binary > custom.patch
```

Then upload `custom.patch` as a **GitLab project snippet** (same project as the token). Store the API raw URL (no token) in the secret **`PATCH_SNIPPET_URL`**; use your existing **`GITLAB_TOKEN`** secret for auth.

### Notes / caveats

- **This workflow force-pushes tags.** If you care about immutability/signatures, consider using a different tag naming scheme (like `1.4.5-custom`) instead of overwriting upstream tag names.
- If the patch no longer applies cleanly, the workflow will fail and no tag will be pushed.
- If `git apply` reports **“No valid patches in input”**, the downloaded body was usually **not** a raw unified diff (HTML sign-in page, JSON error, or wrong snippet URL). **`PATCH_SNIPPET_URL`** should be the GitLab **API** raw URL, e.g. `https://<host>/api/v4/projects/<id>/snippets/<id>/raw`, and the snippet file content should be the output of `git diff` / `git diff --cached`, not a binary or other format.

