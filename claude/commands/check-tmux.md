---
description: "Diagnose a long-running background job (tmux session, batch run, pipeline): progressing or stalled, why, and what to do. Use whenever the user asks 'is it still running', 'how is the job going', 'check the status', or notes a job has been running for hours"
argument-hint: "[tmux session name/number, e.g. '47'; omit to scan all sessions]"
---

# Check a long-running tmux job

The user has a script running in a tmux session and wants to know whether it is actually making progress.
This is read-only diagnosis: never kill, restart, or send keys to the session without explicit approval.

## 1. Locate the session and process

- `tmux ls`, then target the session in `$ARGUMENTS` (or ask which one if several look active and none was given).
- `tmux capture-pane -p -t <session> -S -200` for the recent output.
- `tmux list-panes -t <session> -F '#{pane_pid}'` then `ps --forest -o pid,etime,pcpu,pmem,cmd -g <pid>` to see the real command tree and elapsed time.

## 2. Determine progressing vs stalled

Collect independent signals; pane output alone lies (buffered logs look frozen while work continues):

- CPU/GPU use of the process tree now (`ps`, `nvidia-smi` if relevant).
- mtime and growth of its output artifacts, work dirs, and log files (find them from the command line args).
- Repeated capture 30 to 60 seconds apart: did the output or artifact sizes change?
- For jobs waiting on a remote service (e.g. an Anthropic batch API job printing `in_progress`), low local CPU is normal.
  Judge by whether the remote-side counter (items remaining, batch status) moves between polls, and check the service's expected turnaround before calling it stuck.
- For cluster jobs, check the scheduler too (`squeue`, per the relevant cluster skill).

## 3. Diagnose and estimate

- If progressing: state the evidence, current throughput, and a rough ETA from items-done vs items-total when derivable.
- If stalled: identify the layer that stopped (network wait, deadlock, OOM-killed child, full disk, auth expiry) with evidence, not pattern-matching.
- If genuinely ambiguous, say so and propose the cheapest next probe.

## 4. Report and recommend

- Verdict first: progressing, stalled, or waiting-on-remote, with the ETA or the root cause.
- Then the recommendation (leave it, attach and inspect, restart with a fix), and only act on it after the user agrees.
