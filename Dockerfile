FROM ubuntu:24.04 AS builder

ARG TARGETPLATFORM

# Set Virtuoso commit SHA to Virtuoso 7.2.17 release (2026-05-01)
ARG VIRTUOSO_COMMIT=ad6589ff38488183a35dfe8ba398233c3380b5ba

RUN apt-get update && \
    apt-get install -y build-essential autotools-dev autoconf automake net-tools libtool \
                       flex bison gperf gawk m4 libssl-dev libreadline-dev openssl wget \
                       python-is-python3 bzip2 patch
RUN wget https://github.com/openlink/virtuoso-opensource/archive/${VIRTUOSO_COMMIT}.tar.gz
RUN tar xzf ${VIRTUOSO_COMMIT}.tar.gz

# Build libraries for GeoSPARQL support if not on ARM
RUN if [ "$TARGETPLATFORM" != "linux/arm64" ]; then \
        wget https://download.osgeo.org/proj/proj-4.9.3.tar.gz && \
        tar xzf proj-4.9.3.tar.gz && \
        cd proj-4.9.3 && \
        ./configure && \
        make && \
        make install && \
        cd .. && \
        wget http://download.osgeo.org/geos/geos-3.5.1.tar.bz2 && \
        bzip2 -d geos-3.5.1.tar.bz2 && \
        tar xf geos-3.5.1.tar && \
        cd geos-3.5.1 && \
        ./configure && \
        make && \
        make check && \
        make install && \
        ldconfig; \
    else \
        echo "not building geo plugins on arm"; \
    fi

RUN wget https://github.com/openlink/virtuoso-opensource/archive/${VIRTUOSO_COMMIT}.tar.gz && \
    tar xzf ${VIRTUOSO_COMMIT}.tar.gz
WORKDIR virtuoso-opensource-${VIRTUOSO_COMMIT}

# Build virtuoso from source
RUN ./autogen.sh && \
    case "$TARGETPLATFORM" in \
      "linux/amd64") export CFLAGS="-O2 -m64" ;; \
      "linux/arm64") export CFLAGS="-O2" ;; \
      *) export CFLAGS="-O" ;; \
    esac && \
    ./configure \
        $(if [ "$TARGETPLATFORM" != "linux/arm64" ]; then echo "--enable-geos=/usr/local/lib"; fi) \
        $(if [ "$TARGETPLATFORM" != "linux/arm64" ]; then echo "--enable-proj4=/usr/local/lib"; fi) \
        $(if [ "$TARGETPLATFORM" != "linux/arm64" ]; then echo "--enable-shapefileio"; fi) \
        --disable-graphql \
        --disable-bpel-vad \
        --enable-conductor-vad \
        --enable-fct-vad \
        --disable-dbpedia-vad \
        --disable-demo-vad \
        --disable-isparql-vad \
        --disable-ods-vad \
        --disable-sparqldemo-vad \
        --disable-syncml-vad \
        --disable-tutorial-vad \
        --with-readline --program-transform-name="s/isql/isql-v/" && \
    make && make install

FROM ubuntu:24.04
COPY --from=builder /usr/local/virtuoso-opensource /usr/local/virtuoso-opensource
COPY --from=builder /usr/local/lib/ /usr/local/lib
RUN chgrp -R 0 /usr/local/virtuoso-opensource/var  && chmod -R g=u /usr/local/virtuoso-opensource/var

RUN apt-get update && apt-get install -y libssl-dev crudini

# Use the upstream default config, with plugins disabled and SPARQL query limits restored
RUN mv /usr/local/virtuoso-opensource/var/lib/virtuoso/db/virtuoso.ini /virtuoso.ini && \
    for key in $(crudini --get /virtuoso.ini Plugins | grep -E '^Load[0-9]+$'); do \
        crudini --del /virtuoso.ini Plugins "$key"; \
    done && \
    crudini --set /virtuoso.ini SPARQL ResultSetMaxRows 10000 && \
    crudini --set /virtuoso.ini SPARQL MaxConstructTriples 10000 && \
    crudini --set /virtuoso.ini SPARQL MaxQueryCostEstimationTime 400 && \
    crudini --set /virtuoso.ini SPARQL MaxQueryExecutionTime 60
# Add Virtuoso bin to the PATH
ENV PATH=/usr/local/virtuoso-opensource/bin/:$PATH

# Add sql scripts
COPY dump_nquads_procedure.sql /docker-virtuoso/dump_nquads_procedure.sql
COPY add_cors.sql /docker-virtuoso/add_cors.sql

# Add Virtuoso log cleaning script
COPY clean-logs.sh /clean-logs.sh
RUN chmod +x /clean-logs.sh

# Add startup script
COPY virtuoso.sh /virtuoso.sh

RUN ln -s /usr/local/virtuoso-opensource/var/lib/virtuoso/ /var/lib/virtuoso \
    && ln -s /var/lib/virtuoso/db /data

# Add mu scripts
COPY ./scripts/ /app/scripts/

WORKDIR /data
EXPOSE 8890
EXPOSE 1111

CMD ["/bin/bash", "/virtuoso.sh"]
