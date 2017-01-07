FROM debian
RUN apt-get update && apt-get install --no-install-recommends postfix syslog-ng sasl2-bin libsasl2-modules -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    apt-get clean && \
    cp /etc/services /var/spool/postfix/etc/

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
