# Radicle: Identity Revisions, Delegate Quorum, and What a Peer Actually Holds

Learnings from adding a third delegate to the GIPS repo
(`rad:z3MNVqPxoKmHE2HUSA98RU8qaZdco`) across three machines — minius (the Mac,
`z6Mkish…`), framepop (Pop!_OS, `z6Mkwa72…`) and geeeks (Guix System,
`z6Mktjk4…`) — and from recovering commits that existed on exactly one disk.
Radicle 1.x, `rad` from the Guix profile.

---

## 1. `rad id update` PROPOSES; accepting is a separate step

### Symptom
`rad id update --delegate <did>` was run, reported no error, and changed
nothing. `rad inspect --identity` still showed the old delegate list on every
machine, and `rad id list` still showed three revisions, the newest three
months old.

### Root Cause
`rad id update`'s own help says *"Propose a new revision to the identity
document."* It creates a revision in state `active`. The identity document
does not change until the revision is **accepted**, which is `rad id accept`.
Reading only `rad inspect --identity` after an update makes a successful
proposal look like a total failure.

### Fix
Treat it as two steps, and inspect the revision rather than the document:

```sh
rad id update --repo "$RID" --title "..." --description "..." --delegate "$DID"
rad id list   --repo "$RID"          # find the new revision, note its state
rad id accept <REV> --repo "$RID"
rad sync --announce "$RID"
```

## 2. `threshold: 1` does NOT mean one delegate is enough

### Symptom
The identity doc said `"threshold": 1` and there were two delegates, so one
delegate's acceptance should have been sufficient. After the author-delegate
accepted, the revision was still `active`. Trying to accept again gave:

```
✗ Error: apply failed: delegate already accepted a sibling revision '96f91b9…'
```

which reads like a conflict but only means "your vote is already recorded".

### Root Cause
A change to the identity **document** needs quorum of the delegate set, and
that is not the same number as `threshold`. With two delegates, quorum is
both. `rad id show` is explicit about it where `rad id list` is not:

```
State    active        Quorum   no
✓ did:key:z6Mkish…  durant (you)
? did:key:z6Mkwa72…  durant
```

A `?` is a vote still missing. Note which machine holds that key: it decides
whether the job needs a reboot or just an ssh.

### Fix
Read `rad id show <REV>` for the tally before concluding anything. Expect one
acceptance per delegate, from the machine holding that delegate's key. A peer
cannot vote on its own admission, so the candidate machine is never one of
them.

## 3. No `--title`/`--description` means `$EDITOR`, which silently does nothing

### Symptom
A script running `rad id update --delegate <did>` over ssh, or from any
non-interactive shell, left no new revision behind at all. Re-running it as
`EDITOR=mg ./script.sh` worked.

### Root Cause
Without `--title` and `--description`, `rad id update` opens `$EDITOR` for the
proposal message. With no editor, no tty, or an editor that cannot start, the
command aborts before writing a revision — and a wrapper script that does not
check the result reports success.

### Fix
Always pass both in a script. Then no editor is needed, and it works over ssh
and in cron:

```sh
rad id update --repo "$RID" \
  --title "Add geeeks as a delegate" \
  --description "..." \
  --delegate "$DID"
```

## 4. `--repo <RID>` for `rad id`, but the RID is POSITIONAL for `rad sync`

### Symptom
`rad sync --announce --repo "$RID"` failed with a bare usage line.

### Root Cause
The flag is not uniform across subcommands. `rad id …` takes
`--repo <RID>` ("Specify the repository to operate on. Defaults to the current
repository"), so identity work needs no working copy at all. `rad sync` takes
the RID as a positional argument.

### Fix
```sh
rad id accept <REV> --repo "$RID"     # flag
rad sync --announce "$RID"            # positional
```
`--repo` is worth knowing: it means a delegate's vote can be cast over ssh
from a machine where the repo is not checked out, which avoided a dual-boot
reboot for the proposal half of this job.

## 5. Radicle storage is a bare git repo, so "is this commit in Radicle?" is answerable offline

### Symptom
Needed to know whether 15 commits that existed only in one working copy were
safe anywhere else, without trusting a sync to have happened.

### Root Cause / Mechanism
`~/.radicle/storage/<RID>` is an ordinary bare git repository. Each peer's
refs live under its own namespace:

```
refs/heads/main                                  canonical
refs/namespaces/<NID>/refs/heads/*               that peer's branches
refs/namespaces/<NID>/refs/tags/*                that peer's tags
refs/namespaces/<NID>/refs/rad/{id,root,sigrefs}
```

### Fix / Technique
No network, no `rad` command needed:

```sh
ST=~/.radicle/storage/<RID>
git -C "$ST" for-each-ref                      # every peer's refs
git -C "$ST" cat-file -e <sha>^{commit}        # is this commit in radicle at all?
git -C "$ST" rev-list --all | sort -u          # the whole object set
```

If a commit object is in storage, Radicle has it. This is how 0-of-15 was
established in seconds.

## 6. A peer can only hold what it published — local work is invisible to the network

### Symptom
A working copy's `main` was 16 commits ahead of that same peer's published
`main`, and none of the extra commits existed in any namespace, on any seed.

### Root Cause
Radicle publishes what you push to your namespace. `git commit` is not
`rad push`. The peer's namespace ref is the authority on what it published:

```
z6Mkwa72…/refs/heads/main = 3c0808d (Aug 15)   published
working copy main         = 6b87cad (Aug 16)   local only, 16 commits beyond
```

### Fix / Consequence
Treat `refs/namespaces/<NID>/refs/heads/<branch>` as the answer to "what has
that machine actually shared". A seed can only hold what some peer announced,
so commits absent from every namespace are absent from the network — no amount
of `rad sync --fetch` will produce them. Checking the namespace is a stronger
test than checking seeds.

## 7. Non-delegates can push their own namespace, just not canonical `main`

### Symptom
A non-delegate machine pushed seven annotated tags with
`git push rad 'refs/tags/archive/*:refs/tags/archive/*'`, which succeeded and
synced with three seeds — while canonical `refs/heads/main` stayed put.

### Root Cause
Any peer may write its **own** namespace; delegation governs the canonical
refs and the identity document. The push URL makes this explicit:

```
rad    rad://<RID>                  (fetch)
rad    rad://<RID>/<your NID>       (push)
```

### Fix / Consequence
This is the cheap way to get local-only work off a single disk without any
governance change: push it into your own namespace, under tags if it is an
archive. It is durable and seeded, and it cannot move anyone else's `main`.
Conversely, if a machine's work keeps arriving under someone else's NID, that
machine is not the one publishing it.

## 8. `rad self --nid` is deprecated

```
! Deprecated: The command/option `rad self --nid` is deprecated and will be
  removed. Please use `rad node status --only nid` instead.
```

The warning goes to stderr and the value still prints on stdout, so scripts
that redirect stderr keep working and give no hint they are about to break.
Prefer `rad node status --only nid`, falling back to the old form:

```sh
me="$(rad node status --only nid 2>/dev/null || rad self --nid 2>/dev/null || true)"
```

Note it prints a bare NID (`z6Mk…`), not a `did:key:` URI — a `case` pattern
matching `did:key:z6Mk…` will silently never fire.
