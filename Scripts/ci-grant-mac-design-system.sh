#!/usr/bin/env bash
# Gives a macOS CI job read access to the private cmdux-sh/MacDesignSystem package.
#
# The repository secret MAC_DESIGN_SYSTEM_DEPLOY_KEY holds a read-only SSH deploy key
# registered on cmdux-sh/MacDesignSystem. Package.swift keeps the HTTPS URL, so local
# builds use the developer's normal GitHub credentials; CI rewrites only that one URL to SSH.
# Linux jobs never declare the dependency and do not need this script.
set -euo pipefail

if [[ -z "${MAC_DESIGN_SYSTEM_DEPLOY_KEY:-}" ]]; then
  echo "ERROR: MAC_DESIGN_SYSTEM_DEPLOY_KEY is not available to this job." >&2
  echo "Pull requests from forks cannot read repository secrets; macOS builds need it." >&2
  exit 1
fi

ssh_dir="$HOME/.ssh"
key_path="$ssh_dir/mac_design_system_deploy_key"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
umask 077
printf '%s\n' "$MAC_DESIGN_SYSTEM_DEPLOY_KEY" > "$key_path"

# GitHub's published SSH host keys (https://api.github.com/meta), pinned instead of trusted on first use.
cat >> "$ssh_dir/known_hosts" <<'HOSTS'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
HOSTS

git config --global core.sshCommand "ssh -i $key_path -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
git config --global url."git@github.com:cmdux-sh/MacDesignSystem.git".insteadOf "https://github.com/cmdux-sh/MacDesignSystem.git"
git ls-remote --exit-code https://github.com/cmdux-sh/MacDesignSystem.git HEAD > /dev/null
echo "MacDesignSystem read access configured."
