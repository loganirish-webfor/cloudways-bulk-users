FROM wordpress:cli
# The sandbox MariaDB has no TLS but the Alpine mariadb client demands it, and WP-CLI
# runs the client (mariadb, mariadb-dump) with --no-defaults, so wrap those binaries to add --skip-ssl.
USER root
RUN apk add --no-cache bash coreutils \
 && mkdir -p /fixtures \
 && chown www-data:www-data /fixtures \
 && echo 'memory_limit = 512M' > /usr/local/etc/php/conf.d/zz-memory.ini \
 && printf '#!/bin/sh\nif [ "$1" = "--no-defaults" ]; then shift; exec /usr/bin/mariadb --no-defaults --skip-ssl "$@"; fi; exec /usr/bin/mariadb --skip-ssl "$@"\n' > /usr/local/bin/mariadb \
 && printf '#!/bin/sh\nif [ "$1" = "--no-defaults" ]; then shift; exec /usr/bin/mariadb-dump --no-defaults --skip-ssl "$@"; fi; exec /usr/bin/mariadb-dump --skip-ssl "$@"\n' > /usr/local/bin/mariadb-dump \
 && chmod +x /usr/local/bin/mariadb /usr/local/bin/mariadb-dump
USER www-data
WORKDIR /work
