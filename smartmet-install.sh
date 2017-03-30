#!/bin/sh
cat > /etc/yum.repos.d/smartmet.repo <<EOF
[smartmet-international]
name=FMI SmartMet
baseurl=http://sudan:SmartMetFMI@download.weatherproof.fi/smartmet-international/rhel/7/\$basearch/
enabled=1
gpgcheck=0
metadata_expire=5
http_caching=none

[smartmet-international-noarch]
name=FMI SmartMet
baseurl=http://sudan:SmartMetFMI@download.weatherproof.fi/smartmet-international/rhel/7/noarch/
enabled=1
gpgcheck=0
metadata_expire=5
http_caching=none

[smartmet-base]
name=FMI SmartMet
baseurl=http://sudan:SmartMetFMI@download.weatherproof.fi/smartmet-base/rhel/7/\$basearch/
enabled=1
gpgcheck=0
metadata_expire=5
http_caching=none

[smartmet-base-noarch]
name=FMI SmartMet
baseurl=http://sudan:SmartMetFMI@download.weatherproof.fi/smartmet-base/rhel/7/noarch/
enabled=1
gpgcheck=0
metadata_expire=5
http_caching=none
EOF

echo "Install FMIForge repository" && \
rpm -Uvh http://download.weatherproof.fi/fmiforge/rhel/7/noarch/fmiforge-release-7-1.fmi.noarch.rpm && \
echo "Install EPEL repository" && \
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm && \
echo "Install PostgreSQL repository" && \
rpm -Uvh https://download.postgresql.org/pub/repos/yum/9.3/redhat/rhel-7-x86_64/pgdg-centos93-9.3-3.noarch.rpm && \
echo "Install Docker CE repository" && \
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo && \
echo "Install SmartMet packages" && \
yum -y install smartmet-base-international && \
echo "Update packages" && \
yum -y update
