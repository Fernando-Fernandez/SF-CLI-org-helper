# SF-CLI-org-helper

Small helper scripts for working with Salesforce CLI org aliases.

The Salesforce CLI autocomplete supports command and flag completion, but it does not currently complete dynamic flag values such as org aliases for `--target-org`.

This repo contains two lightweight workarounds:

1. A zsh completion override that adds org alias suggestions for common org flags.
2. An `sfx` wrapper script that prompts you to pick an org when you pass `?`.

These scripts do not replace the Salesforce CLI. They sit beside it and delegate back to `sf`.

## Requirements

- Salesforce CLI installed and authenticated
- `jq`
- For Alternative 1: zsh
- For Alternative 2: bash-compatible shell

Install `jq` on macOS:

```bash
brew install jq
```

Verify Salesforce CLI can list your orgs:

```bash
sf org list --json
```

If you do not see any orgs, log in first:

```bash
sf org login web
```

---

## Alternative 1: zsh completion override

This option extends `sf` tab completion so org aliases appear when completing values for flags such as:

- `--target-org`
- `-o`
- `--target-dev-hub`
- `-v`
- `--source-org`
- `--from-org`

### Step 1: Install Salesforce CLI autocomplete

Run:

```bash
sf autocomplete
```

Follow the instructions printed by the Salesforce CLI for your shell.

For zsh, this usually means adding Salesforce CLI completion setup to your `~/.zshrc`.

### Step 2: Add the org alias completion override

After the `sf autocomplete` block in `~/.zshrc`, add:

```zsh
# --- sf org-alias completion override ---
# Add this after the Salesforce CLI autocomplete setup in ~/.zshrc

_sf_org_cache="${HOME}/.cache/sf-org-aliases"
_sf_org_ttl=300

_sf_refresh_org_cache() {
  local now
  local mtime

  now=$(date +%s)
  mtime=0

  [[ -f "$_sf_org_cache" ]] && mtime=$(stat -f %m "$_sf_org_cache" 2>/dev/null || stat -c %Y "$_sf_org_cache" 2>/dev/null || echo 0)

  if (( now - mtime > _sf_org_ttl )) || [[ ! -s "$_sf_org_cache" ]]; then
    mkdir -p "$(dirname "$_sf_org_cache")"

    command sf org list --json 2>/dev/null \
      | jq -r '[.result.nonScratchOrgs[]?, .result.scratchOrgs[]?, .result.devHubs[]?, .result.sandboxes[]?]
              | .[] | (.alias // .username) | select(. != null and . != "")' \
      | sort -u > "$_sf_org_cache"
  fi
}

_sf_org_completer() {
  _sf_refresh_org_cache

  local -a orgs
  orgs=("${(@f)$(<"$_sf_org_cache")}")

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
```

### Step 3: Reload zsh

```bash
source ~/.zshrc
```

Or open a new terminal session.

### Usage

Start typing a command that expects an org alias:

```bash
sf org open --target-org 
```

Then press `TAB`.

You should see known org aliases from:

```bash
sf org list --json
```

### Cache behavior

Org aliases are cached at:

```bash
~/.cache/sf-org-aliases
```

The cache refreshes every 5 minutes.

To force a refresh:

```bash
rm ~/.cache/sf-org-aliases
```

Then use completion again.

### Notes

- This override is zsh-only.
- The first completion may be slower because it calls `sf org list --json`.
- Later completions use the cache.
- This keeps the normal Salesforce CLI autocomplete behavior for other commands and flags.

---

## Alternative 2: `sfx` interactive org picker

This option creates a small wrapper around `sf`.

Use `sfx` instead of `sf`, and pass `?` as the org value. The wrapper will show a numbered list of org aliases, let you pick one, then run the real `sf` command.

Example:

```bash
sfx org open --target-org ?
```

### Step 1: Create the script

Save this file as:

```bash
/usr/local/bin/sfx
```

Script:

