#!/bin/bash

# Sync down the database and app_data from the remote repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Database configuration from docker-compose.yml
DB_SERVICE="docmost_db"
DB_NAME="project_management"
DB_USER="leedarson"
DB_PASSWORD="lds@firmware#2025"

# Fetch latest changes from remote
git fetch --quiet origin master

# Check if local is behind remote
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "Repository is up to date. No new content to sync."
    exit 0
fi

# Pull changes if there are updates
git pull origin master

tar -xzf "$SCRIPT_DIR/2bplatform_docs.sql.gz" -C "$SCRIPT_DIR" --overwrite
tar -xzf "$SCRIPT_DIR/app_data.tgz" -C "$SCRIPT_DIR" --overwrite

# Import database

# Check if the database container is running
if ! docker-compose ps "$DB_SERVICE" | grep -q "Up"; then
    echo "Error: Database container $DB_SERVICE is not running"
    echo "Please start it with: docker-compose up -d $DB_SERVICE"
    exit 1
fi

# Import database
SQL_FILE="$SCRIPT_DIR/2bplatform_docs.sql"
if [ ! -f "$SQL_FILE" ]; then
    echo "Error: SQL file not found: $SQL_FILE"
    exit 1
fi

echo "Importing database..."
PGPASSWORD="$DB_PASSWORD" docker-compose exec -T "$DB_SERVICE" psql \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    < "$SQL_FILE"

if [ $? -eq 0 ]; then
    echo "Database import completed successfully!"
else
    echo "Error: Database import failed"
    exit 1
fi
