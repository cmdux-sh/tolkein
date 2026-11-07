#!/usr/bin/env bash
# Gives a CI job read access to the private cmdux-sh/internal-ui package (Internal UI).
#
# The repository secret MAC_DESIGN_SYSTEM_DEPLOY_KEY holds a read-only SSH deploy key
# registered on cmdux-sh/internal-ui. The secret keeps its name from before the package was renamed
# (GitHub cannot read a secret back to copy it). Package.swift keeps the HTTPS URL, so local
# builds use the developer's normal GitHub credentials; CI rewrites only that one URL to SSH.
# Linux jobs need it too: SwiftPM clones every pinned package, even ones the manifest only
# declares on macOS.
set -euo pipefail

if [[ -z "${MAC_DESIGN_SYSTEM_DEPLOY_KEY:-}" ]]; then
  echo "ERROR: MAC_DESIGN_SYSTEM_DEPLOY_KEY is not available to this job." >&2
  echo "Pull requests from forks cannot read repository secrets; macOS builds need it." >&2
  exit 1
fi

if [[ -z "${RUNNER_TEMP:-}" ]]; then
  echo "ERROR: run this only inside a GitHub Actions job." >&2
  exit 1
fi

# The key and host keys live in the job's temporary directory, which the runner deletes after the
# job. A dedicated SSH host alias carries the key, so other git SSH traffic never uses it.
# SwiftPM strips GIT_CONFIG_* variables when it runs git, so the rewrite is in the runner's
# (per-job) global git config.
access_dir="$RUNNER_TEMP/internal-ui-access"
key_path="$access_dir/deploy_key"
known_hosts="$access_dir/known_hosts"
mkdir -p "$access_dir"
chmod 700 "$access_dir"
umask 077
printf '%s\n' "$MAC_DESIGN_SYSTEM_DEPLOY_KEY" > "$key_path"

# GitHub's published SSH host keys (https://api.github.com/meta), pinned instead of trusted on first use.
cat > "$known_hosts" <<'HOSTS'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
HOSTS

ssh_dir="$HOME/.ssh"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
cat >> "$ssh_dir/config" <<SSHCONFIG

Host internal-ui.github.com
  HostName github.com
  User git
  IdentityFile $key_path
  IdentitiesOnly yes
  StrictHostKeyChecking yes
  UserKnownHostsFile $known_hosts
SSHCONFIG
chmod 600 "$ssh_dir/config"

git config --global url."internal-ui.github.com:cmdux-sh/internal-ui.git".insteadOf \
  "https://github.com/cmdux-sh/internal-ui.git"
git ls-remote --exit-code https://github.com/cmdux-sh/internal-ui.git HEAD > /dev/null
echo "Internal UI read access configured."
