#!/bin/bash

set -e

if [ -z "${POSTFIX_DOMAIN}" ]; then
    echo "No Postfix Domain Provided. Trying to extract from hostname ..."
    POSTFIX_DOMAIN=$(hostname -d)
    echo "Extract ${POSTFIX_DOMAIN} as POSTFIX_DOMAIN"
fi

if [ -z "${SASL_PASS}" ]; then
    echo "No Sasl Pass provided. Generating one ..."
    SASL_PASS=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)
    echo "Passord generated: ${SASL_PASS}"
fi

if [ -z "${SASL_USER}" ]; then
    echo "No Sasl user provided. Using default/service"
    SASL_USER="default/service"
fi

if [ -z "${MAIL_DOMAIN}" ]; then
    echo "No Sasl Domain Provided. Using Hostname"
    MAIL_DOMAIN=${HOSTNAME}
fi

if [ -z "${DKIM_HOST}" ]; then
    echo "No DKIM_HOST provided. Using opendkim as the value"
    DKIM_HOST=opendkim
fi

if [ -z "${DKIM_PORT}" ]; then
    echo "No DKIM Port provided. Assuming port 5500/tcp"
    DKIM_PORT=5500
fi

if [ ! -f "/var/spool/postfix/etc/sasldb2" ]; then
    echo "${SASL_PASS}" | saslpasswd2 -p -c -f /var/spool/postfix/etc/sasldb2 -u "${POSTFIX_DOMAIN}" -a smtpauth "${SASL_USER}"
    chmod +r postfix /var/spool/postfix/etc/sasldb2

fi

if [ ! -f "/etc/postfix/sasl/smtpd.conf" ]; then
    echo "Configuring smtpd to use sasldb"
    cp /etc/resolv.conf /var/spool/postfix/etc/resolv.conf
    cat << EOT > /etc/postfix/sasl/smtpd.conf
pwcheck_method:auxprop
mech_list: plain login cram-md5 digest-md5
EOT

echo "Writing postfix configuration"
cat <<EOT > /etc/postfix/main.cf
#myorigin = /etc/mailname

smtpd_banner = \$myhostname ESMTP \$mail_name (Debian/GNU)
biff = no
append_dot_mydomain = no
readme_directory = no

# TLS parameters
smtpd_tls_cert_file=/var/spool/postfix/etc/ssl/server.pem
smtpd_tls_key_file=/var/spool/postfix/etc/ssl/server.key
smtpd_use_tls=yes
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtpd_tls_auth_only = yes
# SASL
smtpd_sasl_auth_enable = yes
smtpd_sasl_local_domain = ${MAIL_DOMAIN}
smtpd_sasl_security_options = noanonymous

# See /usr/share/doc/postfix/TLS_README.gz in the postfix-doc package for
# information on enabling SSL in the smtp client.

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = ${MAIL_DOMAIN}
mydomain = ${POSTFIX_DOMAIN}
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
mydestination = ${POSTFIX_DOMAIN}, ${MAIL_DOMAIN}, localhost
relayhost = 
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all

EOT
fi

if [ ! -f "/var/spool/postfix/etc/ssl/server.pem" ]; then
    echo "No TLS certificates Found. Copying system default snake-oil ..."
    cp /etc/ssl/certs/ssl-cert-snakeoil.pem /var/spool/postfix/etc/ssl/server.pem
    cp /etc/ssl/private/ssl-cert-snakeoil.key /var/spool/postfix/etc/ssl/server.key
fi

if [ ! -f "/etc/mailname" ]; then
    echo "${HOSTNAME}" > /etc/mailname
fi

service syslog-ng start
postfix start

exec tail -f /var/log/mail.log
