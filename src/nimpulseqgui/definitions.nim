## Core type definitions for nimpulseqgui.
##
## Defines the ``ProtocolProperty`` tagged union, the ``MRProtocolRef``
## ordered-table container, callback type aliases used throughout the framework,
## and constructor helpers for all property variants.

import std/sequtils
export sequtils
import std/tables
export tables
import nimpulseq
export nimpulseq

type
  PropertyType* = enum
    ## Discriminant tag for ``ProtocolProperty``. Determines which fields are active.
    ptInt,        ## Integer-valued parameter with min/max/increment bounds.
    ptFloat,      ## Floating-point parameter with min/max/increment bounds.
    ptBool,       ## Boolean toggle parameter.
    ptStringList, ## String parameter chosen from a fixed allowed list.
    ptDescription ## Read-only descriptive text shown in the GUI (no editor).
  PropertyValidate* = enum
    ## Strategy used by the property editor when determining valid value ranges.
    pvDoSearch, ## Use binary search (numeric) or full search (string list) to find the valid range automatically.
    pvNoSearch  ## Accept the declared min/max without further validation search.
  ProtocolProperty* = object
    ## A single protocol parameter.
    ##
    ## This is a case object (tagged union) whose active fields are selected by ``pType``.
    ## All variants share the common fields ``unit``, ``validateStrategy``, and ``changed``.
    case pType*: PropertyType ## Active property variant.
    of ptInt:
      intVal*: int    ## Current integer value.
      intMin*: int    ## Minimum allowed integer value.
      intMax*: int    ## Maximum allowed integer value.
      intIncr*: int   ## Step size for integer increment/decrement.
    of ptFloat:
      floatVal*: float  ## Current floating-point value.
      floatMin*: float  ## Minimum allowed floating-point value.
      floatMax*: float  ## Maximum allowed floating-point value.
      floatIncr*: float ## Step size for float increment/decrement.
    of ptBool:
      boolVal*: bool  ## Current boolean value.
    of ptStringList:
      stringVal*: string        ## Currently selected string.
      stringList*: seq[string]  ## Ordered list of allowed strings.
    of ptDescription:
      description*: string  ## Descriptive text displayed in the GUI.
    unit*: string                       ## Physical unit label shown next to the value (e.g. ``"ms"``).
    validateStrategy*: PropertyValidate ## Validation search strategy for the property editor.
    changed*: bool                      ## Set to ``true`` when the value has been modified from its default.
  MRProtocolRef* = OrderedTableRef[string, ProtocolProperty]
    ## Heap-allocated, mutable ordered table mapping parameter names to ``ProtocolProperty`` values.
    ##
    ## The insertion order of entries determines the display order in the GUI.
    ## Because this is a reference type, it can be passed to callbacks and mutated in place.
  ProcValidateProtocol* = proc(opts: Opts, protocol: MRProtocolRef): bool {. closure .}
    ## Callback type that validates an ``MRProtocolRef`` against scanner hardware limits.
    ##
    ## Returns ``true`` if the protocol is valid, ``false`` otherwise.
    ## Called after every property edit and before writing the sequence.
  ProcMakeSequence* = proc(opts: Opts, protocol: MRProtocolRef): Sequence {. closure .}
    ## Callback type that builds a ``Sequence`` from scanner options and protocol parameters.
    ##
    ## Called when the user clicks *Write Sequence* (GUI) or when running headless.
  ProcGetDefaultProtocol* = proc(opts: Opts): MRProtocolRef {. closure .}
    ## Callback type that returns the default ``MRProtocolRef`` for the given scanner options.
    ##
    ## Called once at startup to populate the initial parameter values.

proc copy*(src: MRProtocolRef): MRProtocolRef =
  ## Returns a deep copy of *src*.
  ##
  ## Because ``MRProtocolRef`` is a reference type, assignment only copies the pointer.
  ## Use this proc to obtain an independent copy when validating candidate values without
  ## modifying the live protocol.
  result = new MRProtocolRef
  result[] = src[]

proc newProtocol*(): MRProtocolRef =
  ## Creates and returns a new, empty ``MRProtocolRef``.
  new(result)

proc newFloatProperty*(val, min, max, incr: float; validate: PropertyValidate = pvNoSearch; unit: string = ""): ProtocolProperty =
  ## Creates a floating-point ``ProtocolProperty``.
  ##
  ## - ``val``: initial value.
  ## - ``min`` / ``max``: allowed range.
  ## - ``incr``: step size shown in the editor.
  ## - ``validate``: ``pvDoSearch`` to auto-discover the valid range via binary search.
  ## - ``unit``: display unit label (e.g. ``"ms"``).
  ProtocolProperty(pType: ptFloat, floatVal: val, floatMin: min, floatMax: max, floatIncr: incr,
                   validateStrategy: validate, changed: false, unit: unit)

proc newIntProperty*(val, min, max, incr: int; validate: PropertyValidate = pvNoSearch; unit: string = ""): ProtocolProperty =
  ## Creates an integer ``ProtocolProperty``.
  ##
  ## - ``val``: initial value.
  ## - ``min`` / ``max``: allowed range.
  ## - ``incr``: step size shown in the editor.
  ## - ``validate``: ``pvDoSearch`` to auto-discover the valid range via binary search.
  ## - ``unit``: display unit label.
  ProtocolProperty(pType: ptInt, intVal: val, intMin: min, intMax: max, intIncr: incr,
                   validateStrategy: validate, changed: false, unit: unit)

proc newBoolProperty*(val: bool; validate: PropertyValidate = pvNoSearch): ProtocolProperty =
  ## Creates a boolean ``ProtocolProperty``.
  ##
  ## - ``val``: initial value.
  ## - ``validate``: ``pvDoSearch`` to check whether toggling the value is allowed.
  ProtocolProperty(pType: ptBool, boolVal: val, validateStrategy: validate, changed: false, unit: "")

proc newStringListProperty*(val: string; list: seq[string]; validate: PropertyValidate = pvNoSearch): ProtocolProperty =
  ## Creates a string-list ``ProtocolProperty``.
  ##
  ## - ``val``: initially selected string (must be an element of ``list``).
  ## - ``list``: ordered sequence of allowed values.
  ## - ``validate``: ``pvDoSearch`` to filter the list to only valid choices.
  ProtocolProperty(pType: ptStringList, stringVal: val, stringList: list, validateStrategy: validate, changed: false, unit: "")

proc newDescriptionProperty*(desc: string): ProtocolProperty =
  ## Creates a read-only description ``ProtocolProperty`` with the given text.
  ##
  ## Description properties are displayed as centred labels in the GUI and
  ## have no editor window.
  ProtocolProperty(pType: ptDescription, description: desc)