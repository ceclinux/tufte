---
layout: post
title: "Session state and restore"
date: 2026-06-12
---

Original source: [Original post](<https://herdr.dev/docs/session-state/>)

Herdr has several state paths. They solve different problems.

<table><thead><tr><th>Case</th><th>Processes keep running</th><th>Layout returns</th><th>Recent screen returns</th><th>Agent conversation resumes</th></tr></thead><tbody><tr><td>Detach and reattach</td><td>Yes</td><td>Yes</td><td>Yes, from the live terminal</td><td>Yes, because the process never stopped</td></tr><tr><td>Server restart</td><td>No</td><td>Yes</td><td>Only with pane screen history</td><td>Only with native agent session restore</td></tr><tr><td>Update without <code dir="auto">--handoff</code></td><td>Compatible servers keep running; restart-required servers may need stop/restart</td><td>Yes after restart</td><td>Only with pane screen history</td><td>Only with native agent session restore</td></tr><tr><td>Update with <code dir="auto">--handoff</code></td><td>Best effort for supported running servers</td><td>Yes</td><td>Yes, from the live terminal if handoff succeeds</td><td>Yes, because the process keeps running if handoff succeeds</td></tr></tbody></table>

The sections below explain each path.

Normal detach keeps the Herdr server running. Panes, shells, agents, servers, tests, and command processes keep running inside that server.

Detach the client with `ctrl+b q`. Reattach later:

```
herdr
```

This is the strongest persistence path because the original processes never stop.

If the Herdr server stops and starts again, the original pane processes are gone. Herdr restores the saved session shape: workspaces, tabs, panes, cwd, layout, and focus.

Snapshot restore does not preserve running shells, servers, tests, or arbitrary processes. Panes that cannot use a stronger restore path come back as new shells in their saved directories.

## Pane screen history replay

[Section titled “Pane screen history replay”](#pane-screen-history-replay)

Pane screen history restores recent terminal contents after a full server restart. It restores what Herdr can show, not the old process.

This is off by default because pane output can include secrets, tokens, prompts, and command output. Enable it from Settings > Experiments > pane screen history or with:

```
[experimental]pane_history = true
```

When enabled, Herdr stores saved pane history in `session-history.json` next to `session.json`. Treat the Herdr config/session directory like terminal history.

## Native agent session restore

[Section titled “Native agent session restore”](#native-agent-session-restore)

Some agents can resume their own conversation sessions. Herdr can use official integration-reported session references to restart supported agent panes after a Herdr server restart.

This is enabled by default. Disable it with:

```
[session]resume_agents_on_restore = false
```

Herdr only resumes panes that reported a native session reference through a current official Herdr integration.

After a client attaches and provides terminal size and theme context, Herdr resumes eligible restored agent panes across workspaces and tabs without waiting for each pane to be focused.

Native session restore requires these Herdr integration versions or newer:

<table><thead><tr><th>Agent</th><th>Minimum Herdr integration version</th><th>Resume command</th></tr></thead><tbody><tr><td>Pi</td><td><code dir="auto">2</code></td><td><code dir="auto">pi --session &lt;path-or-id&gt;</code></td></tr><tr><td>Claude Code</td><td><code dir="auto">5</code></td><td><code dir="auto">claude --resume &lt;id&gt;</code></td></tr><tr><td>Codex</td><td><code dir="auto">5</code></td><td><code dir="auto">codex resume &lt;id&gt;</code></td></tr><tr><td>Cursor Agent CLI</td><td><code dir="auto">1</code></td><td><code dir="auto">cursor-agent --resume &lt;id&gt;</code></td></tr><tr><td>GitHub Copilot CLI</td><td><code dir="auto">2</code></td><td><code dir="auto">copilot --resume=&lt;id&gt;</code></td></tr><tr><td>Droid</td><td><code dir="auto">2</code></td><td><code dir="auto">droid --resume &lt;id&gt;</code></td></tr><tr><td>Kimi Code CLI</td><td><code dir="auto">3</code></td><td><code dir="auto">kimi --session &lt;id&gt;</code></td></tr><tr><td>Qoder CLI</td><td><code dir="auto">2</code></td><td><code dir="auto">qodercli --resume &lt;id&gt;</code></td></tr><tr><td>OpenCode</td><td><code dir="auto">5</code></td><td><code dir="auto">opencode --session &lt;id&gt;</code></td></tr><tr><td>Kilo Code CLI</td><td><code dir="auto">1</code></td><td><code dir="auto">kilo --session &lt;id&gt;</code></td></tr><tr><td>Hermes Agent</td><td><code dir="auto">2</code></td><td><code dir="auto">hermes --resume &lt;id&gt;</code></td></tr></tbody></table>

OMP integration version `2` reports agent state, but does not report native session references for restore.

Run `herdr integration status` to check installed integration versions. Reinstall outdated integrations with `herdr integration install <agent>`.

Unsupported, missing, invalid, duplicated, or stale session references restore as normal shells in the saved pane directory.

If native agent session restore applies to a pane, Herdr resumes the agent session instead of replaying saved pane history for that pane.

Live handoff is for update and remote attach flows that need to replace a running Herdr server. It asks the old server to transfer live panes to the new server, so pane processes can keep running across the server replacement.

This is different from snapshot restore, pane history replay, and native agent session restore. Handoff tries to keep the current processes alive. The others reconstruct state after the old server has already stopped.

Live handoff is experimental and opt-in:

```
herdr update --handoffherdr --remote workbox --handoff
```

Plain `herdr update` and plain `herdr --remote workbox` use the normal restart/stop flow by default.

`herdr update --handoff` only applies to installs managed by Herdr’s own updater. Homebrew, mise, and Nix installs are updated through their package managers, so `herdr update` is disabled there and cannot perform live handoff.
