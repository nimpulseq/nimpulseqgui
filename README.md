# nimpulseqgui

nimpulseqgui is a Nim library that provides a GUI and CLI framework for building Pulseq-compatible MRI sequence applications. You implement your sequence logic; the library handles parameter editing, validation, and file output.

The compiled result is an executable file that produces vendor-independent Pulseq `.seq` files to be executed on MR scanners through the vendor-specific interpreters. The advantages of having such an executable file are:
- It can produce adapted `.seq` files for multiple system configurations (specified on the command line).
- It allows executing a GUI to adapt parameters on-the-fly, potentially directly at the scanner.
- It allows distribution of compiled binaries instead of source code, while still being vendor-independent.

## How it works

The library is not a standalone tool — you create your own executable by implementing three callback functions and calling `makeSequenceExe`. The resulting binary has a full GUI for editing protocol parameters and writing `.seq` files, plus a headless mode for scripted use.

```
Your callbacks → makeSequenceExe → GUI or headless execution
```

The three required callbacks are:

| Callback | Type alias | Purpose |
|---|---|---|
| `getDefaultProtocol` | `ProcGetDefaultProtocol` | Returns the initial protocol with all parameters and their defaults |
| `validateProtocol` | `ProcValidateProtocol` | Checks whether the current parameter set is physically feasible |
| `makeSequence` | `ProcMakeSequence` | Builds and returns the actual Pulseq `Sequence` object |

**Execution flow:**

1. `getDefaultProtocol(opts)` is called to initialize the protocol.
2. The default protocol is immediately validated; startup fails if the defaults are invalid for the given system specs.
3. If `--input` was supplied, saved parameters are loaded from a previous `.seq` file and re-validated.
4. In GUI mode, the user edits parameters; each change is validated live.
5. When the user clicks "Write Sequence", `makeSequence` is called and the `.seq` file is written with an embedded protocol preamble (for future reloading with `--input`).
6. In `--no-gui` mode, steps 4–5 happen immediately without user interaction.

## Implementing the callbacks

### `getDefaultProtocol`

```nim
proc myDefaultProtocol(opts: Opts): MRProtocolRef =
    var prot = newProtocol()
    # Insert properties in display order:
    prot["Description"] = newDescriptionProperty("My sequence description")
    prot["FOV"]         = newIntProperty(val=200, min=50, max=500, incr=1, validate=pvDoSearch, unit="mm")
    prot["TE"]          = newFloatProperty(val=5.0, min=1.0, max=100.0, incr=0.1, validate=pvDoSearch, unit="ms")
    prot["RF Spoiling"] = newBoolProperty(val=true)
    return prot
```

`MRProtocolRef` is an `OrderedTableRef[string, ProtocolProperty]`. Insertion order determines the order properties appear in the GUI. The `opts` parameter contains scanner hardware specifications and can be used to set hardware-dependent defaults.

### `validateProtocol`

Called frequently: on startup, on every parameter change in the GUI, and during binary search. It must be **fast** and must **not** produce side effects. The typical pattern is to compute gradient shapes and timings, then return `false` if any constraint is violated.

```nim
proc validateProtocol(opts: Opts, prot: MRProtocolRef): bool =
    let system = opts   # Opts is compatible with nimpulseq's system specs
    let TE = prot["TE"].floatVal * 1e-3

    let gx = makeTrapezoid(channel="x", flatArea=..., system=system)
    let delayTE = TE - calcDuration(gx) / 2.0 - ...

    if delayTE < 0.0:
        return false    # TE is too short; return false, do not raise

    return true
```

Return `false` for any infeasible parameter combination. Do not call `quit` or raise exceptions here.

### `makeSequence`

Called once when the user writes the sequence. May assume the protocol is already valid (validation was just run before this is called). Should build and return the complete Pulseq `Sequence` object.

```nim
proc makeSequence(opts: Opts, prot: MRProtocolRef): Sequence =
    let system = opts
    var seqObj = newSequence(system)

    # build RF pulses, gradients, ADC events ...
    seqObj.addBlock(rf, gz)
    seqObj.addBlock(gx, adc)

    let (ok, report) = seqObj.checkTiming()
    if not ok:
        raise newException(ValueError, "Timing check failed")

    return seqObj
```

### Wiring everything together

Call `makeSequenceExe` as your program's entry point — it handles all CLI parsing and GUI startup:

```nim
import nimpulseqgui

# ... define the three procs above ...

makeSequenceExe(myDefaultProtocol, validateProtocol, makeSequence, "My Sequence Title")
```

The optional `title` string sets the window title.

## Protocol properties

All properties share two optional fields: `validate` (default `pvNoSearch`) and `unit` (display-only string).

```nim
newFloatProperty(val, min, max, incr: float; validate = pvNoSearch; unit = "")
newIntProperty(val, min, max, incr: int;   validate = pvNoSearch; unit = "")
newBoolProperty(val: bool; validate = pvNoSearch)
newStringListProperty(val: string; list: seq[string]; validate = pvNoSearch)
newDescriptionProperty(desc: string)   # read-only label row in the GUI
```

