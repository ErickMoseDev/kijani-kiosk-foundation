# Week 5 Reflection

## 1. Tension Between Requirements

The clearest tension this week was between keeping the pipeline fast and keeping it thorough. The board document requirement asked for a pipeline that gives stakeholders confidence that anything in the registry is safe to deploy. The practical CI requirement asked for a pipeline that gives developers fast feedback so they do not wait around. These two goals pull in opposite directions: the more checks you add, the slower the feedback loop gets.

I chose to prioritise fast feedback. The pipeline runs lint before tests, and tests before the build step, so a failure is caught at the cheapest possible stage and the developer hears about it quickly. The trade-off is that the pipeline does not yet run slower checks such as security scans or integration tests. That decision felt defensible for a four-person team on an early-stage service, but it is also what I called out honestly in the scope section of the board document. Choosing speed over completeness is only acceptable if the team knows the gap exists.

## 2. Board Language vs Technical Language

Board document sentence:

> "The pipeline enforces it automatically, every single time, for every developer on the team regardless of seniority or time pressure."

The same idea in technical language, as I would write it in a Jenkinsfile comment or say to Osei:

> "The `post { failure {} }` block fires on any non-zero exit code from any stage, marking the build as FAILED and triggering a notification before the downstream Build stage can run. There is no manual override in the declarative syntax without an explicit `catchError` or `when` condition."

What is the same in both: the guarantee that a failure stops the pipeline and that no human decides whether to apply the rule.

What is different: the board version describes the outcome and the intent. The technical version describes the mechanism. The board version needs no knowledge of how pipelines work. The technical version is useless without it.

## 3. What Breaks First at Scale

The part that breaks first is the single shared pipeline agent running sequential builds.

Right now, every push triggers one build at a time on one machine. With four developers that is fine. With forty developers pushing throughout the day, builds queue up behind each other. A developer pushing a one-line fix waits ten minutes not because their build takes ten minutes, but because nine other builds are ahead of them in the queue. Fast feedback, which is the main reason the pipeline exists, disappears.

What would need to change is the executor model. The pipeline would need a pool of agents so multiple builds run in parallel, and a mechanism to assign each build to a free agent automatically. Beyond that, the in-memory data store in the payment service itself would need to be replaced with a real database before the service is put under any real load, but that is an application concern rather than a pipeline concern. The pipeline scaling problem is the one that would surface first and affect every developer on the team every day.
