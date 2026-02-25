## Protocol persistence — reading and writing the nimpulseqgui preamble block in Pulseq ``.seq`` files.
##
## The preamble is embedded in the ``.seq`` file between the markers
## ``[NimPulseqGUI Protocol]`` and ``[NimPulseqGUI Protocol End]``.
## Each line has the form ``key: value`` (newlines within values are escaped as ``\n``).

import definitions
import std/strformat, std/strutils
import nimpulseq
import utils

const protocolPreambleStart = "[NimPulseqGUI Protocol]"
const protocolPreambleEnd = "[NimPulseqGUI Protocol End]"

proc readProtocolFromFile*(fileName: string, opts: Opts, defaultProt: MRProtocolRef, validateProc: ProcValidateProtocol): seq[string] =
    ## Reads protocol parameters from the nimpulseqgui preamble block in *fileName*.
    ##
    ## Scans the file for the ``[NimPulseqGUI Protocol]`` marker and parses
    ## ``key: value`` lines until ``[NimPulseqGUI Protocol End]`` or ``[VERSION]`` is reached.
    ## Parsed values are applied to *defaultProt* in place only if the resulting protocol
    ## passes ``validateProc``.
    ##
    ## Returns a sequence of warning strings (empty on full success).
    ## Warnings are emitted for unrecognised keys, out-of-list string values,
    ## a missing preamble block, or a protocol that fails validation.
    # open sequence file and read lines until we find the protocol preamble. Then read the protocol parameters until we find the end of the preamble
    var f = open(fileName)
    var line: string
    var protocolFound = false
    var localProt = defaultProt.copy
    var warnings: seq[string] = @[]
    while not f.endOfFile:
        line = f.readLine()
        if line.startsWith("#"):
            line = line[1..^1].strip() # remove the initial # and the spaces around
        # if line includes [VERSION] we can stop searching, since the preamble should be before that
        if line.contains("[VERSION]"):
            break
        if line.contains(protocolPreambleStart):
            protocolFound = true
            continue
        if line.contains(protocolPreambleEnd):
            break
        if protocolFound:
            # this should be a parameter line. We can split it by ": " to get the name and value (remove the initial # and the spaces around)
            let parts = line.split(": ", maxsplit = 1)
            let varName = parts[0].strip()
            let varValue = parts[1].strip()
            if not localProt.contains(varName):
                warnings.add(&"Warning: Protocol parameter '{varName}' in file not recognized. Ignoring.")
                continue
            case localProt[varName].pType
            of ptDescription:
                localProt[varName].description = varValue.replace("\\n", "\n")
            of ptInt:
                let parsedInt = parseInt(varValue)
                localProt[varName].intVal = parsedInt
            of ptFloat:
                let parsedFloat = parseFloat(varValue)
                localProt[varName].floatVal = parsedFloat
            of ptBool:
                if varValue.toLowerAscii() == "true":
                    localProt[varName].boolVal = true
                else:
                    localProt[varName].boolVal = false
            of ptStringList:
                if localProt[varName].stringList.contains(varValue):
                    localProt[varName].stringVal = varValue
                else:
                    warnings.add(&"Warning: Value '{varValue}' for parameter '{varName}' not in allowed list. Ignoring.")
    f.close()
    if not protocolFound:
        warnings.add("Warning: No protocol preamble found in file. Using default protocol values.")
    if not safeValidateProtocol(opts, localProt, validateProc):
        warnings.add("Warning: Protocol values read from file did not pass validation. Using default protocol values.")
        return warnings
    # if we got here, the protocol is valid, so we can copy the values to the default protocol reference (since the protocol reference is mutable, we can just copy the values over)
    defaultProt[] = localProt[]
    return warnings


proc formatFloat(v: float, increment: float): string =
    if increment < 0.01:
        return &"{v:.3f}"
    if increment < 0.1:
        return &"{v:.2f}"
    return &"{v:.1f}"

proc makeProtocolPreamble*(prot: MRProtocolRef): string =
    ## Serialises *prot* to a nimpulseqgui preamble string suitable for embedding in a ``.seq`` file.
    ##
    ## The returned string starts with ``[NimPulseqGUI Protocol]``, contains one
    ## ``key: value`` line per property (in insertion order), and ends with
    ## ``[NimPulseqGUI Protocol End]``.  Newlines within description values are
    ## escaped as ``\n``.  Pass this string as the ``preamble`` argument to
    ## ``writeSeq``.
    var preambleLines: seq[string] = @[protocolPreambleStart]
    for key in prot.keys:
        let prop = prot[key]
        var line = key & ": "
        case prop.pType
        of ptDescription:
            let escapedDesc = prop.description.replace("\n", "\\n")
            line &= escapedDesc
        of ptInt: line &= $prop.intVal
        of ptFloat: line &= formatFloat(prop.floatVal, prop.floatIncr)
        of ptBool:
            if prop.boolVal:
                line &= "True"
            else:
                line &= "False"
        of ptStringList: line &= prop.stringVal
        preambleLines.add(line)
    preambleLines.add(protocolPreambleEnd)
    return preambleLines.join("\n")

