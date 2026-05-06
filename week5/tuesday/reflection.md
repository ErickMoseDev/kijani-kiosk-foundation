# Week 5 Tuesday Reflection

## Question 1: What the Red Build Proved

Build showing green while Test showed red proved that the stages are isolated units of work. The `npm ci` and `npm run build` steps have nothing to do with test correctness, so they completed with exit code 0. The Test stage ran `npm test` via Jest, which returned a non-zero exit code when the assertion failed, and Jenkins treats any non-zero exit from an `sh` step as a stage failure.

Archive not running proved that `onlyIfSuccessful: true` on `archiveArtifacts` works as intended. There is no point storing a dist folder that came from a build whose tests are known to be broken.

The `post { failure }` block running proved that post conditions are evaluated after all stages settle, not just when a stage fails. Jenkins ran `echo "Pipeline FAILED: apis-and-fetch build ..."` because the overall build result was FAILURE.

If a syntax error crashed Jest instead of producing a failing test, the behavior would look similar from the stage view but for a different reason. Jest would exit with code 1 before writing any test-results/junit.xml, so the JUnit step in `post { always }` would find no XML file. The stage view would still show Test in red, but the test trend graph in Jenkins would show no results rather than one failed test. `allowEmptyResults: true` prevents the JUnit step itself from adding a second failure on top of the Jest crash.

## Question 2: npm ci vs npm install in a Team Context

Imagine the KijaniKiosk team finishes sprint work on Monday. The pipeline runs `npm install`, everything passes, and `package-lock.json` records `jest` at `29.7.0`. On Tuesday morning, the Jest maintainers publish `29.7.1` to the npm registry. No developer touches any code. When the pipeline triggers on a new commit, `npm install` sees that `29.7.1` satisfies the `^29.7.0` range in `package.json` and installs the newer version. If that patch release introduced a regression in jsdom test handling, the build goes red for a reason that has nothing to do with the team's code changes.

The mechanism is that `npm install` resolves semver ranges against the live registry at the time it runs. It can install a different version on Tuesday than it did on Monday.

`npm ci` prevents this by ignoring `package.json` ranges entirely and installing exactly the versions recorded in `package-lock.json`. If `package-lock.json` says `jest 29.7.0`, that is what gets installed, every time, on every machine and every CI run, until a developer deliberately runs `npm install` locally and commits the updated lock file.

## Question 3: The Archived Artifact (Looking Ahead)

For the disk concern, an artifact store needs a retention policy. It should be able to automatically delete old versions after a configurable number of builds or after a set time period, so the disk does not grow unbounded. It also helps if artifacts are deduplicated at the byte level, so storing ten builds that share the same unchanged `styles.css` does not cost ten times the space.

For the other-machine concern, an artifact store needs a network-accessible address and a stable URL scheme per artifact version. Any machine on the team's network should be able to pull a specific build by its version number or build ID without having access to the Jenkins server directly. It also needs to be able to serve the artifact reliably after the originating Jenkins workspace has been cleaned, which `cleanWs()` does at the end of every build in the current pipeline.

Together: versioned storage, retention policies, and a pull-by-version API.

## Question 4: What Tuesday's Pipeline Still Cannot Do

The pipeline cannot catch a security vulnerability in a dependency. Nia is right to ask. `npm ci` installs exactly what is in `package-lock.json` and `npm test` runs Jest unit tests. Neither step inspects the CVE status of any installed package. A developer could push code that pulls in a version of, say, `jest-environment-jsdom` with a known prototype pollution issue and the pipeline would pass every stage without a warning.

Two categories of checks that would address this gap are dependency scanning and static analysis.

For dependency scanning, `npm audit` is already bundled with npm and can be added as a step in the Build stage right after `npm ci`. It queries the npm advisory database and exits with a non-zero code if any installed package has a known vulnerability above a configurable severity threshold. A more thorough option is Snyk, which has a CLI that integrates directly into Jenkins pipelines.

For static analysis, ESLint is already a dev dependency in this project. Adding a Lint stage that runs `npx eslint .` after Build would catch insecure coding patterns like `eval()` use or `dangerouslySetInnerHTML` assignments. The eslint-plugin-security plugin adds rules specifically aimed at Node.js security issues.

The dependency scan belongs in the Build stage or immediately after it, because it validates the installed dependency tree before anything else runs. The lint step belongs in its own stage after Build so the results are reported separately and do not hide behind a generic build failure.
