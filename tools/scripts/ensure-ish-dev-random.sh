#!/usr/bin/env sh
set -eu

if [ "$(id -u)" != "0" ]; then
  echo "ERROR: run as root inside the iSH fakefs so /dev can be repaired." >&2
  exit 1
fi

mkdir -p /dev

ensure_char_device() {
  path="$1"
  major="$2"
  minor="$3"
  mode="$4"
  if [ -c "$path" ]; then
    chmod "$mode" "$path" || true
    return
  fi
  if [ -e "$path" ]; then
    rm -f "$path"
  fi
  mknod -m "$mode" "$path" c "$major" "$minor"
}

ensure_char_device /dev/null 1 3 666
ensure_char_device /dev/random 1 8 666
ensure_char_device /dev/urandom 1 9 666

ls -l /dev/null /dev/random /dev/urandom
