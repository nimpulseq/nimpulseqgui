## CLI entry point for nimpulseqgui sequence applications.
##
## Parses command-line arguments, resolves scanner hardware specifications
## (optionally from the PulseqSystems database), constructs an ``Opts`` record,
## and dispatches to either the interactive GUI or a headless write mode.

import definitions
import sequencegui
import std/parseopt
import pulseqsystems
import nimpulseq
import std/os
import std/strformat, std/strutils
import nigui
import io
import utils

proc printHelp() =
    let name = getAppFilename().extractFilename()
    echo &"Usage: {name} [options]"
    echo "Options:"
    echo "  -o, --output=<file>       Default output file for generated sequence"
    echo "  -i, --input=<file>        Input file to pre-load protocol parameters (e.g. from a previous run) (optional)"
    echo "  --manufacturer=<name>     Scanner manufacturer (e.g. Siemens Healthcare)"
    echo "  --model=<name>            Scanner model (e.g. MAGNETOM Prisma)"
    echo "  --gradient=<name>         Gradient model (optional, defaults to standard gradient specs for the given manufacturer/model)"
    echo "  --maxGrad=<value>        Maximum gradient amplitude in mT/m or Hz/m (optional, overrides system specs)"
    echo "  --maxSlew=<value>        Maximum slew rate in T/m/s or Hz/m/s (optional, overrides system specs)"
    echo "  --riseTime=<value>       Gradient rise time in seconds (optional, overrides system specs)"
    echo "  --rfDeadTime=<value>     RF dead time in seconds (optional, overrides system specs)"
    echo "  --rfRingdownTime=<value> RF ringdown time in seconds (optional, overrides system specs)"
    echo "  --adcDeadTime=<value>      ADC dead time in seconds (optional, overrides system specs)"
    echo "  --adcRasterTime=<value>    ADC raster time in seconds (optional, overrides system specs)"
    echo "  --rfRasterTime=<value>     RF raster time in seconds (optional, overrides system specs)"
    echo "  --gradRasterTime=<value>   Gradient raster time in seconds (optional, overrides system specs)"
    echo "  --blockDurationRaster=<value> Block duration raster time in seconds (optional, overrides system specs)"
    echo "  --adcSamplesLimit=<value>          ADC samples limit (optional, overrides system specs)"
    echo "  --adcSamplesDivisor=<value>         ADC samples divisor (optional, overrides system specs)"
    echo "  --gamma=<value>                    Gyromagnetic ratio in Hz/T (optional, overrides system specs)"
    echo "  --B0=<value>                       Main magnetic field strength in T (optional, overrides system specs)"
    echo "  --scaleGradients=<value>           Scaling factor for gradient amplitudes (optional, only used if manufacturer/model are provided)"
    echo "  --scaleSlewRate=<value>            Scaling factor for slew rate (optional, only used if manufacturer/model are provided)"
    echo "  --gradUnit=<unit>                  Unit for gradient amplitude (mT/m or Hz/m, optional, defaults to Hz/m)"
    echo "  --slewUnit=<unit>                  Unit for slew rate (T/m/s or Hz/m/s, optional, defaults to Hz/m/s)"
    echo "  --no-gui                           Write the sequence to the output file without launching the GUI"
    echo "  -h, --help                         Show this help message and exit"
    echo "  --list-manufacturers               List available manufacturers and models"
    echo "  --list-models                      List available models for a given manufacturer (in conjunction with --manufacturer)"
    echo ""
    echo "All flags are optional except for --output. If values are not specified, the pulseq default values are taken."
    echo "For manufacturer/model specifications, see https://github.com/nimpulseq/PulseqSystems/"

template assignDefault(field: float64) =
    if `field` < 0.0: `field` = opts.`field`

template assignDefault(field: int) =
    if `field` < 0: `field` = opts.`field`

template f(str: string): float64 =
    float64(str.parseFloat)

