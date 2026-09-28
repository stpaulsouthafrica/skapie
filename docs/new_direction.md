# Pasture Studio: the new direction

This document is the starting brief for **Pasture Studio**, the new app that
replaces the old Flutter "Skapie" app. It is written for agents and people who
have never seen this project before. Read all of it before writing any code.

The old Flutter app (the `skapies.com` repo) is a reference only. Do not copy
its code, and do not follow its other docs. Where they disagree with this file,
this file wins.

---

## 1. What we are building

Pasture Studio is a desktop app for Mac and Windows. You work on a
**Pasture**: one big, endless board, like a whiteboard you can pan and zoom. A
user can have many Pastures, one per project or idea.

On a Pasture you place **cards**. Each card does something. You connect cards
with **cables**, and things flow along the cables from one card to another.

A typical Pasture looks like this:

- A **Text** card holds a task: "Add a dark mode to my website".
- The Text card is cabled into an **LLM** card. The LLM card talks to an AI
  model.
- A **Conversation** card is cabled into the LLM, so the model remembers
  earlier messages.
- A **Repository** card points at a folder on your computer.
- **Read**, **Write**, **Edit** and **Shell** cards are cabled from the
  Repository into the LLM. They are the tools the model may use on that folder.
- The LLM's answer flows out along a cable into another Text card.

Press Run on the LLM card and the model reads the task, uses the tools, and
writes its answer. That is the first thing Pasture Studio must do well: be a
visual coding agent.

### The part that matters most

**Every one of those cards is a kit written by a user, not by the app.**

The LLM card, the Read tool, the Conversation card, even the plain Text card:
each one is a folder of TypeScript code in the user's Pasture Studio folder.
Anyone can open that folder, change the code, press Reload, and see the new
behaviour. Anyone can write a brand new kit that does something we never
imagined, and it works like the built-in ones, because there are no built-in
ones.

The app itself is only an **engine**: the Pasture, the cables, the loader, and a
set of hooks that kits use to draw cards, react to events, and talk to each
other. The engine does not know what an LLM is. It does not know what a file
tool is. It has **zero** built-in cards and **zero** built-in tools.

