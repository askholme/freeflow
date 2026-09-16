import Foundation

enum ShortcutCoreTests {
    static func run() {
        testBareFnHoldLifecycle()
        testDefaultShortcutSpecificityOrdering()
        testRightOptionPresetIsSideSpecific()
        testExactModifierMatching()
        testReducerHonorsExactModifierMatching()
        testRepeatedKeyDownDoesNotReactivate()
        testPasteAgainFiresOnLeadingEdgeOnly()
        testBackendResetClearsActiveBindings()
        testBindingMigrationAndIdentity()
        testConflictDetection()
        testHoldSessionControllerLifecycle()
        testToggleSessionControllerLifecycle()
        testHoldToToggleSessionControllerLifecycle()
        testSwitchLanguageDisabledByDefault()
        testSwitchLanguageFiresOnLeadingEdgeOnly()
        testSwitchLanguageCollisionDetection()
        testSwitchLanguagePressedInputAccounting()
        testSwitchLanguageEventConsumption()
        testSwitchLanguageNeverMutatesDictationSession()
        testSwitchLanguageModifierOnlyBindingSideSpecificity()
        testSwitchLanguageExactModifierMatching()
        testReprocessLastRecordingDisabledByDefault()
        testReprocessLastRecordingFiresOnLeadingEdgeOnly()
        testReprocessLastRecordingNeverMutatesDictationSession()
        testReprocessLastRecordingCollisionDetection()
    }

