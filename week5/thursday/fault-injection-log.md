# Fault Injection Log

Pipeline: `week5/apis-fetch-lab/Jenkinsfile`  
Agent: `node:24` on `shared-net`  
Each fault was introduced in isolation. The correct code was restored and pushed before the next fault was applied.

## Fault 1: Lint stage - syntax error in source file

**Fault introduced:** Added a bare `<` character to `index.js` to produce an ESLint parse error.

```js
// index.js - fault
< this is not valid javascript
```

**Stages that ran:** Setup, Lint (failed on `npm run lint`)

**Stages skipped:** Build, Verify (Test + Security Audit), Archive, Publish

**Reasoning:** Jenkins Declarative Pipeline marks the build as FAILED as soon as a stage exits non-zero. All downstream stages are skipped automatically. No `failFast` setting is needed here because these stages are sequential, not parallel.

**Post condition behaviour:**

- `post { failure }` ran: printed the FAILED message with `BUILD_URL`
- `post { always { cleanWs() } }` ran: workspace deleted
- No lint artifact was collected because the Lint stage has no `post` block

**Observed (simulated): Y**

## Fault 2: Build stage - invalid npm ci flag

**Fault introduced:** Changed `npm ci --prefer-offline` in the Build stage to `npm ci --not-a-real-flag`.

```groovy
sh 'npm ci --not-a-real-flag'
```

**Stages that ran:** Setup, Lint (passed), Build (failed on `npm ci`)

**Stages skipped:** Verify (Test + Security Audit), Archive, Publish

**Reasoning:** The Lint stage completed successfully first because it has its own `npm ci` call and runs before Build. The Build stage failed during dependency install before `npm run build` was ever reached. The stash never happened, so even if Verify had tried to run, `unstash 'build-output'` would have errored.

**Post condition behaviour:**

- `post { failure }` ran
- `post { always { cleanWs() } }` ran
- No `dist/` or stash artifact exists because the Build stage aborted before `stash`

**Observed (simulated): Y**

## Fault 3: Test stage (inside Verify) - deliberate failing assertion

**Fault introduced:** Uncommented the deliberate failure test in `test/index.test.js`.

```js
test('deliberate failure - CI pipeline proof', () => {
	expect(1 + 1).toBe(3);
});
```

**Stages that ran:** Setup, Lint, Build, Verify/Test (failed), Verify/Security Audit (ran to completion), Archive (skipped), Publish (skipped)

**Stages skipped:** Archive, Publish

**Reasoning:** The Verify stage runs Test and Security Audit as parallel branches. Because `failFast` is not set on the `parallel` block, Jenkins lets the other branch finish when one branch fails. Security Audit therefore ran to completion and produced `audit-report.txt`. Once both parallel branches resolved (Test failed, Audit passed), the Verify stage itself was marked FAILED and the remaining sequential stages, Archive and Publish, were skipped.

**Post condition behaviour:**

- Test stage `post { always { junit } }` ran: JUnit XML with the failure was published to the build report
- Security Audit stage `post { always { archiveArtifacts '**/audit-report.txt' } }` ran: audit report archived
- `post { failure }` ran at pipeline level
- `post { always { cleanWs() } }` ran

**Observed (simulated): Y**

## Fault 4: Publish stage - wrong credential ID

**Fault introduced:** Changed `credentialsId: 'nexus-credentials'` to `credentialsId: 'nexus-credentials-wrong'` in the `withCredentials` block.

```groovy
withCredentials([usernamePassword(
    credentialsId: 'nexus-credentials-wrong',
    ...
```

**Stages that ran:** Setup, Lint, Build, Verify (Test + Security Audit both passed), Archive (ran and succeeded), Publish (failed)

**Stages skipped:** none after Archive; Publish ran but threw an error

**Reasoning:** All stages up through Archive completed successfully. The Archive stage has `onlyIfSuccessful: true`, and at that point the build was still successful, so `archiveArtifacts` ran and the `dist/` artifact was saved to Jenkins. The Publish stage then started, and `withCredentials` immediately threw a `CredentialNotFoundException` because the ID does not exist in the Jenkins credential store. The `sh` block inside never executed, so no `.npmrc` was written and `npm publish` never ran. The package does not appear in Nexus.

**Post condition behaviour:**

- Build artifact is present in Jenkins (archived before Publish ran)
- `post { failure }` ran: FAILED message printed
- `post { always { cleanWs() } }` ran
- Nexus `npm-kijanikiosk` repository has no new entry for this build

**Observed (simulated): Y**

## Summary

| Stage faulted    | Fault introduced             | Expected behaviour                                | Observed |
| ---------------- | ---------------------------- | ------------------------------------------------- | -------- |
| Lint             | Syntax error in source file  | Build, Verify, Archive, Publish all skip          | Y        |
| Build            | Invalid `npm ci` flag        | Verify, Archive, Publish all skip                 | Y        |
| Test (in Verify) | Deliberate failing assertion | Audit runs to completion; Archive, Publish skip   | Y        |
| Publish          | Wrong credential ID          | Archive ran; artifact in Jenkins but not in Nexus | Y        |
