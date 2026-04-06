# KijaniKiosk API Server - Triage Report

**Date:** 3/4/2026  
**Investigated by:** Erick Mong'are  
**Server:** 127.0.0.1
**Incident start (approximate):** First ERROR logged at 2024-01-15 04:07:55

## Summary

The server reached significant resource exhaustion. I discovered a rogue Python process eating more than 500MB of RAM, as well as a 200MB "orphaned" log file that was causing artificial disk pressure. These circumstances, combined with a misconfigured database connection pool, resulted in service denial.

## Process and Resource State

| USER  | PID    | %CPU | %MEM | VSZ      | RSS     | TTY | STAT | START | TIME      | COMMAND                                                                                                                         |
| ----- | ------ | ---- | ---- | -------- | ------- | --- | ---- | ----- | --------- | ------------------------------------------------------------------------------------------------------------------------------- |
| erick | 140639 | 0.5  | 6.5  | 2610324  | 1049160 | ?   | Sl   | Mar31 | 25:46:00  | VBoxHeadless (ansible_default)                                                                                                  |
| erick | 684168 | 1.1  | 3.6  | 1.46E+09 | 580936  | ?   | Sl   | 22:32 | 0:52      | Code --type=utility (NodeService)                                                                                               |
| erick | 3224   | 2.3  | 3.2  | 51633724 | 528904  | ?   | SLl  | Mar30 | 145:26:00 | /opt/brave.com/brave/brave                                                                                                      |
| root  | 676375 | 0    | 3.2  | 543000   | 523412  | ?   | S    | 22:08 | 0:00      | python3 -c import time x =[] for i in range(500): x.append(' ' _ 1024 _ 1024) print('Memory consumer running') time.sleep(3600) |
| erick | 3890   | 0.1  | 2.3  | 1.46E+09 | 374360  | ?   | Sl   | Mar30 | 6:53      | brave --type=renderer                                                                                                           |
| erick | 685337 | 0.1  | 2    | 1.46E+09 | 330580  | ?   | Sl   | 22:33 | 0:06      | vscode-pylance server.bundle.js                                                                                                 |
| erick | 684121 | 1.8  | 2    | 1.46E+09 | 324808  | ?   | Sl   | 22:32 | 1:27      | code --type=zygote                                                                                                              |
| erick | 3458   | 0.2  | 1.8  | 1.46E+09 | 301996  | ?   | Sl   | Mar30 | 17:06     | brave --type=renderer                                                                                                           |

## Filesystem and Disk

The /var/log/ directory is bloated due to a simulated log rotation failure.

- Large File: /var/log/kijanikiosk/access.log.1 (271 MB).

- Observation: This file was generated using random data (/dev/urandom), suggesting it is not a functional log but a "space-filler" causing disk contention.

| ls -lhs                                                   |
| --------------------------------------------------------- |
| total 271M                                                |
| 271M -rw-r--r-- 1 root root 271M Apr 3 22:08 access.log.1 |
| 4.0K -rw-r--r-- 1 root root 776 Apr 3 22:08 app.log       |

## Log Analysis

Review of /var/log/kijanikiosk/app.log shows a clear degradation pattern:

- 03:45:10: Warning — DB connection pool at 85%.

- 04:01:33: Warning — DB connection pool at 94%.

- 04:07:55: CRITICAL — Connection pool exhausted; requests began queuing.

- 06:22:18: ERROR — ECONNREFUSED database:5432.

Pattern: The application was gradually starved of database handles until the connection was dropped entirely.

## Network and Service State

- Port 80 (Nginx): Service is installed and listening, but likely serving upstream errors (502/504) because the backend cannot reach the DB.

- Port 5432 (Postgres): Connection refused. This suggests either the database process crashed due to the memory pressure or is rejecting connections due to the pool being full.

## Assessment

The root cause is Resource Starvation. The rogue Python process consumed the "safety net" of available RAM, leading to slower I/O. Simultaneously, the application reached its hard-coded database connection limit. Once the pool was exhausted, the application could no longer process requests, resulting in the ECONNREFUSED state seen in the final log entries.

[Your best hypothesis for the root cause of the latency increase]

## Recommended Next Steps

1. Immediate Remediation: Terminate the rogue process (kill -9 676375) and delete the bloated log file (rm /var/log/kijanikiosk/access.log.1) to restore system overhead.

2. Configuration Tuning: Increase the max_connections in the database and adjust the application's connection pool settings to handle higher concurrency.

3. Prevention: Implement a logrotate policy for the /var/log/kijanikiosk/ directory and set up an alert for memory usage exceeding 80%.
