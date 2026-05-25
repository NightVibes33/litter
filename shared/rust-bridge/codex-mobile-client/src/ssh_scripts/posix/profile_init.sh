# Source common shell rc files into PATH so user-installed binaries (npm,
# pnpm, bun, codex) become reachable from `/bin/sh`. We run each rc in a
# subshell so per-shell-only syntax (e.g. zsh-isms) cannot crash the parent
# /bin/sh, then re-import the resulting PATH via a temp file.
_litter_path_prepend() { case ":$PATH:" in *":$1:"*) ;; *) [ -d "$1" ] && PATH="$1:$PATH" ;; esac; }
_litter_pf="/tmp/.litter_path_$$"; for f in "$HOME/.zshenv" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zprofile" "$HOME/.zshrc"; do [ -f "$f" ] && (. "$f" 2>/dev/null; echo "$PATH") > "$_litter_pf" 2>/dev/null && PATH="$(cat "$_litter_pf")" ; done; rm -f "$_litter_pf" 2>/dev/null;
_litter_path_prepend "$NVM_BIN"; _litter_path_prepend "${ASDF_DATA_DIR:-}/shims"; _litter_path_prepend "/opt/homebrew/opt/node/bin"; _litter_path_prepend "/opt/homebrew/bin"; _litter_path_prepend "/usr/local/opt/node/bin"; _litter_path_prepend "/usr/local/bin"; _litter_path_prepend "$HOME/.volta/bin"; _litter_path_prepend "$HOME/.bun/bin"; _litter_path_prepend "$HOME/.local/bin"; _litter_path_prepend "${CARGO_HOME:-$HOME/.cargo}/bin"; _litter_path_prepend "${PNPM_HOME:-$HOME/Library/pnpm}"; _litter_path_prepend "$HOME/.opencode/bin";
_litter_nvm_dir="${NVM_DIR:-$HOME/.nvm}"; if [ -d "$_litter_nvm_dir/versions/node" ]; then _litter_nvm_default=""; [ -f "$_litter_nvm_dir/alias/default" ] && _litter_nvm_default="$(cat "$_litter_nvm_dir/alias/default" 2>/dev/null || true)"; [ -n "$_litter_nvm_default" ] && _litter_path_prepend "$_litter_nvm_dir/versions/node/$_litter_nvm_default/bin"; for d in "$_litter_nvm_dir"/versions/node/*/bin; do [ -x "$d/node" ] && _litter_path_prepend "$d"; done; fi;
if [ -d "$HOME/.fnm/node-versions" ]; then for d in "$HOME"/.fnm/node-versions/*/installation/bin; do [ -x "$d/node" ] && _litter_path_prepend "$d"; done; fi;
_litter_path_prepend "$HOME/.asdf/shims"; _litter_path_prepend "$HOME/.local/share/mise/shims";
export PATH;
