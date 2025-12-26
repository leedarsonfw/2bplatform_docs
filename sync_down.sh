#!/bin/bash

# Sync down the database and app_data from the remote repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fetch latest changes from remote
git fetch origin master

# Check if local is behind remote
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "Repository is up to date. No new content to sync."
    exit 0
fi

# Pull changes if there are updates
git pull origin master

