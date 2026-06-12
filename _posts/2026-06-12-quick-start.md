---
layout: post
title: "Quick start"
date: 2026-06-12
---

Original source: https://herdr.dev/docs/quick-start/

# Quick start

If Herdr is not installed yet, see [Install](https://herdr.dev/docs/install/). Then start Herdr from any project directory:

```
herdr
```

Herdr launches or attaches to your default background session. You do not manage sockets. If you detach, agents keep running.

## Create a workspace

[Section titled “Create a workspace”](#create-a-workspace)

When a session has no workspaces, Herdr opens one automatically. A workspace is a project-level container for tabs, panes, and agents. Give each active project its own workspace; this keeps agent state readable in the sidebar.

Herdr is mouse-native, so start by clicking. Click panes, tabs, workspaces, and agents to focus them. Drag split borders to resize. Right-click for context menus, including splitting panes and creating tabs. Drag-select text to copy it to your clipboard; double-click a token to copy it directly. Copying does not require Ctrl+C.

Ctrl-click opens pane links when your terminal sends the modified click to Herdr. This works for OSC 8 hyperlinks and visible `http://` or `https://` URLs. The portable terminal-native fallback is Shift-Ctrl-click on Linux or Shift-Cmd-click on macOS.

If you configure `ui.right_click_passthrough_modifier`, that modifier plus right-click sends right-click, hold, and drag gestures to mouse-reporting pane apps.

Start your coding agent in a pane:

```
claude
```

Or `codex`, `pi`, `opencode`, or any other [supported agent](https://herdr.dev/docs/agents/). Herdr detects it automatically. The sidebar shows whether each agent is `working`, `blocked`, `done`, or `idle` — across every workspace, so you always know which project needs you.

Keyboard control is optional; the mouse covers everything. Press `ctrl+b` to enter prefix mode, then press an action key.

Common actions:

<table><thead><tr><th>Action</th><th>Key</th></tr></thead><tbody><tr><td>Split right</td><td><code dir="auto">prefix+v</code></td></tr><tr><td>Split down</td><td><code dir="auto">prefix+minus</code></td></tr><tr><td>New tab</td><td><code dir="auto">prefix+c</code></td></tr><tr><td>Next / previous tab</td><td><code dir="auto">prefix+n</code> / <code dir="auto">prefix+p</code></td></tr><tr><td>Workspace navigation</td><td><code dir="auto">prefix+w</code></td></tr><tr><td>New workspace</td><td><code dir="auto">prefix+shift+n</code></td></tr><tr><td>Detach client</td><td><code dir="auto">prefix+q</code></td></tr></tbody></table>

New to the prefix idea? [Keyboard](https://herdr.dev/docs/keyboard/) explains what it is, why multiplexers use one, and how to go prefix-free. Press `prefix+?` inside Herdr to see every active binding, and `prefix+[` to copy from the keyboard in copy mode.

## Detach and come back

[Section titled “Detach and come back”](#detach-and-come-back)

Press `prefix+q` or simply close your terminal window. The Herdr server and every agent keep running. Run `herdr` again to reattach to the same session.

To actually end the session and stop its panes:

```
herdr server stop
```

-   [Concepts](https://herdr.dev/docs/concepts/) — the workspace, tab, pane, and agent model in two minutes.
-   [How to work with Herdr](https://herdr.dev/docs/how-to-work/) — local, SSH, phone, and `herdr --remote` workflows.
-   [Agents](https://herdr.dev/docs/agents/) — supported agents, detection, and integrations that improve state accuracy.
-   [Configuration](https://herdr.dev/docs/configuration/) — keybindings, themes, notifications, and everything else.
