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
  - Downloads a patch from GitLab using a **GitLab API raw URL** (snippet or **repository file**) and **`GITLAB_TOKEN`** in the `PRIVATE-TOKEN` header, then applies it with `git apply`.
  - Creates one commit if the patch changed anything.
  - Creates the tag with the **same name** as upstream pointing at the patched commit.
  - **Force-pushes** that tag to this GitHub repo.

### Required GitHub secrets

Create these in **GitHub → Settings → Secrets and variables → Actions → Secrets**:

- **`UPSTREAM_URL`**: Upstream git remote URL. For private upstream you can embed credentials in the URL.
- **`GITLAB_TOKEN`**: GitLab **project access token** (same project as the patch file or snippet). Used only as `PRIVATE-TOKEN` when downloading — **not** embedded in the URL.
- **`PATCH_RAW_URL`**: GitLab API URL to the **raw patch bytes** (no token in the URL). Either:
  - **Repository file** (recommended):  
    `https://<gitlab>/api/v4/projects/<PROJECT_ID>/repository/files/<URL_ENCODED_PATH>/raw?ref=<branch_or_tag>`  
    Example path encoding: `tools/custom.patch` → `tools%2Fcustom.patch`.
  - **Snippet**:  
    `https://<gitlab>/api/v4/projects/<PROJECT_ID>/snippets/<SNIPPET_ID>/raw`  
    (`PROJECT_ID` may be numeric or URL-encoded `group%2Fproject`.)
- **`GH_PAT`**: GitHub **Personal Access Token** (Classic with `repo` and `workflow` scopes, or Fine-grained with `Contents: write` and `Workflows: write`). This is strictly required because your patch modifies `.github/workflows/` files. The default `GITHUB_TOKEN` is hard-coded by GitHub to reject modifications to workflows.
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

Commit `custom.patch` to a branch in the GitLab project (or keep using a **project snippet**). Store the **API raw** URL (no token) in **`PATCH_RAW_URL`** — for a repo file, use the [Repository Files API](https://docs.gitlab.com/ee/api/repository_files.html#get-raw-file-from-repository) `.../repository/files/.../raw?ref=...` form. Use **`GITLAB_TOKEN`** for auth.

### Notes / caveats

- **This workflow force-pushes tags.** If you care about immutability/signatures, consider using a different tag naming scheme (like `1.4.5-custom`) instead of overwriting upstream tag names.
- If the patch no longer applies cleanly, the workflow will fail and no tag will be pushed.
- If `git apply` reports **“No valid patches in input”**, the downloaded body was usually **not** a raw unified diff (HTML sign-in page, JSON error, or wrong URL). **`PATCH_RAW_URL`** must be the GitLab **API** raw URL (snippet or repository file), not the HTML **/-/blob/** page. The file content must be the output of `git diff` / `git diff --cached`, not a binary or other format.

