## Main GUI window for nimpulseqgui sequence applications.
##
## Builds the primary window containing a scrollable list of protocol property
## rows (Edit button, parameter name, current value), an output-path text box,
## and Write/Load buttons.

import propertyedit
import nimpulseq
import nigui, nigui/msgbox
import definitions
import std/strformat, std/strutils
import io

const darkBGColor = rgb(192, 192, 192)
const lightBGColor = rgb(224, 224, 224)

proc formatFloat(v: float, increment: float): string =
    if increment < 0.01:
        return &"{v:.3f}"
    if increment < 0.1:
        return &"{v:.2f}"
    return &"{v:.1f}"

# this creates a container for a property, which includes the label, the value and the edit button. It also returns a callback that can be used to update the value label when the property is changed
proc createPropertyContainer(propertyName: string, opts: Opts, prot: MRProtocolRef, validateProc: ProcValidateProtocol, parentWindow: Window, darkBG: bool): (LayoutContainer, proc()) =
    let prop = prot[propertyName]

    var propContainer = newLayoutContainer(Layout_Horizontal)
    propContainer.backgroundColor = if darkBG: darkBGColor else: lightBGColor
    propContainer.padding = 0
    propContainer.yAlign = YAlign_Center

    # edit button. Only added if it's not a description
    var editButton = newButton("Edit")
    editButton.heightMode = HeightMode_Fill

    # also the name of the property is only added if it's not a description
    var labelName = newLabel(propertyName & ": ")
    labelName.backgroundColor = if darkBG: darkBGColor else: lightBGColor
    labelName.yTextAlign = YTextAlign_Center
    labelName.widthMode = WidthMode_Expand
    labelName.xTextAlign = XTextAlign_Right
    labelName.heightMode = HeightMode_Fill

    if prop.pType != ptDescription:
        propContainer.add(editButton)
        propContainer.add(labelName)

    var labelValue = newLabel()
    labelValue.backgroundColor = if darkBG: darkBGColor else: lightBGColor
    labelValue.yTextAlign = YTextAlign_Center
    labelValue.widthMode = WidthMode_Expand
    labelValue.heightMode = HeightMode_Fill
    if prop.pType == ptDescription:
        labelValue.xTextAlign = XTextAlign_Center
        labelValue.heightMode = HeightMode_Static
        labelValue.height = editButton.height

    proc updateValue() =
        var valueString: string
        let prop = prot[propertyName]
        case prop.pType
        of ptDescription: valueString = prop.description
        of ptInt: valueString = prop.intVal.repr & " " & prop.unit
        of ptFloat: valueString = formatFloat(prop.floatVal, prop.floatIncr) & " " & prop.unit
        of ptBool: valueString = if prop.boolVal: "True" else: "False"
        of ptStringList: valueString = prop.stringVal
        labelValue.text = " " & valueString

    updateValue()

    proc editPressCallback(click: ClickEvent) =
        var win = createPropertyEditorWindow(opts, prot, propertyName, validateProc)
        win.onDispose = proc(e: WindowDisposeEvent) = updateValue()
        #win.showModalAndRefresh(parentWindow)
        
        proc resizeTimer(event: TimerEvent) =
            let height = win.height
            let width = win.width
            win.height = height+1
            win.width = width+1
            win.height = height
            win.width = width
    
        startTimer(50, resizeTimer)
        
        win.showModal(parentWindow)

    editButton.onClick = editPressCallback

    propContainer.add(labelValue)
    return (propContainer, updateValue)

