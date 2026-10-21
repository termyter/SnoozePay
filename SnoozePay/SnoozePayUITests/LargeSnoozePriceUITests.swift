import XCTest

/// #928: native text input -> keyboard Done -> save -> reopen -> price-cell reuse.
final class LargeSnoozePriceUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIApplication().terminate()
        super.tearDown()
    }

    func testIntMaxCustomPriceSurvivesSaveReopenAndScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "create", "-uitour-reset", "-uitour-alarmkit", "granted"]
        app.launch()
        XCTAssertTrue(app.textFields["createAlarm.nameField"].waitForExistence(timeout: 10))
        let price = revealPrice(in: app)
        focusPrice(price, in: app)
        clearPriceField(price, in: app)
        recordInputState("post-Cut", price: price, in: app)
        let focusTaps = focusPrice(price, in: app)
        let viewportPans = makeFocusedPriceVisible(price, in: app)
        recordInputState("ready", price: price, in: app, focusTaps: focusTaps, viewportPans: viewportPans)
        XCTAssertEqual(price.value as? String, "", "Readiness actions must leave the entire field empty")
        price.typeText("9223372036854775807")
        recordInputState("post-type", price: price, in: app, focusTaps: focusTaps, viewportPans: viewportPans)
        XCTAssertEqual(price.value as? String, "9223372036854775807")
        let done = app.buttons["createAlarm.penaltyDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        recordInputState("before-first-Done", price: price, in: app)
        done.tap()
        // Capture the same immediate sample as before diagnostics were added;
        // collecting the subsequent snapshot must not make a late commit pass.
        let firstDoneValue = price.value as? String
        recordInputState("after-first-Done", price: price, in: app, observedValue: firstDoneValue)
        XCTAssertEqual(firstDoneValue, "9223372036854775808")
        app.buttons["createAlarm.saveButton"].tap()
        XCTAssertTrue(app.textFields["createAlarm.nameField"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        app.tables.cells.firstMatch.tap()
        XCTAssertTrue(app.textFields["createAlarm.nameField"].waitForExistence(timeout: 5))
        let reopenedPrice = revealPrice(in: app)
        XCTAssertEqual(reopenedPrice.value as? String, "9223372036854775808")
        focusPrice(reopenedPrice, in: app)
        makeFocusedPriceVisible(reopenedPrice, in: app)
        XCTAssertEqual(reopenedPrice.value as? String, "9223372036854775808")
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        recordInputState("before-second-Done", price: reopenedPrice, in: app)
        done.tap()
        let secondDoneValue = reopenedPrice.value as? String
        recordInputState("after-second-Done", price: reopenedPrice, in: app, observedValue: secondDoneValue)
        XCTAssertEqual(secondDoneValue, "9223372036854775808")

        let name = app.textFields["createAlarm.nameField"]
        var scrolls = 0
        while scrolls < 8, !name.isHittable {
            app.tables.firstMatch.swipeDown()
            scrolls += 1
        }
        XCTAssertTrue(name.isHittable, "Scroll away from the price card before returning to it")
        XCTAssertEqual(revealPrice(in: app).value as? String, "9223372036854775808")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @discardableResult
    private func focusPrice(_ price: XCUIElement, in app: XCUIApplication) -> Int {
        let focusedPrice = app.textFields.matching(identifier: "createAlarm.penaltyField")
            .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        var taps = 0
        while taps < 3, !focusedPrice.exists {
            price.tap()
            taps += 1
            _ = focusedPrice.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(focusedPrice.exists, "The price field must receive native keyboard input")
        return taps
    }

    private func clearPriceField(_ price: XCUIElement, in app: XCUIApplication) {
        let oldText = price.value as? String ?? ""
        XCTAssertFalse(oldText.isEmpty, "The fixture must start with an existing price to replace")
        XCTAssertTrue(oldText.utf8.allSatisfy { (48...57).contains($0) },
                      "The existing price must be one whole numeric token for native word selection")
        makeFocusedPriceVisible(price, in: app)
        XCTAssertEqual(price.value as? String, oldText, "Revealing the field must not change its contents")
        // A focus tap can leave the caret at the START, where backspaces do
        // nothing. Select the numeric token and require the native Cut action
        // as selection evidence; an empty read-back proves ALL text was cut.
        price.doubleTap()
        XCTAssertEqual(price.value as? String, oldText, "Selection must not type into the obscuring keyboard")
        let cut = editMenuAction(["Cut", "Вырезать"], in: app)
        if !cut.exists {
            // A numeric double-tap can leave only an insertion caret. Open
            // its native edit menu once, then select all only if still needed.
            price.press(forDuration: 1)
            if !cut.exists {
                let selectAll = editMenuAction(["Select All", "Выбрать всё", "Выбрать все",
                                               "Выделить всё", "Выделить все"], in: app)
                XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "Native edit menu must offer Select All")
                XCTAssertTrue(selectAll.isHittable, "Native Select All must be tappable")
                selectAll.tap()
            }
        }
        XCTAssertEqual(price.value as? String, oldText, "Native selection must preserve the entire existing value")
        XCTAssertTrue(cut.waitForExistence(timeout: 5), "Native selection must offer Cut before replacement")
        XCTAssertTrue(cut.isHittable, "The native edit-menu action must be tappable")
        cut.tap()
        XCTAssertEqual(price.value as? String, "", "Clear the entire old price BEFORE typing once")
    }

    private func editMenuAction(_ labels: [String], in app: XCUIApplication) -> XCUIElement {
        let action = NSPredicate(
            format: "(elementType == %lu OR elementType == %lu) AND label IN %@",
            XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue,
            labels as NSArray
        )
        return app.descendants(matching: .any).matching(action).firstMatch
    }

    @discardableResult
    private func makeFocusedPriceVisible(_ price: XCUIElement, in app: XCUIApplication) -> Int {
        let keyboard = app.keyboards.firstMatch
        let toolbar = app.toolbars.containing(.button, identifier: "createAlarm.penaltyDone").firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(toolbar.waitForExistence(timeout: 5))
        let table = app.tables.firstMatch
        func viewport() -> CGRect {
            let frame = table.frame.intersection(app.frame)
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                          height: max(0, min(frame.maxY, toolbar.frame.minY) - frame.minY))
        }
        var pans = 0
        while pans < 3, !viewport().contains(price.frame) || !price.isHittable {
            let visible = viewport()
            XCTAssertFalse(visible.isEmpty, "A native pan needs an unobscured part of the table")
            let origin = table.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: visible.midX - table.frame.minX,
                                                   dy: visible.minY + visible.height * 0.85 - table.frame.minY))
            let end = origin.withOffset(CGVector(dx: visible.midX - table.frame.minX,
                                                 dy: visible.minY + visible.height * 0.15 - table.frame.minY))
            // Keep both ends above the keyboard, including while keyboard
            // presentation changes the table's frame.
            start.press(forDuration: 0.05, thenDragTo: end)
            pans += 1
            XCTAssertTrue(keyboard.exists, "The upward pan must retain the keyboard")
            let focused = app.textFields.matching(identifier: "createAlarm.penaltyField")
                .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
            XCTAssertTrue(focused.exists, "The upward pan must retain price-field focus")
        }
        XCTAssertTrue(viewport().contains(price.frame) && price.isHittable,
                      "The FULL price field \(price.frame) must be above the keyboard toolbar in \(viewport())")
        return pans
    }

    /// Small read-only observations preserve whether a corrective action actually ran.
    /// They do not claim that passing this guard explains the historical partial input.
    private func recordInputState(
        _ stage: String, price: XCUIElement, in app: XCUIApplication,
        focusTaps: Int? = nil, viewportPans: Int? = nil, observedValue: String? = nil
    ) {
        XCTContext.runActivity(named: "Price input readiness: " + stage) { activity in
            let focused = app.textFields.matching(identifier: "createAlarm.penaltyField")
                .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
            let fieldFrame = price.frame
            let fieldValue = String((price.value as? String ?? "<nil>").prefix(32))
            let doneExists = app.buttons["createAlarm.penaltyDone"].exists
            // Capture volatile keyboard/toolbar frames in the app tree instead of
            // resolving children after a separate existence check.
            let appAccessibilitySnapshot = app.debugDescription
            let evidence = """
            stage=\(stage)
            fieldValue=\(fieldValue)
            immediateObservedValue=\(observedValue ?? "not-sampled")
            doneExistsObserved=\(doneExists)
            focusMatch=\(focused.exists) hittable=\(price.isHittable) fieldFrame=\(fieldFrame)
            correctiveFocusTaps=\(focusTaps.map { String($0) } ?? "not-run")
            correctiveViewportPans=\(viewportPans.map { String($0) } ?? "not-run")
            appAccessibilitySnapshot=
            \(appAccessibilitySnapshot)
            """
            let attachment = XCTAttachment(string: evidence)
            attachment.name = "price-input-" + stage
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func revealPrice(in app: XCUIApplication) -> XCUIElement {
        let price = app.textFields["createAlarm.penaltyField"]
        var scrolls = 0
        while scrolls < 8, !price.isHittable {
            app.tables.firstMatch.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(price.exists && price.isHittable, "The snooze-price card must be reachable")
        return price
    }
}
