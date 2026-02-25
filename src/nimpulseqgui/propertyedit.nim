## Modal property editor windows for nimpulseqgui.
##
## Provides type-specific editor dialogs (numeric text box, checkbox, combo box)
## and the binary-search algorithm used to auto-discover valid value ranges when
## a property's ``validateStrategy`` is ``pvDoSearch``.

import nigui
import definitions
import nimpulseq
import std/math
import std/strformat
import std/strutils
import utils

const errorColor = rgb(255, 128, 128, 255)
const okColor = rgb(255, 255, 255, 255)

template addStretch(container: LayoutContainer) =
    var emptyLabel = newLabelFont()
    emptyLabel.heightMode = HeightMode_Expand
    container.add(emptyLabel)

# search the minimum or maximum in a binary search. Assume that the minimum value fails, and the maximum value passes. Ensure this in the 
# calling function.
proc binarySearch[searchMin: static bool, T](opts: Opts, protocolCopy: MRProtocolRef, propertyName: string, validateProc: ProcValidateProtocol): T =
    var lowerBound, upperBound, increment: T
    when T is int:
        lowerBound = protocolCopy[propertyName].intMin
        upperBound = protocolCopy[propertyName].intMax
        increment = protocolCopy[propertyName].intIncr
        template setValue(v: int) =
            protocolCopy[propertyName].intVal = v
        template setMin(v: int) =
            protocolCopy[propertyName].intMin = v
        template setMax(v: int) =
            protocolCopy[propertyName].intMax = v
    when T is float:
        lowerBound = protocolCopy[propertyName].floatMin
        upperBound = protocolCopy[propertyName].floatMax
        increment = protocolCopy[propertyName].floatIncr
        template setValue(v: float) =
            protocolCopy[propertyName].floatVal = v
        template setMin(v: float) =
            protocolCopy[propertyName].floatMin = v
        template setMax(v: float) =
            protocolCopy[propertyName].floatMax = v

    protocolCopy[propertyName].changed = true

    var nSteps = int(round((upperBound - lowerBound)/increment))
    if nSteps <= 1:
        when searchMin:
            # upperbound is for sure passing, when searching for the minimum, so try the lower bound
            setValue(lowerBound)
            if safeValidateProtocol(opts, protocolCopy, validateProc):
                # the lower bound is also passing, so return it
                return lowerBound
            # if the above did not pass, return the upper bound, which is for sure passing
            return upperBound
        else:
            setValue(upperBound)
            if safeValidateProtocol(opts, protocolCopy, validateProc):
                # the upper bound is also passing, so return it
                return upperBound
            return lowerBound

    # test the middle value
    var testValue = lowerBound + increment*T(int(nSteps/2))
    setValue(testValue)
    if safeValidateProtocol(opts, protocolCopy, validateProc):
        when searchMin:
            # the middle value is OK, it means that whatever is larger than this, it must pass also.
            # reduce the upper search bound 
            setMax(testValue)
        else:
            setMin(testValue)
    else:
        when searchMin:
            # the middle value is not OK, so the lower bound must be somewhere above this
            setMin(testValue)
        else:
            setMax(testValue)
    return binarySearch[searchMin, T](opts, protocolCopy, propertyName, validateProc)

