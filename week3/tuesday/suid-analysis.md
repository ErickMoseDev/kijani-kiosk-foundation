# 1. Why does the kernel ignore SUID on interpreted scripts?

The kernel ignores SUID on scripts because there’s a tricky timing problem that could be exploited. When you run a script, the kernel first opens it just to check the shebang (#!) line so it knows which interpreter to use. Then it closes the file and tells something like /bin/bash to run it.

The issue is that there’s a tiny gap between those two steps. In that moment, a malicious user could swap out the original script with something else,like a symbolic link to a different file. If the script had the SUID bit set, the system might end up running that new, malicious file with root privileges.

To avoid this risk entirely, modern systems just ignore the SUID bit on scripts and only allow it on compiled binaries.

# 2. If the SUID bit has no effect on this script, why is the combination of SUID plus world-write still a critical finding?

This is a serious issue because it points to poor system management and risky intentions. Even if the kernel currently ignores the SUID bit on scripts, the fact that it’s set suggests someone meant for this script to run with root privileges.

What makes it worse is that the script is world-writable, meaning any user on the system can change its contents. So even if the SUID bit doesn’t work when the script is run directly, it’s still dangerous. If a legitimate root process runs that script, it will execute whatever code is inside it at that moment.

That means an attacker can simply modify the script and wait for it to be executed by something with root access, effectively guaranteeing a privilege escalation.

# 3. What would make this scenario exploitable in practice?

In this specific scenario, the audit noted that the script is executed by a root-owned cron job. Because the script is world-writable, an attacker can simply append a reverse shell command to the end of deploy.sh. The next time the cron job triggers, the system will execute the attacker's code as root, bypassing the kernel's SUID protections entirely and granting full system control.

### References

1. https://security.stackexchange.com/questions/194166/why-is-suid-disabled-for-shell-scripts-but-not-for-binaries
2. https://coderwall.com/p/gmozfg/never-set-suid-bit-on-shell-scripts
3. https://docstore.mik.ua/orelly/networking/puis/ch05_05.htm
