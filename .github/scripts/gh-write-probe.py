#!/usr/bin/env python3
"""Validate GitHub token write access by creating and deleting a probe comment.

A GET on the comments endpoint succeeds with read-only permissions, so this
script does a real write test: it posts a temporary probe comment and then
deletes it, proving the token really can write.

Exit codes:
  0 = write access confirmed (probe comment created and deleted)
  1 = write access denied or probe failed (error to stderr)

Environment variables (all required):
  GITHUB_TOKEN              Token to test
  GITHUB_REPOSITORY_OWNER   Repository owner
  GITHUB_REPOSITORY_NAME    Repository name
  PR_NUMBER                 Pull request number
"""

import json
import os
import sys
import urllib.error
import urllib.request

PROBE_BODY = "<!-- ollama-write-probe --> temporary CI write-permission probe"


def api(method, url, token, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status, resp.read().decode("utf-8")


def main():
    token = os.environ.get("GITHUB_TOKEN", "")
    owner = os.environ.get("GITHUB_REPOSITORY_OWNER", "")
    repo = os.environ.get("GITHUB_REPOSITORY_NAME", "")
    pr_number = os.environ.get("PR_NUMBER", "")

    if not all([token, owner, repo, pr_number]):
        print(
            "ERROR: GITHUB_TOKEN, GITHUB_REPOSITORY_OWNER, "
            "GITHUB_REPOSITORY_NAME and PR_NUMBER must be set",
            file=sys.stderr,
        )
        sys.exit(1)

    base = f"https://api.github.com/repos/{owner}/{repo}"
    comments_url = f"{base}/issues/{pr_number}/comments"

    # 1. Create the probe comment (requires pull-requests: write)
    try:
        status, body = api("POST", comments_url, token, {"body": PROBE_BODY})
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")[:500]
        print(
            f"CREATE_FAILED: HTTP {e.code} - token cannot post comments. "
            f"Ensure 'pull-requests: write' is in the job permissions. Detail: {detail}",
            file=sys.stderr,
        )
        sys.exit(1)
    except Exception as e:
        print(f"REQUEST_ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)

    if status != 201:
        print(f"CREATE_FAILED: unexpected HTTP {status}", file=sys.stderr)
        sys.exit(1)

    # 2. Delete the probe comment (clean up)
    comment_id = json.loads(body).get("id")
    try:
        del_status, _ = api("DELETE", f"{base}/issues/comments/{comment_id}", token)
    except Exception as e:
        print(
            f"CLEANUP_FAILED: probe comment {comment_id} could not be deleted: {e}",
            file=sys.stderr,
        )
        sys.exit(1)

    if del_status != 204:
        print(f"CLEANUP_FAILED: unexpected HTTP {del_status}", file=sys.stderr)
        sys.exit(1)

    print("ok")


if __name__ == "__main__":
    main()