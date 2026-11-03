# Bitbucket SSH migration

Bitbucket Cloud moves Git SSH traffic to `ssh.bitbucket.org` on November 12,
2026. [Atlassian's migration notice](https://community.atlassian.com/forums/discussion/3234032/upcoming-change-to-bitbucket-cloud-ssh-access-move-from-bitbucket-org-to-ssh-bitbucket-org)
describes the change. HTTPS web, API and Git URLs continue using `bitbucket.org`.

## Each machine

After this branch is merged and pulled on each machine:

* Guix machines: use the usual `make apply`, `make apply-wayland` or
  `make apply-ewm`. All three share the SSH activation and Git configuration.
* Native macOS, Linux/WSL and Termux: use the usual `make set_up_links`
  (also called by `make setup-native` and `bin/termux-setup`).
* To run only the SSH migration, use `make setup-bitbucket-ssh`.
  This does not install the shared Git configuration by itself.
* The guix-dev container has its own SSH directory: rerun
  `make setup-guix-bitbucket-key` to migrate its existing Host block and
  retain its existing key. This may prompt for key creation if none exists.

The migration adds Bitbucket's published Ed25519 key under the new hostname
in the writable `~/.ssh/known_hosts`. It retains existing entries and does
not fetch unverified keys from the SSH network. The pinned fingerprint is
`SHA256:ybgmFkzwOSotHTHLJgHO0QN8L0xErw6vd0VhFA9m3SM`, published by
[Atlassian](https://support.atlassian.com/bitbucket-cloud/docs/configure-ssh-and-two-step-verification/).
Future host-key rotations require reviewing the published key and updating
the setup script.

Explicit `Host bitbucket.org` blocks in `~/.ssh/config` also match
`ssh.bitbucket.org` after migration. Their old `HostName bitbucket.org`
directives move to the new hostname. The script preserves other settings
and saves the previous configuration as `~/.ssh/config.before-bitbucket-ssh`
when it changes the file. Review bespoke aliases, Include files, Match rules
and directives using equals signs separately; these are not parsed by the
migration. Existing port-443 configurations using `altssh.bitbucket.org`
retain that endpoint.

The shared `.gitconfig` rewrites both scp-style and `ssh://` Bitbucket SSH
URLs, including explicit ports, to the new hostname when Git uses them.
Existing clone and submodule configuration can retain its stored URL;
Git's effective fetch and push URLs use the new host. New remote URLs should
use `ssh.bitbucket.org` directly. HTTPS URLs are unaffected.
Guix deploys this config; native macOS and Termux use the include installed
by `make install-gnupg`. Other native setups must include the shared
`~/dot_files/.gitconfig` in their own Git config as well.

## CI/CD and company networks

Automation that loads this shared Git configuration gets the same rewrites.
For isolated runners, update stored SSH clone, fetch, push and submodule
URLs to the new hostname and seed the new hostname's verified key into the
runner user's known_hosts. Run `make setup-bitbucket-ssh` in this checkout
as that user if the runner can use the setup script.

Allow outbound TCP port 22 to `ssh.bitbucket.org` in company network rules,
including hostname-based firewall and proxy allowlists. Use Atlassian's
[network allowlist documentation](https://support.atlassian.com/bitbucket-cloud/docs/what-are-the-bitbucket-cloud-ip-addresses-i-should-use-to-configure-my-corporate-firewall/)
for IP-based rules. This repository does not manage those external rules or
CI settings, and preparing this change does not deploy it to other machines.
