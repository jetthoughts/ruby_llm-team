# Failure modes

Each was reproduced by running code before it was fixed. Numbers here are measured.

* [Forged handoff](forged-handoff.md) - a coworker fabricated an approval from a colleague that never ran.
* [Class-registered re-entrancy](class-registered-reentrancy.md) - the guard missed the path every example used; 51 levels deep.
* [Model self-assessment](model-self-assessment.md) - the reviewer approved the SQL injection it had just reported.
* [Eager Async task start](eager-async-task-start.md) - one crash prevented its sibling tasks from existing.
* [Unverified citations](unverified-citations.md) - nothing checked that cited sources were ever fetched.
