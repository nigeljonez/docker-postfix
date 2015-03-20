#!/bin/bash

#judgement
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
cat >> /opt/postfix.sh <<EOF
#!/bin/bash
service postfix start
tail -f /var/log/mail.log
EOF
chmod +x /opt/postfix.sh
postconf -e myhostname=$maildomain
postconf -F '*/*/chroot = n'

###############
#
################

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
  cp $pipescript /opt

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
EOF

  cat > /etc/postfix/recipients <<EOF
/^fyi.*/                this-is-ignored
EOF
fi
