import XCTest

/// The iPhone app driven by real touches in the Simulator, against the hub on this Mac. Nothing here sends an order.
/// Run: xcodebuild test -project Chums.xcodeproj -scheme Chums -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
/// With TEST_RUNNER_SHOTS_DIR=<folder>, each test leaves screenshots there; with TEST_RUNNER_VIEWER_ID=<artifact id>,
/// the viewer test opens that picture.
final class ChumsPhoneUITests: XCTestCase {
    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ args: [String] = []) {
        app.launchArguments = ["-agent", "ray"] + args
        app.launch()
    }
    private func shot(_ name: String) {
        guard let dir = env["SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func gone(_ e: XCUIElement, _ seconds: Double = 4) -> Bool {
        let p = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: seconds) == .completed
    }

    func testTheGearOpensTheAppSettings() {
        launch()
        app.buttons["Settings"].firstMatch.tap()
        XCTAssert(element("Read replies aloud").waitForExistence(timeout: 5), "the app's settings show")
        XCTAssert(app.staticTexts["Answers in"].exists)
        sleep(2); shot("settings")
        app.swipeDown(velocity: .fast)
        XCTAssert(gone(element("Read replies aloud")), "dragged down, the card goes away")
    }

    func testATapOutsideThePutsTheKeyboardAway() {
        launch()
        let field = element("message")
        XCTAssert(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssert(app.keyboards.firstMatch.waitForExistence(timeout: 4), "typing shows the keyboard")
        shot("keyboard")
        element("state-lane").tap()                       // beside the character: the conversation, never a photo
        XCTAssert(gone(app.keyboards.firstMatch), "a tap on the conversation puts it away")
    }

    func testTheConversationStaysAtTheBottomAfterTheKeyboard() {
        launch(["-demoConversation", "24"])          // long enough to scroll, whatever the hub has
        let last = element("last-line"), field = element("message"), mic = element("mic")
        XCTAssert(last.waitForExistence(timeout: 6) && field.exists && mic.exists)
        sleep(2)
        // the gap between the newest line and the box (the mic sits at a fixed place in it)
        let gap = { mic.frame.minY - last.frame.maxY }
        let gap0 = gap()
        shot("kb-0-rest")
        field.tap()
        XCTAssert(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        sleep(1)
        let gapUp = gap()
        shot("kb-1-up")
        element("state-lane").tap()
        XCTAssert(gone(app.keyboards.firstMatch))
        sleep(1)
        let gap1 = gap()
        shot("kb-2-down")
        XCTAssert(abs(gapUp - gap0) < 6, "with the keyboard up, the newest line still sits on the box (\(gap0) → \(gapUp))")
        XCTAssert(abs(gap1 - gap0) < 6, "after the keyboard, the newest line is back on the box (\(gap0) → \(gap1))")
    }

    func testAHoldWithoutADragLeavesNothingLifted() {
        launch()
        app.buttons["Agents"].tap()
        let row = element("agent-noodle")
        XCTAssert(row.waitForExistence(timeout: 4))
        row.press(forDuration: 1.0)                               // lifted, then let go where it is
        sleep(1)
        XCTAssertEqual(row.value as? String ?? "", "", "the tile settles back down")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'agent-' AND value == 'Lifted'"))
        XCTAssertEqual(rows.count, 0, "no tile stays lifted")
    }

    func testThePlusMenuMovesNothing() {
        launch()
        let last = element("last-line"), character = element("character")
        XCTAssert(last.waitForExistence(timeout: 6))
        sleep(2)
        let y0 = last.frame.maxY, c0 = character.frame
        app.buttons["Add photos or files"].tap()
        XCTAssert(app.buttons["Files"].waitForExistence(timeout: 3))
        sleep(1)
        XCTAssertEqual(last.frame.maxY, y0, accuracy: 2, "the conversation stays where it is")
        XCTAssertEqual(character.frame.minY, c0.minY, accuracy: 2, "and so does the character")
        app.swipeDown()                                           // a scroll behind it closes it, like a tap
        XCTAssert(gone(app.buttons["Files"]), "a scroll closes the menu")
    }

    func testAMessagesMenuCopiesAndMutes() {
        launch()
        let last = app.staticTexts["Done, the test file is removed."].firstMatch
        guard last.waitForExistence(timeout: 6) else { return }                // that line is in this Mac's conversation
        last.press(forDuration: 0.8)
        XCTAssert(app.buttons["Copy"].waitForExistence(timeout: 3), "press and hold: Copy")
        let mute = app.buttons["Mute replies"], unmute = app.buttons["Read replies aloud"]
        XCTAssert(mute.exists || unmute.exists, "and mute")
        sleep(1); shot("message-menu")
        if mute.exists {
            mute.tap()
            last.press(forDuration: 0.8)
            XCTAssert(app.buttons["Read replies aloud"].waitForExistence(timeout: 3), "muted: it offers reading aloud again")
            app.buttons["Read replies aloud"].tap()               // put it back
        } else { unmute.tap() }
    }

    func testTappingTheMicListensUntilSendOrCancel() {
        launch(["-quiet", "YES"])
        let mic = element("mic")
        XCTAssert(mic.waitForExistence(timeout: 5))
        mic.tap()
        XCTAssert(element("cancel-talk").waitForExistence(timeout: 3), "a tap starts listening: × shows")
        XCTAssert(app.buttons["Send"].exists || mic.label == "Send", "and the mic is now send")
        sleep(2)
        shot("listening-tap")
        element("cancel-talk").tap()
        XCTAssert(gone(element("cancel-talk")), "× stops it")
        mic.tap()
        XCTAssert(element("cancel-talk").waitForExistence(timeout: 3))
        sleep(1)
        mic.tap()                                                 // ↑: sends what it heard
        XCTAssert(gone(element("cancel-talk")), "↑ sends it")
    }

    func testHoldingTheMicListensAndSlidingLeftCancels() {
        launch(["-quiet", "YES"])                                   // the Simulator's stand-in microphone
        let mic = element("mic")
        XCTAssert(mic.waitForExistence(timeout: 5))
        let start = mic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 1.0, thenDragTo: start.withOffset(CGVector(dx: -150, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(1)
        XCTAssert(mic.exists, "the microphone is back once you let go")
        shot("after-cancel")
    }

    func testAfterACancelTheLaneStopsSayingListening() {
        launch(["-quiet", "YES"])
        let mic = element("mic"), lane = element("state-lane"), field = element("message")
        XCTAssert(mic.waitForExistence(timeout: 5) && element("character").waitForExistence(timeout: 8))
        sleep(2)
        // the keyboard up first: the hold puts it away as listening starts, so the screen has redrawn with Listening in
        // the lane before the cancel
        field.tap()
        XCTAssert(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        sleep(1)
        let start = mic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 1.5, thenDragTo: start.withOffset(CGVector(dx: -150, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.3)
        let end = Date().addingTimeInterval(0.5)
        var listening = true
        repeat { listening = lane.exists && lane.label.contains("Listening") } while listening && Date() < end
        shot("lane-after-cancel")
        XCTAssertFalse(listening, "let go on ×: within half a second the lane no longer says Listening (\(lane.exists ? lane.label : "no lane"))")
    }

    func testTheAgentsReorderAndOpenTheirSettings() {
        launch()
        app.buttons["Agents"].tap()
        XCTAssert(element("agent-ray").waitForExistence(timeout: 4))
        sleep(1)
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'agent-'")).allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
        XCTAssert(rows.count >= 3)
        let first = element(rows[0].identifier), third = rows[2]
        let y0 = first.frame.midY
        shot("agents")
        first.press(forDuration: 0.8, thenDragTo: third, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssert(first.frame.midY > y0 + 40, "\(rows[0].identifier) moved down to the third place (\(y0) → \(first.frame.midY))")
        shot("agents-reordered")
        element("settings-ray").tap()
        XCTAssert(element("part-voice").waitForExistence(timeout: 5), "… opens Ray's card")
        shot("agent-settings")
    }

    func testTheNameAtTheTopOpensItsCard() {
        launch()
        let name = element("name-button")
        XCTAssert(name.waitForExistence(timeout: 8), "the bar shows the agent's name")
        name.tap()
        XCTAssert(element("part-voice").waitForExistence(timeout: 5), "a tap on it opens its card")
    }

    func testTheNewestLineSitsJustAboveTheCharacter() {
        launch(["-demoConversation", "24"])          // long enough to scroll, whatever the hub has
        let last = element("last-line"), character = element("character")
        XCTAssert(last.waitForExistence(timeout: 8) && character.exists)
        sleep(2)
        let gap = character.frame.minY - last.frame.maxY
        XCTAssert(gap > -4 && gap < 40, "the newest line ends just above the character (gap \(gap))")
        let field = element("message")
        XCTAssert(character.frame.minX < 20 && character.frame.maxY <= field.frame.minY, "which stands at the bottom left, above the box (\(character.frame), the field \(field.frame))")
        shot("dock")
    }

    func testTheCharacterScrollsWithTheConversation() {
        launch(["-demoConversation", "24"])          // long enough to scroll, whatever the hub has
        let character = element("character"), last = element("last-line")
        XCTAssert(character.waitForExistence(timeout: 8) && last.exists)
        sleep(2)
        let y0 = character.frame.minY
        app.swipeDown(velocity: .slow)                             // back up the conversation
        sleep(1)
        XCTAssert(!character.exists || character.frame.minY > y0 + 100 || !character.isHittable,
                  "it's the conversation's last row: it goes down with it (\(y0) → \(character.exists ? character.frame.minY : -1))")
        shot("scrolled-back")
        app.swipeUp(velocity: .fast); app.swipeUp(velocity: .fast)
        sleep(1)
        XCTAssert(character.waitForExistence(timeout: 3) && abs(character.frame.minY - y0) < 4, "and comes back at the end")
    }

    /// The left edge: a swipe in opens the agents; a vertical scroll or a tap there is the conversation's.
    func testTheLeftEdgeOpensTheAgentsAndLetsTheRestThrough() {
        launch(["-demoConversation", "24"])          // long enough to scroll, whatever the hub has
        let last = element("last-line"), character = element("character")
        XCTAssert(last.waitForExistence(timeout: 8))
        sleep(2)
        let y0 = last.frame.minY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.75)), withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
        XCTAssert(last.frame.minY > y0 + 60, "a scroll from the edge scrolls the conversation (\(y0) → \(last.frame.minY))")
        XCTAssert(!element("agent-noodle").isHittable, "and doesn't open the agents")
        app.swipeUp(velocity: .fast); app.swipeUp(velocity: .fast); sleep(1)
        let c = character.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: c.minX + 8, dy: c.midY)).tap()
        sleep(1)
        XCTAssert(character.frame.height > c.height * 2, "a tap on the character's left edge brings it in front")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap(); sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)), withVelocity: .fast, thenHoldForDuration: 0.05)
        XCTAssert(element("agent-noodle").waitForExistence(timeout: 3) && element("agent-noodle").isHittable, "a swipe in from the edge opens the agents")
        shot("edge-agents")
    }

    /// Each agent's conversation opens at its end: its newest line, and the character under it, above the box.
    func testSwitchingAgentsOpensOnTheNewestLine() {
        launch(["-demoConversation", "24"])          // long enough to scroll, whatever the hub has
        let character = element("character"), field = element("message")
        XCTAssert(character.waitForExistence(timeout: 8))
        for id in ["noodle", "ray", "noodle"] {
            app.buttons["Agents"].tap()
            XCTAssert(element("agent-\(id)").waitForExistence(timeout: 4))
            element("agent-\(id)").tap()
            sleep(2)
            XCTAssert(character.waitForExistence(timeout: 4) && character.isHittable, "\(id): the character is on screen")
            XCTAssert(abs(character.frame.maxY - (field.frame.minY - 8)) < 30, "\(id): at the end, just above the box (\(character.frame.maxY), the field at \(field.frame.minY))")
            let gap = character.frame.minY - element("last-line").frame.maxY
            XCTAssert(gap > -4 && gap < 40, "\(id): under its newest line (gap \(gap))")
            shot("switched-\(id)")
        }
    }

    func testWhileItWorksTheLaneShowsItsStep() {
        launch(["-working", "YES"])
        let lane = element("state-lane")
        XCTAssert(lane.waitForExistence(timeout: 8))
        sleep(2)
        XCTAssert(lane.label.contains("Running tests") && lane.label.contains("npm test") && !lane.label.contains("Bash"),
                  "beside it: what it's doing in words, and exactly what on (\(lane.label))")
        XCTAssert(lane.frame.minX >= element("character").frame.maxX - 4, "to the right of the character (\(lane.frame), \(element("character").frame))")
        shot("working-lane")
    }

    /// Opens the page only (a pick would restart a real agent): how it asks before acting, its runtime's setting first.
    func testThePermissionsPageShowsHowItAsks() {
        launch(["-sheet", "ray"])
        let row = element("permission-row")
        XCTAssert(row.waitForExistence(timeout: 6), "the card has a Permissions row")
        row.tap()
        XCTAssert(element("permission-own").waitForExistence(timeout: 6), "it opens the modes: its runtime's setting first")
        for id in ["permission-default", "permission-acceptEdits", "permission-auto"] { XCTAssert(element(id).exists, "and \(id)") }
        XCTAssert(app.staticTexts["Asks first"].exists, "Asks first, in words")
        shot("permissions")
    }

    /// Opens the page only: a pick would restart a real agent (the hub's tests switch a stand-in's model).
    func testTheModelPageShowsWhatItRunsOn() {
        launch(["-sheet", "ray"])
        let row = element("model-row")
        XCTAssert(row.waitForExistence(timeout: 6), "the card has a Model row")
        sleep(2)
        shot("model-row")
        row.tap()
        XCTAssert(element("model-own").waitForExistence(timeout: 5), "it opens the models: the default first")
        XCTAssert(element("model-opus").exists && element("model-sonnet").exists && element("model-fable").exists, "and each model Claude Code offers")
        XCTAssert(element("model-own").isSelected, "Ray has no model of its own: the default is the one picked")
        shot("models")
    }

    /// Opened before the models come back, the page waits for them: it never says the Mac can't be reached.
    func testTheModelPageAsksBeforeItSaysTheMacIsOutOfReach() {
        launch(["-sheet", "ray"])
        let row = element("model-row")
        XCTAssert(row.waitForExistence(timeout: 6))
        row.tap()                                                  // at once, while the card is still asking
        let unreachable = app.staticTexts["Can't reach your Mac"]
        let deadline = Date().addingTimeInterval(5)
        while !element("model-own").exists && Date() < deadline {
            XCTAssertFalse(unreachable.exists, "it says it's asking, not that the Mac is out of reach")
        }
        XCTAssert(element("model-own").exists, "and the models come")
    }

    /// Back on the Model and Voice pages is a plain chevron; the swipe from the left edge goes back too. Opens the
    /// pages only: a pick would change a real agent.
    func testTheCardsPagesGoBackByTheChevronAndTheEdge() {
        launch(["-sheet", "ray"])
        let row = element("model-row")
        XCTAssert(row.waitForExistence(timeout: 6))
        row.tap()
        XCTAssert(element("model-own").waitForExistence(timeout: 5))
        sleep(1); shot("models-page")
        element("back").tap()
        XCTAssert(gone(element("model-own")) && row.waitForExistence(timeout: 2), "the chevron goes back to the card")
        row.tap()
        XCTAssert(element("model-own").waitForExistence(timeout: 5))
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssert(gone(element("model-own")), "a swipe from the left edge goes back")
        let voice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Voice'")).firstMatch
        XCTAssert(voice.waitForExistence(timeout: 2))
        voice.tap()
        XCTAssert(element("back").waitForExistence(timeout: 3))
        XCTAssert(app.staticTexts["British"].waitForExistence(timeout: 6) || app.staticTexts["BRITISH"].exists, "the voices come")
        sleep(1); shot("voices-page")
        element("back").tap()
        XCTAssert(row.waitForExistence(timeout: 3), "back on the card")
    }

    func testTheMicClosesThePlusMenu() {
        launch(["-quiet", "YES"])
        let mic = element("mic")
        XCTAssert(mic.waitForExistence(timeout: 5))
        app.buttons["Add photos or files"].tap()
        XCTAssert(app.buttons["Files"].waitForExistence(timeout: 3))
        mic.tap()
        XCTAssert(gone(app.buttons["Files"], 2), "the menu goes the moment the mic is touched")
        XCTAssert(element("cancel-talk").waitForExistence(timeout: 3), "and it listens")
        shot("mic-after-menu")
        element("cancel-talk").tap()
        XCTAssert(gone(element("cancel-talk")))
    }

    func testASoulPartEditsInPlaceAboveTheKeyboard() {
        launch(["-sheet", "ray"])
        let part = element("part-voice")
        XCTAssert(part.waitForExistence(timeout: 6))
        part.tap()
        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        XCTAssert(field.waitForExistence(timeout: 3), "the part turns into a field")
        XCTAssert(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        sleep(1)
        let kb = app.keyboards.firstMatch.frame
        XCTAssert(field.frame.maxY < kb.minY, "the field sits above the keyboard (\(field.frame.maxY) < \(kb.minY))")
        XCTAssert(app.buttons["Save"].frame.maxY < kb.minY, "and so does Save")
        shot("soul-editing")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssert(gone(app.buttons["Save"]))
    }

    func testTheCharacterComesToTheFrontAndGoesBack() {
        launch()
        let character = element("character")
        XCTAssert(character.waitForExistence(timeout: 5))
        let small = character.frame.height
        character.tap()
        sleep(1)
        XCTAssert(character.frame.height > small * 2, "a tap brings it in front, big")
        shot("front")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.9)).tap()
        sleep(1)
        XCTAssert(character.frame.height < small * 1.2, "a tap outside puts it back")
    }

    func testThePlusOffersPhotosAndFiles() {
        launch()
        app.buttons["Add photos or files"].tap()
        XCTAssert(app.buttons["Photo Library"].waitForExistence(timeout: 3) && app.buttons["Files"].exists)
        sleep(1); shot("plus")
        app.buttons["Close"].firstMatch.tap()
        XCTAssert(gone(app.buttons["Photo Library"]))
    }

    func testAPictureZoomsAndCloses() throws {
        let id = try XCTUnwrap(env["VIEWER_ID"], "set TEST_RUNNER_VIEWER_ID to an artifact id")
        launch(["-viewer", id])
        let view = app.scrollViews["viewer-scroll"]
        XCTAssert(view.waitForExistence(timeout: 8))
        sleep(2)
        view.pinch(withScale: 3, velocity: 3)
        sleep(1)
        let z = Double(String((view.value as? String ?? "zoom 1").dropFirst(5))) ?? 1
        XCTAssert(z > 1.8, "pinching zooms in (zoom \(z))")
        shot("viewer-zoomed")
        view.doubleTap()
        sleep(1)
        XCTAssert((view.value as? String) == "zoom 1.0", "a double tap zooms back out")
        app.swipeDown(velocity: .fast)
        XCTAssert(gone(view), "dragged down, the card goes away")
    }
}

