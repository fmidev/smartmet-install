#!/bin/sh
echo "Install SmartMet Open repository" && \
dnf -y install https://download.fmi.fi/smartmet-open/rhel/9/x86_64/smartmet-open-release-latest-9.noarch.rpm && \
echo "Install yum utils" && \
dnf -y install yum-utils && \
echo "Install Docker CE repository" && \
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo && \
echo "Enable PowerTools" && \
dnf config-manager --set-enabled powertools && \
echo "Install EPEL repository" && \
dnf -y install epel-release && \
echo "Disable eccodes from EPEL" && \
dnf config-manager --setopt="epel.exclude=eccodes*" --save && \
dnf config-manager --set-disabled epel-source && \
echo "Disable postgresql:15 module" && \
dnf -y module disable postgresql:15 && \
echo "Install SmartMet packages" && \
dnf -y install smartmet-base-international && \
echo "Update packages" && \
yum -y update