proc numericEditor[T](window: Window, opts: Opts, prot: MRProtocolRef, propertyName: string, validateProc: ProcValidateProtocol): LayoutContainer =
    var editorContainer = newLayoutContainer(Layout_Vertical)
    when T is int:
        template getVal(protRef: MRProtocolRef): int =
            protRef[propertyName].intVal
        template setVal(protRef: MRProtocolRef, v: int) =
            protRef[propertyName].intVal = v
        template getMin(protRef: MRProtocolRef): int =
            protRef[propertyName].intMin
        template setMin(protRef: MRProtocolRef, v: int) =
            protRef[propertyName].intMin = v
        template getMax(protRef: MRProtocolRef): int =
            protRef[propertyName].intMax
        template setMax(protRef: MRProtocolRef, v: int) =
            protRef[propertyName].intMax = v
        template getIncrement(): int =
            prot[propertyName].intIncr
        template formatVal(v: int): string =
            v.repr
            
    when T is float:
        template getVal(protRef: MRProtocolRef): float =
            protRef[propertyName].floatVal
        template setVal(protRef: MRProtocolRef, v: float) =
            protRef[propertyName].floatVal = v
        template getMin(protRef: MRProtocolRef): float =
            protRef[propertyName].floatMin
        template setMin(protRef: MRProtocolRef, v: float) =
            protRef[propertyName].floatMin = v
        template getMax(protRef: MRProtocolRef): float =
            protRef[propertyName].floatMax
        template setMax(protRef: MRProtocolRef, v: float) =
            protRef[propertyName].floatMax = v
        template getIncrement(): float =
            prot[propertyName].floatIncr
        proc formatVal(v: float): string =
            let increment = getIncrement()
            if increment < 0.01:
                return &"{v:.3f}"
            if increment < 0.1:
                return &"{v:.2f}"
            return &"{v:.1f}"

    template parseNumber(s: string): T =
        T(s.parseFloat)

    var currentVal = getVal(prot)
    var min = getMin(prot)
    var max = getMax(prot)
    var increment = getIncrement()
    if prot[propertyName].validateStrategy == pvDoSearch:
        # use binary search to refine min and max
        var protCopy = prot.copy 
        # find minimum
        setMax(protCopy, currentVal)
        min = binarySearch[true, T](opts, protCopy, propertyName, validateProc)
        protCopy = prot.copy
        setMin(protCopy, currentVal)
        max = binarySearch[false, T](opts, protCopy, propertyName, validateProc)
    var editWidgetsContainer = newLayoutContainer(Layout_Horizontal)
    editWidgetsContainer.yAlign = YAlign_Center
    var nameLabel = newLabelFont(propertyName)
    var textEdit = newTextBox(currentVal.repr)
    var unitLabel = newLabelFont(prot[propertyName].unit)
    var validateButton = newButton("Validate")
    editWidgetsContainer.add(nameLabel)
    editWidgetsContainer.add(textEdit)
    editWidgetsContainer.add(unitLabel)
    editWidgetsContainer.add(validateButton)
    editorContainer.add(editWidgetsContainer)
    var minMaxLabel = newLabelFont("Min: " & formatVal(min) & " Max: " & formatVal(max) & "\nIncrement: " & formatVal(increment))
    minMaxLabel.widthMode = WidthMode_Fill
    minMaxLabel.xTextAlign = XTextAlign_Center
    editorContainer.add(minMaxLabel)
    var okButton = newButton("Ok")
    okButton.widthMode = WidthMode_Expand
    var cancelButton = newButton("Cancel")
    cancelButton.widthMode = WidthMode_Expand
    var buttonContainer = newLayoutContainer(Layout_Horizontal)
    buttonContainer.add(okButton)
    buttonContainer.add(cancelButton)

    addStretch(editorContainer)

    editorContainer.add(buttonContainer)

    # align value to min/max and increment
    proc alignValue(value: T): T =
        var value = value
        if value < min:
            value = min
        elif value > max:
            value = max
        else:
            # align to increment
            value = min + T(int(round(( (value-min) / increment ))))*increment
        return value


    proc validateEntry(doAlign: bool): bool {. discardable .} =
        var value: T
        try:
            value = parseNumber(textEdit.text)
        except: # entry is not a number! If we don't want to do automatic alignment, it's an error
            if doAlign:
                value = T(0)
            else:
                alert(window, "Value must be numeric!")
                textEdit.backgroundColor = errorColor
                return false

        if doAlign:
            value = alignValue(value)
            textEdit.text = formatVal(value)
        
        var localProt = prot.copy
        setVal(localProt, value)
        localProt[propertyName].changed = true
        
        if not safeValidateProtocol(opts, localProt, validateProc):
            alert(window, "Invalid value!")
            textEdit.backgroundColor = errorColor
            return false
        textEdit.backgroundColor = okColor
        return true

    # callbacks
    proc textKeyDownCallback(event: KeyboardEvent) =
        if event.key != Key_Return:
            return
        validateEntry(true)
        
    
    textEdit.onKeyDown = textKeyDownCallback

    proc validatePressCallback(click: ClickEvent) =
        validateEntry(true)

    validateButton.onClick = validatePressCallback

    proc okPressCallback(click: ClickEvent) =
        # if the entry is valid, set it in the protocol, otherwise do nothing (validateEntry already shows an error message)
        if validateEntry(false):
            let value = parseNumber(textEdit.text)
            setVal(prot, value)
            window.dispose

    okButton.onClick = okPressCallback

    proc cancelPressCallback(click: ClickEvent) =
        window.dispose
    
    cancelButton.onClick = cancelPressCallback
    return editorContainer

