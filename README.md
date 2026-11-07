# Athena

Athena is a small native macOS app that lives in your menu bar. It gives you two short tasks a day,
nothing more: today's **LeetCode daily problem**, and a five-minute **Java Daily** exercise written
for you by a local AI model. It shows up when you sit down at your Mac, stays out of the way once you're done,
and remembers how you're doing so each day's Java exercise targets what you need most.

Everything runs on your Mac. There's no account, cloud service or paid API, and your progress never
leaves your machine.

---

## Features

### Two daily tasks
- **LeetCode daily:** fetches the official problem of the day (title, number, difficulty) and opens it
  in your browser. You mark it solved yourself; Athena never signs in to LeetCode or claims a solution
  was accepted.
- **Java Daily:** a short exercise that keeps your Java fluent: collections APIs, strings, sorting and
  comparators, streams, exceptions, `equals`/`hashCode` and generics. It's practical practice, not
  trick questions. There are seven formats: predict the output, find the bug, fix the code, explain a
  concept, recall an API, complete the code, and write a small method.

### Feedback you can trust
- After you submit, you see whether you were right, the correct answer, an explanation, what you
  misunderstood, the type of mistake, and when the topic comes back for revision.
- Short answers (predicted output, API names) are checked by Athena against a reference answer, not
  by the AI.
- For open-ended answers, the AI marks each criterion and Athena computes the verdict. If the AI's
  grading doesn't hold up, you grade yourself against the reference instead, and that attempt never
  silently changes your scores.

### Adapts to you
- Each topic's strength is calculated from your real attempts, with recent attempts weighted most, so
  one old mistake fades instead of marking a topic weak forever.
- Weak topics come back sooner (tomorrow, in 3, 7 or 14 days); strong ones less often.
- The topic, difficulty and exercise type are chosen by fixed, predictable rules. The AI only writes
  the exercise.

### Progress at a glance
- Today's progress (`0/2`–`2/2`) in the window and in the menu bar.
- A monthly calendar: green for days you finished both tasks, dim green for one.
- Your current and best streak, total problems and exercises completed.
- **Java learnings:** a plain summary of your strong topics, the ones that need work, what you
  practised recently, and your most common mistakes.

### Shows up at the right time
- Starts at login and opens only if today's tasks aren't done.
- Comes back when you wake or unlock your Mac while something is still left. Snooze it for an hour
  if you're busy.
- Once both tasks are done, it stays hidden until tomorrow.

### Works offline
- If the local AI isn't running or returns something unusable, Athena uses one of 35 curated
  questions instead. If LeetCode can't be reached, you still get a link to the daily challenge.

### Tunable from the terminal
- The `athena` command shows your progress and lets you steer the exercises: focus on topics,
  exclude some, set difficulty, or describe what you want in plain English.

---

## Requirements

