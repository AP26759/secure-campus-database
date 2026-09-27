#!/usr/bin/env bash

set -euo pipefail

DB_NAME="campus_access"
SQL_FILE="campus_access_solution.sql"

echo "===================================="
echo "CampusAccess Database Setup Script"
echo "===================================="
echo

# -----------------------------
# Check SQL file exists
# -----------------------------
if [ ! -f "$SQL_FILE" ]; then
    echo "ERROR: $SQL_FILE not found in current directory."
    echo "Please place the SQL build file next to setup.sh"
    exit 1
fi

# -----------------------------
# Check PostgreSQL installed
# -----------------------------
if ! command -v psql &> /dev/null
then
    echo "ERROR: PostgreSQL (psql) is not installed."
    echo "Install PostgreSQL before running this script."
    exit 1
fi

echo "PostgreSQL detected."
echo

# -----------------------------
# Create database if needed
# -----------------------------
echo "Creating database '$DB_NAME'"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 || \
sudo -u postgres createdb "$DB_NAME"

echo "Database ready."
echo

# -----------------------------
# Run SQL build script
# -----------------------------
echo "Running schema setup from $SQL_FILE ..."

sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -f "$SQL_FILE"

echo
echo "===================================="
echo "Setup completed successfully."
echo "Database '$DB_NAME' is ready."
echo "===================================="
echo
