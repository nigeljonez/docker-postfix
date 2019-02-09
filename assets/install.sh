#!/bin/bash

# sanity check
if [[ -a /etc/supervisor/conf.d/supervisord.conf ]]; then
  exit 0
fi

#supervisor
cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true

[program:postfix]
command=/opt/postfix.sh

[program:rsyslog]
command=/usr/sbin/rsyslogd -n -c3
EOF

############
#  postfix
############

chown syslog:adm /var/log/mail.err
chown syslog:adm /var/log/mail.log

echo "message_size_limit = 102400000" >> /etc/postfix/main.cf

cat >> /opt/postfix.sh <<EOF
#!/bin/bash
service postfix start
tail -f /var/log/mail.log
EOF
chmod +x /opt/postfix.sh
postconf -e myhostname=$maildomain
postconf -F '*/*/chroot = n'

#####################
# set up destinations
#####################

sed -i "s/localhost.localdomain, , localhost/$maildomain, localhost.localdomain, localhost/" /etc/postfix/main.cf

#####################
# Alaveteli specific
#####################

if [ -n "$alaveteli_user" ]; then
  adduser --quiet --disabled-password \
   --gecos "Alaveteli User" $alaveteli_user
fi


################
# Pipe to script
################

if [ -n "$pipescript" ]; then

  if [ -a $pipescript ]; then

    cp $pipescript /opt

  else

    cat > /opt/$pipescript <<'EOF'
#!/usr/bin/env bash

# Wire this script to receive incoming email for request responses.

INPUT=$(mktemp -t foi-mailin-mail-XXXXXXXX)
OUTPUT=$(mktemp -t foi-mailin-output-XXXXXXXX)

# Read the email message from stdin, and write it to the file $INPUT
cat >"$INPUT"
EOF

    echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID S3_BUCKET=$S3_BUCKET /opt/s3putter <\"\$INPUT\" >\"\$OUTPUT\" 2>&1"  >> /opt/$pipescript

    cat >> /opt/$pipescript <<'EOF'
ERROR_CODE=$?
if [ ! "$ERROR_CODE" = "0" ]
then
  # report exceptions somehow?
  rm -f "$INPUT" "$OUTPUT"
  # tell Postfix error was temporary, so try again later (no point bouncing message to authority)
  exit 75
fi

cat "$OUTPUT"
rm -f "$INPUT" "$OUTPUT"
exit 0
EOF

  chmod +x /opt/$pipescript
  fi

  ### If you want filter by mail prefix
  cat > /etc/postfix/transports <<EOF
/^fyi-request-\d+-[a-f\d]+@/           $alaveteli_user
/^fyi.*/        error:5.1.1 This is not a valid request address, please check the address and send again.
EOF

  cat > /etc/postfix/restrictedrequests <<EOF
/^fyi-request-3986-14d3ee82@/   reject This request is closed and a common spam target, please contact FYI administrators if you need to contact this request
EOF

  cat >> /etc/postfix/master.cf <<EOF
$alaveteli_user unix  - n n - 50 pipe
  flags=R user=$alaveteli_user argv=/opt/$pipescript
EOF

  cat >> /etc/postfix/main.cf <<EOF
transport_maps = pcre:/etc/postfix/transports
local_recipient_maps = proxy:unix:passwd.byname regexp:/etc/postfix/recipients
smtpd_recipient_restrictions = check_recipient_access pcre:/etc/postfix/restrictedrequests,
  reject_rbl_client pbl.spamhaus.org
export_environment = AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY S3_BUCKET TZ MAIL_CONFIG LANG
EOF

  cat > /etc/postfix/recipients <<EOF
/^fyi.*/                this-is-ignored
EOF
fi
