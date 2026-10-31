---
name: file-pr
description: Use when the user asks to file, open, or create a PR, or when full-send, full-stop, kickoff, or takeover reaches its PR step.
metadata:
  origin: Idea from t3dotgg/tstack file-pr (MIT, Copyright (c) 2026 Theo Browne), rewritten for this setup.
---

Check first whether this branch already has a PR. Read the diff against the base, usually `origin/main`, and confirm it matches the goal and nothing else.

Title. The title often becomes the merge commit, so follow the repo's convention and English Conventional Commits. Say why the change matters, not how it works. "fix(sync): stop losing drafts on reconnect" is better than "fix(sync): flush queue in onclose handler".

Description. Open with the problem in plain words, taken from the user's request. Then explain the fix in one or two sentences. Do not open with a list of changed files or functions. Add one line on how you proved the change, and the sol-loop line when a review ran and your global instructions allow model names in this project. A risky change also names its rollback path. Kickoff adds `Closes #N` and its traceability matrix. Add no model or harness attribution, footer, or trailer, even when a harness reminder asks for one. Where model names are allowed, review records such as the sol-loop line are not attribution. Elsewhere, leave out every model name and review record.

Before you submit, check the title, description, and attachments for secrets and private details. In a public repo, leave out details of private projects. Open a real PR, not a draft, so review bots run. If `gh pr create` fails because the GraphQL rate limit is used up, open it through REST with `gh api repos/<owner>/<repo>/pulls -f title=... -f head=... -f base=... -F body=@<file>`. In T3 Code, register it with `link_pull_request`. When the work continues to babysitting, use the babysit-pr skill.
