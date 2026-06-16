# Postgres 16 + analytics tuning + pg_stat_statements pre-enabled
FROM postgres:16-bookworm

LABEL org.opencontainers.image.title="baseball-analytics-postgres"
LABEL org.opencontainers.image.description="Postgres tuned for analytical scans on the Lahman dataset."

# Install client utils used during load (csvkit-friendly) and locales
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip locales \
 && sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen \
 && locale-gen en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PGTZ=UTC \
    TZ=UTC

COPY postgresql.conf /etc/postgresql/postgresql.conf

CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
