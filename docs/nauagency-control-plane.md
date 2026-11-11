# Multi Agent Herdr control plane

Multi Agent Herdr uses one durable control plane for both direct work and
multi-step plans. The app and its bundled core live in this repository; a
separate core checkout is not required.

## Execution model

Multi-step work follows this lifecycle:

`Run -> Plan -> Task DAG -> Attempt -> Event -> Decision`

- A plan has a stable idempotency key and a directed acyclic graph of tasks.
- The scheduler releases a task only after all dependencies complete.
- Every assignment or reassignment creates an attempt with a bounded retry
  count. Superseded and lost attempts remain visible in history.
- Control-plane changes append to a hash-linked JSONL event journal.
- Additional instructions to a busy worker are queued and delivered when the
  terminal is ready.
- Approval requests name an exact decision, kind, scope, and summary. Approving
  one request does not grant permission for later or broader actions.

Simple, independent work may still be dispatched directly. Multi-step work is
submitted as a JSON plan to `space-jobs.ps1 plan-apply`; the scheduler owns task
ordering after that point.

## Local verification

On Windows, run:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/test-control-plane.ps1
```

The integration check covers plan idempotency, dependency blocking and failure
propagation, scoped decisions, queued steering, and the event hash chain.