```bash
#!/usr/bin/env bash
# sfx - sf companion with interactive org picker
#
# Usage:
#   sfx <any sf command> --target-org ?
#   sfx <any sf command> --target-org=?
#
# The ? triggers an interactive picker for org flags.

set -uo pipefail

_sfx_pick_org() {
  local -a orgs=()

  while IFS= read -r line; do
    [[ -n "$line" ]] && orgs+=("$line")
  done < <(
    command sf org list --json 2>/dev/null \
      | jq -r '[.result.nonScratchOrgs[]?, .result.scratchOrgs[]?, .result.devHubs[]?, .result.sandboxes[]?]
              | .[] | (.alias // .username) | select(. != null and . != "")' \
      | sort -u
  )

  if [[ ${#orgs[@]} -eq 0 ]]; then
    echo "sfx: no orgs found - run 'sf org login web' first" >&2
    return 1
  fi

  echo "Select an org:" >&2

  local pick
  PS3="#? "

  select pick in "${orgs[@]}"; do
    if [[ -n "${pick:-}" ]]; then
      echo "$pick"
      return 0
    fi

    echo "Invalid selection. Try again." >&2
  done < /dev/tty

  return 1
}

declare -a args=()
prev=""
org_flags="--target-org -o --target-dev-hub -v --source-org --from-org"

for arg in "$@"; do
  if [[ " $org_flags " == *" $prev "* ]] && [[ "$arg" == "?" ]]; then
    picked="$(_sfx_pick_org)" || { echo "sfx: cancelled" >&2; exit 1; }
    args+=("$picked")

  elif [[ "$arg" == --target-org=\? \
       || "$arg" == --target-dev-hub=\? \
       || "$arg" == --source-org=\? \
       || "$arg" == --from-org=\? ]]; then
    flag="${arg%=*}"
    picked="$(_sfx_pick_org)" || { echo "sfx: cancelled" >&2; exit 1; }
    args+=("$flag=$picked")

  else
    args+=("$arg")
  fi

  prev="$arg"
done

exec sf "${args[@]}"
```

### Step 2: Make it executable

```bash
chmod +x /usr/local/bin/sfx
```

### Step 3: Verify it is on your PATH

```bash
which sfx
```

Expected output:

```bash
/usr/local/bin/sfx
```

### Usage

Use `sfx` like `sf`, but pass `?` for the org value:

```bash
sfx org open --target-org ?
```

You will see a numbered picker:

```text
Select an org:
1) devhub
2) project-scratch
3) full-copy-sandbox
#?
```

Pick a number and press enter.

The wrapper then runs the real Salesforce CLI command with the selected alias.

These forms are supported:

```bash
sfx org open --target-org ?
sfx org open --target-org=?
sfx project deploy start --target-org ?
sfx project deploy start --target-dev-hub ?
sfx data query --target-org ? --query "SELECT Id, Name FROM Account LIMIT 10"
```

Short flags are supported when the value is separated:

```bash
sfx org open -o ?
sfx org create scratch -v ?
```

This wrapper does not currently handle short equals syntax such as:

```bash
sfx org open -o=?
```

Use this instead:

```bash
sfx org open -o ?
```

---

## Which option should I use?

Use the zsh completion override if:

- You use zsh.
- You already use `sf autocomplete`.
- You want aliases to appear when pressing `TAB`.

Use the `sfx` wrapper if:

- You want something simpler.
- You do not want to modify shell completion.
- You want a picker that works even without autocomplete.
- You are using a shell where the zsh override does not apply.

You can use both.

---

## Recommended alias style

Keep Salesforce CLI aliases shell-friendly.

Recommended:

```text
devhub
client-sandbox
billing-scratch
qa-full
```

Avoid spaces, quotes, wildcard characters, and other shell-special characters.

Avoid:

```text
client sandbox
qa "full"
billing*
```

The scripts quote values where possible, but shell workflows are more reliable when aliases are simple.

---

## Limitations

- The zsh completion override is zsh-only.
- The `sfx` wrapper only works when you call `sfx`, not raw `sf`.
- Both scripts require `jq`.
- The zsh option uses a cache that may be stale for up to 5 minutes.
- The first zsh completion may be slow because it calls `sf org list --json`.
- The wrapper currently supports only known org-related flags.
- Aliases with spaces or shell-special characters may behave poorly.
- These scripts do not modify Salesforce CLI or oclif.

---

## Why this exists

This was an exploration of solving a small workflow friction without immediately reaching for a plugin, extension, or upstream change.

Native dynamic autocomplete in Salesforce CLI would be cleaner. But a shell-level workaround solves most of the practical problem today, with less complexity and without depending on Salesforce CLI internals.

If Salesforce CLI or oclif eventually supports dynamic value completion, this helper can be retired.

---

## Future ideas

Possible improvements:

- Add fuzzy search to `sfx`
- Add PowerShell support
- Add bash completion support
- Support more Salesforce CLI flags
- Show usernames and aliases together
- Add cache support to `sfx`
- Add tests around argument parsing
