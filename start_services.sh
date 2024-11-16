#!/bin/bash

# Helper function to handle symlinking and data migration
link_and_migrate() {
  local source_dir=$1
  local target_dir=$2

  # If target_dir (e.g., /mnt/appdata/postgres) does not exist, create it and migrate data
  if [ ! -d "$target_dir" ]; then
    echo "Creating directory $target_dir and migrating data from $source_dir..."
    mkdir -p "$target_dir"
    mv "$source_dir"/* "$target_dir/" 2>/dev/null || true
  fi

  # Ensure permissions are correct for the target directory
  chown -R "$3:$4" "$target_dir"
  chmod -R 755 "$target_dir"

  # Remove source_dir if it exists, then create a symlink
  rm -rf "$source_dir"
  ln -s "$target_dir" "$source_dir"
}

# Handle PostgreSQL
link_and_migrate /var/lib/postgresql/data /mnt/appdata/postgres postgres postgres

if [ -z "$(ls -A /mnt/appdata/postgres)" ]; then
  echo "Initializing PostgreSQL database..."
  su postgres -c "/usr/lib/postgresql/13/bin/initdb -D /mnt/appdata/postgres"
fi

# Ensure correct permissions
chown -R postgres:postgres /mnt/appdata/postgres
chmod -R 0700 /mnt/appdata/postgres

# Remove stale lock files
rm -f /mnt/appdata/postgres/postmaster.pid
rm -f /mnt/appdata/postgres/postmaster.opts

# Start PostgreSQL
su postgres -c "/usr/lib/postgresql/13/bin/pg_ctl start -D /mnt/appdata/postgres -l /mnt/appdata/postgres/logfile"

# Wait for PostgreSQL to start
sleep 5

# Check if PostgreSQL is running
if ! su postgres -c "pg_isready -h localhost -p 5432"; then
  echo "PostgreSQL failed to start. Exiting."
  exit 1
fi

# Handle Grafana
link_and_migrate /usr/share/grafana/data /mnt/appdata/grafana grafana grafana

# Handle Prometheus
link_and_migrate /var/lib/prometheus /mnt/appdata/prometheus prometheus prometheus

# Conditionally start Nginx based on ENABLE_FAKESERVER
if [ "$ENABLE_FAKESERVER" = "True" ]; then
  echo "Starting Nginx..."
  supervisorctl start nginx
else
  echo "Skipping Nginx..."
fi

# Start Supervisor to manage all services
exec supervisord -c /etc/supervisor/conf.d/supervisord.conf
