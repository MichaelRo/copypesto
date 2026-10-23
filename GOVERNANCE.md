# Governance

Pesto has one maintainer, who decides what is merged and released.

- **How decisions are made.** A choice that is hard to reverse (encryption, the paste flow, exclusion rules, what the
  app sends over the network, the license) is written as an ADR in [decisions/](decisions/) before it is built. An
  accepted ADR is not edited; a later one supersedes it. Smaller changes go through pull requests.
- **What will not change.** No analytics, no feature gating or paid tier, no clip content sent to an AI service (ADR
  0001, ADR 0005, AGENTS.md). A proposal that needs one of these starts as an ADR, not a pull request.
- **Merging.** CI is manual until the repository opens, so a merge can combine two branches that were each green and
  be red together (this happened once: a documentation merge broke `PersonalDataTests`). After every merge, on `main`,
  the maintainer runs `scripts/verify.sh --fast` (lint, Core tests, a Debug build) and the full gate before a release.
  When CI is automatic it runs on the merge result and the check is required.
- **Becoming a maintainer.** A person who has landed several well-reviewed changes and knows the conventions can be
  given triage and review rights on request. Signing keys and the update feed stay with the maintainer.
- **Forks.** The code is MIT and a fork is welcome. A fork needs its own name, icon, bundle identifier, update feed and
  signing key ([TRADEMARKS.md](TRADEMARKS.md)).
- **If the project stops.** The last release will point the update feed at a notice that says so, and the repository
  will be archived with the final state of the code. Users keep a working app and an encrypted history that the app
  and its backup format can still read.
- **Support promise.** Security reports are acknowledged within seven days ([SECURITY.md](SECURITY.md)). Other issues
  are read, but replies can take a while.