Reading property values in your callbacks:

```nim
prot["TE"].floatVal         # float
prot["FOV"].intVal          # int
prot["RF Spoiling"].boolVal # bool
prot["Mode"].stringVal      # string (current selection)
prot["Mode"].stringList     # seq[string] (all options)
```

### Validation strategies

`pvDoSearch` enables automatic binary search: when the user edits a numeric property, the GUI searches for the actual valid min/max within the declared range by calling `validateProtocol` repeatedly. This gives the user accurate feedback on which values are achievable. Use it for parameters that directly affect timing feasibility (TE, TR, resolution, etc.).

`pvNoSearch` skips the search and only validates the currently entered value. Use it for parameters where the valid range is already exact (e.g. a boolean flag, or a string selection).

## Accessing scanner hardware specs (`Opts`)

`Opts` is the nimpulseq system specification record. In your callbacks, `opts` holds the hardware parameters resolved from the command-line flags. It can be used directly wherever nimpulseq expects a system spec:

```nim
let system = opts
var seqObj = newSequence(system)
let gx = makeTrapezoid(channel="x", ..., system=system)
```

Key fields include `opts.maxGrad`, `opts.maxSlew`, `opts.gradRasterTime`, `opts.rfDeadTime`, `opts.rfRingdownTime`, `opts.adcDeadTime`, `opts.B0`, `opts.gamma`, etc. These are populated from command-line flags or scanner presets (see CLI reference below).

## Building and running your sequence executable

```bash
nimble install                                     # install dependencies
nim c -o my_sequence my_sequence.nim               # compile
./my_sequence --output result.seq                  # launch GUI
./my_sequence --output result.seq --no-gui         # headless mode
./my_sequence --input previous.seq --output result.seq  # reload saved parameters
```

## CLI reference

All flags are optional except `--output`.

| Flag | Description |
|---|---|
| `-o`, `--output=<file>` | Output `.seq` file path **(required)** |
| `-i`, `--input=<file>` | Load protocol parameters from a previous `.seq` file |
| `--no-gui` | Write the sequence immediately without opening the GUI |
| `--manufacturer=<name>` | Scanner manufacturer (e.g. `Siemens Healthcare`) |
| `--model=<name>` | Scanner model (e.g. `MAGNETOM Prisma`) — requires `--manufacturer` |
| `--gradient=<name>` | Gradient model (optional, defaults to standard for the given model) |
| `--scaleGradients=<value>` | Scale factor for gradient amplitudes (used with manufacturer/model) |
| `--scaleSlewRate=<value>` | Scale factor for slew rate (used with manufacturer/model) |
| `--maxGrad=<value>` | Maximum gradient amplitude (overrides system specs) |
| `--maxSlew=<value>` | Maximum slew rate (overrides system specs) |
| `--gradUnit=<unit>` | Unit for `--maxGrad`: `mT/m` or `Hz/m` (default `Hz/m`) |
| `--slewUnit=<unit>` | Unit for `--maxSlew`: `T/m/s` or `Hz/m/s` (default `Hz/m/s`) |
| `--riseTime=<s>` | Gradient rise time in seconds |
| `--rfDeadTime=<s>` | RF dead time in seconds |
| `--rfRingdownTime=<s>` | RF ringdown time in seconds |
| `--adcDeadTime=<s>` | ADC dead time in seconds |
| `--adcRasterTime=<s>` | ADC raster time in seconds |
| `--rfRasterTime=<s>` | RF raster time in seconds |
| `--gradRasterTime=<s>` | Gradient raster time in seconds |
| `--blockDurationRaster=<s>` | Block duration raster time in seconds |
| `--adcSamplesLimit=<n>` | ADC sample count limit |
| `--adcSamplesDivisor=<n>` | ADC sample count divisor |
| `--gamma=<Hz/T>` | Gyromagnetic ratio |
| `--B0=<T>` | Main magnetic field strength |
| `--list-manufacturers` | Print available manufacturers and exit |
| `--list-models` | Print available models for `--manufacturer` and exit |

For available manufacturer/model/gradient names, see the [PulseqSystems repository](https://github.com/nimpulseq/PulseqSystems/).

## Protocol persistence

When a sequence is written, the current protocol is embedded in the `.seq` file between the markers:

```
[NimPulseqGUI Protocol]
TE=5.0
FOV=200
...
[NimPulseqGUI Protocol End]
```

Pass the file back with `--input` (or via the GUI "Load..." button) to restore these parameters. Unknown or invalid keys are skipped with a warning; missing keys keep their defaults.

## Dependencies

- [`nigui`](https://github.com/simonkrauter/NiGui) — cross-platform GUI
- [`nimpulseq`](https://github.com/nimpulseq/nimpulseq) — Pulseq sequence object and file writer
- [`PulseqSystems`](https://github.com/nimpulseq/PulseqSystems) — scanner hardware presets

## License

See `LICENSE`.
