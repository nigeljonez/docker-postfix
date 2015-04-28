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

    cat > /opt/$pipescript <<EOF
#!/usr/bin/env bash

# Wire this script to receive incoming email for request responses.

INPUT=$(mktemp -t foi-mailin-mail-XXXXXXXX)
OUTPUT=$(mktemp -t foi-mailin-output-XXXXXXXX)

# Read the email message from stdin, and write it to the file $INPUT
cat >"$INPUT"

AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID S3_BUCKET=$S3_BUCKET /opt/s3putter <"$INPUT" >"$OUTPUT" 2>&1

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

  fi

  ### If you want filter by mail prefix
  cat > /etc/postfix/transports <<EOF
/^fyi.*/                $alaveteli_user
EOF

  cat >> /etc/postfix/master.cf <<EOF
$alaveteli_user unix  - n n - 50 pipe
  flags=R user=$alaveteli_user argv=/opt/$pipescript
EOF

  cat >> /etc/postfix/main.cf <<EOF
transport_maps = regexp:/etc/postfix/transports
local_recipient_maps = proxy:unix:passwd.byname regexp:/etc/postfix/recipients
export_environment = AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY S3_BUCKET TZ MAIL_CONFIG LANG
EOF

  cat > /etc/postfix/recipients <<EOF
/^fyi.*/                this-is-ignored
EOF
fi
