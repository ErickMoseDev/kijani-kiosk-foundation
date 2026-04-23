# Week 5 Monday Reflection

## 1. What Today's Pipeline Does Not Do

Tendo is right. The pipeline checks that Node.js is installed, which is a health check on the Jenkins agent, not on the code. CI has three properties: every push triggers the pipeline, the code is built, and the build is verified with automated tests. The current pipeline does none of those last two things.

**What is missing and what to add:**

The first missing property is a build step. For a Node.js project, building means installing dependencies. Without `npm install`, there is nothing to test and no guarantee that the project's dependency tree resolves correctly. I would add a stage before any testing:

```groovy
stage("Install") {
    steps {
        sh 'npm install'
    }
}
```

The second missing property is automated test execution. This is the core of CI. The pipeline must run the test suite and fail the build if any test fails. Since the project uses Jest, the stage would look like this:

```groovy
stage("Test") {
    steps {
        sh 'npm test'
    }
}
```

`npm test` calls the `test` script in `package.json`, which Jest is wired to. If Jest exits with a non-zero code (any test fails), the pipeline marks the build as failed. That failure signal is the point of CI. Without it, pushing broken code has no consequence in the pipeline.

The third missing property is that the trigger must be automatic. A pipeline you run manually is not CI. The webhook or SCM polling configuration ensures every push fires the pipeline without anyone clicking a button. This is already partially addressed by the trigger configuration, but it only matters when the build and test stages are also present. A pipeline that automatically runs a node version check is still not CI.

So the full pipeline that satisfies all three properties would be: trigger on push, run `npm install`, run `npm test`. Everything else is optional until those three are in place.

## 2. The Broken-Build Contract in Practice

**A realistic exception argument:**

A developer is three days into a feature that requires a schema migration. The board review is in two weeks. They push a commit that breaks the test suite because the migration is half-written and the tests that depend on the old schema now fail. Their argument: "I am in the middle of something complex. The migration will take another day to finish. If I revert now, I lose the progress on the feature branch and I will have to redo the work. Can we just leave it for 24 hours while I finish?"

This sounds reasonable. It is not.

**Why the exception is more costly than it appears:**

The moment main is broken, every other developer on the team loses a stable base to work from. If anyone pulls main to start a new feature or sync their branch, they pull the broken state. They now either work on top of broken code (meaning their own tests will fail for reasons unrelated to their changes) or they stop and wait. In a four-person team, three people are now blocked or working with degraded confidence in their own output.

The other cost is diagnostic. Tomorrow, when another developer's push also breaks something, it is no longer clear whether the new failure is related to the original broken migration or is an independent problem. The two failures compound. Debugging time doubles because you have to untangle which broken thing caused which symptom.

Over a two-week sprint the compounding works like this: the first exception is granted on day two. Main stays broken for 24 hours. On day four, a second developer hits a conflict with the broken migration code and decides their fix can also wait one day because "the build is already broken anyway." By day six, two people have internalized that a broken main is acceptable. By day ten, nobody is checking the build status before pushing. The feedback loop that CI was meant to provide has stopped working socially, not technically.

The board review is in three weeks. On day thirteen, someone tries to cut a release from main and discovers that four separate changes have never been tested against each other. That is the real cost of the first "just this once."

The fix for the original scenario is not to leave main broken. The developer should push their migration work to a feature branch, keep main clean, and only merge when the migration and its tests are both complete.

## 3. The Jenkinsfile in the Repository

**Problem one: no recovery after a server failure.**

When Jenkins is rebuilt after a server failure, the server itself is gone. Everything configured through the UI, pipeline steps, environment variables, stage names, credentials references, is gone with it. Rebuilding the pipeline means someone has to remember exactly how it was configured and re-enter it by hand. In practice, nobody remembers exactly. The rebuilt pipeline is subtly different from the original, and those differences only surface when a specific code path triggers the step that was misconfigured.

If the Jenkinsfile lives in the repository, rebuilding Jenkins takes five minutes. You point a new pipeline job at the repository, Jenkins reads the Jenkinsfile, and the pipeline is exactly what it was before the server failed. The repository is the source of truth, and the repository did not go down when Jenkins did.

**Problem two: pipeline changes cannot be reviewed.**

When a developer wants to change the pipeline, for example to add a new test stage or change a deployment target, and the pipeline lives only in the UI, the change happens in the Jenkins interface and goes live immediately. There is no pull request. There is no code review. There is no diff. Nobody else on the team sees the change unless they happen to open the Jenkins UI and compare it to what they remember.

If the Jenkinsfile lives in the repository, a pipeline change is a code change. It goes through the same pull request process as any other change. A teammate can read the diff, ask why a stage was added, catch a mistake in a shell command, or flag that a new environment variable is being referenced but was never added to Jenkins credentials. The pipeline definition becomes auditable and reviewable, which is exactly what the rest of the codebase already is.

## 4. Webhooks vs Polling

**The mechanism I used (webhook):**

When I push to the repository, GitHub sends an HTTP POST request to a specific URL on the Jenkins server. That URL is the webhook endpoint Jenkins exposes. The payload of the request contains metadata about the push: which branch, which commit, which files changed. Jenkins receives the request, matches it to the configured pipeline job, and starts the build immediately. The entire sequence from push to pipeline start takes a few seconds. Jenkins is passive until GitHub contacts it.

**Where polling would be more appropriate:**

Polling makes more sense when Jenkins cannot receive inbound connections from GitHub. This is common when Jenkins runs inside a corporate network behind a firewall that blocks external HTTP traffic. In that environment, GitHub cannot reach Jenkins to deliver a webhook. Polling flips the direction: Jenkins reaches out to GitHub instead. Jenkins asks "has anything changed since I last checked?" on a schedule, and if the answer is yes, it starts the build.

**Where the latency cost of polling becomes real:**

At five-minute polling intervals, a developer waits up to five minutes after pushing before the pipeline starts. For one developer pushing twice a day, that delay is irrelevant. But the latency cost is not about individual pushes, it is about the feedback loop across the whole team.

Consider a four-person team where each developer pushes three times a day. That is twelve pushes per day. With a five-minute maximum delay per push, the team collectively waits up to sixty minutes of pipeline-start delay per day. More importantly, if two developers push within the same five-minute window, both pushes are detected in the same poll and both builds start at the same time. Neither developer gets feedback until the build finishes, which might be another five to ten minutes. A developer who pushed a breaking change might not know about it for ten minutes after the push.

At that team size and push frequency (three to four developers, two to four pushes per person per day), the delay starts to slow down the debug-fix-push cycle in a noticeable way. At ten or more developers each pushing frequently, polling every five minutes means someone is almost always waiting unnecessarily. That is when the gap between polling and webhooks becomes a real argument for switching, even if it requires network changes to allow inbound connections.
