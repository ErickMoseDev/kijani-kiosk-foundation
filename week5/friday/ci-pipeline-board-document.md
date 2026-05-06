# From Code Change to Deployable Software: How Our Pipeline Works

**Prepared for the Kijani Kiosk Board of Directors**

## What Problem This Solves

Before this pipeline existed, getting a code change into production required a developer to manually run checks, manually package the software, and manually hand it off to the operations team. Each of those hand-offs was a chance for something to be missed. A test could be skipped under time pressure. A version number could be wrong. A package could be built from untested code.

The pipeline removes those hand-offs. From the moment a developer pushes code, a repeatable, automated process takes over and either produces a verified artifact ready for deployment or stops and tells the team exactly where the problem is.

## What Happens Between a Code Push and a Versioned Artifact

A developer finishes a change to the payment service and pushes it to the shared code repository. Within seconds, the pipeline wakes up automatically. It does not wait for a human to start it.

The pipeline works through five stages in order. Each stage must pass before the next one begins. If any stage fails, the process stops immediately and the team receives a notification.

| Stage       | What It Does                                                               | What It Confirms                                                                                     |
| ----------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| 1. Checkout | Downloads the exact version of code that was pushed                        | The pipeline is always working from the latest committed code, not a local copy on someone's machine |
| 2. Install  | Fetches all third-party libraries the application depends on               | Every build uses the same dependency versions, no surprises from library updates                     |
| 3. Lint     | Scans the code for formatting errors and obvious mistakes                  | Basic code quality is consistent across the whole team                                               |
| 4. Test     | Runs the automated test suite and measures how much of the code is covered | The application behaves correctly and the tests actually reach the parts of the code that matter     |
| 5. Build    | Packages the application into a versioned folder ready for deployment      | What gets deployed is exactly what was tested, nothing more and nothing less                         |

The whole process takes under two minutes for the payment service in its current form.

## What Happens When Something Goes Wrong

Every stage in the pipeline is a gate. If the gate does not open, nothing moves forward.

If a developer pushes code that breaks a test, the pipeline stops at stage four. No package is produced. No artifact reaches the registry. The developer receives a notification immediately, while the change is still fresh in their mind. The previous working version of the software is untouched.

This means the team has made a standing agreement with itself: code that has not passed every check does not move closer to production. No one has to remember to enforce this rule. The pipeline enforces it automatically, every single time, for every developer on the team regardless of seniority or time pressure.

The result is that the version sitting in the artifact registry is always a version that passed every check the team has defined. Board members and external auditors can ask at any time: "Is the software currently in the registry safe to deploy?" The answer is always yes, because anything unsafe never made it that far.

## What This Pipeline Does Not Yet Do

This pipeline handles the payment service in isolation and does not yet cover deployment to a live environment. After a versioned artifact is produced, a human still has to decide when and whether to deploy it, move it to staging, and promote it to production. The pipeline also does not yet run security scans against known software vulnerabilities, does not test how the payment service behaves when connected to the other Kijani Kiosk services, and does not enforce a minimum test coverage threshold that would cause a build to fail if coverage drops below an agreed level. These are the next logical additions as the team grows its confidence in automated delivery.
