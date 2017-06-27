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
* systemctl restart smb
* Add password for samba user smartmet
```
smbpasswd -a smartmet
```
* Allow samba to write non standard locations if SELinux is enabled
```
setsebool -P samba_export_all_rw 1
```
