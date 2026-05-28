# Decisions log

The orchestrator appends one entry per accept/reject call made while synthesizing specialist
reviews (see `SELF_IMPROVE_LOOP.md` step 4). Keep entries terse; the *why* matters more than the *what*.

Format:

```
## <ISO8601> — <plan item>
- ACCEPT <agent> "<finding>" — <reason>
- REJECT <agent> "<finding>" — <reason> (deferred? → new PLAN item)
- VERIFY: <gate tier run> → <pass/fail> (<task that failed, if any>)
```

---
