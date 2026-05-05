# KijaniKiosk Pipeline Design Review

## Evaluation Against Five Principles

### Principle 1: Fail Fast - PASS

Stage order is Setup, Lint, Build, Verify (Test + Security Audit in parallel), Archive, Publish. Lint runs first and catches syntax errors in roughly 30 seconds before the slower build and test stages run. Each stage only runs if the one before it passed.

### Principle 2: Declare, Don't Inherit - PARTIAL

All environment variables (`NODE_ENV`, `BUILD_DIR`, `APP_NAME`, `NEXUS_URL`) are declared in the `environment` block. Credentials come from the Jenkins store via `withCredentials`. The runtime uses an explicit Docker image rather than the Jenkins host. However, `node:24` is a mutable floating tag. A future image push could silently change the Node version without any change to the Jenkinsfile. Fix: pin to a digest, e.g. `node:24@sha256:<digest>`.

### Principle 3: Clean Up After Every Build - PASS

`cleanWs()` is in `post { always { ... } }`, so the workspace is deleted after every build regardless of outcome. One build's `node_modules`, `dist/`, or stale `.npmrc` cannot carry over into the next.

### Principle 4: Make Diagnostic Output Available Even on Failure - PARTIAL (improved below)

JUnit XML results from the Test stage are published in `post { always { junit ... } }`, which is correct. The Security Audit stage had no `post` block. When `npm audit` fails, the report only existed in the console output and would be deleted by `cleanWs()`. A developer investigating a vulnerability had nothing to inspect after the build finished.

**Improvement implemented:** The Security Audit stage now writes its output to `audit-report.txt` via `tee` (with `pipefail` to preserve the npm audit exit code) and archives that file in `post { always }`. The report is available as a downloadable build artifact on both passing and failing runs.

### Principle 5: The 10-Minute Rule - PASS

The pipeline timeout is set to 15 minutes, but actual wall-clock time is well under 10 minutes. Lint and build are sequential at roughly 1-2 minutes each. The slowest steps, tests and security audit, run in parallel inside the `Verify` stage. Publish only runs after everything passes, so slow operations do not delay developer feedback.

## Improvement Implemented

**Principle:** 4 - diagnostic output not available on failure  
**Stage affected:** `Security Audit`  
**Change:** Redirected `npm audit` output to `audit-report.txt` using `tee` inside a `pipefail` shell, and added `post { always { archiveArtifacts } }` to persist the report as a build artifact regardless of whether the audit passed or failed.

Before:

```groovy
stage('Security Audit') {
    steps {
        dir(env.APP_DIR) {
            echo 'Running dependency security audit...'
            sh 'npm audit --audit-level=high'
        }
    }
}
```

After:

```groovy
stage('Security Audit') {
    steps {
        dir(env.APP_DIR) {
            echo 'Running dependency security audit...'
            sh '''
set -o pipefail
npm audit --audit-level=high 2>&1 | tee audit-report.txt
'''
        }
    }
    post {
        always {
            archiveArtifacts artifacts: '**/audit-report.txt',
                             allowEmptyArchive: true
        }
    }
}
```

`set -o pipefail` ensures the shell exits with `npm audit`'s exit code rather than `tee`'s (which is always 0), preserving the fail-on-high-severity behaviour. `allowEmptyArchive: true` prevents the archive step from failing if the audit exited before writing the file.