/// Every screen and state, as screenshots in TEST_RUNNER_SHOTS_DIR, for reviewing the design. Sends no orders.
final class ChumsPhoneTour: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private func shot(_ name: String) {
        guard let dir = env["SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("tour-\(name).png"))
    }
    private func run(_ agent: String, _ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-agent", agent] + args
        app.launch()
        sleep(3)
        return app
    }

    func testTour() {
        var app = run("ray")
        shot("01-conversation")
        app.descendants(matching: .any)["message"].firstMatch.tap(); sleep(1)
        shot("02-typing")
        app.descendants(matching: .any)["state-lane"].firstMatch.tap(); sleep(1)
        app.buttons["Add photos or files"].tap(); sleep(1)
        shot("03-plus")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap(); sleep(1)
        app.descendants(matching: .any)["character"].firstMatch.tap(); sleep(2)
        shot("04-front")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.9)).tap(); sleep(1)
        app.buttons["Agents"].tap(); sleep(1)
        shot("05-agents")
        app.descendants(matching: .any)["settings-ray"].firstMatch.tap(); sleep(2)
        shot("06-agent-settings")
        app.swipeUp(); sleep(1)
        shot("07-agent-settings-scrolled")
        let ask = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        if ask.exists { ask.tap(); sleep(1); shot("08-soul-typing") }
        app.terminate()

        app = run("ray", ["-settings", "YES"])
        shot("09-app-settings")
        app.terminate()

        app = run("stretch")
        shot("10-empty-agent")
        app.terminate()

        app = run("ray", ["-approval", "YES"])
        shot("13-approval")
        app.terminate()

        app = run("ray", ["-attach", "YES"])
        shot("14-attachments")
        app.terminate()

        app = run("ray", ["-quiet", "YES", "-listen", "YES"])
        sleep(1)
        shot("15-listening")
        app.terminate()

        app = run("ray", ["-working", "YES"])
        sleep(2)
        shot("16-working")
        app.terminate()

        if let id = env["VIEWER_ID"] {
            app = run("ray", ["-viewer", id])
            sleep(2)
            shot("11-viewer")
            app.buttons["Share"].firstMatch.tap(); sleep(2)
            shot("12-share")
            app.terminate()
        }
    }
}
