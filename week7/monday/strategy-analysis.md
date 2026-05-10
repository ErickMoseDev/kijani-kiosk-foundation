# Deployment Strategy Analysis

## Scenario 1: The Overnight Batch Processor

**Selected Strategy: Recreate (in-place replacement)**

The scenario requires zero customer-visible impact and allows rollback within 24 hours. Both constraints are met by a recreate deployment: the old version is stopped, v2.1.0 is deployed, and if the output is wrong the batch is simply re-run with the old version. The strategy comparison table lists recreate as having zero infrastructure overhead, which matches the minimal budget constraint, and it requires no traffic-splitting or load balancer changes since the VM handles no external traffic.

## Scenario 2: The User-Facing Authentication Service

**Selected Strategy: Blue-Green Deployment**

The new JWT token structure is not backwards-compatible: tokens issued by v1.x cannot be validated by v2.0, and vice versa. Running both versions at the same time, as canary or rolling would require, would cause unpredictable authentication failures for users whose requests hit the wrong version. Blue-green avoids this by keeping the full v2.0 fleet idle until the low-traffic window, then switching all traffic at once with a single load-balancer flip. That same flip also satisfies the rollback constraint of under 5 minutes, and the double server count budget covers the cost of running both environments during the window.

## Scenario 3: The Machine Learning Recommendation Engine

**Selected Strategy: Canary Deployment**

During the rollout, the team needs to collect click-through rate and p99 latency for both v2.8 and v3.0 side by side using the platform's existing metrics system. The go signal at each stage is that v3.0 CTR meets or exceeds v2.8 CTR and p99 latency stays within the SLO. The no-go signal is any latency regression past the SLO threshold or a drop in CTR, at which point traffic is shifted back to v2.8. Canary satisfies all three constraints: it allows a real-traffic comparison before full commitment, supports rollback at any stage, and accepts mixed model serving across the user base.
