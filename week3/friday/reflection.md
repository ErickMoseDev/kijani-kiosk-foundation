# Reflection

## 1. When did two requirements conflict, and what did I learn?

I hit this when I was working on the logrotate config and realized it was going to break the ACL setup from Tuesday. The problem is that logrotate's `create 0660 kk-logs kijanikiosk` only sets normal UNIX permissions on the new file,it doesn't know anything about ACLs. So after a rotation, kk-api and kk-payments would lose write access to the new log file, and logs would just silently stop.

The fix was making sure the default ACLs on the shared/logs directory were set up properly in Phase 3 with `setfacl -d`. Default ACLs automatically get applied to any new file created in that directory, including the ones logrotate creates. I also needed the `su kk-logs kijanikiosk` line in the logrotate config so it wouldn't choke on the SGID 2770 directory.

The big takeaway for me was that things can work fine on their own but break when you put them together. The logrotate config was fine. The ACLs were fine. But together they had a gap. I only caught it because I ran `sudo -u kk-api touch` after a forced rotation,that's the test that actually proves it works end to end.

## 2. Rewriting one sentence for Tendo

**Nia version (from hardening-decisions.md):**

> "An attacker who gains code execution inside a service cannot escalate to administrator access."

**Tendo version:**

> "Setting `CapabilityBoundingSet=` to empty drops all 41 Linux capabilities from the bounding set, so even if someone gets RCE in the kk-payments process, they can't re-acquire `CAP_SYS_ADMIN` or any other capability through `execve()`,the kernel blocks it at the bounding set check."

What you gain is precision,Tendo can look at that and know exactly which mechanism is doing the work and verify it's correct. What you lose is that Nia would stop reading after "bounding set." She cares about the risk ("can't become admin"), not the kernel internals. For Nia the _what_ matters, for Tendo the _how_ matters.

## 3. The most fragile part of the script

The hardcoded nginx version string,`nginx=1.24.0-2ubuntu7.6`. That version suffix is tied to this specific Ubuntu release. On a different release, different arch, or a different apt mirror, that exact package probably won't exist and the whole script fails on Phase 1.

To fix this I'd need to know:

- What Ubuntu release and architecture the target servers run
- Whether there's a private apt mirror (which might not have this exact version)
- Whether the policy is "this exact build" or "any 1.24.x"

A better approach would be pinning to a version range or hosting the `.deb` in an internal artifact repo so we're not depending on the upstream archive still having that specific build available.