This is the same idea as [pi](https://github.com/badlogic/pi-mono), a coding
agent whose core stays tiny while extensions add everything else. Pasture
Studio goes one step further: even the basic tools and the model itself are
kits.

### Why we left Flutter

A shipped Flutter app cannot load new Dart code while it runs. The old app
tried to work around this with a Dart interpreter. Kits could only do what the
host had wired up for them one by one, so the real code for every kit kept
ending up in the host. We moved to web technology because it can load new code
on reload by design.

### What is out of scope for now

Accounts, cloud sync and cloud backup. The goal is a working app on one
computer, end to end. Nothing in this plan talks to our servers.

---

## 2. The two rules

### Rule 1: the host contains no kit code

1. No file under `src/` may mention a kit id, such as `harness.llm`.
2. No file under `src/` may import anything from `kits/`.
3. The host never checks what kind of card something is to decide how to
   behave. It never writes code like `if (card.type === 'harness.llm')`.
4. The host has no tools, no model providers, no prompts, no file-access
   rules, and no "starter" behaviour in code.
5. If you delete every kit, the app still starts and shows an empty Pasture
   with no errors.

If a feature seems to need the host to know about one specific kit, the answer
is always the same. **Add a general hook to the kit API, then use it from the
kit.** For example, "the Repository card needs a folder picker" becomes "the
kit API offers `pickFolder()`, and the Repository kit calls it".

An automatic test enforces points 1 and 2 (see Phase 1). It must never be
weakened or skipped.

### Rule 2: one folder holds everything

Tools like this often scatter things across a computer: skills in one hidden
folder, settings in another, project files somewhere else. We do not.

**Everything the user creates or the app saves lives in one visible folder:
the Pasture Studio folder.** That means every kit, every Pasture, every kit's
saved data, and the app's settings. The user can always answer "where does
Pasture Studio get this from?" by opening that one folder.

- The app never loads kits from anywhere else. No per-project kit folders, no
  hidden dot-folders, no environment variables pointing elsewhere.
- Only one file in the host decides paths: `src/main/studio-folder.ts`. Every
  other file asks it.
- The app has an **Open Pasture Studio folder** command, and the settings
  sheet shows the folder's location.

The only files outside that folder are Electron's own internal caches, which
every Electron app keeps in the system's standard app-data place. They hold
nothing the user made, and the user never needs to look at them.

---

## 3. The Pasture Studio folder

### Where it lives

Kits are things users write and edit in other apps, like their code editor.
The standard home for user-made files on both Mac and Windows is the
**Documents** folder. Arduino, for example, keeps sketches and libraries in
`Documents/Arduino` on both systems. So:

| System | Location |
|---|---|
| Mac | `~/Documents/Pasture Studio/` |
| Windows | `Documents\Pasture Studio\` (for example `C:\Users\<name>\Documents\Pasture Studio\`) |

In code, always build the path from Electron's `app.getPath('documents')`.
Never hard-code it. On Windows, this also finds Documents correctly when
OneDrive has moved it.

If the user syncs Documents with iCloud or OneDrive, their Pasture Studio
folder is backed up by that service for free. If one of those services has
stored a file online only and not downloaded it, the loader must say so
clearly ("file not downloaded yet") instead of failing silently.

### What is inside

```
Pasture Studio/
  README.md          a short, friendly note: what this folder is and what each part holds
  settings.json      app settings, such as the last opened Pasture
  secrets.json       saved API keys, encrypted by the system (see Phase 5)
  kits/              every kit, one folder each
    board.text/
      kit.json
      kit.tsx
  pastures/          every Pasture, one file each
    <pasture id>.json
  kit-data/          each kit's own saved files and settings
    <kit id>/
```

The host creates the folder and its parts on first launch if they are missing.
It never deletes or overwrites anything the user made.

### While developing the app

When the app runs from the repo (`npm run dev`, not a shipped build):

- Kits load from the repo's own `kits/` folder, so developers edit the starter
  kits in place.
- Everything else goes to `.dev-studio/` in the repo, which is git-ignored, so
  development never touches a real Pasture Studio folder.

`studio-folder.ts` makes this choice with Electron's `app.isPackaged`. It is
the only place that knows about it.

---

## 4. Words we use

| Word | Meaning |
|---|---|
| **Pasture Studio** | The app. |
| **Pasture Studio folder** | The one folder that holds everything (section 3). |
| **Host** | The app's own code: everything under `src/`. The engine. |
| **Kit** | One folder under `kits/` with `kit.json` and `kit.tsx`. |
| **`skapie`** | The name of the kit API. A skapie is a baby sheep: each kit is a little lamb in the Pasture. |
| **Pasture** | One board of cards and cables. Saved as one file in `pastures/`. |
| **Card** | One thing on a Pasture. A kit registers card types; the user places cards. |
| **Port** | A connection point on a card. `in` ports receive, `out` ports send. |
| **Kind** | A label on a port, such as `text` or `tool`. Cables join ports of the same kind. Kits invent kinds; the host only compares the labels. |
| **Cable** | A line from an `out` port to an `in` port. |
| **Reload** | Unload every kit, read `kits/` again, and load every kit fresh. |

---

## 5. Technology

| Part | Choice | Why |
|---|---|---|
| App shell | **Electron** | Gives kits full Node access (files, shell, network) and real web UI, on Mac and Windows. Proven for plugin apps: VS Code, Obsidian, Cursor. |
| Language | **TypeScript** everywhere | One language for host and kits. |
| UI | **React** | Kits draw their cards as React components. |
| Pasture view | **React Flow** (`@xyflow/react`) | A free, well-used library for card-and-cable editors. Nodes, ports and cables come built in. |
| Build | **electron-vite** starter | The standard, simple Electron + Vite + React + TypeScript setup. |
| Kit compiler | **esbuild** | Turns a kit's `kit.tsx` into runnable code in milliseconds, at runtime. |
| Tests | **Vitest** | Simple, fast, works with Vite. |
| Package manager | **npm** | Boring and standard. |

Use the latest stable versions at setup time. Do not add other libraries
without a clear reason. In particular, do not add a state library: a small
store with React's `useSyncExternalStore` is enough.

### Two deliberate choices

**Kits have full power.** Kit code runs inside the app window with Node turned
on. A kit can read any file, run any command, and call any website. This is on
purpose: it is how pi and Obsidian plugins work, and it is what makes kits
truly open. It also means "grants", such as which folder a tool may touch, are
rules that kits keep between themselves, not locks the host enforces. A user
should only install kits they trust, the same as with any plugin.

**Kits share the host's React.** A kit must use the same copy of React as the
app, or its cards will break. That is why we compile kits with esbuild and
hand them the host's React ourselves, instead of letting kits load their own.

---

## 6. How a kit looks

A kit is a folder in `Pasture Studio/kits/`. The folder name must equal the
kit `id`.

`kit.json` describes the kit:

```json
{
  "id": "board.text",
  "name": "Text",
  "description": "A card that holds text.",
  "version": "1.0.0",
  "main": "kit.tsx",
  "skapieApi": 1
}
```

`kit.tsx` holds all of the kit's logic. It exports one default function. The
host calls that function on load and passes it the kit API, named `skapie`:

```tsx
import type { Skapie } from '@skapie/kit'

export default function kit(skapie: Skapie) {
  skapie.cards.register({
    type: 'board.text',
    title: 'Text',
    defaultSize: { width: 260, height: 140 },
    defaultData: { content: '' },
    render: ({ card, update }) => (
      <textarea
        className="skapie-fill"
        value={String(card.data.content ?? '')}
        onChange={(event) => update({ content: event.target.value })}
      />
    ),
  })
}
```

Rules for kit code:

- A kit may `import` its own files, Node's built-in modules (`fs`, `path`,
  `child_process`, `os`, ...), and `react`.
- Imports from `@skapie/kit` are types only. The live API arrives as the
  `skapie` argument.
- A card type must start with its kit id, such as `board.text` or
  `board.text/note`. The host rejects anything else, so two kits can never
  clash.
- A kit keeps its own saved files in `skapie.kit.dataFolder`
  (`kit-data/<kit id>/`), never anywhere else on the computer.
- A kit may return a cleanup function from its default function. The host
  calls it before a reload. Everything the kit registered through `skapie` is
  removed automatically, so most kits need no cleanup.

---

## 7. Setting up the new repo

Do this once, by hand or by an agent.

1. **Freeze the old repo.** Commit and push everything in the Flutter repo to
   `main`. From now on, treat it as read-only reference.
2. **Create the new app** next to it:

   ```bash
   cd ~/Development
   npm create @quick-start/electron@latest pasture-studio -- --template react-ts
   cd pasture-studio
   npm install
   npm install @xyflow/react esbuild
   npm install -D vitest
   git init -b main
   ```

   Answer "no" to optional extras such as the auto-updater. Stay on `main`; do
   not create branches.
3. In `electron-builder.yml`, set `productName: Pasture Studio` and
   `appId: com.skapies.pasturestudio`. In `package.json`, set `"name":
   "pasture-studio"`.
4. Add `.dev-studio/` to `.gitignore`.
5. **Create a new GitHub repo** named `pasture-studio` and push `main` to it.
6. **Add `AGENTS.md`** at the root with the text in section 9.
7. **Copy this file** into the new repo as `docs/new_direction.md`. It is the
   only doc the new repo starts with.
8. Check that `npm run dev` opens a window before starting Phase 1.

---

## 8. The phases

Each phase ends with something that works and can be shown. Do the phases in
order. Finish and commit one phase before starting the next.

Every phase has the same checks at the end:

- `npm test` passes, including the "host has no kit code" test.
- `npm run typecheck` passes, and it covers the `kits/` folder too.
- Deleting or renaming the `kits/` folder still gives a working, empty app.
- Nothing is written outside the Pasture Studio folder (or `.dev-studio/` in
  development).

---

### Phase 1: the empty engine and the first kit

**This is the first task to give an agent in the new repo.**

**Goal:** the app opens to an empty, dark Pasture. It creates the Pasture
Studio folder, loads kits from its `kits/` folder, and one kit, **Text**, can be
added from a command palette. The Pasture is saved and restored on restart.
Editing `kits/board.text/kit.tsx` and choosing **Reload kits** changes the card
without rebuilding the app.

Nothing else. No cables, no ports, no inspector, no LLM, no list of Pastures.

#### 1.1 Window settings

In `src/main/index.ts`, the main window uses:

```ts
webPreferences: {
  nodeIntegration: true,
  contextIsolation: false,
  sandbox: false,
  webSecurity: false,
}
```

- Remove the starter's preload script and its reference; it is not needed.
- Remove the `Content-Security-Policy` line from `src/renderer/index.html`.
  Kits run their own code and call any website on purpose, and that line would
  block both.

Electron prints security warnings in development because of these settings.
That is expected; see "Kits have full power" in section 5.

#### 1.2 File layout

One topic per file. Keep files small.

```
kits/
  board.text/
    kit.json
    kit.tsx
src/
  main/
    index.ts            window, and registers the IPC handlers below
    studio-folder.ts    THE one place that decides every path (section 3)
    kit-folder.ts       lists kit folders and reads each kit.json
    compile-kit.ts      compiles one kit's main file with esbuild
    pasture-file.ts     reads and writes one Pasture file
  renderer/src/
    main.tsx            React entry
    App.tsx             lays out the Pasture, the palette, and the status list
    native.ts           the only file that touches window.require / ipcRenderer
    kit-api/
      types.ts          THE public kit API types (what kits see)
      create-api.ts     builds the `skapie` object for one kit
    kit-host/
      evaluate.ts       runs compiled kit code and returns its default function
      kit-require.ts    what `require` means inside kit code
      registry.ts       card types and commands, grouped by kit
      load-kits.ts      reload: clean up, fetch compiled kits, run each one
    pasture/
      pasture-store.ts  cards, undo and redo, change notifications
      use-pasture.ts    React hook over the store
    canvas/
      PastureView.tsx   React Flow view of the store
      CardView.tsx      draws one card: frame, header, and the kit's render
      CardBoundary.tsx  catches a crashing card so the app keeps running
    palette/
      CommandPalette.tsx  Space opens it; lists "Add <card>" and commands
    status/
      StatusList.tsx    kit load errors and kit messages, top left
    theme.css           colours and base styles (see 1.9)
test/
  host-has-no-kit-code.test.ts
  kit-folder.test.ts
  pasture-store.test.ts
```

The host folder is named `kit-host`, not `kits`, so the guard test can tell
host code apart from the real `kits/` folder.

#### 1.3 The Pasture Studio folder

`studio-folder.ts` exports one function:

```ts
export interface StudioPaths {
  home: string       // the Pasture Studio folder itself
  kits: string
  pastures: string
  kitData: string
  settings: string   // settings.json
}

export function studioPaths(): StudioPaths
```

- Shipped app: `home` is `<Documents>/Pasture Studio`, with `kits` inside it.
- Development (`app.isPackaged` is false): `kits` is the repo's `kits/`, and
  everything else is under the repo's `.dev-studio/`.
- On launch, the main process creates any missing folders and writes
  `README.md` if it is missing. The README explains, in plain words, what each
  part of the folder holds.

Every other host file gets its paths from `studioPaths()`. Tests pass paths to
the functions they test, so they never touch a real folder.

#### 1.4 The Pasture file

Each Pasture is one file, `pastures/<pasture id>.json`:

```json
{
  "version": 1,
  "id": "p_1",
  "name": "My first Pasture",
  "cards": [
    {
      "id": "c_1",
      "type": "board.text",
      "name": "Text",
      "x": 0,
      "y": 0,
      "width": 260,
      "height": 140,
      "data": { "content": "hello" }
    }
  ],
  "cables": []
}
```

- `data` belongs to the kit. The host saves it and never looks inside it.
- On launch, open the Pasture named in `settings.json` as the last one opened.
  If there is none, open the most recently changed file. If `pastures/` is
  empty, create "My first Pasture".

#### 1.5 The public kit API, version 1

`src/renderer/src/kit-api/types.ts`. Keep it exactly this small in Phase 1.
Later phases add to it; nothing gets removed without bumping `skapieApi`.

```ts
import type { ReactNode } from 'react'

export type CardData = Record<string, unknown>

export interface Card<Data extends CardData = CardData> {
  id: string
  type: string
  name: string
  x: number
  y: number
  width: number
  height: number
  data: Data
}

export interface CardProps<Data extends CardData = CardData> {
  card: Card<Data>
  selected: boolean
  update(patch: Partial<Data>): void
}

export interface CardType<Data extends CardData = CardData> {
  /** Must start with the kit id, e.g. `board.text` or `board.text/note`. */
  type: string
  title: string
  defaultSize: { width: number; height: number }
  defaultData: Data
  render(props: CardProps<Data>): ReactNode
}

export interface Command {
  id: string
  label: string
  run(): void | Promise<void>
}

export interface Skapie {
  apiVersion: 1
  kit: { id: string; folder: string; dataFolder: string }
  cards: { register<Data extends CardData>(type: CardType<Data>): void }
  commands: { register(command: Command): void }
  pasture: {
    get(cardId: string): Card | undefined
    update(cardId: string, patch: CardData): void
  }
  status: { report(message: string): void }
}

export type KitMain = (skapie: Skapie) => void | (() => void)
```

The repo's `tsconfig` maps `@skapie/kit` to this file, so kits in `kits/` get
type checking and editor help.

#### 1.6 Loading kits

Loading happens in two halves.

**Main process (Node).** An IPC handler, `kits:load`:

1. Lists the folders in `kits/`, sorted by name.
2. For each folder, reads `kit.json`. The folder name must equal `id`, and
   `skapieApi` must be `1`.
3. Creates `kit-data/<kit id>/` if it is missing.
4. Compiles the `main` file with esbuild.
5. Returns one entry per folder: either `{ id, folder, dataFolder, code }` or
   `{ id, folder, error }`. One broken kit never stops the others.

```ts
// src/main/compile-kit.ts
import { build } from 'esbuild'

export async function compileKit(entryFile: string): Promise<string> {
  const result = await build({
    entryPoints: [entryFile],
    bundle: true,
    write: false,
    format: 'cjs',
    platform: 'node',
    jsx: 'automatic',
    external: ['react', 'react/jsx-runtime', 'electron', '@skapie/kit'],
    logLevel: 'silent',
  })
  return result.outputFiles[0].text
}
```

**Window (renderer).** `load-kits.ts`:

1. Calls every loaded kit's cleanup function, if it gave one, and clears the
   registry.
2. Asks the main process for `kits:load`.
3. For each entry with code: runs it with `evaluate.ts`, builds a `skapie`
   object with `create-api.ts`, and calls the kit's default function inside
   `try`/`catch`. If the kit throws, everything it registered is removed and
   the error goes to the status list.
4. Entries with an error go straight to the status list.

```ts
// src/renderer/src/kit-host/evaluate.ts
import type { KitMain } from '../kit-api/types'

export function evaluateKit(code: string, kitRequire: (name: string) => unknown): KitMain {
  const module = { exports: {} as Record<string, unknown> }
  new Function('require', 'module', 'exports', code)(kitRequire, module, module.exports)
  const main = module.exports.default
  if (typeof main !== 'function') {
    throw new Error('kit.tsx must export a default function')
  }
  return main as KitMain
}
```

```ts
// src/renderer/src/kit-host/kit-require.ts
import * as React from 'react'
import * as jsxRuntime from 'react/jsx-runtime'
import { nodeRequire } from '../native'

const shared: Record<string, unknown> = {
  react: React,
  'react/jsx-runtime': jsxRuntime,
  '@skapie/kit': {},
}

export function kitRequire(name: string): unknown {
  return name in shared ? shared[name] : nodeRequire(name)
}
```

`registry.ts` keeps card types and commands grouped by kit id. It rejects a
card type that does not start with its kit id, and a type that another kit
already registered. Both cases become status messages, not crashes.

#### 1.7 The Pasture

- `pasture-store.ts` holds the open Pasture: cards now, cables from Phase 3.
  - Every change goes through one method, which saves a copy of the previous
    Pasture for undo. Keep at most 100 steps.
  - The store notifies listeners after each change and saves the Pasture file
    shortly afterwards.
- `PastureView.tsx` shows the store with React Flow, using one custom node
  type, `card`.
  - Dragging moves cards on screen, and only the final position is written to
    the store when the drag ends. One drag is one undo step.
- `CardView.tsx` draws the host frame: dark panel, thin border, and a header
  with the card name. Inside the frame it calls the kit's `render`, wrapped in
  `CardBoundary`.
  - If the card's kit is not loaded, it shows "Missing kit: <type>" and keeps
    the card's data untouched. Reload the kit and the card comes back.
- Keys: `Delete`/`Backspace` removes selected cards, `Cmd+Z` / `Ctrl+Z` undoes,
  `Cmd+Shift+Z` / `Ctrl+Shift+Z` redoes. These are engine actions, so they live
  in the host.

#### 1.8 The command palette

- `Space` opens it when the user is not typing. `Escape` closes it.
- It lists:
  - "Add <title>" for every registered card type. The new card goes to the
    centre of the view.
  - Every command kits registered.
  - The engine's own commands: **Reload kits**, **Open Pasture Studio
    folder**, **Undo**, **Redo**.
- Typing filters the list. Up/Down moves, Enter runs.

#### 1.9 The look

Dark Pasture, champagne-gold accent. Put these in `theme.css` as CSS
variables, so kits can use them too:

```css
:root {
  --skapie-canvas: #0c0c0e;
  --skapie-panel: #161618;
  --skapie-ink: #f4efe6;
  --skapie-muted: rgba(244, 239, 230, 0.55);
  --skapie-hairline: rgba(244, 239, 230, 0.12);
  --skapie-accent: #c4a46a;
  --skapie-on-accent: #1a1408;
  --skapie-danger: #b85c5c;
  --skapie-success: #6e9b6a;
  --skapie-radius: 8px;
}
```

Also add one helper class, `.skapie-fill`, that makes an element fill the card
body with the panel background and ink colour. The Text kit uses it.

#### 1.10 The Text kit

`kits/board.text/kit.json` and `kits/board.text/kit.tsx`, exactly as shown in
section 6.

#### 1.11 Tests (keep them simple)

**`test/host-has-no-kit-code.test.ts`**, the guard. It must stay in the repo
forever:

```ts
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

function filesIn(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    return statSync(path).isDirectory() ? filesIn(path) : [path]
  })
}