    private static func testBareFnHoldLifecycle() {
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .disabled)
        let down = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: down.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        )

        TestSupport.expectEqual(down.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(down.consumeDecision, .consume)
        TestSupport.expectEqual(up.emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(up.consumeDecision, .consume)
    }

    private static func testDefaultShortcutSpecificityOrdering() {
        let configuration = ShortcutConfiguration(
            hold: .defaultHold,
            toggle: .defaultToggle
        )
        let commandDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: configuration
        )
        let fnDown = ShortcutMatcher.reduce(
            state: commandDown.state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let fnUp = ShortcutMatcher.reduce(
            state: fnDown.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        )

        TestSupport.expectEqual(fnDown.emittedEvents, [.toggleActivated, .holdActivated])
        TestSupport.expectEqual(fnUp.emittedEvents, [.holdDeactivated, .toggleDeactivated])
    }

    private static func testRightOptionPresetIsSideSpecific() {
        let configuration = ShortcutConfiguration(
            hold: ShortcutPreset.rightOption.binding,
            toggle: .disabled
        )
        let leftOption = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 58, isDown: true),
            configuration: configuration
        )
        let rightOption = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: configuration
        )

        TestSupport.expectEqual(leftOption.emittedEvents, [])
        TestSupport.expectEqual(rightOption.emittedEvents, [.holdActivated])
    }

    private static func testExactModifierMatching() {
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch([54], exactModifierKeyCodes: [54, 55]),
            "A generic Command binding should accept Right Command"
        )
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch([55], exactModifierKeyCodes: [54, 55]),
            "A generic Command binding should accept Left Command"
        )
        TestSupport.expect(
            !ShortcutBinding.exactModifierKeyCodesMatch([55, 56], exactModifierKeyCodes: [55]),
            "Unexpected Shift should invalidate an exact Command binding"
        )
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch(
                [55, 56],
                exactModifierKeyCodes: [55],
                permittedAdditionalExactMatchModifiers: [.shift]
            ),
            "Explicitly permitted Shift should not invalidate an exact Command binding"
        )
    }

    private static func testReducerHonorsExactModifierMatching() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [55]
        )

        let rightCommandState = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 54, isDown: true),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        ).state
        let rightCommandKey = ShortcutMatcher.reduce(
            state: rightCommandState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        )
        TestSupport.expectEqual(rightCommandKey.emittedEvents, [])

        let leftCommandState = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        ).state
        let leftCommandKey = ShortcutMatcher.reduce(
            state: leftCommandState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        )
        TestSupport.expectEqual(leftCommandKey.emittedEvents, [.holdActivated])

        let shiftedState = ShortcutMatcher.reduce(
            state: leftCommandState,
            event: .modifierChanged(keyCode: 56, isDown: true),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        ).state
        let shiftedKey = ShortcutMatcher.reduce(
            state: shiftedState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        )
        TestSupport.expectEqual(shiftedKey.emittedEvents, [])

        let permittedConfiguration = ShortcutConfiguration(
            hold: binding,
            toggle: .disabled,
            permittedAdditionalExactMatchModifiers: [.shift]
        )
        let permittedKey = ShortcutMatcher.reduce(
            state: shiftedState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: permittedConfiguration
        )
        TestSupport.expectEqual(permittedKey.emittedEvents, [.holdActivated])
    }

    private static func testRepeatedKeyDownDoesNotReactivate() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: binding, toggle: .disabled)
        let first = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: first.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: true),
            configuration: configuration
        )

        TestSupport.expectEqual(first.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(repeated.state, first.state)
        TestSupport.expectEqual(repeated.consumeDecision, .consume)
    }

    private static func testPasteAgainFiresOnLeadingEdgeOnly() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, copyAgain: binding)
        let firstDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: firstDown.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: repeated.state,
            event: .keyChanged(keyCode: 96, isDown: false, isRepeat: false),
            configuration: configuration
        )
        let secondDown = ShortcutMatcher.reduce(
            state: up.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )

        TestSupport.expectEqual(firstDown.emittedEvents, [.copyAgainTriggered])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(up.emittedEvents, [])
        TestSupport.expectEqual(secondDown.emittedEvents, [.copyAgainTriggered])
    }

    private static func testBackendResetClearsActiveBindings() {
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .defaultToggle)
        let commandDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: configuration
        )
        let fnDown = ShortcutMatcher.reduce(
            state: commandDown.state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let reset = ShortcutMatcher.reduce(
            state: fnDown.state,
            event: .backendReset,
            configuration: configuration
        )

        TestSupport.expectEqual(reset.emittedEvents, [.holdDeactivated, .toggleDeactivated])
        TestSupport.expectEqual(reset.consumeDecision, .passthrough)
        TestSupport.expect(reset.state.pressedKeyCodes.isEmpty, "Backend reset should clear pressed keys")
        TestSupport.expect(reset.state.pressedModifierKeyCodes.isEmpty, "Backend reset should clear modifiers")
        TestSupport.expect(!reset.state.holdIsActive && !reset.state.toggleIsActive, "Backend reset should clear active bindings")
    }

    private static func testBindingMigrationAndIdentity() {
        let stored = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [999, 61]
        )
        let normalized = stored.normalizedForStorageMigration()
        TestSupport.expectEqual(normalized.exactModifierKeyCodes, [61])
        TestSupport.expectEqual(normalized.modifiers, [.option])

        let first = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command, .option],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [55, 58]
        )
        let second = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.option, .command],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [58, 55]
        )
        TestSupport.expectEqual(first.id, second.id)
    }

    private static func testConflictDetection() {
        let first = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let same = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let different = ShortcutBinding(
            keyCode: 97,
            keyDisplay: "F6",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )

        TestSupport.expect(first.conflicts(with: same), "Equivalent bindings should conflict")
        TestSupport.expect(same.conflicts(with: first), "Conflict detection should be symmetric")
        TestSupport.expect(!first.conflicts(with: different), "Different primary keys should not conflict")
        TestSupport.expect(!first.conflicts(with: .disabled), "Disabled bindings should not conflict")
    }

    private static func testHoldSessionControllerLifecycle() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: true), nil)
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        TestSupport.expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), .stop)
        TestSupport.expectEqual(controller.activeMode, nil)
    }

    private static func testToggleSessionControllerLifecycle() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .start(.toggle))
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.handle(event: .toggleDeactivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.toggleStopArmed, true)
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .stop)
        TestSupport.expectEqual(controller.activeMode, nil)
    }

    private static func testHoldToToggleSessionControllerLifecycle() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .switchedToToggle)
        TestSupport.expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.activeMode, .toggle)
        TestSupport.expectEqual(controller.handle(event: .copyAgainTriggered, isTranscribing: false), nil)
        controller.beginManual(mode: .hold)
        TestSupport.expectEqual(controller.activeMode, .hold)
        controller.forceToggleMode()
        TestSupport.expectEqual(controller.activeMode, .toggle)
        controller.reset()
        TestSupport.expectEqual(controller.activeMode, nil)
        TestSupport.expectEqual(controller.toggleStopArmed, false)
    }

    // MARK: - Switch Language

    private static func testSwitchLanguageDisabledByDefault() {
        TestSupport.expect(
            ShortcutConfiguration.disabled.switchLanguage.isDisabled,
            "The shared disabled configuration must keep Switch Language disabled"
        )
        TestSupport.expect(
            ShortcutConfiguration(hold: .defaultHold, toggle: .defaultToggle).switchLanguage.isDisabled,
            "Switch Language must default to disabled when a caller omits it, matching Paste Again"
        )
    }

    private static func testSwitchLanguageFiresOnLeadingEdgeOnly() {
        let binding = ShortcutBinding(
            keyCode: 97,
            keyDisplay: "F6",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, switchLanguage: binding)
        let firstDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 97, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: firstDown.state,
            event: .keyChanged(keyCode: 97, isDown: true, isRepeat: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: repeated.state,
            event: .keyChanged(keyCode: 97, isDown: false, isRepeat: false),
            configuration: configuration
        )
        let secondDown = ShortcutMatcher.reduce(
            state: up.state,
            event: .keyChanged(keyCode: 97, isDown: true, isRepeat: false),
            configuration: configuration
        )

        TestSupport.expectEqual(firstDown.emittedEvents, [.switchLanguageTriggered])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(up.emittedEvents, [])
        TestSupport.expectEqual(secondDown.emittedEvents, [.switchLanguageTriggered])
    }

    private static func testSwitchLanguageCollisionDetection() {
        let switchLanguage = ShortcutBinding(
            keyCode: 97,
            keyDisplay: "F6",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let sameKeyAndModifiers = ShortcutBinding(
            keyCode: 97,
            keyDisplay: "F6",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let differentKey = ShortcutBinding(
            keyCode: 98,
            keyDisplay: "F7",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )

        TestSupport.expect(
            switchLanguage.conflicts(with: sameKeyAndModifiers),
            "Switch Language must conflict with an equivalent hold/toggle/copyAgain-style binding"
        )
        TestSupport.expect(
            sameKeyAndModifiers.conflicts(with: switchLanguage),
            "Conflict detection against Switch Language must be symmetric"
        )
        TestSupport.expect(
            !switchLanguage.conflicts(with: differentKey),
            "Switch Language must not conflict with a binding on a different key"
        )
        TestSupport.expect(
            !switchLanguage.conflicts(with: .disabled),
            "A disabled binding must never conflict with Switch Language"
        )
        TestSupport.expect(
            !ShortcutBinding.disabled.conflicts(with: switchLanguage),
            "Switch Language must never conflict with a disabled binding (symmetric)"
        )

        // Prove Switch Language sits in the same conflict-detection
        // universe as the other three roles, not just against an
        // anonymous binding: assign the identical key+modifiers to
        // every role of a real `ShortcutConfiguration` (the same struct
        // `AppState.activeShortcutConfiguration`/`setShortcut` build
        // from `hold`/`toggle`/`copyAgain`/`switchLanguage`) and confirm
        // `.switchLanguage` conflicts, in both directions, against each
        // of `.hold`, `.toggle`, and `.copyAgain` individually.
        let sharedKeyAndModifiers = ShortcutBinding(
            keyCode: 99,
            keyDisplay: "F8",
            modifiers: [.option],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(
            hold: sharedKeyAndModifiers,
            toggle: sharedKeyAndModifiers,
            copyAgain: sharedKeyAndModifiers,
            switchLanguage: sharedKeyAndModifiers
        )

        TestSupport.expect(
            configuration.switchLanguage.conflicts(with: configuration.hold),
            "Switch Language must conflict with an equivalent Hold to Talk binding"
        )
        TestSupport.expect(
            configuration.hold.conflicts(with: configuration.switchLanguage),
            "Hold to Talk vs Switch Language conflict detection must be symmetric"
        )
        TestSupport.expect(
            configuration.switchLanguage.conflicts(with: configuration.toggle),
            "Switch Language must conflict with an equivalent Tap to Toggle binding"
        )
        TestSupport.expect(
            configuration.toggle.conflicts(with: configuration.switchLanguage),
            "Tap to Toggle vs Switch Language conflict detection must be symmetric"
        )
        TestSupport.expect(
            configuration.switchLanguage.conflicts(with: configuration.copyAgain),
            "Switch Language must conflict with an equivalent Paste Again binding"
        )
        TestSupport.expect(
            configuration.copyAgain.conflicts(with: configuration.switchLanguage),
            "Paste Again vs Switch Language conflict detection must be symmetric"
        )
    }

    private static func testSwitchLanguagePressedInputAccounting() {
        let binding = ShortcutBinding(
            keyCode: 97,
            keyDisplay: "F6",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, switchLanguage: binding)

        var state = ShortcutInputState()
        TestSupport.expect(
            !state.hasPressedShortcutInputs(configuration: configuration),
            "No inputs pressed yet must report no pressed shortcut inputs"
        )

        state.pressedKeyCodes.insert(97)
        TestSupport.expect(
            state.hasPressedShortcutInputs(configuration: configuration),
            "Holding the Switch Language key must count as a pressed shortcut input"
        )
    }

    private static func testSwitchLanguageEventConsumption() {
        let binding = ShortcutBinding(
            keyCode: 97,
            keyDisplay: "F6",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, switchLanguage: binding)

        let down = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 97, isDown: true, isRepeat: false),
            configuration: configuration
        )
        TestSupport.expectEqual(down.consumeDecision, .consume)

        let unrelatedKey = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 55, isDown: true, isRepeat: false),
            configuration: configuration
        )
        TestSupport.expectEqual(unrelatedKey.emittedEvents, [])
        TestSupport.expectEqual(unrelatedKey.consumeDecision, .passthrough)
    }

    /// The matched `.switchLanguageTriggered` event must never reach the
    /// dictation session controller in a way that starts, stops, or
    /// otherwise mutates recording state — regardless of whether the
    /// controller is idle, mid-hold, or mid-toggle, and regardless of
    /// `isTranscribing`. Mirrors the same isolation contract already
    /// covered for `.copyAgainTriggered`.
    private static func testSwitchLanguageNeverMutatesDictationSession() {
        let idleController = DictationShortcutSessionController()
        TestSupport.expectEqual(
            idleController.handle(event: .switchLanguageTriggered, isTranscribing: false),
            nil
        )
        TestSupport.expectEqual(idleController.activeMode, nil)

        let idleWhileTranscribing = DictationShortcutSessionController()
        TestSupport.expectEqual(
            idleWhileTranscribing.handle(event: .switchLanguageTriggered, isTranscribing: true),
            nil
        )
        TestSupport.expectEqual(idleWhileTranscribing.activeMode, nil)

        let holdController = DictationShortcutSessionController()
        TestSupport.expectEqual(holdController.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        TestSupport.expectEqual(
            holdController.handle(event: .switchLanguageTriggered, isTranscribing: false),
            nil
        )
        TestSupport.expectEqual(holdController.activeMode, .hold)

        let toggleController = DictationShortcutSessionController()
        TestSupport.expectEqual(toggleController.handle(event: .toggleActivated, isTranscribing: false), .start(.toggle))
        TestSupport.expectEqual(
            toggleController.handle(event: .switchLanguageTriggered, isTranscribing: false),
            nil
        )
        TestSupport.expectEqual(toggleController.activeMode, .toggle)
    }

    /// Modifier-only (`.modifierKey`-kind) Switch Language bindings must
    /// be side-specific like the existing `ShortcutPreset.rightOption`
    /// hold binding (`testRightOptionPresetIsSideSpecific`), must fire
    /// the one-shot `.switchLanguageTriggered` event and consume the
    /// matching side's modifier event, and must be reflected correctly
    /// by `hasPressedShortcutInputs` for pressed-input accounting.
    private static func testSwitchLanguageModifierOnlyBindingSideSpecificity() {
        let configuration = ShortcutConfiguration(
            hold: .disabled,
            toggle: .disabled,
            switchLanguage: ShortcutPreset.rightOption.binding
        )

        let leftOption = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 58, isDown: true),
            configuration: configuration
        )
        let rightOption = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: configuration
        )

        TestSupport.expectEqual(leftOption.emittedEvents, [])
        TestSupport.expectEqual(leftOption.consumeDecision, .passthrough)
        TestSupport.expectEqual(rightOption.emittedEvents, [.switchLanguageTriggered])
        TestSupport.expectEqual(rightOption.consumeDecision, .consume)

        TestSupport.expect(
            !leftOption.state.hasPressedShortcutInputs(configuration: configuration),
            "Holding the non-matching Left Option modifier must not count as a pressed Switch Language input"
        )
        TestSupport.expect(
            rightOption.state.hasPressedShortcutInputs(configuration: configuration),
            "Holding the exact Right Option modifier must count as a pressed Switch Language input"
        )

        // Leading-edge only: releasing and re-pressing Right Option must
        // retrigger exactly once each time, never on repeated down state.
        let rightOptionStillDown = ShortcutMatcher.reduce(
            state: rightOption.state,
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: configuration
        )
        TestSupport.expectEqual(rightOptionStillDown.emittedEvents, [])

        let rightOptionUp = ShortcutMatcher.reduce(
            state: rightOptionStillDown.state,
            event: .modifierChanged(keyCode: 61, isDown: false),
            configuration: configuration
        )
        TestSupport.expectEqual(rightOptionUp.emittedEvents, [])
        TestSupport.expect(
            !rightOptionUp.state.hasPressedShortcutInputs(configuration: configuration),
            "Releasing Right Option must clear the pressed Switch Language input"
        )

        let rightOptionDownAgain = ShortcutMatcher.reduce(
            state: rightOptionUp.state,
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: configuration
        )
        TestSupport.expectEqual(rightOptionDownAgain.emittedEvents, [.switchLanguageTriggered])
    }

    /// Exact-modifier-match Switch Language bindings must honor the same
    /// left/right-specific and `permittedAdditionalExactMatchModifiers`
    /// rules already covered for hold in
    /// `testReducerHonorsExactModifierMatching`, including pressed-input
    /// accounting and event consumption for the matching case.
    private static func testSwitchLanguageExactModifierMatching() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [55]
        )
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, switchLanguage: binding)

        // Pressed-input accounting on modifier state alone (before the
        // Switch Language key itself is ever pressed) exercises
        // `referencesPressedModifiers`'s exact-match branch directly:
        // only the exact left-Command modifier code should reference
        // this binding, not right Command. (Once the bound key itself
        // is physically down, `hasPressedShortcutInputs` reports true
        // regardless of modifiers — it accounts for the raw key
        // reference, not full-binding activation — so that check
        // belongs here, on modifier-only state, not after a key press.)
        let rightCommandModifierOnly = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 54, isDown: true),
            configuration: configuration
        ).state
        TestSupport.expect(
            !rightCommandModifierOnly.hasPressedShortcutInputs(configuration: configuration),
            "Right Command alone does not reference an exact left-Command Switch Language binding"
        )

        let leftCommandModifierOnly = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: configuration
        ).state
        TestSupport.expect(
            leftCommandModifierOnly.hasPressedShortcutInputs(configuration: configuration),
            "The exact left-Command modifier alone must reference the Switch Language binding"
        )

        let rightCommandState = rightCommandModifierOnly
        let rightCommandKey = ShortcutMatcher.reduce(
            state: rightCommandState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        TestSupport.expectEqual(rightCommandKey.emittedEvents, [])
        TestSupport.expectEqual(rightCommandKey.consumeDecision, .passthrough)

        let leftCommandState = leftCommandModifierOnly
        let leftCommandKey = ShortcutMatcher.reduce(
            state: leftCommandState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        TestSupport.expectEqual(leftCommandKey.emittedEvents, [.switchLanguageTriggered])
        TestSupport.expectEqual(leftCommandKey.consumeDecision, .consume)

        let shiftedState = ShortcutMatcher.reduce(
            state: leftCommandState,
            event: .modifierChanged(keyCode: 56, isDown: true),
            configuration: configuration
        ).state
        let shiftedKey = ShortcutMatcher.reduce(
            state: shiftedState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        TestSupport.expectEqual(shiftedKey.emittedEvents, [])

        let permittedConfiguration = ShortcutConfiguration(
            hold: .disabled,
            toggle: .disabled,
            switchLanguage: binding,
            permittedAdditionalExactMatchModifiers: [.shift]
        )
        let permittedKey = ShortcutMatcher.reduce(
            state: shiftedState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: permittedConfiguration
        )
        TestSupport.expectEqual(permittedKey.emittedEvents, [.switchLanguageTriggered])
    }

    private static func testReprocessLastRecordingDisabledByDefault() {
        TestSupport.expect(
            ShortcutConfiguration.disabled.reprocessLastRecording.isDisabled,
            "The shared disabled configuration must keep Re-run Last Recording disabled"
        )
        TestSupport.expect(
            ShortcutConfiguration(hold: .defaultHold, toggle: .defaultToggle).reprocessLastRecording.isDisabled,
            "Re-run Last Recording must default to disabled when a caller omits it, matching Switch Language"
        )
    }

    private static func testReprocessLastRecordingFiresOnLeadingEdgeOnly() {
        let binding = ShortcutBinding(
            keyCode: 98,
            keyDisplay: "F7",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, reprocessLastRecording: binding)
        let firstDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 98, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: firstDown.state,
            event: .keyChanged(keyCode: 98, isDown: true, isRepeat: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: repeated.state,
            event: .keyChanged(keyCode: 98, isDown: false, isRepeat: false),
            configuration: configuration
        )
        let secondDown = ShortcutMatcher.reduce(
            state: up.state,
            event: .keyChanged(keyCode: 98, isDown: true, isRepeat: false),
            configuration: configuration
        )

        TestSupport.expectEqual(firstDown.emittedEvents, [.reprocessLastRecordingTriggered])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(up.emittedEvents, [])
        TestSupport.expectEqual(secondDown.emittedEvents, [.reprocessLastRecordingTriggered])
    }

    /// The matched `.reprocessLastRecordingTriggered` event must never
    /// reach the dictation session controller as a start/stop/mode
    /// action, mirroring `testSwitchLanguageNeverMutatesDictationSession`.
    private static func testReprocessLastRecordingNeverMutatesDictationSession() {
        let idleController = DictationShortcutSessionController()
        TestSupport.expectEqual(
            idleController.handle(event: .reprocessLastRecordingTriggered, isTranscribing: false),
            nil
        )

        let idleWhileTranscribing = DictationShortcutSessionController()
        TestSupport.expectEqual(
            idleWhileTranscribing.handle(event: .reprocessLastRecordingTriggered, isTranscribing: true),
            nil
        )

        let holdController = DictationShortcutSessionController()
        _ = holdController.handle(event: .holdActivated, isTranscribing: false)
        TestSupport.expectEqual(
            holdController.handle(event: .reprocessLastRecordingTriggered, isTranscribing: false),
            nil
        )
        TestSupport.expectEqual(holdController.activeMode, .hold)

        let toggleController = DictationShortcutSessionController()
        _ = toggleController.handle(event: .toggleActivated, isTranscribing: false)
        TestSupport.expectEqual(
            toggleController.handle(event: .reprocessLastRecordingTriggered, isTranscribing: false),
            nil
        )
        TestSupport.expectEqual(toggleController.activeMode, .toggle)
    }

    private static func testReprocessLastRecordingCollisionDetection() {
        let sharedKeyAndModifiers = ShortcutBinding(
            keyCode: 100,
            keyDisplay: "F9",
            modifiers: [.control],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(
            hold: sharedKeyAndModifiers,
            toggle: sharedKeyAndModifiers,
            copyAgain: sharedKeyAndModifiers,
            switchLanguage: sharedKeyAndModifiers,
            reprocessLastRecording: sharedKeyAndModifiers
        )

        TestSupport.expect(
            configuration.reprocessLastRecording.conflicts(with: configuration.hold),
            "Re-run Last Recording must conflict with an equivalent Hold to Talk binding"
        )
        TestSupport.expect(
            configuration.hold.conflicts(with: configuration.reprocessLastRecording),
            "Hold to Talk vs Re-run Last Recording conflict detection must be symmetric"
        )
        TestSupport.expect(
            configuration.reprocessLastRecording.conflicts(with: configuration.switchLanguage),
            "Re-run Last Recording must conflict with an equivalent Switch Language binding"
        )
        TestSupport.expect(
            configuration.switchLanguage.conflicts(with: configuration.reprocessLastRecording),
            "Switch Language vs Re-run Last Recording conflict detection must be symmetric"
        )
        TestSupport.expect(
            !ShortcutBinding.disabled.conflicts(with: configuration.reprocessLastRecording),
            "Re-run Last Recording must never conflict with a disabled binding"
        )
    }
}
