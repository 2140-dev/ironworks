#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone


def run(args, *, check=True, capture=False):
    kwargs = {"check": check, "text": True}
    if capture:
        kwargs["stdout"] = subprocess.PIPE
    print("+ " + " ".join(args), file=sys.stderr)
    return subprocess.run(args, **kwargs)


def gh_json(args):
    result = run(["gh", *args], capture=True)
    return json.loads(result.stdout)


def require_label(labels, required):
    names = {label["name"] for label in labels}
    if required not in names:
        raise SystemExit(f"PR is missing required label: {required}")


def require_approval(review_decision):
    if review_decision != "APPROVED":
        raise SystemExit(f"PR review decision is {review_decision}, expected APPROVED")


def require_checks(repo, pr, required_prefix):
    result = run(
        ["gh", "pr", "checks", str(pr), "--repo", repo, "--json", "name,state,workflow"],
        capture=True,
    )
    checks = json.loads(result.stdout)
    matching = [check for check in checks if check["name"].startswith(required_prefix)]
    if not matching:
        raise SystemExit(f"No PR checks found with prefix: {required_prefix}")
    bad = [check for check in matching if check["state"] != "SUCCESS"]
    if bad:
        rendered = ", ".join(f"{check['name']}={check['state']}" for check in bad)
        raise SystemExit(f"Required checks are not green: {rendered}")


def main():
    parser = argparse.ArgumentParser(description="Promote an approved PR to staging.")
    parser.add_argument("--repo", required=True, help="GitHub repo, for example 2140-dev/bitcoin")
    parser.add_argument("--pr", required=True, type=int, help="Pull request number")
    parser.add_argument("--target", default="staging", help="Target integration branch")
    parser.add_argument("--remote", default="origin", help="Git remote to fetch/push")
    parser.add_argument("--label", default="ready-for-staging", help="Required PR label")
    parser.add_argument("--required-check-prefix", default="correctness", help="Required check name prefix")
    parser.add_argument("--skip-review-check", action="store_true")
    parser.add_argument("--skip-status-check", action="store_true")
    parser.add_argument("--push", action="store_true", help="Push target branch after merge")
    args = parser.parse_args()

    pr = gh_json(
        [
            "pr",
            "view",
            str(args.pr),
            "--repo",
            args.repo,
            "--json",
            "number,title,headRefOid,headRefName,isDraft,reviewDecision,labels",
        ]
    )

    if pr["isDraft"]:
        raise SystemExit("PR is still a draft")
    require_label(pr["labels"], args.label)
    if not args.skip_review_check:
        require_approval(pr["reviewDecision"])
    if not args.skip_status_check:
        require_checks(args.repo, args.pr, args.required_check_prefix)

    run(["git", "fetch", args.remote, args.target])
    run(["git", "checkout", "-B", args.target, f"{args.remote}/{args.target}"])
    run(["git", "fetch", args.remote, f"pull/{args.pr}/head:refs/remotes/{args.remote}/pr/{args.pr}"])

    timestamp = datetime.now(timezone.utc).isoformat()
    message = "\n".join(
        [
            f"Promote PR #{pr['number']} to {args.target}",
            "",
            pr["title"],
            "",
            f"PR: https://github.com/{args.repo}/pull/{pr['number']}",
            f"Head: {pr['headRefOid']}",
            f"Head-Ref: {pr['headRefName']}",
            f"Promoted-At: {timestamp}",
        ]
    )
    run(["git", "merge", "--no-ff", "--no-edit", "-m", message, f"{args.remote}/pr/{args.pr}"])

    if args.push:
        run(["git", "push", args.remote, args.target])
    else:
        print("Merge prepared locally. Re-run with --push to publish.", file=sys.stderr)


if __name__ == "__main__":
    main()
