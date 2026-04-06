# Multi-Component Access Control Tasks

Commands for the tasks in the challenge

## Task 1

- Create three system service accounts following least-privilege principles. Each account must have no login shell, no home directory, and a descriptive comment.

```
sudo useradd -r -s /usr/sbin/nologin -M -c "Kijani Kiosk Nodejs API service" kk-api
sudo useradd -r -s /usr/sbin/nologin -M -c "Kijani Kiosk Payment processing service" kk-payments
sudo useradd -r -s /usr/sbin/nologin -M -c "Kijani Kiosk Log aggregation service" kk-logs
```

- Create a shared kijanikiosk group and add all three service accounts plus your regular user to it

```
sudo usermod -aG kijanikiosk kk-api
sudo usermod -aG kijanikiosk kk-payments
sudo usermod -aG kijanikiosk kk-logs
```

## Task 2

1. Confirm the current dangerous state using find and stat

```
find /opt/kijanikiosk -perm -4000 -ls
stat /opt/kijanikiosk/scripts/deploy.sh
```

2. Remove the SUID bit from `deploy.sh`

```
sudo chmod u-s /opt/kijanikiosk/scripts/deploy.sh
```

3. Remove the world-write and world-execute permissions

```
sudo chmod o-w /opt/kijanikiosk/scripts/deploy.sh
sudo chmod o-x /opt/kijanikiosk/scripts/deploy.sh
```

4. Set the final permissions to 750 owned by `root:root`

```
sudo chmod 750 /opt/kijanikiosk/scripts/deploy.sh
sudo chown root:root /opt/kijanikiosk/scripts/deploy.sh

output:
-rwxr-x--- 1 root root 44 Apr  6 15:02 /opt/kijanikiosk/scripts/deploy.sh
```

## Task 3

- /opt/kijanikiosk/api/: owned by kk-api:kk-api, mode 750

```
sudo chown kk-api:kk-api /opt/kijanikiosk/api/
sudo chmod 750 /opt/kijanikiosk/api/

output: sudo ls -lh /opt/kijanikiosk/

drwxr-x--- 2 kk-api kk-api 4.0K Apr  6 15:02 api
```

- /opt/kijanikiosk/payments/: owned by kk-payments:kk-payments, mode 750

```
sudo chown kk-payments:kk-payments /opt/kijanikiosk/payments/
sudo chmod 750 /opt/kijanikiosk/payments/

output: sudo ls -lh /opt/kijanikiosk/

drwxr-x--- 2 kk-payments kk-payments 4.0K Apr  6 15:02 payments
```

- /opt/kijanikiosk/logs/: owned by kk-logs:kk-logs, mode 750

```
sudo chown kk-logs:kk-logs /opt/kijanikiosk/logs/
sudo chmod 750 /opt/kijanikiosk/logs/

output: sudo ls -lh /opt/kijanikiosk/

drwxr-x--- 2 kk-logs     kk-logs     4.0K Apr  6 15:02 logs

```

- /opt/kijanikiosk/config/: owned by root:kijanikiosk, mode 640 for files, 750 for the directory itself

```
sudo chown root:kijanikiosk /opt/kijanikiosk/config/
sudo chmod 750 /opt/kijanikiosk/config/

- for files: sudo chmod 640 /opt/kijanikiosk/config/*.env

output:

drwxr-x--- 2 root        kijanikiosk 4.0K Apr  6 15:02 config
```

- /opt/kijanikiosk/shared/logs/: owned by kk-logs:kk-logs, mode 2770 (SGID set)

```
sudo chown kk-logs:kk-logs /opt/kijanikiosk/shared/logs/
sudo chmod 2770 /opt/kijanikiosk/shared/logs/

output: sudo ls -lh /opt/kijanikiosk/shared/
drwxrws--- 2 kk-logs kk-logs 4.0K Apr  6 15:02 logs
```

- kk-api write access to /opt/kijanikiosk/shared/logs/

```
sudo setfacl -m u:kk-api:rwx /opt/kijanikiosk/shared/logs/
```

- kk-payments read access to /opt/kijanikiosk/shared/logs/

```
sudo setfacl -m u:kk-payments:rx /opt/kijanikiosk/shared/logs/
```

- Your regular user read access to /opt/kijanikiosk/shared/logs/ and read access to /opt/kijanikiosk/config/

```
sudo setfacl -m u:erick:rx /opt/kijanikiosk/shared/logs/
sudo setfacl -m u:erick:rx /opt/kijanikiosk/config/
```

## Task 4

```
sudo tee /etc/sudoers.d/amina << 'EOF'

Cmnd_Alias KK_SERVICES = /usr/bin/systemctl restart kk-api, /usr/bin/systemctl restart kk-payments, /usr/bin/systemctl restart kk-logs, \
                         /usr/bin/systemctl status kk-api, /usr/bin/systemctl status kk-payments, /usr/bin/systemctl status kk-logs
Cmnd_Alias KK_LOGS = /usr/bin/journalctl -u kk-api, /usr/bin/journalctl -u kk-payments, /usr/bin/journalctl -u kk-logs
Cmnd_Alias KK_NGINX = sudoedit /etc/nginx/nginx.conf

amina ALL=(ALL:ALL) NOPASSWD: KK_SERVICES, KK_LOGS, KK_NGINX
EOF

sudo chmod 440 /etc/sudoers.d/amina
```
