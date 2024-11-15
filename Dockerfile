# Stage 1: Build frmcompanion binary
FROM --platform=$BUILDPLATFORM golang:1.20-bullseye AS frmcompanion-builder
WORKDIR /usr/src/frmcompanion
RUN git clone --depth 1 -b featheredtoast-main https://github.com/featheredtoast/FicsitRemoteMonitoringCompanion.git .
RUN cd Companion && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /usr/local/bin/companion main.go

# Stage 2: Build frmcache binary
FROM --platform=$BUILDPLATFORM golang:1.20-bullseye AS frmcache-builder
WORKDIR /usr/src/frmcache
COPY ./frmcache/src/app .
RUN GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /usr/local/bin/frmcache ./...

# Stage 3: Build alertmanager-config binary
FROM --platform=$BUILDPLATFORM golang:1.20-bullseye AS alertmanager-config-builder
WORKDIR /usr/src/alertmanager-config
COPY ./alertmanager-config/src/app .
RUN GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /usr/local/bin/alertmanager-config main.go

# Final Stage: Unified Image
FROM debian:bullseye-slim AS final

# Install dependencies
RUN apt-get update && apt-get install -y \
    nginx \
    postgresql \
    prometheus \
    grafana \
    supervisor \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set up PostgreSQL directories
RUN mkdir -p /var/lib/postgresql/data /docker-entrypoint-initdb.d

# Copy initialization script for PostgreSQL
COPY init-postgres.sql /docker-entrypoint-initdb.d/init-postgres.sql

# Copy built binaries
COPY --from=frmcompanion-builder /usr/local/bin/companion /usr/local/bin/companion
COPY --from=frmcache-builder /usr/local/bin/frmcache /usr/local/bin/frmcache
COPY --from=alertmanager-config-builder /usr/local/bin/alertmanager-config /usr/local/bin/alertmanager-config

# Copy additional resources
COPY ./frmcache/src/db/ /var/lib/frmcache/
COPY ./alertmanager-config/src/templates/alertmanager.yml.tmpl /var/lib/alertmanager-config/templates/alertmanager.yml.tmpl
COPY ./fakeserver /usr/share/nginx/html/
COPY ./grafana /etc/grafana/

# Configure Supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Environment variables
ENV FRM_HOST="host.docker.internal"
ENV FRM_PORT="8080"
ENV PG_HOST="localhost"
ENV PG_PORT="5432"
ENV PG_PASSWORD="secretpassword"
ENV PG_USER="postgres"
ENV PG_DB="postgres"
ENV DISCORD_WEBHOOK=""
ENV DISCORD_WEBHOOKS=""

# Expose ports
EXPOSE 8080 9000 9090 9093 3000

# Run Supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
