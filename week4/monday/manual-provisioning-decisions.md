# Manual Provisioning Decisions - KijaniKiosk API Server

| Decision         | Value I chose            | Reason                                                                                                                                              |
| ---------------- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cloud Provider   | Amazon Web Services      | AWS has the closest African region (Cape Town) to KijaniKiosk's Kenyan user base, reducing latency compared to providers without an Africa presence |
| Region           | Africa (Cape Town)       | Closest AWS region to East Africa, minimizing network latency for Kenyan customers as recommended in our regions-azs strategy                       |
| Operating System | Ubuntu 24.04.4 LTS       | LTS release ensures 5 years of security patches and stable package support; widely documented and compatible with the application stack             |
| Instance Type    | t3.micro                 | Sufficient CPU and memory for a low-traffic API server in a non-production lab environment; falls within the AWS free tier                          |
| VPC              | vpc-075e27fb21f6549ca    | Default VPC in the Cape Town region; acceptable for a lab/dev workload without custom networking requirements                                       |
| Subnet           | subnet-04977da9e75e06cc9 | Public subnet within the chosen VPC, allowing the instance to receive inbound traffic and be reachable over SSH                                     |
| Security Group   | launch-wizard-1          | Auto-generated security group created during launch; permits SSH access for initial configuration of the server                                     |
| SSH key Pair     | personal laptop          | Existing key pair on the local machine, enabling passwordless SSH access without generating and distributing a new key                              |
| Root volume size | 8 GB                     | Default size for Ubuntu on AWS; adequate for the OS, packages, and a lightweight API server with no large data storage needs                        |
| Public IP?       | 13.245.4.6               | Public IP assigned so the API server is reachable from the internet for testing and SSH administration                                              |
| Tags / Labels    | week4-monday             | Identifies the instance by the week and day of the content it was supposed to be provisioned                                                        |

# Recorded Output after Provisioning the VM

`uname -a`

```
Linux ip-172-31-10-109 6.17.0-1007-aws #7~24.04.1-Ubuntu SMP Thu Jan 22 21:04:49 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux
```

`lsb_release -a`

```
No LSB modules are available.
Distributor ID:	Ubuntu
Description:	Ubuntu 24.04.4 LTS
Release:	24.04
Codename:	noble
```

`df -h`

```
Filesystem       Size  Used Avail Use% Mounted on
/dev/root        6.8G  1.8G  4.9G  27% /
tmpfs            456M     0  456M   0% /dev/shm
tmpfs            183M  872K  182M   1% /run
tmpfs            5.0M     0  5.0M   0% /run/lock
efivarfs         128K  3.6K  120K   3% /sys/firmware/efi/efivars
/dev/nvme0n1p16  881M   94M  726M  12% /boot
/dev/nvme0n1p15  105M  6.2M   99M   6% /boot/efi
tmpfs             92M   12K   92M   1% /run/user/1000
```

`free -h`

```

            total        used      free      shared      buff/cache   available
Mem:        911Mi        370Mi     319Mi     2.7Mi       379Mi        541Mi
Swap:       0B           0B        0B
```

`ip addr show`

```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq state UP group default qlen 1000
    link/ether 06:90:a6:52:61:ab brd ff:ff:ff:ff:ff:ff
    altname enp0s5
    inet 172.31.10.109/20 metric 100 brd 172.31.15.255 scope global dynamic ens5
       valid_lft 2201sec preferred_lft 2201sec
    inet6 fe80::490:a6ff:fe52:61ab/64 scope link
       valid_lft forever preferred_lft forever
```
