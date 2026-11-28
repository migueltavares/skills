# Prepare a repo for mig-merge

Read this only when the project's instructions have no `## Deploy` section. A repo with one has been prepared.

## Squash only

Check with `gh api repos/<owner>/<repo> --jq '{squash: .allow_squash_merge, merge: .allow_merge_commit, rebase: .allow_rebase_merge}'`. When merge commits or rebase are allowed, ask the user before changing the repo settings, since merge approval doesn't cover them. On a yes:

```bash
gh repo edit --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false \
  --squash-merge-commit-message pr-title-description
```

Without admin rights on the repo, say so and carry on. `--squash` on each merge gives the same result.

## Deploy section

Read the project's instructions: AGENTS.md, or CLAUDE.md when it holds the guidance instead of pointing to AGENTS.md. Work the deploy out:

- Run `gh workflow list --all` and read the deploy workflows in `.github/workflows/`. Note how each one starts: on push to the default branch, after another workflow finishes (`workflow_run`, usually CI), by hand (`workflow_dispatch`), or on a release tag. Note any `paths-ignore` or `paths` filter. A workflow marked disabled deploys nothing.
- A hosting platform that deploys on push (Forge, Ploi, Vercel, Netlify, a PaaS) means the platform deploys. Look for its API or CLI. Ask the user for a read-only token with the host's secret tool (`request_secret` in T3 Code), and write the status command into the section, so later runs check the deploy themselves instead of asking the user.
- Nothing of the above means a manual deploy. Ask the user where they run it (a server alias, never a secret), the directory, the command, and how they know it worked.
- A repo that ships nothing on merge (a library, a docs or skills repo) gets `Method: none`. Confirm it with the user before writing it.

Then write the section into the file that owns the guidance, never into both. When neither file exists, create AGENTS.md, plus a CLAUDE.md that holds only `@AGENTS.md`.

```markdown
## Deploy

- Trigger: merge to `main`. Pushes that change only <paths> deploy nothing.
- Method: GitHub Actions, workflow `deploy.yml`.
  (Or: Platform, <name>, status with `<command>`. Or: Manual, on <server>, run `cd <dir> && ./deploy.sh`.)
- Starts: on push. (Or: after the CI workflow `ci.yml` passes on `main`. Or: by hand, `gh workflow run deploy.yml --ref main`. Or: on a release tag, `<command>`.)
- Environment: production, <URL>.
- Healthy when: the workflow run succeeds, and <URL> returns 200.
```

The edit goes in a small docs PR. Ask the user whether to add it to the end of this run. A yes approves merging that docs PR in this run too.
