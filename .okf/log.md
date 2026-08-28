# Update Log

## 2026-08-28

* **Initialization**: Created the bundle after four independent reviews — a maintainer, a security auditor, an SRE, and a newcomer — surfaced defects that existed only as prose in `docs/`.
* **Creation**: Five [failure modes](/failure-modes/index.md), each reproduced before it was fixed.
* **Creation**: Three [decisions](/decisions/index.md) whose reasoning the code does not carry.
* **Note**: A previous `.okf/` bundle was removed earlier the same day for duplicating `docs/`. This one is scoped to what has no other home.

* **Update**: Absorbed the mechanics behind three known weaknesses from `docs/DECISIONS.md`, which now states them in one line each and links here. Docs are for humans deciding whether to depend on the library; this bundle carries the evidence.
