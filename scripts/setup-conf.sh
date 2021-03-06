#!/usr/bin/env bash

source /scripts/env-data.sh

SETUP_LOCKFILE="${ROOT_CONF}/.postgresql.conf.lock"
if [ -f "${SETUP_LOCKFILE}" ]; then
	return 0
fi

list=(`echo ${POSTGRES_DBNAME} | tr ',' ' '`)
arr=(${list})
SINGLE_DB=${arr[0]}
# This script will setup necessary configuration to enable replications

# Refresh configuration in case environment settings changed.
cat $CONF.template > $CONF

# Reflect DATADIR loaction
# Delete any data_dir declarations
sed -i '/data_directory/d' $CONF
echo "data_directory = '${DATADIR}'" >> $CONF

# This script will setup necessary configuration to optimise for PostGIS and to enable replications
cat >> $CONF <<EOF
superuser_reserved_connections= 10
listen_addresses = '${IP_LIST}'
shared_buffers = 500MB
work_mem = 16MB
maintenance_work_mem = ${MAINTAINANCE_WORK_MEM}
wal_buffers = 1MB
random_page_cost = 2.0
xmloption = 'document'
max_parallel_maintenance_workers = ${MAINTAINANCE_WORKERS}
max_parallel_workers = ${MAX_WORKERS}
shared_preload_libraries = '${SHARED_PRELOAD_LIBRARIES}'
cron.database_name = '${SINGLE_DB}'
password_encryption= '${PASSWORD_AUTHENTICATION}'
timezone='${TIMEZONE}'
EOF

# This script will setup necessary replication settings



if [[  "${REPLICATION}" =~ [Tt][Rr][Uu][Ee] && "$WAL_LEVEL" == 'logical' ]]; then
cat >> "$CONF" <<EOF
wal_level = ${WAL_LEVEL}
max_wal_senders = ${PG_MAX_WAL_SENDERS}
wal_keep_segments = ${PG_WAL_KEEP_SEGMENTS}
min_wal_size = ${MIN_WAL_SIZE}
max_wal_size = ${WAL_SIZE}
max_logical_replication_workers = ${MAX_LOGICAL_REPLICATION_WORKERS}
max_sync_workers_per_subscription = ${MAX_SYNC_WORKERS_PER_SUBSCRIPTION}
EOF
fi

if [[ "${REPLICATION}" =~ [Tt][Rr][Uu][Ee] &&  "$WAL_LEVEL" == 'replica' ]]; then
cat >> "$CONF" <<EOF
wal_level = ${WAL_LEVEL}
archive_mode = ${ARCHIVE_MODE}
archive_command = '${ARCHIVE_COMMAND}'
restore_command = '${RESTORE_COMMAND}'
archive_cleanup_command = '${ARCHIVE_CLEANUP_COMMAND}'
max_wal_senders = ${PG_MAX_WAL_SENDERS}
wal_keep_segments = ${PG_WAL_KEEP_SEGMENTS}
min_wal_size = ${MIN_WAL_SIZE}
max_wal_size = ${WAL_SIZE}
hot_standby = on
checkpoint_timeout = ${CHECK_POINT_TIMEOUT}
primary_conninfo = 'host=${REPLICATE_FROM} port=${REPLICATE_PORT} user=${REPLICATION_USER} password=${REPLICATION_PASS} sslmode=${PGSSLMODE}'
recovery_target_timeline=${TARGET_TIMELINE}
recovery_target_action=${TARGET_ACTION}
promote_trigger_file = '${PROMOTE_FILE}'
shared_preload_libraries = 'pg_cron,auto_explain,pg_qualstats,pg_stat_statements'
auto_explain.log_min_duration=3000
auto_explain.log_analyze=true
auto_explain.log_format=json
auto_explain.log_timing=true
cron.database_name = '${SINGLE_DB}'
pg_qualstats.enabled = true
pg_qualstats.track_constants = true
pg_qualstats.max = 1000
pg_qualstats.resolve_oids = true
pg_qualstats.sample_rate = 0.1
track_activity_query_size = 4096
EOF
fi

echo -e $EXTRA_CONF >> $CONF

# Optimise PostgreSQL shared memory for PostGIS
# shmall units are pages and shmmax units are bytes(?) equivalent to the desired shared_buffer size set in setup_conf.sh - in this case 500MB
echo "kernel.shmmax=543252480" >> /etc/sysctl.conf
echo "kernel.shmall=2097152" >> /etc/sysctl.conf

# Put lock file to make sure conf was not reinitialized
touch ${SETUP_LOCKFILE}
