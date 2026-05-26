#!/usr/bin/env bash

# Detect if Homebrew is in /opt/homebrew (Apple Silicon) or /usr/local (Intel)
if [[ -d "/opt/homebrew" ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
elif [[ -d "/usr/local" ]]; then
    export PATH="/usr/local/bin:$PATH"
fi

# Check if wget and curl are installed; if not, install them via Homebrew
if ! command -v wget &> /dev/null; then
    echo "wget not found, attempting to install via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install wget
    else
        echo "Homebrew is not installed. Please install Homebrew and rerun the script."
        exit 1
    fi
fi

if ! command -v curl &> /dev/null; then
    echo "curl not found, attempting to install via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install curl
    else
        echo "Homebrew is not installed. Please install Homebrew and rerun the script."
        exit 1
    fi
fi

check_for_update() {
    if [ -f ".skip-prebuilt-fetch-$1" ]; then
        echo "Skipping prebuilt fetch for $1 since .skip-prebuilt-fetch-$1 exists. If you are developing $1 alongside SideStore, don't remove this file, or this script will replace your locally built binaries with the ones built by GitHub Actions."
        return
    fi

    if [ ! -f ".last-prebuilt-fetch-$1" ]; then
        echo "0,none" > ".last-prebuilt-fetch-$1"
    fi

    LAST_FETCH=`cat .last-prebuilt-fetch-$1 | perl -n -e '/([0-9]*),([^ ]*)$/ && print $1'`
    LAST_COMMIT=`cat .last-prebuilt-fetch-$1 | perl -n -e '/([0-9]*),([^ ]*)$/ && print $2'`

    # Check if required library files exist
    FORCE_DOWNLOAD=false
    if [ ! -f "lib$1-sim.a" ] || [ ! -f "lib$1-ios.a" ]; then
        echo "Required libraries missing for $1, forcing download..."
        FORCE_DOWNLOAD=true
    fi

    echo "Checking $1 for update"
    echo
    LATEST_COMMIT=`curl https://api.github.com/repos/SideStore/$1/releases/latest | perl -n -e '/Commit: https:\\/\\/github\\.com\\/[^\\/]*\\/[^\\/]*\\/commit\\/([^"]*)/ && print $1'`
    echo
    echo "Last commit: $LAST_COMMIT"
    echo "Latest commit: $LATEST_COMMIT"

    NOT_UPTODATE=false
    if [[ "$LAST_COMMIT" != "$LATEST_COMMIT" ]]; then
        echo "Found update on the remote: https://api.github.com/repos/SideStore/$1/releases/latest"
        NOT_UPTODATE=true
    fi

    # Download if:
    # 1. Libraries are missing, or
    # 2. New commit is available
    if [ "$FORCE_DOWNLOAD" = true ] || [ "$NOT_UPTODATE" = true ] ;then
        echo "downloading binaries"
        echo
        wget -O "lib$1-sim.a"    "https://github.com/SideStore/$1/releases/latest/download/lib$1-sim.a"
        wget -O "lib$1-ios.a"    "https://github.com/SideStore/$1/releases/latest/download/lib$1-ios.a"
        wget -O "$1.h"           "https://github.com/SideStore/$1/releases/latest/download/$1.h"
        wget -O "$1.swift"       "https://github.com/SideStore/$1/releases/latest/download/$1.swift"
        echo
    else
        echo "Up-to-date"
    fi
    echo "$(date +%s),$LATEST_COMMIT" > ".last-prebuilt-fetch-$1"
}

if [ -z "$1" ]; then
    echo "$(basename "$0"): error: missing argument" >&2
    exit 1
fi

check_for_update "$1"