proc boolEditor(window: Window, opts: Opts, prot: MRProtocolRef, propertyName: string, validateProc: ProcValidateProtocol): LayoutContainer =
    var editorContainer = newLayoutContainer(Layout_Vertical)

    var checkboxContainer = newLayoutContainer(Layout_Horizontal)
    var emptyLabel1 = newLabelFont()
    emptyLabel1.widthMode = WidthMode_Expand
    var emptyLabel2 = newLabelFont()
    emptyLabel2.widthMode = WidthMode_Expand
    var propertyCheckbox = newCheckbox(propertyName)
    var currentVal = prot[propertyName].boolVal
    propertyCheckbox.checked = currentVal
    propertyCheckbox.widthMode = WidthMode_Fill
    checkboxContainer.add(emptyLabel1)
    checkboxContainer.add(propertyCheckbox)
    checkboxContainer.add(emptyLabel2)
    editorContainer.add(checkboxContainer)

    var okButton = newButton("Ok")
    okButton.widthMode = WidthMode_Expand
    var cancelButton = newButton("Cancel")
    cancelButton.widthMode = WidthMode_Expand
    var buttonContainer = newLayoutContainer(Layout_Horizontal)
    buttonContainer.add(okButton)
    buttonContainer.add(cancelButton)

    addStretch(editorContainer)

    editorContainer.add(buttonContainer)

    proc validateEntry(value: bool): bool =
        # create a copy of the protocol and test it
        var localProt = prot.copy
        localProt[propertyName].changed = true
        localProt[propertyName].boolVal = value

        return safeValidateProtocol(opts, localProt, validateProc)

    # if the property has a search strategy, check the other value to see if it's admissible
    if prot[propertyName].validateStrategy == pvDoSearch:
        if not validateEntry(not currentVal):
            propertyCheckbox.enabled = false

    proc okPressCallback(click: ClickEvent) =
        # if the entry is valid, set it in the protocol, otherwise do nothing (validateEntry already shows an error message)
        if validateEntry(propertyCheckbox.checked):
            prot[propertyName].boolVal = propertyCheckbox.checked
            window.dispose
        else:
            alert(window, "Invalid value!")
            propertyCheckbox.checked = not propertyCheckbox.checked


    okButton.onClick = okPressCallback

    proc cancelPressCallback(click: ClickEvent) =
        window.dispose
    
    cancelButton.onClick = cancelPressCallback

    return editorContainer


proc comboEditor(window: Window, opts: Opts, prot: MRProtocolRef, propertyName: string, validateProc: ProcValidateProtocol): LayoutContainer =
    var editorContainer = newLayoutContainer(Layout_Vertical)

    var comboContainer = newLayoutContainer(Layout_Horizontal)
    var nameLabel = newLabelFont(propertyName)
    nameLabel.widthMode = WidthMode_Auto
    nameLabel.heightMode = HeightMode_Fill
    nameLabel.yTextAlign = YTextAlign_Center
    var propertyCombo = newComboBox()
    propertyCombo.widthMode = WidthMode_Expand
    
    comboContainer.add(nameLabel)
    comboContainer.add(propertyCombo)
    editorContainer.add(comboContainer)

    var okButton = newButton("Ok")
    okButton.widthMode = WidthMode_Expand
    var cancelButton = newButton("Cancel")
    cancelButton.widthMode = WidthMode_Expand
    var buttonContainer = newLayoutContainer(Layout_Horizontal)
    buttonContainer.add(okButton)
    buttonContainer.add(cancelButton)

    addStretch(editorContainer)
    
    editorContainer.add(buttonContainer)

    proc validateEntry(value: string): bool =
        # create a copy of the protocol and test it
        var localProt = prot.copy
        localProt[propertyName].changed = true
        localProt[propertyName].stringVal = value

        return safeValidateProtocol(opts, localProt, validateProc)

    # if the property has a search strategy, only add the entries that are admissible
    if prot[propertyName].validateStrategy == pvDoSearch:
        var optionsSeq: seq[string]
        for option in prot[propertyName].stringList:
            if validateEntry(option):
                optionsSeq.add(option)
        propertyCombo.options = optionsSeq
    else:
        propertyCombo.options = prot[propertyName].stringList
    propertyCombo.value = prot[propertyName].stringVal


    proc okPressCallback(click: ClickEvent) =
        # if the entry is valid, set it in the protocol, otherwise do nothing (validateEntry already shows an error message)
        if validateEntry(propertyCombo.value):
            prot[propertyName].stringVal = propertyCombo.value
            window.dispose
        else:
            alert(window, "Invalid value!")


    okButton.onClick = okPressCallback

    proc cancelPressCallback(click: ClickEvent) =
        window.dispose
    
    cancelButton.onClick = cancelPressCallback

    return editorContainer

