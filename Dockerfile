FROM sonarqube@sha256:9026624a61cd25542a402a9e7213dd7dbb39724ac9597e331e6b85362558c079

USER root

# SonarQube launches its embedded Elasticsearch with -Des.enforce.bootstrap.checks=true, so
# unlike a plain single-node OpenSearch it DOES hit the production bootstrap checks and dies on
# `max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]`.
# A Railway container cannot sysctl, so the mmap requirement is removed instead: with
# allow_mmap=false Lucene falls back to niofs and the check no longer applies. Measured with
# vm.max_map_count deliberately set to 65530 -- boots clean to status UP.
ENV SONAR_SEARCH_JAVAADDITIONALOPTS="-Dnode.store.allow_mmap=false" \
    SONAR_JDBC_USERNAME=postgres \
    SONAR_PATH_DATA=/opt/sonarqube/extensions/.sq-data

# Railway gives a service exactly one volume. It is mounted at /opt/sonarqube/extensions so
# that plugins the deployer installs survive a redeploy -- those are the part that cannot be
# rebuilt -- and the Elasticsearch index is relocated onto the same volume via sonar.path.data.
# Mounting over extensions hides the plugins the image ships, so stash a copy the entrypoint
# can seed an empty volume from. (Docker copies image content into an empty named volume by
# itself; Railway does not, so this cannot be left to the runtime.)
RUN cp -a /opt/sonarqube/extensions /opt/sonarqube/extensions-image

# Railway's private network is IPv6-only, and the JVM prefers IPv4, so the JDBC connection to
# the Postgres service times out with `SocketTimeoutException: Connect timed out` even though
# the hostname resolves. JAVA_TOOL_OPTIONS reaches every JVM SonarQube spawns (app, web,
# compute engine, search), which is what this needs -- setting it on one of them is not enough.
ENV JAVA_TOOL_OPTIONS="-Djava.net.preferIPv6Addresses=true"

COPY --chmod=0755 railway-entrypoint.sh /usr/local/bin/railway-entrypoint
COPY --chmod=0755 railway-seed-admin.sh /usr/local/bin/railway-seed-admin

ENTRYPOINT ["/usr/local/bin/railway-entrypoint"]
