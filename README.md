# Install SmartMet Server Environment

* install AlmaLinux 8 minimal https://mirrors.almalinux.org/isos.html or Rocky Linux 8 https://rockylinux.org/download
  * enable network
  * enable ntp
  * create and mount biggest partition as /smartmet
* login as root
* run smartmet-install.sh as root user
```
curl -O https://raw.githubusercontent.com/fmidev/smartmet-install/master/smartmet-install-8.sh
chmod a+x smartmet-install-8.sh
./smartmet-install-8.sh
```
* Change password for smartmet user created by install script
```
passwd smartmet
```
* Add password for samba user smartmet
```
smbpasswd -a smartmet
```
* yum install smartmet-data-gfs (if needed) edit area and times /smartmet/cnf/data/gfs.cnf
* yum install smartmet-data-gem (if needed) edit area and times /smartmet/cnf/data/gem.cnf
* yum install smartmet-data-metar (if needed)
* edit correct timezone to /etc/php.d/smartmet.ini
