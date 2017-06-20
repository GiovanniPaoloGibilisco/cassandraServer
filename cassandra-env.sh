# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Determine the sort of JVM we'll be running on.
java_ver_output=`"${JAVA:-java}" -version 2>&1`
jvmver=`echo "$java_ver_output" | grep '[openjdk|java] version' | awk -F'"' 'NR==1 {print $2}' | cut -d\- -f1`
JVM_VERSION=${jvmver%_*}
JVM_PATCH_VERSION=${jvmver#*_}

if [ "$JVM_VERSION" \< "1.8" ] ; then
	echo "Cassandra 3.0 and later require Java 8u40 or later."
	exit 1;
fi

if [ "$JVM_VERSION" \< "1.8" ] && [ "$JVM_PATCH_VERSION" -lt 40 ] ; then
	echo "Cassandra 3.0 and later require Java 8u40 or later."
	exit 1;
fi

jvm=`echo "$java_ver_output" | grep -A 1 'java version' | awk 'NR==2 {print $1}'`
case "$jvm" in
	OpenJDK)
		JVM_VENDOR=OpenJDK
		# this will be "64-Bit" or "32-Bit"
		JVM_ARCH=`echo "$java_ver_output" | awk 'NR==3 {print $2}'`
		;;
	"Java(TM)")
		JVM_VENDOR=Oracle
		# this will be "64-Bit" or "32-Bit"
		JVM_ARCH=`echo "$java_ver_output" | awk 'NR==3 {print $3}'`
		;;
	*)
		# Help fill in other JVM values
		JVM_VENDOR=other
		JVM_ARCH=unknown
		;;
esac

#GC log path has to be defined here because it needs to access CASSANDRA_HOME
JVM_OPTS="$JVM_OPTS -Xloggc:${CASSANDRA_HOME}/logs/gc.log"

# Here we create the arguments that will get passed to the jvm when
# starting cassandra.

# Read user-defined JVM options from jvm.options file
# Our modification: append the JVM_OPTS variable AFTER the jvm.options
# in this way we can give arguments in the env variable and overwrite the ones
# defined in the file
JVM_OPTS_CASS=""
JVM_OPTS_FILE=$CASSANDRA_CONF/jvm.options
for opt in `grep "^-" $JVM_OPTS_FILE`
do
	JVM_OPTS_CASS="$JVM_OPTS_CASS $opt"
done

JVM_OPTS="$JVM_OPTS_CASS $JVM_OPTS"

# Check what parameters were defined on jvm.options file to avoid conflicts
echo $JVM_OPTS | grep -q UseConcMarkSweepGC
USING_CMS=$?
echo $JVM_OPTS | grep -q UseG1GC
USING_G1=$?


# Set this to control the amount of arenas per-thread in glibc
#export MALLOC_ARENA_MAX=4
if [ "x$MALLOC_ARENA_MAX" = "x" ] ; then
	export MALLOC_ARENA_MAX=4
fi

# provides hints to the JIT compiler
JVM_OPTS="$JVM_OPTS -XX:CompileCommandFile=$CASSANDRA_CONF/hotspot_compiler"

# add the jamm javaagent
JVM_OPTS="$JVM_OPTS -javaagent:$CASSANDRA_HOME/lib/jamm-0.3.0.jar"

# set jvm HeapDumpPath with CASSANDRA_HEAPDUMP_DIR
if [ "x$CASSANDRA_HEAPDUMP_DIR" != "x" ]; then
	JVM_OPTS="$JVM_OPTS -XX:HeapDumpPath=$CASSANDRA_HEAPDUMP_DIR/cassandra-`date +%s`-pid$$.hprof"
fi

# jmx: metrics and administration interface
#
# add this if you're having trouble connecting:
# JVM_OPTS="$JVM_OPTS -Djava.rmi.server.hostname=<public name>"
#
# see
# https://blogs.oracle.com/jmxetc/entry/troubleshooting_connection_problems_in_jconsole
# for more on configuring JMX through firewalls, etc. (Short version:
# get it working with no firewall first.)
#
# Cassandra ships with JMX accessible *only* from localhost.  
# To enable remote JMX connections, uncomment lines below
# with authentication and/or ssl enabled. See https://wiki.apache.org/cassandra/JmxSecurity 
#
if [ "x$LOCAL_JMX" = "x" ]; then
	LOCAL_JMX=yes
