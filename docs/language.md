# Language

Words this repository uses for its concepts. Each row is one replacement.
The term in **Use** is the one to write now. A later row may replace it again.

| Since | Commit | Use | Instead of | Why |
| --- | --- | --- | --- | --- |
| 2026-11-03 | `5e62c577bb428b81c067716f3a2deafcdb1241cb` | `check-ssh-with-gpg-for-egress` | `check-ssh` | The target only checks that gpg-agent is serving SSH keys, while outbound login uses the file key on minius, so `check-ssh` and `check-ssh-agent` are removed. |
| 2026-11-03 | `5e62c577bb428b81c067716f3a2deafcdb1241cb` | `check-sshd-for-ingress-tests` | `check-sshd-bootstrap` | `check-sshd-bootstrap` sounded like it started sshd, and the target only runs the unit tests. |
| 2026-11-03 | `5e62c577bb428b81c067716f3a2deafcdb1241cb` | `check-sshd-for-ingress` | `check-sshd` | This is the live incoming-server check that pairs with `setup-sshd-for-ingress`, so `check-sshd` is removed. |
| 2026-11-03 | `5e62c577bb428b81c067716f3a2deafcdb1241cb` | `setup-sshd-for-ingress` | `setup-sshd` | The old name was easy to read as the gpg-agent SSH client, and this target enables the incoming server, so `setup-sshd` is removed. |
| 2026-11-03 | `938d26c77733f367432d9f8ab3c9c30aca1e2553` | `HOMEBASE` | `HOME_BASE` | One name for the home-base host. `HOME_BASE` is no longer set. |
