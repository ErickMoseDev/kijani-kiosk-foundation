# Week 5 Thursday Reflection

## Question 1: Docker Agent Isolation in Depth

**Approach 1 (quickest): Switch to a different base image**

Change `image 'node:24'` to `image 'node:24-bookworm'` or another Debian-based image that includes native build tooling. Then install `libvips` in the `steps` block with `sh 'apt-get install -y libvips'` before running the app. This is the fastest change because it only touches one line in the Jenkinsfile.  
Disadvantage: `apt-get install` runs on every build, adding latency and depending on an external package registry being available at build time.

**Approach 2 (moderate): Mount a volume with the library pre-installed**

Use the `args` option to bind-mount a host directory containing the pre-built `libvips` files: `args '--network shared-net -v /opt/libvips:/usr/local/lib/libvips'`. The library is available without installing it at build time.  
Disadvantage: The Jenkins host must have the library pre-installed and kept up to date manually, which breaks the "declare, don't inherit" principle and ties the pipeline to a specific host configuration.

**Approach 3 (most maintainable): Write a custom Dockerfile**

Create a `Dockerfile` that extends `node:24` and adds `RUN apt-get install -y libvips`. Build and push it to a registry, then reference it in the Jenkinsfile with `image 'your-registry/node-libvips:24'`. The image is versioned and reproducible.  
Disadvantage: Adds a separate build and push step to maintain the custom image, and requires a container registry to host it.

## Question 2: Parallel Stage Design Decisions

Adding an 8-minute integration test suite that requires a running database to the Verify stage would push the total pipeline time well past 10 minutes. Even with parallelism, the pipeline cannot finish faster than its slowest branch. Every push would force developers to wait for a database to start, data to seed, and long-running tests to complete before they get any feedback. That delay breaks the feedback loop that a CI pipeline is designed to provide.

The correct architecture is to keep the Verify stage limited to fast, self-contained checks (unit tests and dependency audit) and move the integration suite to a separate downstream pipeline. In Jenkins, this is done with a second `Jenkinsfile` configured as a multibranch pipeline or a separate job that uses the `upstream` trigger or a post-build action to start only after the main pipeline passes. The integration pipeline can run on merge to the main branch rather than on every push, so it does not slow down developer feedback while still catching integration failures before deployment.

## Question 3: The Week as a Complete System

**Plain language (for the board):**

When a developer saves and submits their code changes, an automated process starts within seconds. It first checks that the code follows the formatting and style rules the team agreed on. If it does not, the process stops immediately and the developer is told what to fix. If the code looks correct, the process packages it into a deployable file, the same way every time, regardless of whose laptop or which server it runs on. It then runs the full set of automated checks the team has written, including tests that verify the application behaves correctly and a scan that flags any known security problems in the software it depends on. If all of those pass, the packaged file is saved to a central storage location with a unique version label that includes the exact code change it came from. From that point, the operations team can pick up that file and deploy it knowing exactly what code it contains and that it has passed every automated check.

**Technical explanation (for Tendo):**

A push to the repository triggers a Jenkins multibranch pipeline job. The pipeline runs inside a `node:24` Docker container attached to the `shared-net` Docker network, ensuring the runtime environment is fully declared and isolated from the Jenkins host. The Setup stage detects the working directory and constructs a semver artifact version by combining the `package.json` version with the short Git SHA. Lint runs `eslint` via `npm run lint` to enforce code style. Build runs `npm ci --prefer-offline` for a deterministic install, then `npm run build` to populate `dist/`, and stashes the output for downstream stages. The Verify stage runs Test and Security Audit in parallel: Jest produces JUnit XML consumed by the `junit` post step, and `npm audit --audit-level=high` writes to `audit-report.txt` which is archived via `archiveArtifacts` in `post { always }`. Archive saves the `dist/` tree to Jenkins with fingerprinting. Publish uses `withCredentials` to retrieve Nexus credentials, generates a Basic auth token via `base64`, writes a scoped `.npmrc`, runs `npm version` with `--no-git-tag-version`, and publishes to the `npm-kijanikiosk` hosted repository on Nexus with `--tag build`. `cleanWs()` runs unconditionally in `post { always }`.

**What is the same:** Both explanations describe the same sequence of events and the same outcome: code is checked, packaged, verified, and stored with a traceable version label.

**What is different:** The plain language explanation describes intent and business outcome (the team can trust the file, the version is traceable, the process is consistent). The technical explanation describes the exact mechanism at every step: tool names, flags, credential handling, artifact format, and network topology. The board needs to understand what the system does for the business. Tendo needs to understand how to maintain, debug, and extend it.

## Question 4: What the Pipeline Cannot Prevent

**Category 1: Logic errors and incorrect business behaviour**

The pipeline runs the test suite that exists in the repository. If a developer implements the wrong behaviour but writes tests that match that wrong behaviour, every check passes and the artifact is published. A fully green pipeline only proves the code does what the tests say it does, not that the tests describe the right thing. The check that catches this is human code review before the branch is merged, combined with acceptance testing by a product owner or QA engineer against the defined requirements. This belongs outside the CI pipeline because it requires human judgement about intent, not automated verification of correctness.

**Category 2: Runtime and environment-specific failures**

The pipeline builds and tests the application in a controlled Docker container with mocked or absent external dependencies. Problems that only appear when the application runs against a real database, a live third-party API, or under production load (race conditions, connection pool exhaustion, memory leaks, latency spikes) are invisible to the pipeline. `npm audit` catches known vulnerabilities in declared dependencies but does not catch misconfigured infrastructure, secrets exposed at runtime, or emergent behaviour under concurrent load. These are caught by integration tests, load tests, and staged rollout (canary or blue-green deployment) in a pre-production environment. These checks belong outside the CI pipeline because they require running infrastructure, realistic data, and time that would violate the 10-minute rule on every push.
