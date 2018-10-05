#!/bin/bash
set -e

# first arg is `-f` or `--some-option`
# or there are no args
if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
	set -- cassandra -f "$@"
fi

# allow the container to be started with `--user`
if [ "$1" = 'cassandra' -a "$(id -u)" = '0' ]; then
	chown -R cassandra /var/lib/cassandra /var/log/cassandra "$CASSANDRA_CONFIG"
	exec gosu cassandra "$BASH_SOURCE" "$@"
fi

_ip_address() {
	# scrape the first non-localhost IP address of the container
	# in Swarm Mode, we often get two IPs -- the container IP, and the (shared) VIP, and the container IP should always be first
	ip address | awk '
		$1 == "inet" && $NF != "lo" {
			gsub(/\/.+$/, "", $2)
			print $2
			exit
		}
	'
}

echo Server IP "$(_ip_address)"


if [ -z "$CASSANDRA_SEEDS" ]; then
    NEED_INIT=1
    echo Running Cassandra seed server.
else
    NEED_INIT=0
    echo Running regular Cassandra server.
fi
ls -alh /etc/cassandra/
cp /etc/cassandra/cassandra.yaml.new /etc/cassandra/cassandra.yaml
ls -alh /etc/cassandra/

if [ "$1" = 'cassandra' ]; then
	: ${CASSANDRA_RPC_ADDRESS='0.0.0.0'}

	: ${CASSANDRA_LISTEN_ADDRESS='auto'}
	if [ "$CASSANDRA_LISTEN_ADDRESS" = 'auto' ]; then
		CASSANDRA_LISTEN_ADDRESS="$(_ip_address)"
	fi

	: ${CASSANDRA_BROADCAST_ADDRESS="$CASSANDRA_LISTEN_ADDRESS"}

	if [ "$CASSANDRA_BROADCAST_ADDRESS" = 'auto' ]; then
		CASSANDRA_BROADCAST_ADDRESS="$(_ip_address)"
	fi
	: ${CASSANDRA_BROADCAST_RPC_ADDRESS:=$CASSANDRA_BROADCAST_ADDRESS}

	if [ -n "${CASSANDRA_NAME:+1}" ]; then
		: ${CASSANDRA_SEEDS:="cassandra"}
	fi
	: ${CASSANDRA_SEEDS:="$CASSANDRA_BROADCAST_ADDRESS"}
	
	sed -ri 's/(- seeds:).*/\1 "'"$CASSANDRA_SEEDS"'"/' "$CASSANDRA_CONFIG/cassandra.yaml"

	for yaml in \
		broadcast_address \
		broadcast_rpc_address \
		cluster_name \
		endpoint_snitch \
		listen_address \
		num_tokens \
		rpc_address \
		start_rpc \
	; do
		var="CASSANDRA_${yaml^^}"
		val="${!var}"
		if [ "$val" ]; then
			sed -ri 's/^(# )?('"$yaml"':).*/\2 '"$val"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
		fi
	done

	for rackdc in dc rack; do
		var="CASSANDRA_${rackdc^^}"
		val="${!var}"
		if [ "$val" ]; then
			sed -ri 's/^('"$rackdc"'=).*/\1 '"$val"'/' "$CASSANDRA_CONFIG/cassandra-rackdc.properties"
		fi
	done
fi

echo "Cassandra listening on $CASSANDRA_LISTEN_ADDRESS"

cp /etc/cassandra/jvm.options.new /etc/cassandra/jvm.options

cassandra
sleep 5

exit=0
if [ $NEED_INIT -eq 1 ]; then
    echo ======================================================
    echo Create a usertable for the seed server
    echo ======================================================
    while [ $exit -eq 0 ]; do
        if cqlsh localhost -f /setup_tables.txt ; then
            exit=1
        else
            echo Cannot connect to the seed server. Trying again...
        fi
        sleep 5
    done

    printf "========\n--------------Keyspace usertable was created--------------\n========\n"
else
    echo "Cassandra seed server exists"
fi

while true; do
    sleep 100;
done