proc createPropertyEditorWindow*(opts: Opts, prot: MRProtocolRef, propertyName: string, validateProc: ProcValidateProtocol): Window {. discardable .} =
    ## Creates and returns a modal editor window for the named protocol property.
    ##
    ## The editor type is selected automatically from the property's ``pType``:
    ##
    ## - ``ptFloat`` / ``ptInt``: numeric text box with min/max/increment display and *Validate* button.
    ##   If ``validateStrategy == pvDoSearch``, binary search is used to narrow the displayed range
    ##   to the values that actually pass *validateProc*.
    ## - ``ptBool``: checkbox; the other value is tested first, and the checkbox is disabled if
    ##   toggling is not allowed.
    ## - ``ptStringList``: combo box; entries that fail validation are omitted when ``pvDoSearch``.
    ## - ``ptDescription``: no editor is opened (returns without adding a container).
    ##
    ## The window is not shown automatically — call ``window.showModal(parent)`` after this proc.
    let prop = prot[propertyName]
    var editorWindow = newWindow("Edit property " & propertyName)
    editorWindow.width = 300.scaleToDpi
    editorWindow.height = 170.scaleToDpi
    var container: LayoutContainer
    case prop.pType
    of ptInt:
        container = numericEditor[int](editorWindow, opts, prot, propertyName, validateProc)
    of ptFloat:
        container = numericEditor[float](editorWindow, opts, prot, propertyName, validateProc)
    of ptBool:
        container = boolEditor(editorWindow, opts, prot, propertyName, validateProc)
    of ptStringList:
        container = comboEditor(editorWindow, opts, prot, propertyName, validateProc)
    of ptDescription:
        discard
    editorWindow.add(container)
    return editorWindow


# Test

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

    var teProperty = ProtocolProperty(pType: ptFloat, floatMin: 0, floatMax: 1000, floatVal: 50, floatIncr: 1, validateStrategy: pvDoSearch, changed: false, unit: "ms")
    var intProperty = ProtocolProperty(pType: ptInt, intMin: 20, intMax: 100, intVal: 50, intIncr: 1, validateStrategy: pvNoSearch, changed: false, unit: "u")
    var boolProperty = ProtocolProperty(pType: ptBool, boolVal: true, validateStrategy: pvNoSearch, changed: false, unit: "")
    var stringProperty = ProtocolProperty(pType: ptStringList, stringVal: "Hello", stringList: @["Ciao", "Hello", "Hallo", "Geia"], validateStrategy: pvDoSearch, changed: false, unit: "")
    var prot = MRProtocolRef()
    var opts = newOpts()
    prot["TE"] = teProperty
    prot["Int"] = intProperty
    prot["Bool"] = boolProperty
    prot["String"] = stringProperty
    var protCopy = prot.copy
    protCopy["TE"].floatMax = prot["TE"].floatVal
    echo binarySearch[true, float](opts, protCopy, "TE", validateTest)
    protCopy = prot.copy
    protCopy["TE"].floatMin = prot["TE"].floatVal
    echo binarySearch[false, float](opts, protCopy, "TE", validateTest)
    app.init()
    var window = newWindow("Test")
    window.width = 300
    window.height = 100
    window.resizable = false
    var editorContainer = numericEditor[float](window, opts, prot, "TE", validateTest)
    #var editorContainer = boolEditor(window, opts, prot, "Bool", validateTest)
    #var editorContainer = comboEditor(window, opts, prot, "String", validateTest)


    window.add(editorContainer)
    window.show()
    app.run()