fi

# Specifies the default port over which Cassandra will be available for
# JMX connections.
# For security reasons, you should not expose this port to the internet.  Firewall it if needed.
JMX_PORT="7199"

if [ "$LOCAL_JMX" = "yes" ]; then
	JVM_OPTS="$JVM_OPTS -Dcassandra.jmx.local.port=$JMX_PORT"
	JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.authenticate=false"
else
	JVM_OPTS="$JVM_OPTS -Dcassandra.jmx.remote.port=$JMX_PORT"
	# if ssl is enabled the same port cannot be used for both jmx and rmi so either
	# pick another value for this property or comment out to use a random port (though see CASSANDRA-7087 for origins)
	JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.rmi.port=$JMX_PORT"

	# turn on JMX authentication. See below for further options
	JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.authenticate=true"

	# jmx ssl options
	#JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.ssl=true"
	#JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.ssl.need.client.auth=true"
	#JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.ssl.enabled.protocols=<enabled-protocols>"
	#JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.ssl.enabled.cipher.suites=<enabled-cipher-suites>"
	#JVM_OPTS="$JVM_OPTS -Djavax.net.ssl.keyStore=/path/to/keystore"
	#JVM_OPTS="$JVM_OPTS -Djavax.net.ssl.keyStorePassword=<keystore-password>"
	#JVM_OPTS="$JVM_OPTS -Djavax.net.ssl.trustStore=/path/to/truststore"
	#JVM_OPTS="$JVM_OPTS -Djavax.net.ssl.trustStorePassword=<truststore-password>"
fi

# jmx authentication and authorization options. By default, auth is only
# activated for remote connections but they can also be enabled for local only JMX
## Basic file based authn & authz
JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.password.file=/etc/cassandra/jmxremote.password"
#JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.access.file=/etc/cassandra/jmxremote.access"
## Custom auth settings which can be used as alternatives to JMX's out of the box auth utilities.
## JAAS login modules can be used for authentication by uncommenting these two properties.
## Cassandra ships with a LoginModule implementation - org.apache.cassandra.auth.CassandraLoginModule -
## which delegates to the IAuthenticator configured in cassandra.yaml. See the sample JAAS configuration
## file cassandra-jaas.config
#JVM_OPTS="$JVM_OPTS -Dcassandra.jmx.remote.login.config=CassandraLogin"
#JVM_OPTS="$JVM_OPTS -Djava.security.auth.login.config=$CASSANDRA_HOME/conf/cassandra-jaas.config"

## Cassandra also ships with a helper for delegating JMX authz calls to the configured IAuthorizer,
## uncomment this to use it. Requires one of the two authentication options to be enabled
#JVM_OPTS="$JVM_OPTS -Dcassandra.jmx.authorizer=org.apache.cassandra.auth.jmx.AuthorizationProxy"

# To use mx4j, an HTML interface for JMX, add mx4j-tools.jar to the lib/
# directory.
# See http://wiki.apache.org/cassandra/Operations#Monitoring_with_MX4J
# By default mx4j listens on 0.0.0.0:8081. Uncomment the following lines
# to control its listen address and port.
#MX4J_ADDRESS="-Dmx4jaddress=127.0.0.1"
#MX4J_PORT="-Dmx4jport=8081"

# Cassandra uses SIGAR to capture OS metrics CASSANDRA-7838
# for SIGAR we have to set the java.library.path
# to the location of the native libraries.
JVM_OPTS="$JVM_OPTS -Djava.library.path=$CASSANDRA_HOME/lib/sigar-bin"

JVM_OPTS="$JVM_OPTS $MX4J_ADDRESS"
JVM_OPTS="$JVM_OPTS $MX4J_PORT"
JVM_OPTS="$JVM_OPTS $JVM_EXTRA_OPTS"

