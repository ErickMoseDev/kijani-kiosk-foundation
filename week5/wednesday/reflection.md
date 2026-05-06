# Week 5 Wednesday Reflection

## Question 1: Artifact Versioning Under Real Team Conditions

Developer A merges first. The pipeline checks out that commit, reads `1.0.0` from `package.json`, and gets the short SHA for that commit, say `a3f2c8b`. It publishes `kijanikiosk-payments@1.0.0-a3f2c8b` to Nexus with `--tag build`.

Developer B merges while that pipeline is still running. Their pipeline checks out a different commit with SHA `b7d9e2a` and publishes `kijanikiosk-payments@1.0.0-b7d9e2a`.

These two version strings are completely different. They do not conflict at all, even with Disable redeploy turned on. The short SHA is what makes them unique. Disable redeploy only blocks a second publish attempt for the exact same version string. Since `a3f2c8b` and `b7d9e2a` are different strings, Nexus treats them as two separate packages and accepts both without complaint.

This is exactly why the git SHA is included in the version. The `package.json` version alone would conflict on every build until someone bumped it. The SHA makes each CI-produced artifact immutable and traceable back to the specific commit it came from.

## Question 2: The withCredentials Masking Limit

Jenkins masks credentials by scanning log output for the literal string value of the secret. If the password is `hunter2`, Jenkins replaces every occurrence of `hunter2` in the log with `****`.

The specific scenario is the Base64 encoding step in the Publish stage. The pipeline runs `echo -n "${NEXUS_USER}:${NEXUS_PASS}" | base64` and stores the result in `NEXUS_TOKEN`. The raw password `hunter2` gets masked, but `NEXUS_TOKEN` now holds `aHVudGVyMg==`. Jenkins has no knowledge of that derived value and does not mask it. If anything in the script prints `NEXUS_TOKEN`, or if an error message from npm includes the auth header, the Base64 string appears in the log in plain text. Anyone who sees it can run `echo aHVudGVyMg== | base64 -d` and recover the password immediately.

The defence is to never print the token variable and to write it directly into `.npmrc` without echoing it, which the current pipeline already does. The cleanup `rm -f .npmrc` at the end of the step enforces this by removing the file before Jenkins archives any workspace artifacts. This practice should be enforced in the same `sh` block that creates the file, not in a separate step, so a mid-stage failure cannot leave the file behind before the `post` block runs.

## Question 3: The Immutability Requirement

The incident immutability prevents is a silent dependency swap. Here is the failure chain.

Team A deploys version `2.1.0` of the payments library to production. It works. Three weeks later, a developer on Team B notices a bug fix they need is only in `2.1.0` and they have not published a new version yet, so they republish their own build as `2.1.0`, quietly overwriting what Team A had put there.

Team A's deployment pipeline triggers for an unrelated reason, pulls `2.1.0` from the registry, and deploys Team B's code to the payments service. Neither team is aware this happened. The version number in every log, every alert, and every rollback script still says `2.1.0`, so the change is invisible.

This is particularly dangerous in a shared registry because each team assumes that a version string they have already validated points to the same bytes it did last time they checked. With overwrite allowed, that assumption is false and there is no warning when it breaks. Immutability makes the version string a permanent, trustworthy reference.

## Question 4: Credential Rotation

When the Nexus password is rotated, here is exactly what happens in each system.

In Nexus: an administrator goes to the admin panel and changes the password for the account that Jenkins uses to publish. The old password stops working immediately.

In Jenkins: an administrator opens Manage Jenkins, goes to Credentials, finds the credential stored under the ID `nexus-credentials`, and updates the password field to the new value. Jenkins saves the new password and starts using it for all future builds.

In the Jenkinsfile: nothing. Not a single character changes.

The Jenkinsfile references the credential by its ID string `nexus-credentials`. That ID is just a lookup key. The actual secret value lives only inside Jenkins' encrypted credential store and is never written into the pipeline code. When Jenkins runs `withCredentials([usernamePassword(credentialsId: 'nexus-credentials', ...)])`, it fetches the current value from the store at runtime. Since the store was updated in step two, the next build automatically uses the new password.

This separation is valuable because the Jenkinsfile is committed to the git repository and visible to anyone with repo access. If credentials were stored there, rotation would require a code change, a pull request, a review, and a merge, and the old password would remain in git history forever. Storing secrets only in Jenkins means rotation is a single admin action with no code exposure and no git history to clean up.
