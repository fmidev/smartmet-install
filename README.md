# Install SmartMet Server Environment

* install RedHat or CentOS 7 minimal
* login as root
* run smartmet-install.sh as root user
```
curl -O https://raw.githubusercontent.com/fmidev/smartmet-install/master/smartmet-install.sh
chmod a+x smartmet-install.sh
./smartmet-install.sh
```
* Change password for smartmet user created by install script
```
passwd smartmet
```
* emacs /etc/samba/smb.conf (share directory /smartmet/editor for user smartmet):
```
[smartmet]
comment = SmartMet Data
path = /smartmet/editor
public = yes
writable = yes
printable = no
valid users = smartmet
```
