## Upstream tag mirror (with custom patch)

This repository contains a GitHub Actions workflow that **mirrors the latest upstream version tag** into this repo, after applying a custom patch, and then **force-pushes the same tag name** here.

Workflow file: `./.github/workflows/sync-upstream-tags.yml`

### How it works

- **Schedule**: runs daily (and can be run manually with `workflow_dispatch`).
- **Tag selection**:
  - Reads all upstream tags, filters them with `UPSTREAM_TAG_REGEX`, and selects the **highest** tag using `sort -V`.
  - Compares it to the **highest local** tag matching the same regex.
  - Proceeds only if the upstream tag is strictly higher and not already present locally.
- **Mirroring**:
  - Fetches the upstream tag commit.
  - Downloads a patch (from a GitLab snippet URL) and applies it with `git apply`.
  - Creates one commit if the patch changed anything.
  - Creates the tag with the **same name** as upstream pointing at the patched commit.
  - **Force-pushes** that tag to this GitHub repo.

### Required GitHub secrets

Create these in **GitHub → Settings → Secrets and variables → Actions → Secrets**:

- **`UPSTREAM_URL`**: Upstream git remote URL. For private upstream you can embed credentials in the URL.
- **`PATCH_URL`**: URL to the raw patch content (GitLab snippet “raw” URL or GitLab API raw endpoint).  
  Store it as a secret because it can include a token/credentials.
- **`GIT_USER_NAME`**: Git author/committer name for the patch commit.
- **`GIT_USER_EMAIL`**: Git author/committer email for the patch commit.

### Optional GitHub variables

Create these in **GitHub → Settings → Secrets and variables → Actions → Variables**:

- **`UPSTREAM_TAG_REGEX`**: Regex used to decide which upstream tags are “version tags”.
  - Default used by the workflow: `^[0-9]+(\.[0-9]+){2}(-[0-9]+)?$`
  - Example for tags like `v1.2.3`: `^v?[0-9]+(\.[0-9]+){2}(-[0-9]+)?$`

Yes: **`UPSTREAM_TAG_REGEX` is a GitHub Actions _variable_ (`vars.*`), not a secret**.

### Creating / updating the patch

Create a patch that applies cleanly on top of the upstream tag you expect:

```bash
git fetch --tags upstream
git checkout --detach <upstream-tag>
# make your changes...
git add -A
git diff --cached --binary > custom.patch
```

Then upload `custom.patch` as a **GitLab snippet** (private) and copy its **raw** URL into the GitHub secret `PATCH_URL`.

### Notes / caveats

- **This workflow force-pushes tags.** If you care about immutability/signatures, consider using a different tag naming scheme (like `1.4.5-custom`) instead of overwriting upstream tag names.
- If the patch no longer applies cleanly, the workflow will fail and no tag will be pushed.

