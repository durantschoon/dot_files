# Removed notes

These files were dropped because the checkout no longer follows them. To print
one as it was just before deletion:

```sh
git log -1 --diff-filter=D --format=%H -- PATH
git show <that-commit>^:PATH
```

`git checkout <that-commit>^ -- PATH` puts the file back in the worktree.

- `docs/archive/QUICK_START_DOCKER.md`
- `docs/archive/DOCKER_FULL_TIME_SETUP.md`
- `docs/archive/DOCKER_GUIX_DEBUG.md`
- `docs/archive/DEPLOY_TO_GUIX_SYSTEM.md`
- `docs/GUIX_MIGRATION_PLAN.md`
- `docs/GUIX_APPARMOR.md`
- `tmp-pop-os-apparmor-steps.sh`
