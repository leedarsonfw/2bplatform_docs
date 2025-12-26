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

# Extract database and app_data files
SQL_GZ_FILE="$SCRIPT_DIR/2bplatform_docs.sql.gz"
APP_DATA_TGZ_FILE="$SCRIPT_DIR/app_data.tgz"

# Check and extract SQL file
if [ ! -f "$SQL_GZ_FILE" ]; then
    echo "Error: SQL archive not found: $SQL_GZ_FILE"
    exit 1
fi

if [ ! -s "$SQL_GZ_FILE" ]; then
    echo "Error: SQL archive is empty: $SQL_GZ_FILE"
    exit 1
fi

echo "Extracting SQL file..."
# Remove existing SQL file if it exists
SQL_FILE="$SCRIPT_DIR/2bplatform_docs.sql"
if [ -f "$SQL_FILE" ]; then
    rm -f "$SQL_FILE"
fi

# Test and extract gzip file
if ! gzip -t "$SQL_GZ_FILE" 2>&1; then
    echo "Error: Invalid gzip archive: $SQL_GZ_FILE"
    exit 1
fi

if ! gunzip -c "$SQL_GZ_FILE" > "$SQL_FILE" 2>&1; then
    echo "Error: Failed to extract gzip archive: $SQL_GZ_FILE"
    exit 1
fi

# Check and extract app_data file
if [ ! -f "$APP_DATA_TGZ_FILE" ]; then
    echo "Error: app_data archive not found: $APP_DATA_TGZ_FILE"
    exit 1
fi

if [ ! -s "$APP_DATA_TGZ_FILE" ]; then
    echo "Error: app_data archive is empty: $APP_DATA_TGZ_FILE"
    exit 1
fi

echo "Extracting app_data..."
if ! tar -tzf "$APP_DATA_TGZ_FILE" > /dev/null 2>&1; then
    echo "Error: Invalid tar archive: $APP_DATA_TGZ_FILE"
    exit 1
fi

tar -xzf "$APP_DATA_TGZ_FILE" -C "$SCRIPT_DIR" --overwrite

# Import database

# Check if the database container is running
if ! docker-compose ps "$DB_SERVICE" | grep -q "Up"; then
    echo "Error: Database container $DB_SERVICE is not running"
    echo "Please start it with: docker-compose up -d $DB_SERVICE"
    exit 1
fi

# Import database
if [ ! -f "$SQL_FILE" ]; then
    echo "Error: SQL file not found: $SQL_FILE"
    exit 1
fi

echo "Importing database..."
PGPASSWORD="$DB_PASSWORD" docker-compose exec -T "$DB_SERVICE" psql \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -q \
    < "$SQL_FILE" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Database import completed successfully!"
else
    echo "Error: Database import failed"
    exit 1
fi
