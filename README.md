# tern-notch

Puts your agents in the MacBook notch. While an agent in Tern works, four bars
move beside the camera and its context use sits on the other side; when it asks
a question, an orange dot blinks there. Hover the notch and it opens into a
panel: the question's options to pick, a prompt box for messages and slash
commands, and the agent's model, branch and diff.

- **Closed notch**: at the notch's own size while nothing runs; with wings
  while an agent works (activity bars, then context used or the tightest usage
  limit) or waits on you (a blinking dot, and optionally a chime).
- **Questions**: omp's `ask` dialogs show as buttons. Single choices answer on
  click, multi-select options toggle, multi-question asks keep their tabs, and
  **Other…** or typing in the prompt box sends a custom answer. Skip, Submit
  and the dialog's other buttons work as in Tern.
- **Prompt box**: messages go to the selected agent; `/` lists omp's commands
  with their arguments (↑/↓ to choose, Tab or Return to complete, Esc to
  dismiss), including the project's `.omp/commands` and `.claude/commands`.
  The **+ New** tab starts omp in a new Tern tab, in the folder of the focused
  pane.
- **Model and effort**: menus under the prompt box switch a running agent's
  model (`/switch`) or thinking level (`/effort`), or set them for the next
  new agent (`--model`, `--thinking`), from the models `omp models` lists.
- **Folder facts**: the target folder, its branch, and lines added and removed
  since `HEAD`.
- **Settings**: from the gear in the open panel, a right click on the notch, or
  **Agent Notch: settings** in the palette. Opening on hover or click, delays,
  haptics, what shows beside the notch, idle shrinking, blinking, the chime,
  panel width, glass darkness, which display, full-screen apps, and every
  usage limit from `omp usage` with its reset time.

Agents are any omp running in Tern: agent blocks and `omp` typed in a shell.
Their state comes from Tern (`cx.agents`), the rest from omp's own surface in
the pane (`cx.session:surface`), so questions are answered with the same events
a click in the pane sends.

## Install

The notch is drawn by a small helper app the plugin builds with `swiftc` on
first load, so it needs macOS 14 or later and the Xcode Command Line Tools
(`xcode-select --install`). Then:

```sh
tern plugin install github.com/<you>/tern-notch
```

or, to load a clone in place and reload on every save:

```sh
git clone https://github.com/<you>/tern-notch
tern plugin link tern-notch
```

The helper is built into `~/Library/Application Support/TernNotch/TernNotch.app`
and started by the plugin; it quits with Tern. After changing `app/Sources`,
run `./build.sh` and **Agent Notch: restart helper** from the palette.

The plugin and the helper talk through files in
`~/Library/Application Support/TernNotch`: the plugin writes `state.json`
(agents, questions, usage, folders) and `catalog.json` (models and commands),
and runs the commands the helper drops in `inbox/`. Only one Tern window
publishes at a time. Surface reads are spread across ticks to stay inside the
window half's 50 ms budget; `omp usage` runs every two minutes, `omp models`
every ten, and `git` for one folder every 1.5 seconds.

Another notch app (NotchNook and the like) draws over the same spot; quit it,
or turn its notch off, while this one runs.