proc printManufacturers() =
    echo "Available manufacturers:"
    echo ""
    let manufacturers = listManufacturers()
    echo manufacturers.join("\n")

proc printModels(manufacturer: string) =
    echo &"Available models for manufacturer '{manufacturer}':"
    echo ""
    let models = listModels(manufacturer)
    for model in models:
        echo model
        let gradients = listGradients(manufacturer, model)
        for gradient in gradients:
            echo &"    {gradient}"

proc makeSequenceExe*(getDefaultProtocol: ProcGetDefaultProtocol,
                     validateProtocol: ProcValidateProtocol,
                     makeSequence: ProcMakeSequence,
                     title: string = "") =
    ## Application entry point for nimpulseqgui-based sequence executables.
    ##
    ## Call this proc as the body of your ``main`` (or at the top level of your
    ## script) with three user-supplied callbacks:
    ##
    ## - ``getDefaultProtocol`` — returns the default ``MRProtocolRef`` for the given ``Opts``.
    ## - ``validateProtocol`` — returns ``true`` when the current protocol is valid.
    ## - ``makeSequence`` — builds and returns a ``Sequence`` from the current protocol.
    ##
    ## The optional ``title`` parameter sets the GUI window title.
    ##
    ## Supported command-line flags (parsed automatically):
    ##
    ## - ``--output / -o`` : output ``.seq`` file path.
    ## - ``--input / -i``: load protocol parameters from an existing ``.seq`` file.
    ## - ``--manufacturer``, ``--model``, ``--gradient``: select a scanner preset from PulseqSystems.
    ## - ``--maxGrad``, ``--maxSlew``, ``--riseTime``: override gradient hardware limits.
    ## - ``--rfDeadTime``, ``--rfRingdownTime``, ``--adcDeadTime``: override timing dead times.
    ## - ``--adcRasterTime``, ``--rfRasterTime``, ``--gradRasterTime``, ``--blockDurationRaster``: raster overrides.
    ## - ``--adcSamplesLimit``, ``--adcSamplesDivisor``: ADC constraint overrides.
    ## - ``--gamma``, ``--B0``: physical constants overrides.
    ## - ``--scaleGradients``, ``--scaleSlewRate``: scaling factors applied to preset specs.
    ## - ``--gradUnit``, ``--slewUnit``: units for gradient and slew-rate values.
    ## - ``--no-gui``: write the sequence directly without launching the GUI.
    ## - ``--list-manufacturers``, ``--list-models``: list available PulseqSystems presets and exit.
    ## - ``--fontSize`` : set the font size for the GUI (optional, for hi-dpi screens, defaults to 14)
    ## - ``--help / -h``: print help and exit.
    var prot: MRProtocolRef
    var defaultOutput: string = "out.seq"
    var inputProtocolFile: string = ""
    var manufacturer, model, gradient: string = ""
    var maxGrad, maxSlew, riseTime, rfDeadTime, rfRingdownTime, adcDeadTime, adcRasterTime, rfRasterTime, gradRasterTime, blockDurationRaster, gamma, B0: float64 = -1
    var adcSamplesLimit, adcSamplesDivisor: int = -1
    var gradUnit = "Hz/m"
    var slewUnit = "Hz/m/s"
    var scaleGradients, scaleSlewRate: float64 = 1.0
    var launchGUI = true
    var doListModels = false

    for kind, key, val in getopt():
        case kind
        of cmdArgument:
            discard
        of cmdLongOption, cmdShortOption:
            case key
            of "h", "help":
                printHelp()
                quit(0)
            of "output", "o":
                defaultOutput = val
            of "manufacturer":
                echo "manufacturer: ", val
                manufacturer = val
            of "model":
                echo "model: ", val
                model = val
            of "gradient":
                gradient = val
            of "maxGrad":
                maxGrad = f(val)
            of "maxSlew":
                maxSlew = f(val)
            of "riseTime":
                riseTime = f(val)
            of "rfDeadTime":
                rfDeadTime = f(val)
            of "rfRingdownTime":
                rfRingdownTime = f(val)
            of "adcDeadTime":
                adcDeadTime = f(val)
            of "adcRasterTime":
                adcRasterTime = f(val)
            of "rfRasterTime":
                rfRasterTime = f(val)
            of "gradRasterTime":
                gradRasterTime = f(val)
            of "blockDurationRaster":
                blockDurationRaster = f(val)
            of "adcSamplesLimit":
                adcSamplesLimit = val.parseInt()
            of "adcSamplesDivisor":
                adcSamplesDivisor = val.parseInt()
            of "gamma":
                gamma = f(val)
            of "B0":
                B0 = f(val)
            of "scaleGradients":
                scaleGradients = f(val)
            of "scaleSlewRate":
                scaleSlewRate = f(val)
            of "gradUnit":
                gradUnit = val
            of "slewUnit":
                slewUnit = val
            of "no-gui":
                launchGUI = false
            of "input", "i":
                inputProtocolFile = val
            of "list-manufacturers":
                printManufacturers()
                quit(0)
            of "list-models":
                doListModels = true
            of "fontSize":
                globalFontSize = val.parseInt()
            else:
                echo "Unknown option: ", key
                printHelp()
                quit(1)
        of cmdEnd:
            discard

    if doListModels:
        if manufacturer == "":
            echo "To list models, please provide a manufacturer using the --manufacturer flag."
            quit(1)
        printModels(manufacturer)
        quit(0)

    
    # if manufacturer and model are provided, we can try to get system specs and fill in any missing options.
    # Explicit options on the command line take precedence over system specs, which take precedence over defaults.

    if (manufacturer == "") xor (model == ""):
        echo "Both manufacturer and model must be provided to get system specs."
        printHelp()
        quit(1)

    if manufacturer != "" and model != "":
        var systemSpecs = getPulseqSpecs(manufacturer, model, gradient, scaleGradients, scaleSlewRate)
        if B0 < 0.0:
            B0 = systemSpecs.B0
        if maxGrad < 0.0:
            maxGrad = systemSpecs.maxGrad
            gradUnit = systemSpecs.gradUnit
        if maxSlew < 0.0:
            maxSlew = systemSpecs.maxSlew
            slewUnit = systemSpecs.slewUnit
    
    var opts = newOpts() # get default options
    # assign defaults for any options that were not set by the user or filled in by system specs
    assignDefault(maxGrad)
    assignDefault(maxSlew)
    assignDefault(riseTime)
    assignDefault(rfDeadTime)
    assignDefault(rfRingdownTime)
    assignDefault(adcDeadTime)
    assignDefault(adcRasterTime)
    assignDefault(rfRasterTime)
    assignDefault(gradRasterTime)
    assignDefault(blockDurationRaster)
    assignDefault(adcSamplesLimit)
    assignDefault(adcSamplesDivisor)
    assignDefault(gamma)
    assignDefault(B0)

    prot = getDefaultProtocol(opts)
    if not safeValidateProtocol(opts, prot, validateProtocol):
        echo "FATAL ERROR:"
        echo "     The default protocol is not valid with the provided system specifications!"
        quit(1)
    
    if inputProtocolFile != "":
        var warnings = readProtocolFromFile(inputProtocolFile, opts, prot, validateProtocol)
        for warning in warnings:
            echo warning
    
    if launchGUI:
        app.init()
        var window = sequenceGUI(defaultOutput, opts, prot, validateProtocol, makeSequence)
        if title != "":
            window.title = title
        window.show()
        
        # the following is a trick to allow correct sizing of the containers under windows
        proc resizeTimer(event: TimerEvent) =
            let height = window.height
            window.height = height+1
            window.height = height
        
        startTimer(100, resizeTimer)
        app.run()
    else:
        let seq = makeSequence(opts, prot)
        let preamble = makeProtocolPreamble(prot)
        write_seq(seq, defaultOutput, preamble=preamble)
    