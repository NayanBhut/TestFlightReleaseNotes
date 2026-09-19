#!/usr/bin/env python3
"""Call Ollama Cloud API to review a PR diff from a file."""

import json
import os
import sys
import urllib.request
import urllib.error


def main():
    model = os.environ.get("REVIEW_MODEL", "kimi-k3:cloud")
    diff_file = os.environ.get("PR_DIFF_FILE", "/tmp/pr_diff.txt")
    api_key = os.environ.get("OLLAMA_API_KEY", "")

    if not api_key:
        print("ERROR: OLLAMA_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(diff_file):
        print(f"ERROR: Diff file not found: {diff_file}", file=sys.stderr)
        sys.exit(1)

    with open(diff_file, "r", encoding="utf-8", errors="replace") as f:
        diff = f.read()

    if not diff.strip():
        print("ERROR: Diff file is empty", file=sys.stderr)
        sys.exit(1)

    system_msg = (
        "You are an expert iOS/Swift code reviewer. Review this PR diff carefully.\n\n"
        "For each finding, use this format:\n"
        "- **[BUG]** / **[IMPROVEMENT]** / **[BEST PRACTICE]** / **[SECURITY]** / **[PERFORMANCE]** / **[UI]**\n"
        "- Severity: **[CRITICAL]** / **[HIGH]** / **[MEDIUM]** / **[LOW]**\n"
        "- File: filename.swift (line N)\n"
        "- Description: Clear explanation\n"
        "- Suggestion: How to fix\n\n"
        "Categories:\n"
        "- BUG: Crashes, logic errors, memory leaks, threading issues\n"
        "- IMPROVEMENT: Could be done better but works\n"
        "- BEST PRACTICE: Coding standards, naming, structure\n"
        "- SECURITY: Vulnerabilities, unsafe code\n"
        "- PERFORMANCE: Slow code, unnecessary work\n"
        "- UI: Interface issues, accessibility\n\n"
        'If no issues found, say: "✅ No issues found. Great job!"'
    )

    # Limit diff size to avoid hitting token limits
    MAX_DIFF_SIZE = 200000
    if len(diff) > MAX_DIFF_SIZE:
        diff = diff[:MAX_DIFF_SIZE]

    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": f"Review this Swift/iOS PR diff:\n\n{diff}"},
        ],
        "stream": False,
        "options": {"temperature": 0.3, "num_predict": 8192},
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://ollama.com/v1/chat/completions",
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            print(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        print(f"HTTP_ERROR: {e.code}: {body}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"REQUEST_ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
