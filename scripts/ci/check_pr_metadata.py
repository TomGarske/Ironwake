#!/usr/bin/env python3
"""
Validates that a PR body contains the required sections defined in
.github/PULL_REQUEST_TEMPLATE.md.

Called by .github/workflows/adr-governance.yml.
Reads the PR body from the PR_BODY environment variable.
Exits with code 1 and a descriptive message if any required section is missing.
"""

import os
import sys

REQUIRED_SECTIONS = [
    "## Problem",
    "## Architecture Impact",
    "## Risks",
]

def main() -> None:
    pr_body = os.environ.get("PR_BODY", "")

    if not pr_body.strip():
        print("ERROR: PR body is empty. Please fill in the PR template.", file=sys.stderr)
        sys.exit(1)

    missing = [s for s in REQUIRED_SECTIONS if s not in pr_body]

    if missing:
        print("ERROR: PR is missing required sections:", file=sys.stderr)
        for section in missing:
            print(f"  - {section}", file=sys.stderr)
        print(
            "\nPlease fill in all sections from the PR template (.github/PULL_REQUEST_TEMPLATE.md).",
            file=sys.stderr,
        )
        sys.exit(1)

    print("PR metadata check passed. Required sections found:")
    for section in REQUIRED_SECTIONS:
        print(f"  {section}")

if __name__ == "__main__":
    main()
