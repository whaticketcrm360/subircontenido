#!/bin/bash

source "${PROJECT_ROOT}"/lib/_backend.sh
source "${PROJECT_ROOT}"/lib/_preflight.sh
source "${PROJECT_ROOT}"/lib/_frontend.sh
source "${PROJECT_ROOT}"/lib/_inquiry.sh
source "${PROJECT_ROOT}"/lib/_migration.sh
source "${PROJECT_ROOT}"/lib/_pendingfix.sh
source "${PROJECT_ROOT}"/lib/_redis.sh
source "${PROJECT_ROOT}"/lib/_system.sh
source "${PROJECT_ROOT}"/lib/_tenant.sh
source "${PROJECT_ROOT}"/lib/_update.sh
source "${PROJECT_ROOT}"/lib/_wwebjs.sh
# source "${PROJECT_ROOT}"/lib/_updateall.sh
source "${PROJECT_ROOT}"/lib/_update_instancias_secundarias.sh
source "${PROJECT_ROOT}"/lib/_firewall.sh
source "${PROJECT_ROOT}"/lib/_rollback.sh
source "${PROJECT_ROOT}"/lib/_healthcheck.sh
source "${PROJECT_ROOT}"/lib/_frontnovo.sh
source "${PROJECT_ROOT}"/lib/_docker.sh
source "${PROJECT_ROOT}"/lib/_security_audit.sh
source "${PROJECT_ROOT}"/lib/_pgbouncer.sh
source "${PROJECT_ROOT}"/lib/_postgres_tune.sh
source "${PROJECT_ROOT}"/lib/_pm2_health.sh