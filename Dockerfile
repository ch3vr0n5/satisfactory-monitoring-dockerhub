# Stage 1: Build frmcompanion binary
FROM --platform=$BUILDPLATFORM golang:1.23 AS frmcompanion-builder
WORKDIR /usr/src/frmcompanion
RUN git clone --depth 1 -b featheredtoast-main https://github.com/featheredtoast/FicsitRemoteMonitoringCompanion.git .
RUN cd Companion && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /usr/local/bin/companion main.go

# Stage 2: Build frmcache binary
FROM --platform=$BUILDPLATFORM golang:1.23 AS frmcache-builder
WORKDIR /usr/src/frmcache
COPY ./frmcache/src/app .
RUN GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /usr/local/bin/frmcache ./...

# Stage 3: Build alertmanager-config binary
FROM --platform=$BUILDPLATFORM golang:1.23 AS alertmanager-config-builder
WORKDIR /usr/src/alertmanager-config
COPY ./alertmanager-config/src/app .
RUN GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /usr/local/bin/alertmanager-config main.go

# Final Stage: Unified Image
FROM debian:bullseye-slim AS final

# Install dependencies
RUN apt-get update && apt-get install -y \
    nginx \
    postgresql \
    postgresql-contrib \
    supervisor \
    gnupg2 \
    software-properties-common \
    curl \
    && curl -fsSL https://github.com/prometheus/prometheus/releases/download/v2.47.1/prometheus-2.47.1.linux-amd64.tar.gz | tar -xz -C /usr/bin --strip-components=1 \
    && curl -fsSL https://packages.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana-archive-keyring.gpg \
    && curl -fsSL https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz | tar -xz -C /usr/bin --strip-components=1 \
    && echo "deb [signed-by=/usr/share/keyrings/grafana-archive-keyring.gpg] https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list \
    && apt-get update && apt-get install -y grafana \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


# Set up PostgreSQL directories
RUN mkdir -p /var/lib/postgresql/data /docker-entrypoint-initdb.d && \
    chown -R postgres:postgres /var/lib/postgresql

# Copy initialization script for PostgreSQL
COPY init-postgres.sql /docker-entrypoint-initdb.d/init-postgres.sql

# Initialize Postgres DB
RUN su postgres -c "/usr/lib/postgresql/13/bin/initdb -D /var/lib/postgresql/data"

# Copy built binaries
COPY --from=frmcompanion-builder /usr/local/bin/companion /usr/local/bin/companion
COPY --from=frmcache-builder /usr/local/bin/frmcache /usr/local/bin/frmcache
COPY --from=alertmanager-config-builder /usr/local/bin/alertmanager-config /usr/local/bin/alertmanager-config

# Copy Prometheus configuration
COPY ./prometheus /etc/prometheus

# Copy Alertmanager configuration
COPY ./alertmanager /etc/alertmanager

# Copy Fakeserver (Nginx) files
COPY ./fakeserver/metrics /usr/share/nginx/html/metrics
COPY ./fakeserver/data /usr/share/nginx/html/data
COPY ./fakeserver/default.conf /etc/nginx/conf.d/default.conf

# Copy Grafana configuration and dashboards
COPY ./grafana/datasources /usr/share/grafana/conf/provisioning/datasources
COPY ./grafana/dashboards.yml /usr/share/grafana/conf/provisioning/dashboards/dashboards.yml
COPY ./grafana/dashboards /var/lib/grafana/dashboards
COPY ./grafana/grafana.ini /usr/share/grafana/conf/grafana.ini
COPY ./grafana/icons /usr/share/grafana/public/img/icons/satisfactory

# Ensure correct ownership and permissions for provisioning files and dashboards
#RUN chown -R root:grafana /etc/grafana/provisioning && \
#    chmod -R 644 /etc/grafana/provisioning && \
#    chown -R root:grafana /var/lib/grafana/dashboards && \
#    chmod -R 644 /var/lib/grafana/dashboards && \
#    chown root:grafana /etc/grafana/grafana.ini && \
#    chmod 644 /etc/grafana/grafana.ini

# Copy additional resources
COPY ./frmcache/src/db/ /var/lib/frmcache/
COPY ./alertmanager-config/src/templates/alertmanager.yml.tmpl /var/lib/alertmanager-config/templates/alertmanager.yml.tmpl

# Configure Supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Environment variables
ENV FRM_HOST="host.docker.internal"
ENV FRM_PORT="64500"
ENV PG_HOST="localhost"
ENV PG_PORT="5432"
ENV PG_PASSWORD="secretpassword"
ENV PG_USER="postgres"
ENV PG_DB="postgres"
ENV DISCORD_WEBHOOK=""
ENV DISCORD_WEBHOOKS=""
ENV ENABLE_FAKESERVER="False"

# Expose ports
EXPOSE 3000

# Copy the startup script
COPY start_services.sh /usr/local/bin/start_services.sh

# Make it executable
RUN chmod +x /usr/local/bin/start_services.sh

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/start_services.sh"]

