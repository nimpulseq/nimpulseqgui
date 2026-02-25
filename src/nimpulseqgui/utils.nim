import definitions
import nigui

var globalFontSize*: int = 14

proc safeValidateProtocol*(opts: Opts, protocol: MRProtocolRef, validateProc: ProcValidateProtocol): bool =
  ## Calls *validateProc* and returns its result, catching any exception.
  ##
  ## If *validateProc* raises an exception, the error message is printed and
  ## ``false`` is returned so the GUI can report an invalid state instead of crashing.
  var isValid: bool
  try:
      isValid = validateProc(opts, protocol)
  except Exception as e:
      echo "Error during protocol validation: ", e.msg
      return false
  return isValid

proc newLabelFont*(text: string = ""): Label =
  ## Creates a new ``Label`` with the global font size.
  let lbl = newLabel(text)
  lbl.fontSize = globalFontSize.float
  result = lbl