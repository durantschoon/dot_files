# Language

Words this repository uses for its concepts. Each row is one replacement.
The term in **Use** is the one to write now. A later row may replace it again.

| Since | Commit | Use | Instead of | Why |
| --- | --- | --- | --- | --- |
| 2026-11-19 | `0ecf8836ef5184270404512b73676a2624b253f3` | `setup-native-links` | `set_up_links` | The old name did not say which of the two link paths it is, and it must not be run on a Guix machine, where guix home owns those files. Also the only underscore target among 117 hyphenated ones. `set_up_links` is removed, not aliased; it was last in place at `f841e8c29bb2223959ffb2be0a14f7efe821a96c`, so `git show f841e8c:Makefile` still shows the old target. |
| 2026-11-19 | `7e414bbdd1244961e93e626964c1a8d1c6a0ca57` | `probpush` | `pushprob` | Groups with `probpop` and `probtree` on the noun, so the three sort and tab-complete together; `pushprob` is removed, not aliased. |
| 2026-11-03 | `5e62c577bb428b81c067716f3a2deafcdb1241cb` | `check-ssh-with-gpg-for-egress` | `check-ssh` | The target only checks that gpg-agent is serving SSH keys, while outbound login uses the file key on minius, so `check-ssh` and `check-ssh-agent` are removed. |
| 2026-11-03 | `5e62c577bb428b81c067716f3a2deafcdb1241cb` | `check-sshd-for-ingress-tests` | `check-sshd-bootstrap` | `check-sshd-bootstrap` sounded like it started sshd, and the target only runs the unit tests. |
| 2026-11-03 | `5e62c577bb428b81c067716f3a2deafcdb1241cb` | `check-sshd-for-ingress` | `check-sshd` | This is the live incoming-server check that pairs with `setup-sshd-for-ingress`, so `check-sshd` is removed. |
| 2026-11-03 | `5e62c577bb428b81c067716f3a2deafcdb1241cb` | `setup-sshd-for-ingress` | `setup-sshd` | The old name was easy to read as the gpg-agent SSH client, and this target enables the incoming server, so `setup-sshd` is removed. |
| 2026-11-03 | `938d26c77733f367432d9f8ab3c9c30aca1e2553` | `HOMEBASE` | `HOME_BASE` | One name for the home-base host. `HOME_BASE` is no longer set. |