const kitIds = readdirSync('kits').filter((name) => statSync(join('kits', name)).isDirectory())
const hostFiles = filesIn('src')

describe('the host has no kit code', () => {
  it('never names a kit', () => {
    for (const file of hostFiles) {
      const text = readFileSync(file, 'utf8')
      for (const id of kitIds) {
        expect(text.includes(id), `${file} mentions ${id}`).toBe(false)
      }
    }
  })

  it('never imports from the kits folder', () => {
    for (const file of hostFiles) {
      const text = readFileSync(file, 'utf8')
      expect(/from\s+['"][^'"]*\bkits\//.test(text), file).toBe(false)
    }
  })
})
```

**`test/kit-folder.test.ts`**, using a temporary folder:

- A good kit comes back with code.
- A kit with a syntax error comes back with an error, and a good kit next to
  it still loads.
- A folder whose name does not match its `id` comes back with an error.
- An empty `kits/` folder gives an empty list.

**`test/pasture-store.test.ts`:**

- Add a card, move it, undo: it is back where it started.
- Save the Pasture to JSON and load it back: the result is the same Pasture.

#### 1.12 Done when

- `npm run dev` opens a dark, empty Pasture, and `.dev-studio/` appears with
  `README.md`, `pastures/`, `kit-data/` and `settings.json`.
- `Space`, then "Add Text", places a Text card. You can type in it, drag it,
  and delete it. Undo brings it back.
- Quit and reopen: the card is still there with its text.
- Change the placeholder or colour in `kits/board.text/kit.tsx`, choose
  **Reload kits**, and the change shows without restarting.
- Put a typo in `kit.tsx` and reload: the status list shows the error, and the
  app keeps running. The existing card shows "Missing kit" and gets its text
  back once the typo is fixed and you reload.
- **Open Pasture Studio folder** opens `.dev-studio/` in Finder or Explorer.
- All the checks at the top of section 8 pass.

---

### Phase 2: your Pastures

**Goal:** the user has many Pastures and moves between them easily. This is
host-only work.

- A **Pastures** screen that lists every Pasture, newest first, with its name
  and when it was last changed. It shows on launch when there is more than one
  Pasture, and from the palette at any time.
- Palette commands: **New Pasture**, **Open Pasture…**, **Rename Pasture**,
  **Duplicate Pasture**, **Delete Pasture**. Deleting asks first, and moves the
  file to the system trash, not straight to deletion.
- The window title shows "Pasture Studio — <Pasture name>".
- The last opened Pasture is saved in `settings.json`.

**Done when:** you can create three Pastures, rename one, delete one, and quit.
Reopening lands on the one you last used, and every Pasture is one file in
`pastures/`.

---

### Phase 3: ports, cables, and data flow

**Goal:** cards have ports. The user drags cables between them. Kits pass
values along cables. The host still has no idea what the values mean.

Additions to the kit API:

```ts
export interface PortSpec {
  id: string                  // unique within the card, e.g. 'out'
  label: string
  direction: 'in' | 'out'
  kind: string                // e.g. 'text'. Invented by kits. The host only compares.
  multiple?: boolean          // in ports: may take more than one cable. Default false.
}

export interface CardContext<Data extends CardData = CardData> {
  card: Card<Data>
  update(patch: Partial<Data>): void
  /** Values from every cable plugged into one of my in ports. */
  read(portId: string): Promise<unknown[]>
  /** Push a value out of one of my out ports, along every cable. */
  send(portId: string, value: unknown): Promise<void>
  /** Cards plugged into one of my ports, for display. */
  connections(portId: string): Array<{ card: Card; portId: string }>
}

// Added to CardType:
ports?: PortSpec[]
/** What each out port provides when a neighbour reads it. */
provide?: Record<string, (ctx: CardContext<Data>) => unknown | Promise<unknown>>
/** What happens when a value is sent into one of my in ports. */
receive?: Record<string, (ctx: CardContext<Data>, value: unknown) => void | Promise<void>>
/** Extra controls shown in the inspector when the card is selected. */
inspector?: (props: CardProps<Data>) => ReactNode

// CardProps gains `ctx: CardContext<Data>`.
// Skapie gains: on('cable:connected' | 'cable:removed' | 'card:removed', handler)
```

There are two ways a value moves, and both are generic:

- **Pull.** An LLM card calls `ctx.read('input')`. The host finds each cable
  into that port, and asks the card at the other end for its value through its
  `provide` function.
- **Push.** An LLM card calls `ctx.send('output', reply)`. The host calls
  `receive` on every card cabled to that port.

A value can be anything, including an object with functions. For example, a
tool card can provide a tool the LLM can call. The host passes it along
without looking.

Host work:

- Draw ports as React Flow handles on the card edges: `in` on the left, `out`
  on the right.
- A cable is allowed only from `out` to `in`, when the two `kind`s are equal
  and the `in` port is free or has `multiple: true`.
- Cables are saved in the Pasture file and go through undo like everything
  else.
- Hovering a cable shows a scissor. Clicking cuts the cable. A selected cable
  is cut with `Delete`.
- Protect against loops: if reading goes more than 20 cards deep, stop with
  "Cables loop back on themselves".
- **Inspector:** a floating panel on the right when a card is selected. It
  shows:
  - the card name, which can be edited;
  - a generic list of each port with what it is cabled to, with a Cut button;
  - the card type's own `inspector`, if it has one.

Update the Text kit:

- An `in` port and an `out` port, both kind `text`.
- `provide.out` returns its content, and `receive.in` replaces its content.
- A small "Send" button on the card calls `ctx.send('out', content)`.

**Done when:** two Text cards cabled together, where pressing Send on the first
fills the second. Cut the cable and Send does nothing. Undo brings the cable
back.

---

### Phase 4: the Repository kit and the Read tool

**Goal:** a kit can reach the computer. A Repository card points at a folder,
and a Read card can list, search and read files in it. There is still no LLM,
so the Read kit gets a small "Try it" box in its own inspector to prove it
works.

Addition to the kit API:

- `skapie.dialog.pickFolder(): Promise<string | null>`, done in the main
  process over IPC.

New kits, **all logic inside their folders**:

- **`coding.repository`**
  - Double-clicking the card, or a button in its inspector, picks a folder.
    The folder's path is saved in the card's data. The folder itself stays
    where it is: it is the user's project, not part of the Pasture Studio
    folder.
  - Two out ports: `read` (kind `folder.read`) and `write` (kind
    `folder.write`).
  - Each port provides a **folder handle**: an object with safe methods such as
    `list()`, `search(text)`, `readFile(path)` and, on the write handle,
    `writeFile(path, text)`. Every method refuses paths that leave the folder.
  - The handle is the grant. Tools only get what the Repository kit lets them
    do.
  - The handle's type lives in `kits/coding.repository/contract.ts`. Other kits
    use `import type` from that file for editor help, so there is no copied
    code.
- **`tools.read`**
  - One in port, `repository` (kind `folder.read`), and one out port, `tool`
    (kind `tool`).
  - `provide.tool` returns a tool object: `{ name, description, parameters,
    run(args) }`, where `parameters` is a JSON schema. `run` reads the
    `repository` port and uses the folder handle.
  - The tool shape lives in `kits/harness.llm/contract.ts`, because the LLM kit
    is the one that uses tools. Create that file now with only the tool type in
    it.

**Done when:** Repository → Read is cabled, a folder is picked, and "Try it"
in the Read inspector lists the files. With the cable cut, "Try it" says no
folder is connected. The guard test still passes.

---

### Phase 5: the LLM and Conversation kits

**Goal:** the full coding-agent Pasture works: Task text → LLM → Output text,
with Conversation memory and the Read tool.

Additions to the kit API:

- `skapie.settings.register({ id, title, render })`: kits add sections to the
  host's settings sheet, opened with `Cmd+,` / `Ctrl+,`. The host draws the
  sheet; the kits fill it.
- `skapie.secrets.get(name)` and `skapie.secrets.set(name, value)`: for API
  keys.
  - The host encrypts values with Electron's `safeStorage`, which uses the
    Mac Keychain or Windows' own protection, and saves them in
    `secrets.json` in the Pasture Studio folder.
  - Keys are kept per kit, so one kit cannot read another kit's secrets by
    accident.
  - An encrypted key is safe even if the folder is synced by iCloud or
    OneDrive.
- `skapie.pasture.selected(): Card[]`, so a kit command can act on the
  selected card.

New kits:

- **`harness.llm`**, all inside its folder, in small files:
  - Ports: `input` (kind `text`), `context` (kind `text`, multiple),
    `conversation` (kind `conversation`), `tools` (kind `tool`, multiple), and
    `output` (kind `text`).
  - The card shows the model name, a Run button, and a status: Ready, Running,
    Completed or Failed.
  - A settings section to choose a provider and model and enter an API key.
    Keys go through `skapie.secrets`. Environment variables such as
    `OPENAI_API_KEY` also work.
  - Providers, one file each: OpenCode Go, OpenRouter, OpenAI, and custom
    (any OpenAI-compatible address). Support the three ways models are called
    today: chat completions, responses, and Anthropic-style messages.
  - The agent loop, in its own file:
    1. Read input, context, conversation and tools.
    2. Send them to the model.
    3. If the model asks for a tool, run it, add the result, and ask again.
    4. Stop at a final answer or after a step limit (start with 20).
    5. Send the answer out of `output`. Tell the conversation what happened.
  - A "Run selected LLM" command.
- **`harness.conversation`**
  - One in port, `in` (kind `conversation`).
  - It provides the LLM with an object: `{ turns, append(user, assistant) }`.
    It stores turns in its card data and shows them as a readable transcript.
  - Because the LLM reads and writes through that object, the host never knows
    what a conversation is.

**Done when:**
- A real model call works: a task in a Text card, cabled into Input, gives an
  answer in the Output Text card.
- With Read cabled into Tools, the model can read files from the Repository
  folder.
- The second run remembers the first through the Conversation card.
- The API key survives a restart, and `secrets.json` does not contain it in
  plain text.
- Removing the `harness.llm` folder and reloading leaves "Missing kit" cards
  and a working app.

---

### Phase 6: Write, Edit and Shell

**Goal:** the model can change code, not just read it. After this phase the app
works end to end.

New kits, each with an in port `repository` (kind `folder.write`) and an out
port `tool` (kind `tool`):

- **`tools.write`**: create or replace a file.
- **`tools.edit`**: replace exact text in a file.
- **`tools.shell`**: run a command with the folder as its working directory,
  with a time limit. On Mac it uses the user's shell; on Windows it uses
  PowerShell. This is the kit's choice, not the host's.

They use the write handle from the Repository kit. If a helper is needed by
more than one tool, it belongs on the handle in `coding.repository`, not
copied into each tool.

**Done when:** the model can add a line to a file in the picked folder and run
a command there, such as `git status`, and the answer shows the result. This
works on both Mac and Windows.

---

### Phase 7: kits that build and extend kits

**Goal:** the pi-like loop. Kits can extend other kits, and the model can
write a new kit and load it while the app is running.

Additions to the kit API:

- `skapie.services.provide(name, value)` and `skapie.services.list(name)`: a
  plain shared list that kits use to offer things to each other. It is emptied
  on reload.
  - The LLM kit adds `services.list('llm.provider')` to its own providers, so
    a user can add a new model provider as a separate kit, without touching the
    LLM kit.
- `skapie.kits.reload()`, `skapie.kits.list()` and `skapie.kits.folder` (the
  `kits/` folder).
- On launch, the host writes `skapie-kit.d.ts` (a copy of the public types)
  and a small `tsconfig.json` into `kits/`. A kit opened in any editor then
  gets autocompletion.
- A **New kit…** command: asks for a name, creates `kits/<id>/` with a working
  `kit.json` and `kit.tsx`, reloads, and opens the folder. Every new kit
  starts in the one right place.

New kit:

- **`skapie.extensions`**
  - Holds `docs/` inside its folder: how to write a kit, the full kit API, and
    the tool and folder-handle contracts.
  - One out port, `docs` (kind `text`), that provides those docs. Cable it
    into an LLM's Context and the model knows how to write kits.
  - A "Reload kits" tool (kind `tool`) that calls `skapie.kits.reload()`.

**Done when:** a Pasture has an LLM, with Extensions cabled into its Context
and a Repository whose write folder is `kits/` itself. Asking "make a kit that
shows a clock" writes a new kit folder. The model reloads the kits and a Clock
card is available in the palette. Nobody touched the host.

---

### Phase 8: feel and polish

**Goal:** a Pasture feels as good as the old Flutter board did. All of this is
engine work, with no kit knowledge.

- Keyboard:
  - `Tab`/`Shift+Tab` moves through cards.
  - `P`/`Shift+P` moves through the selected card's ports.
  - `Enter` on a port opens "Connect mode" in the palette. It lists compatible
    targets as "Card · Port" and existing cables as "Cut · Card · Port".
- Cable animation: a short flash in the target card's colour when a cable
  connects, and the ends pull back when cut.
- `ctx.pulse(portId)`: a kit asks the host to pulse the cables on a port. The
  LLM kit pulses a tool's cable while that tool runs.
- A colour swatch per card (ten colours) that tints its border and cables.
- Resizing cards by dragging the bottom edge.
- `skapie.ui.open(component)`: kits can open a full-screen overlay, for
  example a large text editor or a request viewer. The host owns the overlay;
  the kit owns what is inside.
- `frame: false` on a card type: the kit draws the whole card itself, while
  the host still draws its ports.

---

### Phase 9: shipping the app

**Goal:** an app a user can install on Mac and Windows, with the starter kits
in their Pasture Studio folder.

- **App icon:** a stylised lamb (a skapie) drawn as one scribbled, continuous
  line. Gold (`#c4a46a`) on the dark canvas colour. Make it clear at small
  sizes: a Mac `.icns` and a Windows `.ico`, from one source drawing.
- **Mac:** build a `.dmg` with electron-builder. Sign and notarise it with an
  Apple Developer ID, so macOS will open it.
- **Windows:** build an installer (electron-builder's NSIS target). Sign it
  when a code-signing certificate is available; until then, Windows shows a
  warning on first run.
- Mark esbuild as unpacked from the app archive (`asarUnpack` for
  `node_modules/esbuild` and `node_modules/@esbuild`). Otherwise kits cannot be
  compiled in the shipped app.
- Ship the repo's `kits/` folder inside the app as extra resources.
- On launch, copy any starter kit that is missing from the user's `kits/`
  folder into it. Never overwrite a folder that already exists: that is the
  user's copy.
- A **Restore starter kit…** command copies one starter kit back, after
  asking, for when a user breaks one.
- Always build and install release versions.

---

## 9. `AGENTS.md` for the new repo

Put this at the root of the new repo:

```markdown
Hello. I am Anthony, the owner of Pasture Studio.

Read docs/new_direction.md before any work. It is the plan.

On every turn, name the layer first: KIT (`kits/<id>/`) | HOST (`src/`) | PASTURE.
Say the kit id if any, give a one-sentence Change, and stop after this layer.
Briefly explain why and the files touched.

- The host contains no kit code. Never name a kit id in `src/`, never import
  from `kits/`, never branch on a card type. If a kit needs something, add a
  general hook to the kit API.
- The guard test `test/host-has-no-kit-code.test.ts` must always pass. Never
  weaken or skip it.
- Everything the app saves lives in the Pasture Studio folder. Only
  `src/main/studio-folder.ts` decides paths. Never read kits or save data
  anywhere else.
- Stay on main.
- Use good coding practices.
- Do not copy and paste code, ever. Build re-usable, modular code. If you find
  code that can be simplified, fix it.
- Keep the file system modular. One topic = one file.
- Keep systems boring and solid. Do not add complexity or libraries that are
  not needed.
- No vibe slop. Keep prose simple, informative and in plain terms.
- Keep tests simple and straightforward.
- At the end of every response, add a sheep emoji to acknowledge you read my
  rules.
- Gracefully stop your work if the 5h usage drops to 5% or below.
```

---

## 10. Mistakes to refuse

Earlier agents made these mistakes. Do not repeat them.

- **A stub kit that hands work back to the host.** A `kit.tsx` that returns
  "please do this for me" while the real code sits in `src/` breaks rule 1.
  The real code goes in the kit.
- **"Just this once" host shortcuts.** For example, `if (type === 'harness.llm')`
  for rounder corners or a special icon. Add a general option to `CardType`
  instead.
- **Host-owned port names.** The host must not define `input`, `tools` or
  `repository`. Kits declare their own ports.
- **Starter content in host code.** The starter kits are folders in `kits/`.
  The host never lists them.
- **Data outside the Pasture Studio folder.** No kits, settings, logs or kit
  data in hidden folders, the home folder, or project folders. A kit that needs
  to save something uses its `dataFolder`.
- **Porting Flutter code line by line.** Use the old app to see how things
  should behave, then write fresh, small TypeScript.
- **Big files.** Split them by topic.
- **Growing the API for one kit's convenience.** Every new hook must make sense
  for kits nobody has written yet.

---

## 11. From the old app: what to keep and what to leave

**Keep (as ideas):**
- The dark and champagne-gold look.
- The palette-first feel: `Space` to add, no toolbars.
- The keyboard flow for ports and cables.
- The starter kits and their ports.
- A running LLM shows its status on the card.

**Leave behind for now:**
- Run ledgers, checkpoints, pause and resume, conversation compaction, context
  previews and request previews. They lived in the old host. If we want them
  back, they come back as features of the LLM kit, after Phase 7.
- Accounts, cloud sync and cloud backup. Out of scope until the app works end
  to end.
