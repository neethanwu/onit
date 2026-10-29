<p align="center">
  <br>
  <img src="assets/icon.png" width="96" alt="onit icon">
  <br>
</p>

<h1 align="center">onit</h1>

<p align="center">
  keep an eye on everything your mac does on a schedule, from the notch or the menu bar.
</p>

<p align="center">
  <a href="https://github.com/neethanwu/onit/releases/latest/download/onit.dmg">
    <img src="https://img.shields.io/badge/download-onit.dmg-black" alt="download onit.dmg">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-black" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-6.2%2B-F05138" alt="Swift 6.2+">
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="License: MIT">
</p>

## Why

Agents, scripts and tools are good at setting up work that runs on a schedule: a nightly backup, a retro every morning, a sync that runs all day. On a Mac that work ends up as launchd agents and crontab entries, and there is no comfortable place to see them. You have to know where the plist files live, read `launchctl` output, and guess what `StartCalendarInterval` means.

onit puts all of it in one small panel, in plain language: what you have scheduled, when it runs next, whether it worked last time, and what to do when it didn't.

## Features

- **Everything scheduled, in one list.** Your launchd agents and crontab entries, each with a readable name, a launchd or cron tag, and its schedule in words ("Hourly + daily at 8:00 AM", "Weekdays at 6:30 PM").
- **Status at a glance.** Running, OK, failed, paused or not run yet, with when it last ran and when it runs next. A "Next up" card shows the next thing to happen.
- **Failures explained.** When a task fails, onit reads the end of its log and says what went wrong in plain words ("A file or folder it needs is missing"), shows the raw error line underneath, and tells you how many runs in a row have failed.
- **Fixes you can hand to your agent.** "Copy for your agent" copies a ready prompt with the task's definition, schedule, exit code and recent log, so your coding agent can find and fix the problem.
- **Schedules that run more than you think.** A launchd job with both `StartInterval` and `StartCalendarInterval` runs on both. onit flags it, says how many runs a day that adds up to, and offers a fix prompt.
- **Run history.** Each run is recorded with when it finished and how long it took. onit also reads recent runs from the system log when it starts.
- **Simple actions.** Run now (or try again), pause and resume, open the log in Console, show the plist in Finder, copy the command.
- **Only your tasks.** Apple's agents, Homebrew services and helpers that ship inside apps are hidden. You can show them, and hide or unhide any task yourself.
- **Notch or menu bar.** On a Mac with a notch, onit lives there by default. If the notch isn't available, for example on an external display, it moves to the menu bar on its own. You can switch either way from the ··· menu.
- **Bead.** A small character that shows how things are: dozing when all is well, running back and forth while a task runs, amber when something needs a look, red and sweating when something failed. It blinks, looks around, and looks at your pointer when it comes near.

## Install

1. Download **onit.dmg** from the [latest release](https://github.com/neethanwu/onit/releases/latest).
2. Open it and drag **onit** into **Applications**.
3. Open onit from Applications. It has no Dock icon: look for Bead beside the notch, or in the menu bar on a Mac without one.
4. Optional: turn on **Open at Login** from the ··· menu.

onit is signed with a Developer ID and notarized by Apple, so it opens without a Gatekeeper warning.

Requirements: macOS 26 or later, on Apple silicon or Intel.

### Build from source

```bash
git clone https://github.com/neethanwu/onit.git
cd onit
make run
```

`make run` builds the app, wraps it in `onit.app`, signs it ad hoc and opens it. Building needs Xcode 26 or later (Swift 6.2+).

## Using onit

- **Notch mode.** Two short wings appear beside the notch: Bead on the left, and on the right the time to the next run, a running pulse, or a count of tasks that need you. Click either wing to open the panel. Click anywhere else or press Escape to close it.
- **Menu bar mode.** Bead sits in the menu bar. Click it to open the panel.
- **A task's detail.** Click a task to see its schedule, next run, what it runs, recent runs and actions. Press Escape or the back button to return to the list.
- **More options.** The ··· menu holds the notch or menu bar switch, Show Hidden Tasks, Open at Login, About and Quit.

## What onit reads

onit only reads from your own Mac and never sends anything anywhere.

| Source | What onit uses it for |
| --- | --- |
| `~/Library/LaunchAgents/*.plist` | Your launchd agents: label, program, schedule, log paths |
| `launchctl list`, `launchctl print`, `launchctl print-disabled` | Whether each agent is loaded, running or disabled, its last exit code and run count |
| `crontab -l` | Your cron entries. A comment line just above an entry becomes its name |
| The unified log (`log show`) | Recent "service inactive" events at launch, to fill in runs from before onit started |
| Each task's log file | The last lines, to explain a failure and to notice cron runs |

onit stores its run history in `~/Library/Application Support/onit/history.json` and keeps the last 50 runs per task.

Actions use `launchctl kickstart`, `disable` / `bootout` and `enable` / `bootstrap` on the agent in your own user domain. onit never edits your plists or your crontab.

## Limitations

- launchd doesn't keep a history of runs, so onit's run history starts when onit does (plus whatever the system log still has from the last two hours).
- cron reports nothing about its runs. onit can only see a cron task run when its command writes to a log file (`>> ~/logs/task.log`). It can run a cron task now, but can't pause one, since that would mean editing your crontab.
- Only agents in your user domain are shown. System-wide daemons in `/Library/LaunchDaemons` are out of scope.
- The plain-language failure reasons cover common errors (missing files, permissions, missing programs, network, disk full). Anything else falls back to the exit code and the raw error line.

## Development

```bash
make run     # build, bundle, sign ad hoc and open onit.app
make test    # run the unit tests
make bundle  # build onit.app without opening it
make sign    # sign with SIGN_IDENTITY (set it in .env for a Developer ID build)
make release # sign, notarize and package onit.dmg (needs SIGN_IDENTITY and NOTARY_PROFILE in .env)
make icon    # redraw the app icon and assets/icon.png from SupportFiles/generate-icon.swift
```

The project is a Swift package with no dependencies.

```
Onit/
  OnitApp.swift            App entry: menu bar extra and notch controller
  Models/                  Job, run records and the JobStore that polls and acts
  Services/                launchd, cron and unified log readers, schedule text,
                           failure explanations and fix prompts
  Notch/                   Notch window, geometry and the notch view
  Views/                   Shared list, detail, Bead and control components
  Utilities/               Time formatting and the menu bar icon
Tests/OnitTests/           Schedule, parsing and naming tests
SupportFiles/              Info.plist, app icon and the script that draws it
```

## License

[MIT](LICENSE)
