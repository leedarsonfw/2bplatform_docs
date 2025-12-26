#!/bin/bash

# Database export script for docmost
# Based on docker-compose.yml configuration

set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Database configuration from docker-compose.yml
DB_SERVICE="docmost_db"
DB_NAME="project_management"
DB_USER="leedarson"
DB_PASSWORD="lds@firmware#2025"

# Export directory
EXPORT_DIR="$SCRIPT_DIR"
EXPORT_FILE="$EXPORT_DIR/2bplatform_docs.sql"
TEMP_EXPORT_FILE="$EXPORT_DIR/2bplatform_docs_temp.sql"
SIZE_CACHE_FILE="$EXPORT_DIR/.db_size"

# Create export directory if it doesn't exist
mkdir -p "$EXPORT_DIR"

# Change to project root to use docker-compose
cd "$PROJECT_ROOT"

# Check if the database container is running
if ! docker-compose ps "$DB_SERVICE" | grep -q "Up"; then
    echo "Error: Database container $DB_SERVICE is not running"
    echo "Please start it with: docker-compose up -d $DB_SERVICE"
    exit 1
fi

# Export database to temporary file for comparison
echo "Exporting database to temporary file for comparison..."
docker-compose exec -T "$DB_SERVICE" pg_dump \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    --clean \
    --if-exists \
    --no-owner \
    --no-acl \
    > "$TEMP_EXPORT_FILE"

# Check if export was successful
if [ ! -f "$TEMP_EXPORT_FILE" ] || [ ! -s "$TEMP_EXPORT_FILE" ]; then
    echo "Error: Failed to export database"
    rm -f "$TEMP_EXPORT_FILE"
    exit 1
fi

# Get current SQL file size
CURRENT_SIZE=$(stat -f%z "$TEMP_EXPORT_FILE" 2>/dev/null || stat -c%s "$TEMP_EXPORT_FILE" 2>/dev/null)

# Check if size cache exists and compare file sizes
if [ -f "$SIZE_CACHE_FILE" ]; then
    PREVIOUS_SIZE=$(cat "$SIZE_CACHE_FILE" 2>/dev/null || echo "")
    
    if [ -n "$PREVIOUS_SIZE" ] && [ "$CURRENT_SIZE" = "$PREVIOUS_SIZE" ]; then
        echo "Database file size has not changed (${CURRENT_SIZE} bytes). Skipping export."
        rm -f "$TEMP_EXPORT_FILE"
        exit 0
    else
        echo "Database file size has changed (previous: ${PREVIOUS_SIZE:-unknown} bytes, current: $CURRENT_SIZE bytes). Proceeding with export..."
    fi
else
    echo "No previous size cache found. Proceeding with export..."
fi

# Move temporary file to final export file
mv "$TEMP_EXPORT_FILE" "$EXPORT_FILE"

# Save current size to cache file
echo "$CURRENT_SIZE" > "$SIZE_CACHE_FILE"

# Compress the export file
echo "Compressing export file..."
# Remove existing compressed file if it exists
if [ -f "${EXPORT_FILE}.gz" ]; then
    rm -f "${EXPORT_FILE}.gz"
fi
gzip "$EXPORT_FILE"
EXPORT_FILE="${EXPORT_FILE}.gz"

echo "Database export completed successfully!"
echo "Export file: $EXPORT_FILE"
echo "File size: $(du -h "$EXPORT_FILE" | cut -f1)"

# Package app_data directory
APP_DATA_DIR="$EXPORT_DIR/app_data"
APP_DATA_ARCHIVE="$EXPORT_DIR/app_data.tgz"

if [ -d "$APP_DATA_DIR" ]; then
    echo "Packaging app_data directory..."
    cd "$EXPORT_DIR"
    # Remove existing archive if it exists
    if [ -f "$APP_DATA_ARCHIVE" ]; then
        rm -f "$APP_DATA_ARCHIVE"
    fi
    tar zcvf "$APP_DATA_ARCHIVE" app_data
    echo "app_data packaged: $APP_DATA_ARCHIVE"
    echo "Archive size: $(du -h "$APP_DATA_ARCHIVE" | cut -f1)"
else
    echo "Warning: app_data directory not found at $APP_DATA_DIR"
fi

# Git operations
cd "$PROJECT_ROOT"

# Check if this is a git repository
if [ ! -d ".git" ]; then
    echo "Warning: Not a git repository. Skipping git operations."
    exit 0
fi

# Add files to git
echo "Adding files to git..."
git add "$EXPORT_FILE"

if [ -f "$APP_DATA_ARCHIVE" ]; then
    git add "$APP_DATA_ARCHIVE"
fi

# Check if there are changes to commit
if git diff --cached --quiet; then
    echo "No changes to commit."
else
    # Commit changes
    COMMIT_MESSAGE="Update database and app_data backup - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Committing changes..."
    git commit -m "$COMMIT_MESSAGE"
    
    # Push to remote
    echo "Pushing to remote repository..."
    git push origin master
    echo "Git operations completed successfully!"
fi

