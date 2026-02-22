# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**nimpulseqgui** is a Nim library and framework for building GUI/CLI applications that define, validate, and write Pulseq-compatible MRI sequences. It is not a standalone tool — users extend it by providing three callbacks and compiling their own executable.

## Build and Run

```bash
# Install dependencies
nimble install

# Compile the example sequence application
nim c -o sequence_example sequence_example.nim

# Run with GUI (requires --output)
./sequence_example --output out.seq

# Run headless
./sequence_example --output out.seq --no-gui

# Compile with cross-compilation (e.g. for Windows EXE, as hinted by propertyedit.exe)
nim c --os:windows -o propertyedit.exe src/nimpulseqgui/propertyedit.nim
```

There are no automated tests in this repo. Manual testing is done by running the compiled sequence executable.

## Architecture

The framework uses a **callback architecture**: users implement three procs and call `makeSequenceExe(getDefaultProtocol, validateProtocol, makeSequence)` as their `main`.

### Module Roles

- **`src/nimpulseqgui.nim`** — library entry point; re-exports all public APIs
- **`src/nimpulseqgui/definitions.nim`** — core types: `MRProtocolRef` (an `OrderedTableRef[string, ProtocolProperty]`), the tagged-union `ProtocolProperty`, property constructors, and callback type aliases
- **`src/nimpulseqgui/sequenceexe.nim`** — CLI engine; parses command-line options into `Opts` (scanner hardware specs), calls the three user callbacks, and dispatches to GUI or headless mode
- **`src/nimpulseqgui/sequencegui.nim`** — builds the main window with a vertical list of property rows (Edit button + name + value), output path field, and Write/Load buttons
- **`src/nimpulseqgui/propertyedit.nim`** — modal editor windows for each property type; implements the binary search feature (`pvDoSearch`) that auto-discovers valid min/max bounds
- **`src/nimpulseqgui/io.nim`** — reads/writes a protocol preamble block (`[NimPulseqGUI Protocol]` … `[NimPulseqGUI Protocol End]`) embedded in Pulseq `.seq` files

### Data Flow

```
CLI args → Opts (scanner hardware)
         → getDefaultProtocol(opts) → MRProtocolRef
         → [GUI] user edits properties via propertyedit windows
         → validateProtocol(opts, prot) → bool (red/white feedback)
         → makeSequence(opts, prot) → Sequence
         → io.nim writes .seq file with embedded preamble
```

### Key Types

- `MRProtocolRef` — mutable `OrderedTableRef`; insert order determines GUI display order
- `ProtocolProperty` — case object: `ppInt`, `ppFloat`, `ppBool`, `ppStringList`, `ppDescription`
- `PropertyValidate` — `pvDoSearch` triggers binary search on validation; `pvNoSearch` does not
- `Opts` — hardware specification record passed to all three callbacks

### Property Constructors

```nim
newFloatProperty(val, min, max, incr: float; validate = pvNoSearch; unit = "")
newIntProperty(val, min, max, incr: int;   validate = pvNoSearch; unit = "")
newBoolProperty(val: bool; validate = pvNoSearch)
newStringListProperty(val: string; list: seq[string]; validate = pvNoSearch)
newDescriptionProperty(desc: string)
```

## Dependencies

- `nigui` — cross-platform GUI framework
- `nimpulseq` (https://github.com/nimpulseq/nimpulseq) — Pulseq sequence object and file writer
- `PulseqSystems` (https://github.com/nimpulseq/PulseqSystems) — scanner hardware presets (manufacturer/model/gradient system definitions)

## Sequence File Format

Protocol parameters are persisted inside `.seq` files between special markers:

```
[NimPulseqGUI Protocol]
key=value
...
[NimPulseqGUI Protocol End]
```

Newlines within values are escaped as `\n`. The `io.nim` module handles reading and writing this block.