| | |
|---|---|
| macOS | 14 (Sonoma) or newer, Apple silicon recommended |
| Swift | 6.0 or newer: Xcode 16+ **or** just the Command Line Tools |
| [Ollama](https://ollama.com) | to run the AI model locally |
| AI model | `qwen3:4b` by default (~2.5 GB download) |
| Disk / memory | ~3 GB for the model; 8 GB RAM minimum, 16 GB comfortable |
| JDK (optional) | only for `athena verify-bank` |

Athena has no third-party code dependencies. SQLite ships with macOS.

---

## Installation

### 1. Install a Swift toolchain
If you have Xcode, open it once to accept the license. Otherwise, install the Command Line Tools:
```bash
xcode-select --install
```
Check with `swift --version` (6.0 or newer).

### 2. Install Ollama and the model
Download the Ollama app from [ollama.com](https://ollama.com) and open it, **or** use Homebrew:
```bash
brew install ollama
```
```bash
brew services start ollama
```
Then download the model:
```bash
ollama pull qwen3:4b
```
Check it's available (the output should list `qwen3:4b`):
```bash
curl -s localhost:11434/api/tags
```

### 3. Build and install Athena
From the folder that contains `Package.swift`:
```bash
./scripts/build-app.sh --install
```
This builds a release version and installs:
- **`~/Applications/Athena.app`:** the app.
- **`~/.local/bin/athena`:** the terminal command.

If `athena` isn't found afterwards, add that folder to your PATH:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

### 4. Launch
```bash
open ~/Applications/Athena.app
```
On first launch, Athena:
- creates its database at `~/Library/Application Support/Athena/athena.sqlite`;
- registers itself to open at login (turn this off with **Open at Login** in the menu bar menu);
- fetches today's LeetCode problem and writes your first Java exercise, which takes about 10–30
  seconds the first time while the model loads.

### Updating
Pull or copy in the new source, then run `./scripts/build-app.sh --install` again. Your progress is
kept, because it lives in the database rather than in the app.

### Uninstalling
Quit Athena from its menu bar menu, turn off **Open at Login** first if you want it removed from login
items, then:
```bash
rm -rf ~/Applications/Athena.app ~/.local/bin/athena
```
To also delete your progress:
```bash
rm -rf ~/Library/Application\ Support/Athena
```

---

## Using Athena

### The window
The window shows one screen at a time and sizes itself to fit it. It always opens centred on the
screen and never goes past the screen's edges. It's capped at a comfortable height; longer feedback
scrolls inside its own box.

| Screen | What it shows |
|---|---|
| **Start** | Greeting, date, a hint of what's waiting today, and **Start →** |
| **LeetCode** | Today's problem, **Open on LeetCode →** and a **Mark solved** checkbox. Marking it solved moves you on to Java Daily. |
| **Java Daily** | The exercise, your answer box and **Submit** (⌘↩ for multi-line answers), then feedback. **Practice another** gives you extra exercises once today's is done. |
| **Progress** | Opened from the calendar badge at the top right: streak, calendar and **Java learnings**. |

Use **‹ Prev / Next ›** to move between LeetCode and Java Daily. **Snooze 1h**, at the bottom right,
hides the window for an hour.

### The menu bar
The brain icon shows today's progress (`1/2`) and turns green when you're done. Its menu has
**Open Athena**, **Snooze 1 hour**, **Open at Login** and **Quit**. Closing the window doesn't quit
Athena; it keeps running in the menu bar.

### When the window appears

| Trigger | Behaviour |
|---|---|
| Login | Opens only if today's tasks are incomplete |
| Wake, display wake or screen unlock | Opens, or comes to the front, while a task is incomplete, unless snoozed. Several events within 30 seconds count once. If the window is already open, it just comes forward and keeps your place. |
| Opening it yourself (menu bar, Finder, Spotlight) | Always opens |
| Launching a second copy | Hands off to the running one and exits |

A "day" is your local calendar day, rolling over at local midnight.

---

## Terminal commands

```bash
athena help
```

| Command | What it does |
|---|---|
| `athena status` | Today's tasks, streak and totals |
| `athena topics` | Every topic's status, accuracy and next revision date |
| `athena summary` | Java learnings summary |
| `athena next` | Which topic, difficulty and type would be picked next, and why |
| `athena prefs` | Every saved setting |
| `athena tune "more PriorityQueue, medium difficulty"` | Describe what you want; the local model turns it into settings, and Athena checks them before saving |
| `athena prompt "Phrase questions like a phone screen"` | Standing guidance added to every exercise (`--clear` removes it) |
| `athena focus PriorityQueue,ArrayDeque` | Practise these topics more (`--clear` resets) |
| `athena exclude Generics` | Never schedule these topics (`--clear` resets) |
| `athena difficulty auto\|easy\|medium\|hard` | Fix the difficulty, or let Athena choose (`auto`) |
| `athena types predict_output,api_recall` | Limit exercise formats (`all` resets) |
| `athena add-topic "ConcurrentHashMap" Concurrency` | Add a new topic |
| `athena model qwen3:4b` | Choose which Ollama model to use |
| `athena think on\|off` | Let the model reason before answering (slower, sometimes better) |
| `athena unsnooze` | Cancel an active snooze |
| `athena generate [--think]` | Dry run: write the next exercise and print it with timing; nothing is saved |
| `athena grade <bank-id> "answer"` | Try the grader on a curated question; nothing is saved |
| `athena verify-bank` | Check the curated predict-output answers against your JDK |
| `athena db` | Print the database path |

Settings take effect the next time Athena picks an exercise; you don't need to restart the app.

---

## How it works

```
SwiftUI views ── view models ── AthenaStore (application layer)
                                   ├── LearningEngine     picks topic, difficulty, revision dates
                                   ├── ExerciseGenerator  asks the model, validates, falls back to the bank
                                   ├── ChallengeEvaluator grades answers
                                   ├── OllamaService      localhost:11434, JSON-schema responses
                                   ├── LeetCodeService    public daily-problem query, no cookies
                                   └── Repositories       SQLite (the single source of truth)
```

- **The app (`Athena`) and the CLI (`athena`) share one core library (`AthenaCore`)** and the same
  database, so they always agree.
- **Grading:**
  - Predicted output and API names are compared by Athena itself.
  - A generated predict-output question is kept only if the model gives the same answer when asked a
    second time, independently.
  - Open-ended answers pass at ≥75% of criteria met. If the model's overall verdict contradicts its own
    criteria, the grade is rejected.
- **Scheduling:**
  - Mastery is 70% recent accuracy (last 5 attempts, each older one weighted ×0.75) plus 30% overall,
    pulled toward 50% until there are 3 attempts.
  - Revision intervals: <50% → 1 day, 50–70% → 3, 70–85% → 7, ≥85% → 14. Three correct in a row
    doubles it (max 30 days), and a conceptual mistake brings the topic back tomorrow.
- **Safety:** Athena never runs code the model writes. `verify-bank` only compiles the curated
  questions that ship with the app.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Ollama isn't running" on the Java card | Open the Ollama app or run `brew services start ollama`, then click **Retry** |
| "Model qwen3:4b isn't downloaded" | `ollama pull qwen3:4b`, or switch with `athena model <tag>` |
| Exercises keep falling back to saved questions | `ATHENA_DEBUG=1 athena generate` prints the model's raw output |
| "Couldn't reach LeetCode" | Check your connection; the daily-challenge link still works |
| `athena: command not found` | Run `./scripts/build-app.sh --install`, and add `~/.local/bin` to your PATH |
| "Couldn't change the login item" | The app must be in `~/Applications` or `/Applications`; use `--install` |
| Build fails with "precompiled file … was compiled with module cache path …" | You moved or copied the folder; run `rm -rf .build` and build again |
| `no such module 'Testing'` when running tests | Use `./scripts/test.sh`, which adds the paths the Command Line Tools need |

---

## Development

```bash
./scripts/test.sh          # run the 38 tests
swift build                # debug build
./scripts/build-app.sh     # release build into ./build without installing
```
- Open the folder in Xcode (File → Open, select the folder with `Package.swift`). The schemes are
  **AthenaApp** (the app), **athena** (the CLI) and **AthenaCore**; ⌘U runs the tests.
- **Environment variables:**
  - `ATHENA_DB=/path/to/file.sqlite` uses a separate database, which is handy for experiments.
  - `ATHENA_DEBUG=1` prints raw model responses.

### Project layout
```
Sources/
  AthenaCore/     Models, Persistence (SQLite + repositories), Services (engine, grading, Ollama,
                  LeetCode, prompts, question bank), AthenaStore
  Athena/         App lifecycle, view models, SwiftUI views
  athena-cli/     The `athena` terminal command
Tests/AthenaCoreTests/
scripts/          build-app.sh, test.sh
```

---

## Roadmap
- Feedback on individual Java questions ("not useful", with a reason), used to steer future exercises.
- Run submitted code against test cases, inside a proper sandbox.
- An app icon.
