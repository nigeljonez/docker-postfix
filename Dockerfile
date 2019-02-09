From ubuntu:bionic
MAINTAINER FYI Admin Team

# Set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND noninteractive

# Update
RUN apt-get update && apt-get -y install supervisor postfix ca-certificates rsyslog

# Add files
ADD assets/scripts/* /opt/
ADD assets/install.sh /opt/install.sh

# Run
CMD /opt/install.sh;/usr/bin/supervisord -c /etc/supervisor/supervisord.conf
