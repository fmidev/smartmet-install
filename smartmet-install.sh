#!/bin/sh
echo "Install SmartMet Open repository" && \
rpm -Uvh https://download.fmi.fi/smartmet-open/rhel/7/x86_64/smartmet-open-release-17.9.28-1.el7.fmi.noarch.rpm && \
echo "Install EPEL repository" && \
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm && \
echo "Install PostgreSQL repository" && \
rpm -Uvh https://download.postgresql.org/pub/repos/yum/9.3/redhat/rhel-7-x86_64/pgdg-centos93-9.3-3.noarch.rpm && \
echo "Install yum-utils package" && \
yum -y install yum-utils && \
echo "Install Docker CE repository" && \
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo && \
echo "Install SmartMet packages" && \
yum -y install smartmet-base-international && \
echo "Update packages" && \
yum -y update
