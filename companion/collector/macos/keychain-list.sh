# Keep the login keychain on the user search list.
# macOS /bin/bash is 3.2, and create-keychain can replace the search list.
# Sourced by sign-app.sh. KEYCHAIN and LOGIN_KEYCHAIN must already be set.

keychain_snapshot_search_list() {
  local line trimmed
  KEYCHAIN_SNAPSHOT=""
  while IFS= read -r line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%\"}"
    trimmed="${trimmed#\"}"
    if [[ -n "$trimmed" ]]; then
      KEYCHAIN_SNAPSHOT="${KEYCHAIN_SNAPSHOT}${trimmed}"$'\n'
    fi
  done < <(security list-keychains -d user)
}

keychain_restore_search_list() {
  local -a final=()
  local item seen skip
  final[0]="$KEYCHAIN"
  if [[ -n "${LOGIN_KEYCHAIN:-}" ]]; then
    final[${#final[@]}]="$LOGIN_KEYCHAIN"
  fi
  while IFS= read -r item; do
    if [[ -z "$item" ]]; then
      continue
    fi
    skip=0
    for seen in "${final[@]}"; do
      if [[ "$seen" == "$item" ]]; then
        skip=1
      fi
    done
    if [[ "$skip" -eq 0 ]]; then
      final[${#final[@]}]="$item"
    fi
  done <<EOF
${KEYCHAIN_SNAPSHOT:-}
EOF
  security list-keychains -d user -s "${final[@]}"
}

# Put the search list back exactly as it was before signing. The signing keychain only
# needs to be on the list while codesign runs.
keychain_reset_search_list() {
  local -a items=()
  local item
  while IFS= read -r item; do
    if [[ -n "$item" ]]; then
      items[${#items[@]}]="$item"
    fi
  done <<EOF
${KEYCHAIN_SNAPSHOT:-}
EOF
  if [[ ${#items[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${items[@]}"
  fi
}
