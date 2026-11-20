import UIKit
import XCTest
@testable import SnoozePay

/// Dynamic Type, slice 3 part 1: the alarm editor's text rows — the snooze
/// length card, the Звук / Тема / Вибрация card and the progressive card
/// (#1111).
///
/// Same approach as `AlarmsListDynamicTypeTests`: every measurement sets the
/// category explicitly, so nothing depends on what the simulator is set to.
@MainActor
final class CreateAlarmDynamicTypeTests: XCTestCase {

    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
    /// Every size that stacks (`AppTypography.stacksDenseRows`), up to the largest.
    private static let grown: [UIContentSizeCategory] = [.extraLarge, .extraExtraLarge, .extraExtraExtraLarge, ax5]
    /// The narrowest supported phone and today's default one.
    private static let screens: [CGFloat] = [375, 402]

    private static let snooze = IndexPath(row: 0, section: CreateAlarmViewController.Section.snoozeTime.rawValue)
    private static let sound = IndexPath(row: 0, section: CreateAlarmViewController.Section.settings.rawValue)
    private static let theme = IndexPath(row: 1, section: CreateAlarmViewController.Section.settings.rawValue)
    private static let vibration = IndexPath(row: 2, section: CreateAlarmViewController.Section.settings.rawValue)
    private static let progressive = IndexPath(
        row: 0, section: CreateAlarmViewController.Section.progressiveScale.rawValue
    )

    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true; $0.rootViewController = nil }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - Main's geometry

    /// One measured view: a label by its text, or «value» (the trailing name
    /// of the sound / theme row), «icon» (its leading icon or thumbnail),
    /// «chain», «switch» or «slider».
    private struct Spot {
        let row: IndexPath
        let text: String
        let frame: CGRect

        init(_ row: IndexPath, _ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            self.row = row
            self.text = text
            frame = CGRect(x: x, y: y, width: width, height: height)
        }
    }

    /// Measured on main (65cd789e), before this change, with `mount` at
    /// `.large`: a cold editor in a real window, on an iPhone 17 simulator
    /// with iOS 27.0. Frames are in each cell's content view, in pixels of
    /// that 3× screen (`px(53)` = 17⅔pt); `mount` checks the scale.
    private static func mainFrames(on screen: CGFloat) -> [Spot] {
        func px(_ pixels: CGFloat) -> CGFloat { pixels / 3 }
        let wide = screen == 402
        let shift: CGFloat = wide ? 27 : 0
        let column = 222 + shift
        let caption = "ДЛИТЕЛЬНОСТЬ ОТКЛАДЫВАНИЯ"
        let hint = "На сколько минут отодвигается звонок"
        let snoozeFrames = wide ? [
            Spot(snooze, caption, 20, 20, px(715), px(53)),
            Spot(snooze, hint, 20, px(119), 246, 18),
            Spot(snooze, "9 мин", 286, px(77), 56, px(80)),
            Spot(snooze, "1 мин", 20, px(323), px(98), 18),
            Spot(snooze, "15 мин", 302, px(323), 40, 18),
            Spot(snooze, "slider", 20, px(197), 322, 34)
        ] : [
            Spot(snooze, caption, 20, 20, px(715), px(53)),
            Spot(snooze, hint, 20, px(119), 133, px(107)),
            Spot(snooze, "9 мин", 259, px(103), 56, px(80)),
            Spot(snooze, "1 мин", 20, px(376), px(98), 18),
            Spot(snooze, "15 мин", 275, px(376), 40, 18),
            Spot(snooze, "slider", 20, px(250), 295, 34)
        ]
        return snoozeFrames + [
            // A symbol's frame is not its 24×24 alignment rect.
            Spot(sound, "icon", 20, px(42), 24, px(64)),
            Spot(theme, "icon", 20, px(32), 28, 28),
            Spot(sound, "Звук", 56, 13, px(113), px(70)),
            Spot(sound, "value", 246 + shift, px(47), px(154), 18),
            Spot(theme, "Тема", 60, 13, px(121), px(70)),
            Spot(theme, "value", 246 + shift, px(47), px(154), 18),
            Spot(vibration, "Вибрация", 56, 13, px(242), px(70)),
            Spot(vibration, "switch", 254 + shift, px(32), 63, 28),
            Spot(progressive, "Прогрессивный режим", 48, px(62), column - 28, px(70)),
            Spot(progressive, "Каждое откладывание — в 2\u{00A0}раза дороже.", 20, px(151), column, px(107)),
            Spot(progressive, "chain", 20, 98, column, 22),
            Spot(progressive, "switch", 254 + shift, 20, 63, 28)
        ]
    }

    /// Row heights on main, same measurement.
    private static func mainRowHeights(on screen: CGFloat) -> [(IndexPath, CGFloat)] {
        [
            (snooze, screen == 402 ? 145 + 2.0 / 3 : 163 + 1.0 / 3),
            (sound, 49), (theme, 49), (vibration, 49),
            (progressive, 140)
        ]
    }

    // MARK: - Seam

    func testTheEditorRolesAreTheFixedFontsAtTheDefaultSizeAndCappedAtAX5() {
        let large = UITraitCollection(preferredContentSizeCategory: .large)
        let grown = UITraitCollection(preferredContentSizeCategory: Self.ax5)
        let roles: [(fixed: UIFont, style: UIFont.TextStyle)] = [
            (AppTypography.h4, .headline),
            (AppTypography.moneyMd, .title3),
            (AppFonts.mono(.semibold, 14), .subheadline),
            (AppFonts.mono(.bold, 16), .subheadline)
        ]
        for (fixed, style) in roles {
            let name = "\(fixed.fontName) \(fixed.pointSize)"
            let atLarge = AppTypography.scaled(fixed, as: style, compatibleWith: large)
            let atAX5 = AppTypography.scaled(fixed, as: style, compatibleWith: grown)
            XCTAssertEqual(atLarge.pointSize, fixed.pointSize, "\(name) moved at the default size")
            XCTAssertEqual(atLarge.fontName, fixed.fontName, "\(name) changed face")
            XCTAssertGreaterThan(atAX5.pointSize, fixed.pointSize, "\(name) ignores Dynamic Type")
            XCTAssertLessThanOrEqual(atAX5.pointSize, fixed.pointSize * AppTypography.maximumScale)
        }
    }

    // MARK: - The hosted editor

    func testAColdEditorAtTheDefaultSizeMatchesMain() throws {
        for screen in Self.screens {
            let sut = mount(width: screen, category: .large)
            try assertMainGeometry(in: sut, on: screen, "cold, \(screen)")
            let fixed: [String: (row: IndexPath, font: UIFont)] = [
                "Звук": (Self.sound, AppTypography.bodyLg),
                "Вибрация": (Self.vibration, AppTypography.bodyLg),
                "На сколько минут отодвигается звонок": (Self.snooze, AppTypography.meta),
                "ДЛИТЕЛЬНОСТЬ ОТКЛАДЫВАНИЯ": (Self.snooze, AppTypography.caps),
                "Прогрессивный режим": (Self.progressive, AppTypography.h4)
            ]
            for (text, role) in fixed {
                let drawn = try attributedFont(of: label(text, in: hostedCell(role.row, of: sut)))
                XCTAssertEqual(drawn.pointSize, role.font.pointSize, "«\(text)» at \(screen)")
                XCTAssertEqual(drawn.fontName, role.font.fontName, "«\(text)» at \(screen)")
            }
        }
    }

    /// The window's category changes under a running editor: every row grows
    /// and stacks, survives the settings rows being reloaded, and coming back
    /// restores main's geometry to the third of a point.
    ///
    /// The table hands out other cell instances after each change (measured:
    /// none of the three snooze cells is the same object), so a cell's own
    /// way back to `.large` is on trial in the per-row tests below.
    func testALiveChangeToAX5AndBackRestoresMainsGeometry() throws {
        for screen in Self.screens {
            let sut = mount(width: screen, category: .large)
            try setCategory(Self.ax5, of: sut)
            try assertGrownEditor(sut, on: screen, "live AX5, \(screen)")

            // The path back from the sound and theme pickers: `viewWillAppear`
            // reloads the settings section, so its rows are dequeued afresh.
            sut.tableView.reloadSections(
                IndexSet([CreateAlarmViewController.Section.settings.rawValue]), with: .none
            )
            sut.tableView.layoutIfNeeded()
            try assertGrownEditor(sut, on: screen, "reloaded at AX5, \(screen)")

            try setCategory(.large, of: sut)
            try assertMainGeometry(in: sut, on: screen, "back to .large, \(screen)")
        }
    }

    /// Every run of every label in the five rows, read off the hosted editor:
    /// at AX5 it is larger than at `.large` and at most twice that — the
    /// reading's «мин», the chain's last sum, the hint, the bounds and the
    /// subtitle included — and the chain's last sum leads its steps at both.
    func testEveryTextRunGrowsAtAX5AndAtMostDoubles() throws {
        for screen in Self.screens {
            let sut = mount(width: screen, category: .large)
            let atLarge = try runSizes(in: sut)
            try setCategory(Self.ax5, of: sut)
            let atAX5 = try runSizes(in: sut)
            XCTAssertEqual(Set(atAX5.keys), Set(atLarge.keys), "\(screen): the labels changed")
            // Caption, hint, reading and two bounds; two names and two
            // titles; «Вибрация»; title, subtitle and chain.
            XCTAssertEqual(atLarge.count, 13, "\(screen): \(atLarge.keys.sorted())")
            for (key, before) in atLarge {
                let after = atAX5[key] ?? []
                XCTAssertEqual(after.count, before.count, "\(screen): «\(key)» changed its runs")
                for (run, (small, grown)) in zip(before, after).enumerated() {
                    let name = "\(screen): «\(key)» run \(run), \(small) → \(grown)"
                    XCTAssertGreaterThan(grown, small, "\(name) did not grow")
                    XCTAssertLessThanOrEqual(grown, small * AppTypography.maximumScale + 0.01, "\(name) over 2×")
                }
            }
            let chain = try XCTUnwrap(atLarge.keys.first { $0.contains(" → ") }, "no chain")
            for runs in [atLarge[chain] ?? [], atAX5[chain] ?? []] {
                XCTAssertGreaterThan(runs.count, 1, "\(screen): the chain is one run")
                XCTAssertGreaterThan(runs.last ?? 0, runs.first ?? 0, "\(screen): the last sum lost its lead")
            }
        }
    }

    /// Users with large text on at launch take this path: the first layout is
    /// already the grown one.
    func testAColdEditorAtAX5IsGrownFromTheFirstLayout() throws {
        for screen in Self.screens {
            let sut = mount(width: screen, category: Self.ax5)
            try assertGrownEditor(sut, on: screen, "cold AX5, \(screen)")
        }
    }

    // MARK: - Звук / Тема

    /// From XL the name moves under the title, at the title's leading edge,
    /// clear of the chevron — with the longest real names, in both languages.
    func testFromXLTheSoundAndThemeNamesMoveUnderTheirTitles() throws {
        let sounds = [
            "Bach's Badinerie", "Размышление", "Своя мелодия", "Custom Melody",
            Localized.text("create_alarm.sound.fallback")
        ]
        let themes = AlarmTheme.builtInOrder.map(\.displayName) + [
            Localized.text("create_alarm.theme.name.custom"), "Your Photo", "Mountains"
        ]
        let soundTitle = Localized.text("create_alarm.sound.title")
        let themeTitle = Localized.text("create_alarm.theme.title")
        for category in Self.grown {
            for screen in Self.screens {
                for name in sounds {
                    let row = SoundCell(style: .default, reuseIdentifier: nil)
                    row.configure(soundName: name)
                    try assertStacked(row, title: soundTitle, value: name, category, screen)
                }
                for name in themes {
                    let row = ThemeRowCell(style: .default, reuseIdentifier: nil)
                    row.configure(theme: .dawn, themeName: name)
                    try assertStacked(row, title: themeTitle, value: name, category, screen)
                }
            }
        }
    }

    /// Up to `.large` a long name still sits beside the title on one line, in
    /// today's 48pt row.
    func testAtTheDefaultSizeTheLongestSoundNameStaysBesideTheTitle() throws {
        let row = SoundCell(style: .default, reuseIdentifier: nil)
        row.configure(soundName: "Bach's Badinerie")
        override(row, to: .large)
        layOut(row, width: 335)
        let title = try label(Localized.text("create_alarm.sound.title"), in: row)
        let value = try label("Bach's Badinerie", in: row)
        XCTAssertEqual(value.numberOfLines, 1)
        XCTAssertEqual(value.frame.midY, title.frame.midY, accuracy: 0.5, "the name left the title's line")
        XCTAssertGreaterThan(value.frame.minX, title.frame.maxX)
        XCTAssertEqual(fitted(row.contentView, width: 335), 48, accuracy: 0.01)
        XCTAssertFalse(isClipped(value))
    }

    // MARK: - Вибрация

    func testTheVibrationTitleGrowsWithoutReachingTheSwitch() throws {
        for category in Self.grown {
            for screen in Self.screens {
                let row = VibrationCell(style: .default, reuseIdentifier: nil)
                override(row, to: category)
                layOut(row, width: Self.cardWidth(screen))
                let name = "\(category.rawValue) at \(screen)"
                let title = try label(Localized.text("create_alarm.vibration.title"), in: row)
                let toggle = try XCTUnwrap(descendants(of: SPSwitch.self, in: row.contentView).first)
                XCTAssertGreaterThan(try attributedFont(of: title).pointSize, AppTypography.bodyLg.pointSize, name)
                XCTAssertEqual(title.numberOfLines, 1, name)
                XCTAssertFalse(isClipped(title), "\(name): the title is clipped")
                XCTAssertLessThanOrEqual(title.frame.maxX, toggle.frame.minX - AppSpacing.sp2 + 0.5, name)
                XCTAssertGreaterThanOrEqual(title.frame.minY, AppSpacing.sp3 - 0.5, "\(name): the title left the row")
                XCTAssertLessThanOrEqual(title.frame.maxY, row.contentView.bounds.maxY - AppSpacing.sp3 + 0.5, name)
            }
        }
    }

    // MARK: - Snooze length

    /// From XL the caption and the hint take the card's width and the reading
    /// gets its own line above the track; at XL on a 375pt card the caption
    /// alone already reaches under the reading.
    func testFromXLTheSnoozeReadingMovesUnderTheHint() throws {
        for category in Self.grown {
            for screen in Self.screens {
                let row = SnoozeSliderCell(style: .default, reuseIdentifier: nil)
                row.configure(minutes: 15)
                override(row, to: category)
                layOut(row, width: Self.cardWidth(screen))
                let name = "\(category.rawValue) at \(screen)"
                let caption = try label(Localized.text("create_alarm.snooze.caps").uppercased(), in: row)
                let hint = try label(Localized.text("create_alarm.snooze.hint"), in: row)
                let reading = try label("15 мин", in: row, first: true)
                let slider = try XCTUnwrap(descendants(of: UISlider.self, in: row.contentView).first)
                XCTAssertGreaterThanOrEqual(reading.frame.minY, hint.frame.maxY, "\(name): reading beside the hint")
                XCTAssertGreaterThanOrEqual(slider.frame.minY, reading.frame.maxY, "\(name): reading over the track")
                XCTAssertEqual(reading.frame.minX, AppSpacing.cardHorizontalPadding, accuracy: 0.01, name)
                // The frame spans the card either way; only the alignment
                // says where «15 мин» is drawn in it.
                XCTAssertEqual(reading.textAlignment, .natural, "\(name): the reading is drawn at the right edge")
                for text in [caption, hint] {
                    XCTAssertLessThanOrEqual(
                        text.frame.maxX, row.contentView.bounds.maxX - AppSpacing.cardHorizontalPadding + 0.5, name
                    )
                }
                let digit = try attributedFont(of: reading)
                XCTAssertGreaterThan(digit.pointSize, AppTypography.moneyMd.pointSize, "\(name): number not grown")
                XCTAssertGreaterThan(try attributedFont(of: caption).pointSize, AppTypography.caps.pointSize, name)
                assertNothingClipped(in: row, atLeast: 5)

                // The same cell back at `.large`: the hosted editor's table
                // may hand out another instance after a category change, so
                // only here is the restore itself on trial.
                override(row, to: .large)
                layOut(row, width: Self.cardWidth(screen))
                XCTAssertEqual(reading.textAlignment, .right, "\(name) → .large: the reading lost its right alignment")
                XCTAssertLessThan(reading.frame.minY, hint.frame.maxY, "\(name) → .large: the reading stayed under")
            }
        }
    }

    /// Moving the slider at AX5 re-renders the reading at the grown size, and
    /// the grown caption keeps +0.12em tracking.
    func testAtAX5TheSnoozeReadingAndCaptionStayScaled() throws {
        let row = SnoozeSliderCell(style: .default, reuseIdentifier: nil)
        row.configure(minutes: 3)
        override(row, to: Self.ax5)
        layOut(row, width: 335)
        let slider = try XCTUnwrap(descendants(of: UISlider.self, in: row.contentView).first)
        slider.value = 12
        slider.sendActions(for: .valueChanged)
        let reading = try label("12 мин", in: row, first: true)
        let digit = try attributedFont(of: reading)
        XCTAssertGreaterThan(digit.pointSize, AppTypography.moneyMd.pointSize)
        XCTAssertLessThanOrEqual(digit.pointSize, AppTypography.moneyMd.pointSize * AppTypography.maximumScale)

        let caps = Localized.text("create_alarm.snooze.caps").uppercased()
        let caption = try XCTUnwrap(try label(caps, in: row).attributedText)
        let font = try XCTUnwrap(caption.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let kern = try XCTUnwrap(caption.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat)
        XCTAssertGreaterThan(font.pointSize, AppTypography.caps.pointSize)
        XCTAssertEqual(
            kern / font.pointSize, AppTypography.capsKerning / AppTypography.caps.pointSize, accuracy: 0.0001
        )
    }

    // MARK: - Progressive card

    /// From XL the switch drops under the column, which takes the card's
    /// width, and the flame goes above the title; the title wraps between its
    /// words and the chain only at its arrows — with four-digit amounts, armed
    /// and not.
    func testFromXLTheProgressiveSwitchDropsUnderTheColumn() throws {
        for category in Self.grown {
            for screen in Self.screens {
                for isOn in [true, false] {
                    try assertStackedProgressiveCard(isOn: isOn, category, screen)
                }
            }
        }
    }

    /// Flipping the switch either way repaints the chain — the first step
    /// goes from warn to the card's meta ink and back — and the repainted
    /// chain keeps the grown size.
    func testTogglingTheProgressiveCardAtAX5RepaintsTheScaledChain() throws {
        let row = ProgressiveScaleCell(style: .default, reuseIdentifier: nil)
        row.configure(isOn: true, chain: [50, 100, 200, 400], currency: .rub, accessibilityChain: "")
        override(row, to: Self.ax5)
        layOut(row, width: 335)
        let traits = row.traitCollection
        let firstStepInk = { (label: UILabel) in
            (label.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)?
                .resolvedColor(with: traits)
        }
        XCTAssertEqual(try firstStepInk(chainLabel(in: row)), AppColors.warn400.resolvedColor(with: traits))
        let toggle = try XCTUnwrap(descendants(of: SPSwitch.self, in: row.contentView).first)
        for (isOn, ink) in [(false, AppColors.fg3), (true, AppColors.warn400)] {
            toggle.isOn = isOn
            toggle.sendActions(for: .valueChanged)
            let chain = try chainLabel(in: row)
            XCTAssertEqual(firstStepInk(chain), ink.resolvedColor(with: traits), "on: \(isOn): not repainted")
            let step = try XCTUnwrap(chain.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
            XCTAssertGreaterThan(step.pointSize, 14, "on: \(isOn)")
            XCTAssertLessThanOrEqual(step.pointSize, 14 * AppTypography.maximumScale, "on: \(isOn)")
        }
    }

    // MARK: - Assertions

    private func assertMainGeometry(in sut: CreateAlarmViewController, on screen: CGFloat, _ name: String) throws {
        for (row, height) in Self.mainRowHeights(on: screen) {
            XCTAssertEqual(sut.tableView.rectForRow(at: row).height, height, accuracy: 0.01, "\(name): row \(row)")
        }
        for pinned in Self.mainFrames(on: screen) {
            let cell = try hostedCell(pinned.row, of: sut)
            let view = try spot(pinned.text, in: cell)
            let frame = view.convert(view.bounds, to: cell.contentView)
            let edges: KeyValuePairs<String, (CGRect) -> CGFloat> = [
                "x": { $0.minX }, "y": { $0.minY }, "width": { $0.width }, "height": { $0.height }
            ]
            for (edge, value) in edges {
                XCTAssertEqual(
                    value(frame), value(pinned.frame), accuracy: 0.01, "\(name): «\(pinned.text)» \(edge) moved"
                )
            }
        }
        // The 56pt frame is wider than «9 мин»: a reading left aligned would
        // move its glyphs without moving the frame.
        let reading = try label("9 мин", in: hostedCell(Self.snooze, of: sut))
        XCTAssertEqual(reading.textAlignment, .right, "\(name): the reading lost its right alignment")
    }

    private func assertGrownEditor(_ sut: CreateAlarmViewController, on screen: CGFloat, _ name: String) throws {
        XCTAssertEqual(sut.traitCollection.preferredContentSizeCategory, Self.ax5, "\(name): the override did not land")
        for (row, height) in Self.mainRowHeights(on: screen) {
            XCTAssertGreaterThan(
                sut.tableView.rectForRow(at: row).height, height + 20, "\(name): row \(row) kept its size"
            )
            let cell = try hostedCell(row, of: sut)
            XCTAssertEqual(cell.bounds.height, sut.tableView.rectForRow(at: row).height, accuracy: 1, name)
            assertNothingClipped(in: cell, atLeast: 1)
        }
        let soundRow = try hostedCell(Self.sound, of: sut)
        let title = try label(Localized.text("create_alarm.sound.title"), in: soundRow)
        let value = try XCTUnwrap(
            descendants(of: UILabel.self, in: soundRow.contentView).first { $0 !== title && !$0.isHidden }
        )
        XCTAssertGreaterThanOrEqual(value.frame.minY, title.frame.maxY, "\(name): the sound name beside the title")
        let progressiveRow = try hostedCell(Self.progressive, of: sut)
        let toggle = try XCTUnwrap(descendants(of: SPSwitch.self, in: progressiveRow.contentView).first)
        let chain = try chainLabel(in: progressiveRow)
        XCTAssertGreaterThanOrEqual(
            toggle.frame.minY, chain.convert(chain.bounds, to: progressiveRow.contentView).maxY,
            "\(name): the progressive switch beside the column"
        )
        let snoozeRow = try hostedCell(Self.snooze, of: sut)
        let hint = try label(Localized.text("create_alarm.snooze.hint"), in: snoozeRow)
        let reading = try label("9 мин", in: snoozeRow)
        XCTAssertGreaterThanOrEqual(reading.frame.minY, hint.frame.maxY, "\(name): the reading beside the hint")
        XCTAssertEqual(reading.textAlignment, .natural, "\(name): the reading is drawn at the right edge")
    }

    private func assertStacked(
        _ row: UITableViewCell, title titleText: String, value valueText: String,
        _ category: UIContentSizeCategory, _ screen: CGFloat
    ) throws {
        override(row, to: category)
        layOut(row, width: Self.cardWidth(screen))
        let name = "«\(valueText)», \(category.rawValue) at \(screen)"
        let title = try label(titleText, in: row)
        let value = try label(valueText, in: row)
        let chevron = try XCTUnwrap(
            descendants(of: UIImageView.self, in: row.contentView).max { $0.frame.maxX < $1.frame.maxX }
        )
        XCTAssertGreaterThan(try attributedFont(of: title).pointSize, AppTypography.bodyLg.pointSize, name)
        XCTAssertLessThanOrEqual(try attributedFont(of: title).pointSize, AppTypography.bodyLg.pointSize * 2, name)
        XCTAssertGreaterThan(value.font.pointSize, AppTypography.meta.pointSize, name)
        XCTAssertGreaterThanOrEqual(value.frame.minY, title.frame.maxY, "\(name): the name beside the title")
        XCTAssertEqual(value.frame.minX, title.frame.minX, accuracy: 0.01, name)
        XCTAssertLessThanOrEqual(
            value.frame.maxX, chevron.frame.minX - AppSpacing.sp2 + 0.5, "\(name): under the chevron"
        )
        XCTAssertLessThanOrEqual(value.frame.maxY, row.contentView.bounds.maxY - AppSpacing.sp3 + 0.5, name)
        XCTAssertEqual(title.numberOfLines, 1, name)
        // As in iOS Settings: the icon or thumbnail stays on the title's
        // line, not in the middle of a row now two lines tall. Measured by
        // its alignment rect — a symbol's frame is not centred on it.
        let icon = try XCTUnwrap(row.contentView.subviews.min { $0.frame.minX < $1.frame.minX })
        let iconRect = { icon.alignmentRect(forFrame: icon.frame) }
        XCTAssertEqual(iconRect().midY, title.frame.midY, accuracy: 0.5, "\(name): the icon left the title's line")
        XCTAssertGreaterThanOrEqual(iconRect().minY, 0, "\(name): the icon runs off the row")
        assertNothingClipped(in: row, atLeast: 2)

        // The same cell back at `.large` (the hosted table hands out other
        // instances after a category change): one 48pt line again.
        override(row, to: .large)
        layOut(row, width: Self.cardWidth(screen))
        XCTAssertEqual(fitted(row.contentView, width: Self.cardWidth(screen)), 48, accuracy: 0.01, "\(name) → .large")
        XCTAssertEqual(value.numberOfLines, 1, "\(name) → .large")
        XCTAssertEqual(value.frame.midY, title.frame.midY, accuracy: 0.5, "\(name) → .large: the name stayed under")
        XCTAssertEqual(iconRect().midY, row.contentView.bounds.midY, accuracy: 0.5, "\(name) → .large: the icon")
    }

    private func assertStackedProgressiveCard(
        isOn: Bool, _ category: UIContentSizeCategory, _ screen: CGFloat
    ) throws {
        let row = ProgressiveScaleCell(style: .default, reuseIdentifier: nil)
        row.configure(isOn: isOn, chain: [1000, 2000, 4000, 8000], currency: .rub, accessibilityChain: "")
        override(row, to: category)
        let width = Self.cardWidth(screen)
        layOut(row, width: width)
        let name = "\(category.rawValue) at \(screen), on: \(isOn)"
        let edge = width - AppSpacing.cardHorizontalPadding
        let title = try label(Localized.text("create_alarm.progressive.title"), in: row)
        let flame = try XCTUnwrap(descendants(of: UIImageView.self, in: row.contentView).first)
        let chain = try chainLabel(in: row)
        let toggle = try XCTUnwrap(descendants(of: SPSwitch.self, in: row.contentView).first)
        let frame = { (view: UIView) in view.convert(view.bounds, to: row.contentView) }

        XCTAssertGreaterThanOrEqual(frame(title).minY, frame(flame).maxY, "\(name): the flame beside the title")
        XCTAssertLessThanOrEqual(frame(title).maxX, edge + 0.5, "\(name): the title runs off the card")
        XCTAssertEqual(frame(chain).maxX, edge, accuracy: 0.5, "\(name): the column is not the card's width")
        XCTAssertGreaterThanOrEqual(frame(toggle).minY, frame(chain).maxY, "\(name): the switch beside the column")
        XCTAssertEqual(frame(toggle).minX, AppSpacing.cardHorizontalPadding, accuracy: 0.01, name)
        XCTAssertLessThanOrEqual(frame(toggle).maxY, row.contentView.bounds.maxY - AppSpacing.sp5 + 0.5, name)
        XCTAssertEqual(chain.numberOfLines, 0, name)
        XCTAssertFalse(chain.adjustsFontSizeToFitWidth, "\(name): the chain shrinks instead of wrapping")
        // Groups split by U+00A0 and the sign by U+202F, both no-break: the
        // chain may wrap only at the plain spaces around its arrows.
        let text = chain.attributedText?.string ?? ""
        XCTAssertEqual(
            text, "1\u{00A0}000 → 2\u{00A0}000 → 4\u{00A0}000 → 8\u{00A0}000\u{202F}₽",
            "\(name): \(text.unicodeScalars.map { String($0.value, radix: 16) })"
        )
        let step = try XCTUnwrap(chain.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertGreaterThan(step.pointSize, 14, "\(name): the chain did not grow")
        if category == Self.ax5 && screen == 375 {
            XCTAssertGreaterThan(chain.bounds.height, step.lineHeight * 1.5, "\(name): the chain did not wrap")
        }
        XCTAssertGreaterThan(try attributedFont(of: title).pointSize, AppTypography.h4.pointSize, name)
        assertNothingClipped(in: row, atLeast: 3)

        // The same cell back at `.large`: the switch beside the column, the
        // flame beside the title, the chain one shrinking line.
        override(row, to: .large)
        layOut(row, width: width)
        let back = "\(name) → .large"
        XCTAssertEqual(frame(toggle).minY, AppSpacing.sp5, accuracy: 0.01, "\(back): the switch stayed under")
        // Main's x (254 / 281): the switch's frame overhangs the padding by 2pt.
        XCTAssertEqual(frame(toggle).minX, width - 81, accuracy: 0.01, back)
        XCTAssertLessThanOrEqual(frame(flame).maxX, frame(title).minX, "\(back): the flame stayed above")
        XCTAssertEqual(chain.numberOfLines, 1, back)
        XCTAssertTrue(chain.adjustsFontSizeToFitWidth, back)
    }

    private func assertNothingClipped(
        in cell: UITableViewCell, atLeast count: Int, file: StaticString = #filePath, line: UInt = #line
    ) {
        let labels = descendants(of: UILabel.self, in: cell.contentView)
            .filter { !$0.isHidden && !($0.attributedText?.string ?? "").isEmpty }
        XCTAssertGreaterThanOrEqual(labels.count, count, "too few labels to say anything", file: file, line: line)
        for label in labels {
            XCTAssertFalse(
                isClipped(label), "«\(label.attributedText?.string ?? "")» is clipped: \(label.bounds)",
                file: file, line: line
            )
        }
    }

    // MARK: - Harness

    private static func cardWidth(_ screen: CGFloat) -> CGFloat {
        // `.insetGrouped` leaves 20pt either side on both phones (measured).
        screen - 40
    }

    /// The editor, cold, in a real window at `category`: a rouble wallet,
    /// injected defaults, a 9-minute snooze, every row on screen.
    private func mount(width: CGFloat, category: UIContentSizeCategory) -> CreateAlarmViewController {
        let defaults = makeIsolatedDefaults()
        let viewModel = CreateAlarmViewModel(
            alarm: nil,
            repository: AlarmRepository(defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler()),
            defaults: AlarmDefaults(defaults: defaults),
            balanceService: BalanceService(defaults: defaults, notificationCenter: NotificationCenter()),
            backendMonitor: AlarmBackendMonitor(
                probe: AlarmsListBackendGuardTests.StubProbe(result: .available),
                notificationCenter: NotificationCenter()
            ),
            priceContext: .scale(.rouble)
        )
        viewModel.snoozeMinutes = 9
        let sut = CreateAlarmViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 4000))
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        // `mainFrames` is in thirds of a point, measured on a 3× iPhone 17
        // simulator (iOS 27.0); a 2× device rounds to other pixels.
        XCTAssertEqual(window.windowScene?.screen.scale, 3, "pinned in 3x pixels")
        override(window, to: category)
        window.rootViewController = sut
        window.isHidden = false
        hostWindows.append(window)
        window.layoutIfNeeded()
        sut.tableView.layoutIfNeeded()
        XCTAssertEqual(sut.view.bounds.width, width, "the window was not laid out at \(width)")
        XCTAssertEqual(sut.traitCollection.preferredContentSizeCategory, category, "the editor missed the override")
        return sut
    }

    /// The window's category changes under the running editor.
    private func setCategory(_ category: UIContentSizeCategory, of sut: CreateAlarmViewController) throws {
        let window = try XCTUnwrap(sut.view.window)
        override(window, to: category)
        window.layoutIfNeeded()
        sut.tableView.layoutIfNeeded()
        XCTAssertEqual(sut.traitCollection.preferredContentSizeCategory, category, "the editor missed the change")
    }

    /// The point size of every font run of every visible label in the five
    /// rows, keyed by row and text.
    private func runSizes(in sut: CreateAlarmViewController) throws -> [String: [CGFloat]] {
        var sizes: [String: [CGFloat]] = [:]
        for row in [Self.snooze, Self.sound, Self.theme, Self.vibration, Self.progressive] {
            let cell = try hostedCell(row, of: sut)
            for label in descendants(of: UILabel.self, in: cell.contentView) {
                guard !label.isHidden, let text = label.attributedText, text.length > 0 else { continue }
                var runs: [CGFloat] = []
                text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { font, _, _ in
                    runs.append(((font as? UIFont) ?? label.font).pointSize)
                }
                sizes["\(row.section).\(row.row) \(text.string)"] = runs
            }
        }
        return sizes
    }

    private func hostedCell(_ row: IndexPath, of sut: CreateAlarmViewController) throws -> UITableViewCell {
        try XCTUnwrap(sut.tableView.cellForRow(at: row), "row \(row) is not on screen")
    }

    /// A label by its text, the sound / theme row's trailing name («value»)
    /// or leading icon / thumbnail («icon»), the progressive chain, or the
    /// row's switch or slider.
    private func spot(_ text: String, in cell: UITableViewCell) throws -> UIView {
        switch text {
        case "switch": return try XCTUnwrap(descendants(of: SPSwitch.self, in: cell.contentView).first)
        case "slider": return try XCTUnwrap(descendants(of: UISlider.self, in: cell.contentView).first)
        case "icon": return try XCTUnwrap(cell.contentView.subviews.min { $0.frame.minX < $1.frame.minX })
        case "chain":
            let chain = try chainLabel(in: cell)
            XCTAssertEqual(chain.attributedText?.string, "50 → 100 → 200 → 400\u{202F}₽")
            return chain
        case "value":
            let labels = descendants(of: UILabel.self, in: cell.contentView).filter { !$0.isHidden }
            XCTAssertEqual(labels.count, 2, "a settings row is a title and a value")
            return try XCTUnwrap(labels.max { $0.frame.minX < $1.frame.minX })
        default: return try label(text, in: cell)
        }
    }

    private func chainLabel(in cell: UITableViewCell) throws -> UILabel {
        try XCTUnwrap(
            descendants(of: UILabel.self, in: cell.contentView).first { $0.text?.contains(" → ") == true },
            "no chain label"
        )
    }

    private func override(_ view: UIView, to category: UIContentSizeCategory) {
        view.traitOverrides.preferredContentSizeCategory = category
        view.updateTraitsIfNeeded()
        XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, category, "override did not land")
    }

    private func layOut(_ cell: UITableViewCell, width: CGFloat) {
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 200)
        cell.layoutIfNeeded()
        cell.frame.size.height = fitted(cell.contentView, width: width)
        cell.layoutIfNeeded()
    }

    private func fitted(_ view: UIView, width: CGFloat) -> CGFloat {
        view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    /// `first`: the slider reading and the range bound read the same at 15,
    /// and the reading is laid out first.
    private func label(_ text: String, in root: UIView, first: Bool = false) throws -> UILabel {
        let matches = descendants(of: UILabel.self, in: root).filter { ($0.attributedText?.string ?? $0.text) == text }
        if !first { XCTAssertLessThanOrEqual(matches.count, 1, "«\(text)» is ambiguous") }
        return try XCTUnwrap(matches.first, "no label «\(text)»")
    }

    /// The font the label actually draws — the attributed run's, where one is set.
    private func attributedFont(of label: UILabel) throws -> UIFont {
        let font = label.attributedText.flatMap { text in
            text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont : nil
        }
        return try XCTUnwrap(font ?? label.font)
    }

    /// As in `AlarmsListDynamicTypeTests`: measured against unlimited lines at
    /// the label's width; a one-line shrink-to-fit label is clipped only when
    /// its minimum scale overflows; a wrapping label is clipped too when one
    /// of its words is wider than the label, since UIKit then breaks it
    /// mid-word.
    private func isClipped(_ label: UILabel) -> Bool {
        if label.numberOfLines == 1 && label.adjustsFontSizeToFitWidth {
            return naturalWidth(of: label) * label.minimumScaleFactor > label.bounds.width + 0.5
        }
        let unlimited = label.textRect(
            forBounds: CGRect(x: 0, y: 0, width: label.bounds.width, height: .greatestFiniteMagnitude),
            limitedToNumberOfLines: 0
        )
        if unlimited.height > label.bounds.height + 0.5 { return true }
        if label.numberOfLines == 1 && naturalWidth(of: label) > label.bounds.width + 0.5 { return true }
        return label.numberOfLines != 1 && widestWord(of: label) > label.bounds.width + 0.5
    }

    /// Splits only where UIKit may break a line: the amounts' U+202F and the
    /// subtitle's U+00A0 keep «1 000 ₽» and «2 раза» one word.
    private func widestWord(of label: UILabel) -> CGFloat {
        guard let text = label.attributedText, text.length > 0 else { return 0 }
        var widest: CGFloat = 0
        var start = 0
        let string = text.string as NSString
        for index in 0...string.length {
            let isBreak = index == string.length || string.character(at: index) == 0x20
            guard isBreak else { continue }
            if index > start {
                let word = text.attributedSubstring(from: NSRange(location: start, length: index - start))
                widest = max(widest, word.size().width)
            }
            start = index + 1
        }
        return widest
    }

    private func naturalWidth(of label: UILabel) -> CGFloat {
        let infinite = CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        return label.textRect(forBounds: infinite, limitedToNumberOfLines: 1).width
    }

    private func descendants<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        root.subviews.flatMap { [$0 as? T].compactMap { $0 } + descendants(of: type, in: $0) }
    }
}
