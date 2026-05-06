# --- sf org-alias completion override ---
# After installing sf's own zsh completion per the standard instructions (sf autocomplete), add this block immediately below that in ~/.zshrc

_sf_org_cache="${HOME}/.cache/sf-org-aliases"
_sf_org_ttl=300

_sf_refresh_org_cache() {
  local now=$(date +%s)
  local mtime=0
  [[ -f "$_sf_org_cache" ]] && mtime=$(stat -f %m "$_sf_org_cache" 2>/dev/null || stat -c %Y "$_sf_org_cache" 2>/dev/null || echo 0)
  if (( now - mtime > _sf_org_ttl )) || [[ ! -s "$_sf_org_cache" ]]; then
    mkdir -p "$(dirname $_sf_org_cache)"
    sf org list --json 2>/dev/null \
      | jq -r '[.result.nonScratchOrgs[]?, .result.scratchOrgs[]?, .result.devHubs[]?, .result.sandboxes[]?]
              | .[] | (.alias // .username) | select(. != null and . != "")' \
      | sort -u > "$_sf_org_cache"
  fi
}

_sf_org_completer() {
  _sf_refresh_org_cache
  local -a orgs
  orgs=("${(@f)$(<$_sf_org_cache)}")
  _describe -t sforgs 'sf org' orgs
}

_sf_with_orgs() {
  local cur="${words[CURRENT]}"
  local prev="${words[CURRENT-1]}"

  case "$cur" in
    --target-org=*|--target-dev-hub=*|--source-org=*|--from-org=*)
      compset -P '*='
      _sf_org_completer
      return
      ;;
  esac

  case "$prev" in
    --target-org|-o|--target-dev-hub|-v|--source-org|--from-org)
      _sf_org_completer
      return
      ;;
  esac

  (( ${+functions[_sf]} )) || autoload -Uz _sf
  _sf "$@"
}

compdef _sf_with_orgs sf