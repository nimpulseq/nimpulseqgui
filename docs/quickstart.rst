Quick Start
===========

Requirements
------------

- `Nim <https://nim-lang.org/>`_ >= 2.0.0
- `nigui <https://github.com/simonkrauter/NiGui>`_ — cross-platform GUI toolkit
- `nimpulseq <https://github.com/fsantini/nimpulseq>`_ — Pulseq sequence writer
- `PulseqSystems <https://github.com/fsantini/PulseqSystems>`_ — scanner hardware presets

Installation
------------

Add nimpulseqgui to your ``.nimble`` project:

.. code-block:: nim

   requires "https://github.com/fsantini/nimpulseqgui"

Or install via nimble:

.. code-block:: bash

   nimble install https://github.com/fsantini/nimpulseqgui

Design Pattern
--------------

nimpulseqgui is a **framework**, not a standalone tool.  Users implement three
callback procs and hand them to ``makeSequenceExe``:

.. code-block:: text

   getDefaultProtocol(opts) → MRProtocolRef
        ↓  (GUI edits / CLI flags)
   validateProtocol(opts, prot) → bool
        ↓  (on Write button / headless)
   makeSequence(opts, prot) → Sequence
        ↓
   writeSeq(...) → .seq file

Minimal Example
---------------

.. code-block:: nim

   import nimpulseqgui

   proc getDefaultProtocol(opts: Opts): MRProtocolRef =
     result = newProtocol()
     result["TE"] = newFloatProperty(val = 10.0, min = 5.0, max = 100.0,
                                     incr = 1.0, unit = "ms",
                                     validate = pvDoSearch)
     result["TR"] = newFloatProperty(val = 500.0, min = 100.0, max = 5000.0,
                                     incr = 10.0, unit = "ms")

   proc validateProtocol(opts: Opts, prot: MRProtocolRef): bool =
     prot["TE"].floatVal < prot["TR"].floatVal

   proc makeSequence(opts: Opts, prot: MRProtocolRef): Sequence =
     var seqObj = newSequence(opts)
     # ... build your sequence here ...
     result = seqObj

   makeSequenceExe(getDefaultProtocol, validateProtocol, makeSequence,
                   title = "My Sequence")

Running
-------

Compile and run:

.. code-block:: bash

   nim c -o my_sequence my_sequence.nim

   # Launch GUI
   ./my_sequence 

   # Run headless (no GUI)
   ./my_sequence --no-gui

   # Pre-load protocol from a previous run
   ./my_sequence ---input=previous.seq

   # Use a scanner preset from PulseqSystems
   ./my_sequence --manufacturer="Siemens Healthcare" \
                 --model="MAGNETOM Prisma"

   # List available scanner presets
   ./my_sequence --list-manufacturers
   ./my_sequence --manufacturer="Siemens Healthcare" --list-models

Protocol Persistence
--------------------

When ``makeSequence`` calls ``writeSeq``, nimpulseqgui embeds the current
protocol parameters in the ``.seq`` file between special markers::

   [NimPulseqGUI Protocol]
   TE: 10.0
   TR: 500.0
   [NimPulseqGUI Protocol End]

The *Load...* button (GUI) or ``--input`` flag (CLI) reads these parameters
back from an existing file.
