import os
import sys
import urllib.parse


def required_env(name: str) -> str:
    v = os.environ.get(name, "")
    if not v:
        raise SystemExit(f"Missing required env var: {name}")
    return v


def main() -> int:
    base = required_env("GITLAB_URL").rstrip("/")
    push = required_env("GITLAB_PUSH_URL")
    project_path = required_env("GITLAB_PROJECT_PATH").strip("/")

    # If a full URL is provided, use it as-is.
    if "://" in push:
        if "@" not in push:
            raise SystemExit(
                "GITLAB_PUSH_URL looks like a URL without credentials. "
                "Set it to either the token only or a full URL like "
                "https://oauth2:<token>@host/group/project.git"
            )
        print(push)
        return 0

    # Otherwise treat it as a token and construct an authenticated HTTPS URL.
    u = urllib.parse.urlparse(base)
    if not u.scheme or not u.netloc:
        raise SystemExit("GITLAB_URL must include scheme+host, e.g. https://gitlab.example.com")

    prefix = u.path.rstrip("/")
    if prefix:
        repo_path = f"{prefix}/{project_path}.git"
    else:
        repo_path = f"/{project_path}.git"

    token = urllib.parse.quote(push, safe="")
    netloc = f"oauth2:{token}@{u.netloc}"
    remote = urllib.parse.urlunparse((u.scheme, netloc, repo_path, "", "", ""))
    print(remote)
    return 0


if __name__ == "__main__":
    sys.exit(main())