proc sequenceGUI*(outputFolder: string, opts: Opts, prot: MRProtocolRef, validateProc: ProcValidateProtocol, makeSequence: ProcMakeSequence): Window {. discardable .} =
    ## Creates and returns the main sequence GUI window.
    ##
    ## The window contains one row per entry in *prot* (in insertion order), showing
    ## an *Edit* button, the parameter name, and the current value.  Below the
    ## property list there is an output-path text box, a *Write Sequence* button
    ## (validates the protocol, calls *makeSequence*, and writes the ``.seq`` file),
    ## and a *Load...* button (opens a file dialog and reads protocol parameters from
    ## an existing ``.seq`` file).
    ##
    ## The returned window is not shown automatically — call ``window.show()`` after
    ## optionally customising the title.
    var window = newWindow("Nimpulseq GUI")
    window.width = 600.scaleToDpi
    window.height = 600.scaleToDpi
    var mainContainer = newLayoutContainer(Layout_Vertical)
    var propertyPanelContainer = newLayoutContainer(Layout_Vertical)
    propertyPanelContainer.widthMode = WidthMode_Expand
    propertyPanelContainer.heightMode = HeightMode_Expand

    var darkBG = false
    var updateCallbacks: seq[proc()] = @[]
    for propName in prot.keys:
        let (propContainer, updateCallback) = createPropertyContainer(propName, opts, prot, validateProc, window, darkBG)
        propertyPanelContainer.add(propContainer)
        updateCallbacks.add(updateCallback)
        darkBG = not darkBG
    mainContainer.add(propertyPanelContainer)

    var saveContainer = newLayoutContainer(Layout_Horizontal)
    saveContainer.yAlign = YAlign_Center
    saveContainer.padding = 10

    var savePathText = newTextBox(outputFolder)
    savePathText.widthMode = WidthMode_Expand


    var saveButton = newButton("Write Sequence")
    saveButton.onClick = proc(click: ClickEvent) =
        let outputFolder = savePathText.text
        if safeValidateProtocol(opts, prot, validateProc):
            var seq: Sequence
            try:
                seq = makeSequence(opts, prot)
            except Exception as e:
                msgBox(window, "Error compiling sequence:\n" & e.msg, "Error")
                return
            let preamble = makeProtocolPreamble(prot)
            try:
                writeSeq(seq, outputFolder, preamble = preamble)
                msgBox(window, "Sequence written successfully to:\n" & outputFolder, "Success")
            except OSError as e:
                msgBox(window, "Error writing sequence to file:\n" & e.msg, "Error")
        else:
            msgBox(window, "Validation Error!\nOne or more protocol parameters are out of the allowed range. Please check your parameters and try again.", "Error")

    var loadButton = newButton("Load...")
    loadButton.onClick = proc(click: ClickEvent) =
        var fileDialog = newOpenFileDialog()
        fileDialog.title = "Select Sequence File"
        fileDialog.multiple = false
        fileDialog.run
        if fileDialog.files.len > 0:
            let selectedFile = fileDialog.files[0]
            var warnings = readProtocolFromFile(selectedFile, opts, prot, validateProc)
            if warnings.len > 0:
                msgBox(window, "Warnings while reading protocol from file:\n" & warnings.join("\n"), "Warning")
            else:
                msgBox(window, "Protocol loaded successfully from file.", "Success")
            
            # update the view
            for callback in updateCallbacks:
                callback()


    saveContainer.add(savePathText)
    saveContainer.add(saveButton)
    saveContainer.add(loadButton)
    mainContainer.add(saveContainer)

    window.add(mainContainer)
    return window

when isMainModule:
    proc validateTest(opts: Opts, protocol: MRProtocolRef): bool =
        var prop = protocol["TE"].floatVal
        if prop < 10 or prop > 100:
            return false
        if protocol["Bool"].boolVal == false:
            return false
        if protocol["String"].stringVal == "Hallo":
            return false
        return true

    proc makeSequence(opts: Opts, protocol: MRProtocolRef): Sequence =
        # Empty sequence for testing
        var seq = newSequence()
        return seq

    var teProperty = ProtocolProperty(pType: ptFloat, floatMin: 0, floatMax: 1000, floatVal: 50, floatIncr: 1, validateStrategy: pvDoSearch, changed: false, unit: "ms")
    var intProperty = ProtocolProperty(pType: ptInt, intMin: 20, intMax: 100, intVal: 50, intIncr: 1, validateStrategy: pvNoSearch, changed: false, unit: "myunit")
    var boolProperty = ProtocolProperty(pType: ptBool, boolVal: true, validateStrategy: pvNoSearch, changed: false, unit: "")
    var descProperty = ProtocolProperty(pType: ptDescription, description: "This is a description test")
    var stringProperty = ProtocolProperty(pType: ptStringList, stringVal: "Hello", stringList: @["Ciao", "Hello", "Hallo", "Geia"], validateStrategy: pvDoSearch, changed: false, unit: "")
    var prot = MRProtocolRef()
    var opts = newOpts()
    prot["TE"] = teProperty
    prot["Int"] = intProperty
    prot["Bool"] = boolProperty
    prot["Desc"] = descProperty
    prot["String"] = stringProperty
    
    app.init()
    var window = sequenceGUI("test.seq", opts, prot, validateTest, makeSequence)
    window.show()
    app.run()