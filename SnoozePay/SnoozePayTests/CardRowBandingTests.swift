import UIKit
import XCTest
@testable import SnoozePay

/// Light-theme banding on `.insetGrouped` card sections (#515).
///
/// The reported symptom was a striped card: the first and last row of every
/// section filled `#F0F1F2` while the middle rows stayed `#FFFFFF`, and dark
/// was uniform. The lead pointed at `.secondarySystemBackground` in the cells,
/// but that colour is `#F2F2F7` and `styleAsCardRow` overwrites the cell's own
/// `backgroundColor` with `.clear` in `willDisplay` anyway.
///
/// The actual source is the ambient stop of `--sp-shadow-1`. Only section caps
/// carry it (`CardRowBackgroundView` skips it for `.middle`), it is a
/// clear-filled `CAShapeLayer` sublayer, and Core Animation draws a layer's
/// shadow *above* whatever is already composited behind it — so the blurred
/// silhouette's solid interior landed on the card fill rather than only
/// haloing around it. Dark drops the ambient layer entirely, which is why the
/// stripes were light-only.
@MainActor
final class CardRowBandingTests: XCTestCase {

    /// Rows only resolve their theme through a real hierarchy, so every
    /// subject is hosted in a window that outlives the assertion.
    private var hostWindows: [UIWindow] = []

    override func tearDown() {
        hostWindows.forEach { $0.isHidden = true }
        hostWindows.removeAll()
        super.tearDown()
    }

    // MARK: - The decoration must not paint over the surface it decorates

    func testAmbientStop_isMaskedOutOfTheCardSurface() throws {
        let row = laidOutRow(position: .first, style: .light)
        let ambient = try XCTUnwrap(
            ambientLayer(of: row),
            "a light section cap should carry the ambient shadow-1 stop"
        )
        let mask = try XCTUnwrap(
            ambient.mask as? CAShapeLayer,
            "an unmasked ambient stop washes the card it is supposed to lift"
        )
        let path = try XCTUnwrap(mask.path)
        let spread = AppShadow.ambientShadow1Spread

        let insideTheCard = CGPoint(x: spread + row.bounds.midX, y: spread + row.bounds.midY)
        XCTAssertFalse(
            path.contains(insideTheCard, using: .evenOdd),
            "the ambient stop must not composite over the row's own fill"
        )

        // Sampled ABOVE a `.first` row, not below it. Below a section cap is
        // the next row's own `bg1`, so the stop must NOT halo there — that is
        // the seam, and #674 is exactly the decoration that used to land in
        // it. The outward direction for a `.first` row is up.
        let outsideTheCard = CGPoint(x: spread + row.bounds.midX, y: spread + row.bounds.minY - 2)
        XCTAssertTrue(
            path.contains(outsideTheCard, using: .evenOdd),
            "…but the halo around the card is the whole point of the stop"
        )
    }

    /// The measured version of the same claim, through the render path that can
    /// actually see a shadow: on a cap row, the corner in the seam and the
    /// centre of the row are the same colour.
    func testCapRowCorners_renderTheSameFillAsItsCentre() throws {
        let renderPath = try shadowCapableRenderPath()
        for position in [CardRowPosition.first, .last] {
            let row = laidOutRow(position: position, style: .light)
            let window = try XCTUnwrap(row.window)
            let inset: CGFloat = 3
            let seamY = position == .first
                ? window.bounds.maxY - inset
                : window.bounds.minY + inset

            let centre = pixel(of: window, at: self.centre(of: window), using: renderPath)
            for x in [window.bounds.minX + inset, window.bounds.maxX - inset] {
                let corner = pixel(of: window, at: CGPoint(x: x, y: seamY), using: renderPath)
                assertSameColour(
                    corner,
                    centre,
                    "\(position) seam corner at x=\(x) vs the row's centre"
                )
            }
        }
    }

    /// The asymmetry that turned a wash into visible stripes: caps carry the
    /// ambient stop, middles never do.
    func testMiddleRows_carryNoAmbientStop() {
        XCTAssertNil(ambientLayer(of: laidOutRow(position: .middle, style: .light)))
    }

    func testDarkRows_carryNoAmbientStop() {
        for position in [CardRowPosition.first, .middle, .last, .single] {
            XCTAssertNil(
                ambientLayer(of: laidOutRow(position: position, style: .dark)),
                "\(position) in dark must stay on the single deep stop"
            )
        }
    }

    // MARK: - Measured fill

    /// The assertion the issue actually asks for: a cap row and a middle row of
    /// the same section must render the same fill, in both themes.
    func testCapRowAndMiddleRow_renderTheSameFill_inBothThemes() throws {
        let path = try shadowCapableRenderPath()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cap = renderedFill(position: .first, style: style, using: path)
            let middle = renderedFill(position: .middle, style: style, using: path)
            assertSameColour(cap, middle, "cap vs middle row fill in \(style.debugName)")
            assertSameColour(
                cap, AppColors.bg1.resolved(style),
                "cap row fill vs the bg1 token in \(style.debugName)"
            )
        }
    }

    /// Why the issue title says `#F0F1F2` and not `#F2F2F7`: the reported
    /// colour is `bg1` under the ambient stop, not the system grey the lead
    /// blamed. If this ever stops matching, the shadow recipe moved and the
    /// diagnosis above needs rereading.
    func testTheReportedColour_isTheAmbientWashOverBg1_notTheSystemGrey() {
        let wash = UIColor(red: 8.0 / 255.0, green: 14.0 / 255.0, blue: 30.0 / 255.0, alpha: 0.06)
        let washed = channels(composite(wash, over: AppColors.bg1.resolved(.light)))
        XCTAssertEqual(washed.red * 255, 240, accuracy: 0.6, "0xF0")
        XCTAssertEqual(washed.green * 255, 241, accuracy: 0.6, "0xF1")
        XCTAssertEqual(washed.blue * 255, 242, accuracy: 0.6, "0xF2")

        let systemGrey = channels(UIColor.secondarySystemBackground.resolved(.light))
        XCTAssertNotEqual(systemGrey.red * 255, 240, accuracy: 0.6, "#F2F2F7 is a different colour")
    }

    /// The measurement the issue actually describes: **two** stacked rows,
    /// probed in the seam they share.
    ///
    /// Every other fixture in these two files hosts a single row, so the seam
    /// existed only as a coordinate, never as a boundary between two real
    /// surfaces. `path.contains` proves the mask's geometry; only a pixel
    /// proves what a reader sees.
    ///
    /// ## The oracle is differential, twice over
    ///
    /// Each probe is compared against a pixel from the MIDDLE of the same row
    /// in the same frame, not against the `bg1` token. That is not about
    /// jitter — measured, the two oracles return the same number to 14 decimal
    /// places — it is about not depending on a token's VALUE: change `bg1`, or
    /// change how it resolves in the test trait, and a token-based baseline
    /// silently starts measuring something else.
    ///
    /// Then the whole measurement is taken TWICE: once as shipped, and once
    /// with each row's ambient stop re-installed with `openEdges: []` and
    /// `corners: .allCorners` so its mask clips nothing. That reverts the
    /// AMBIENT half only — the key stop's `shadowPath` stays corrected, so
    /// this control is not "the app before #674". The assertion is the GAP between those two numbers,
    /// never an absolute threshold. An absolute threshold would have to be
    /// calibrated on one machine and then trusted on the CI runner, which has
    /// a different simulator, scale and colour profile — and the quantity
    /// being thresholded is a `max` over ~2150 samples, the least stable
    /// statistic available. Both ends are now measured wherever the test runs.
    ///
    /// ## Numbers, and where they came from
    ///
    /// On the PM's simulator, light: **11/255** for the control, **6/255** as
    /// shipped. Dark: 4/255 either way, and that is not a defect — dark
    /// carries no ambient stop at all (`testDarkRows_carryNoAmbientStop`), so
    /// there is no mask for `openEdges` to disable and its 4/255 is the key
    /// stop's own residue. The assertions below say exactly that: a gap in
    /// light, none in dark.
    ///
    /// These figures are recorded for scale only. Nothing asserts them.
    func testTheSeamBetweenTwoRows_rendersAsOneContinuousFill() throws {
        let renderPath = try shadowCapableRenderPath()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let shipped = try seamDeviation(style: style, unmasked: false, using: renderPath)
            let control = try seamDeviation(style: style, unmasked: true, using: renderPath)

            switch style {
            case .dark:
                // Not "the control changed nothing", which is what the two
                // numbers below would say: in dark `cardRows(in:)` finds
                // nothing to re-install on, because there is no ambient
                // sublayer to find. So the invariant is asserted directly, and
                // the two renders stay as a reproducibility check on top.
                XCTAssertTrue(
                    Self.cardRows(in: laidOutSection(style: .dark)).isEmpty,
                    """
                    dark grew an ambient stop. This test's control cannot model that: \
                    re-installing with the row's own dark trait REMOVES the layer rather \
                    than unmasking it — see testDarkRows_carryNoAmbientStop
                    """
                )
                XCTAssertEqual(
                    shipped.deviation, control.deviation, accuracy: 0.5,
                    """
                    two renders of the same dark fixture disagreed: \
                    \(control.deviation)/255 vs \(shipped.deviation)/255
                    """
                )
            default:
                XCTAssertGreaterThanOrEqual(
                    control.deviation - shipped.deviation, Self.seamGap,
                    """
                    \(style.debugName): the ambient mask is not removing the band. \
                    With the mask disabled the seam sits \(control.deviation)/255 from the \
                    row's own centre; as shipped it sits \(shipped.deviation)/255 at \
                    \(shipped.at) (\(hex(shipped.colour))). A section reads as \
                    separately-rounded rows exactly when that band survives — see #674
                    """
                )
            }
        }
    }

    /// How much better the masked seam has to be than the unmasked one.
    ///
    /// Both sides are measured in the same process on the same machine, so
    /// this is a gap between two numbers rather than a threshold on one, and
    /// it does not have to absorb any machine-to-machine variation. What it
    /// does have to clear is sampling noise within one run, and there the only
    /// remaining source is `drawHierarchy(afterScreenUpdates:)` — a render
    /// server round trip that this very file has already seen return a black
    /// frame once (run 33260176424, documented on `probeShadowRed` and
    /// `present`). The two sides are separate frames, so a degenerate one
    /// would NOT cancel out — a black shipped frame reads 0/255, the best
    /// possible deviation, and would satisfy this gap instead of failing it.
    /// That hole is closed inside `seamDeviation`, which makes each frame
    /// prove it rendered `bg1` before its numbers are used.
    ///
    /// The separation measured locally is 11 − 6 = 5/255, so 3 leaves 2/255 of
    /// headroom — 40%, not a multiple. That is not generous, and the reason it
    /// is workable is that both ends are measured in the same process rather
    /// than one being carried between machines.
    ///
    /// The gap does NOT tell the two halves of #674 apart. The control reverts
    /// `corners` and `openEdges` together, so the 5/255 is their sum, and the
    /// `corners` half is worth about 1/255 on its own — a regression in it
    /// alone would move shipped 6 → 7, leave a gap of 4, and pass here. The
    /// `openEdges` half is held separately, at the path level, by
    /// `CardRowSeamShadowTests.testAmbientStop_emitsNoHaloAcrossTheSeam`.
    /// The `corners` half of the AMBIENT mask is held at the path level, by the
    /// two grown-corner probes in
    /// `CardRowSeamShadowTests.testAmbientStop_isMaskedOutOfTheCornersACapRowDoesNotRound`
    /// (#692) — one asserting the squared corners stay square, one asserting the
    /// rounded corners stay rounded. Both are needed: the square probe alone
    /// leaves `corners: []` at the call site green across the whole suite.
    /// That test's original probe — (spread + inset, spread + maxY − inset) —
    /// held neither: with `openEdges` still growing the hole downwards that
    /// point stays inside the hole whichever way `corners` is set. The probes
    /// added for #692 sit in the corners of the GROWN hole instead, which is
    /// the one place the two halves of #674 are separable.
    ///
    /// If a future change makes this red, read both printed numbers before
    /// touching it: the interesting failure is the control collapsing towards
    /// the shipped number, which means the band stopped being there to remove.
    private static let seamGap: CGFloat = 3

    /// The worst deviation anywhere in the seam band, in one rasterisation.
    ///
    /// `unmasked: true` re-installs each row's ambient stop with
    /// `openEdges: []` AFTER layout has settled, so its mask clips nothing —
    /// which is the pre-#674 AMBIENT mask — not the pre-#674 rendering, since
    /// the key stop's `shadowPath` stays corrected on both sides. It is re-applied immediately before
    /// the frame is taken; if a layout pass were to slip in between and put
    /// the real mask back, the control would collapse onto the shipped number
    /// and the gap assertion goes red rather than quietly green.
    private func seamDeviation(
        style: UIUserInterfaceStyle,
        unmasked: Bool,
        using renderPath: RenderPath
    ) throws -> (deviation: CGFloat, at: CGPoint, colour: UIColor) {
        let window = laidOutSection(style: style)
        if unmasked {
            for row in Self.cardRows(in: window) {
                AppShadow.installAmbientShadow1Layer(
                    on: row.layer,
                    cornerRadius: AppRadius.sm,
                    trait: row.traitCollection,
                    corners: .allCorners,
                    openEdges: []
                )
            }
        }
        // ONE frame. `drawHierarchy(afterScreenUpdates:)` is a forced render
        // server round trip, and scanning it per point would compare thousands
        // of independent rasterisations.
        let (bitmap, scale) = try XCTUnwrap(render(window, using: renderPath))
        let referenceColour = sample(bitmap, scale: scale, at: CGPoint(x: window.bounds.midX, y: 26))
        let reference = channels(referenceColour)

        // A degenerate frame reads 0 everywhere, and 0 is the BEST possible
        // deviation — on the shipped side that would satisfy the gap
        // assertion instead of failing it. `drawHierarchy(afterScreenUpdates:)`
        // has returned an all-black frame in this file before (run
        // 33260176424; see `probeShadowRed` and `present`), so each frame has
        // to prove it rendered the card before its numbers are believed.
        let fill = channels(AppColors.bg1.resolved(style))
        XCTAssertEqual(
            reference.red, fill.red, accuracy: 4.0 / 255,
            """
            \(style.debugName): the row's own centre came back \(hex(referenceColour)) \
            instead of bg1 — this frame did not render, and every deviation \
            measured against it is meaningless
            """
        )
        var worst: (deviation: CGFloat, at: CGPoint, colour: UIColor) = (0, .zero, .clear)

        // Both axes. The horizontal one is the half that matters for the
        // corners: `shadowPath` changed only where a cap row is SQUARE — the
        // two ends of the seam — so a probe down the middle cannot see that
        // half of the fix at all, in either theme.
        for offset in stride(from: -6.0, through: 6.0, by: 0.5) {
            for xPos in stride(from: 2.0, through: window.bounds.width - 2, by: 4.0) {
                let point = CGPoint(x: xPos, y: Self.rowHeight + offset)
                let got = channels(sample(bitmap, scale: scale, at: point))
                let deviation = max(
                    abs(got.red - reference.red),
                    abs(got.green - reference.green),
                    abs(got.blue - reference.blue)
                ) * 255
                if deviation > worst.deviation {
                    worst = (deviation, point, sample(bitmap, scale: scale, at: point))
                }
            }
        }
        return worst
    }

    /// The two styled row views inside a `laidOutSection` window.
    private static func cardRows(in view: UIView) -> [UIView] {
        view.subviews.flatMap { subview -> [UIView] in
            let isRow = subview.layer.sublayers?.contains {
                $0.name == AppShadow.ambientShadow1LayerName
            } ?? false
            return isRow ? [subview] : cardRows(in: subview)
        }
    }

    private static let rowHeight: CGFloat = 52

    // MARK: - Fixtures

    private func laidOutRow(
        position: CardRowPosition,
        style: UIUserInterfaceStyle
    ) -> CardRowBackgroundView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 343, height: 52))
        window.overrideUserInterfaceStyle = style
        window.backgroundColor = AppColors.bg0
        present(window)
        hostWindows.append(window)

        let row = CardRowBackgroundView(position: position, cornerRadius: AppRadius.sm)
        row.frame = window.bounds
        window.addSubview(row)
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return row
    }

    /// A real two-row section: `.first` on top of `.last`, edge to edge, the
    /// way `.insetGrouped` stacks them. Returns the WINDOW, because the thing
    /// under test is the boundary between the two rows and not either of them.
    private func laidOutSection(style: UIUserInterfaceStyle) -> UIWindow {
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 343, height: Self.rowHeight * 2)
        )
        window.overrideUserInterfaceStyle = style
        window.backgroundColor = AppColors.bg0
        present(window)
        hostWindows.append(window)

        for (index, position) in [CardRowPosition.first, .last].enumerated() {
            let row = CardRowBackgroundView(position: position, cornerRadius: AppRadius.sm)
            row.frame = CGRect(
                x: 0, y: CGFloat(index) * Self.rowHeight,
                width: window.bounds.width, height: Self.rowHeight
            )
            window.addSubview(row)
        }
        window.setNeedsLayout()
        window.layoutIfNeeded()
        return window
    }

    private func ambientLayer(of row: UIView) -> CAShapeLayer? {
        row.layer.sublayers?
            .first { $0.name == AppShadow.ambientShadow1LayerName } as? CAShapeLayer
    }

    /// Composite the row over its page and read the pixel at the row's centre.
    private func renderedFill(
        position: CardRowPosition,
        style: UIUserInterfaceStyle,
        using path: RenderPath
    ) -> UIColor {
        let row = laidOutRow(position: position, style: style)
        guard let window = row.window else {
            XCTFail("the row lost its host window")
            return .clear
        }
        return pixel(
            of: window,
            at: CGPoint(x: window.bounds.midX, y: window.bounds.midY),
            using: path
        )
    }

    /// How the sample bitmap is produced. Two paths, because they do not see
    /// the same thing.
    private enum RenderPath {
        /// Through the render server. Composites shadows.
        case hierarchy
        /// Straight off the layer tree. Documented not to render shadows —
        /// which is why this file used to skip its only measured case.
        case layer
    }

    /// The render path that can actually see a shadow here, or a failure
    /// (#568).
    ///
    /// This used to be a `XCTSkipUnless(rendererReproducesShadows())` over the
    /// layer path alone, and `CALayer.render(in:)` does not composite shadows —
    /// so the guard was true on every run and the one case in this file that
    /// measures pixels never executed once. The probe is still honest about what
    /// it can see; it tries the render server first instead of giving up, and
    /// says so in red if neither path works.
    ///
    /// It also asks two questions rather than one. The single question "did the
    /// pixel come back dark?" is satisfied by a *broken* render just as well as
    /// by a shadow: run 33260176424 had `drawHierarchy` return #000000 for a
    /// window the render server was not presenting, and the probe called that
    /// success.
    private func shadowCapableRenderPath() throws -> RenderPath {
        var seen: [String] = []
        for candidate in [RenderPath.hierarchy, .layer] {
            // Two questions, and asking only the second one is how this probe
            // fooled itself: does the path render a plain white window as
            // white, and does adding an opaque shadow then darken it?
            let blank = probeShadowRed(using: candidate, withShadow: false)
            let shadowed = probeShadowRed(using: candidate)
            seen.append("\(candidate) → blank \(blank), shadowed \(shadowed)")
            if blank > 0.9 && shadowed < 0.5 { return candidate }
        }
        XCTFail(
            "no render path both reproduced a blank white window and darkened it under an "
            + "opaque shadow (\(seen.joined(separator: "; "))) — this measurement cannot see "
            + "the defect. Fix the harness; do not skip"
        )
        throw HarnessFailure.noShadowCapableRenderPath
    }

    private enum HarnessFailure: Error {
        case noShadowCapableRenderPath
    }

    /// A clear-filled shape layer with an opaque shadow over white: if the
    /// renderer sees shadows at all, the centre pixel comes back dark.
    private func probeShadowRed(using renderPath: RenderPath, withShadow: Bool = true) -> CGFloat {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        window.backgroundColor = .white
        present(window)
        hostWindows.append(window)

        guard withShadow else {
            // Baseline: the same white window with nothing on it. A path that
            // cannot even reproduce this is rendering garbage, and a garbage
            // bitmap is dark — which is indistinguishable from "sees a shadow"
            // unless it is asked separately. Measured the hard way in run
            // 33260176424, where `drawHierarchy` on a non-key window returned
            // #000000 and the probe read it as success.
            return channels(pixel(of: window, at: centre(of: window), using: renderPath)).red
        }

        let probe = CAShapeLayer()
        probe.frame = window.bounds
        let path = UIBezierPath(rect: window.bounds).cgPath
        probe.path = path
        probe.fillColor = UIColor.clear.cgColor
        probe.shadowPath = path
        probe.shadowColor = UIColor.black.cgColor
        probe.shadowOpacity = 1
        probe.shadowRadius = 0
        probe.shadowOffset = .zero
        window.layer.addSublayer(probe)

        return channels(pixel(of: window, at: centre(of: window), using: renderPath)).red
    }

    private func centre(of view: UIView) -> CGPoint {
        CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    /// Put `window` on screen for real.
    ///
    /// Attaching the scene matters as much as `makeKeyAndVisible()`: in a
    /// scene-based app a window with no `windowScene` is never presented, and
    /// `drawHierarchy(afterScreenUpdates:)` renders a window the server does not
    /// present as solid black.
    private func present(_ window: UIWindow) {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            window.windowScene = scene
        }
        window.makeKeyAndVisible()
    }

    // MARK: - Pixels

    /// Rasterise `view` ONCE.
    ///
    /// `drawHierarchy(afterScreenUpdates: true)` is a forced render-server
    /// round trip, so calling it per sample is both slow and wrong: a scan of
    /// N points would compare N INDEPENDENT rasterisations, which is a lottery
    /// on a test whose whole margin is a few /255. One frame, many samples.
    private func render(_ view: UIView, using renderPath: RenderPath) -> (CGImage, CGFloat)? {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            switch renderPath {
            case .hierarchy:
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            case .layer:
                view.layer.render(in: context.cgContext)
            }
        }
        guard let bitmap = image.cgImage else {
            XCTFail("rendering produced no bitmap")
            return nil
        }
        return (bitmap, image.scale)
    }

    private func sample(_ bitmap: CGImage, scale: CGFloat, at point: CGPoint) -> UIColor {
        let x = min(max(Int(point.x * scale), 0), bitmap.width - 1)
        let y = min(max(Int(point.y * scale), 0), bitmap.height - 1)
        guard let cropped = bitmap.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            XCTFail("could not crop the sample pixel")
            return .clear
        }
        return colour(of: cropped)
    }

    /// Kept for the single-sample call sites, which pay for their own frame.
    private func pixel(of view: UIView, at point: CGPoint, using renderPath: RenderPath) -> UIColor {
        guard let (bitmap, scale) = render(view, using: renderPath) else { return .clear }
        return sample(bitmap, scale: scale, at: point)
    }

    private func colour(of sample: CGImage) -> UIColor {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        buffer.initialize(repeating: 0, count: 4)
        defer {
            buffer.deinitialize(count: 4)
            buffer.deallocate()
        }
        guard let context = CGContext(
            data: buffer,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("could not build a 1×1 sampling context")
            return .clear
        }
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UIColor(
            red: CGFloat(buffer[0]) / 255.0,
            green: CGFloat(buffer[1]) / 255.0,
            blue: CGFloat(buffer[2]) / 255.0,
            alpha: CGFloat(buffer[3]) / 255.0
        )
    }

    /// 3/255 of slack absorbs colour-space round-tripping through the
    /// renderer. The banding this file pins measured 15/255 per channel before
    /// #515; the seam wash #674 fixed is softer, so the tolerance is what makes
    /// both readable as "the same fill".
    private func assertSameColour(_ lhs: UIColor, _ rhs: UIColor, _ message: String) {
        let left = channels(lhs)
        let right = channels(rhs)
        let detail = "\(message): \(hex(lhs)) vs \(hex(rhs))"
        XCTAssertEqual(left.red * 255, right.red * 255, accuracy: 3, detail)
        XCTAssertEqual(left.green * 255, right.green * 255, accuracy: 3, detail)
        XCTAssertEqual(left.blue * 255, right.blue * 255, accuracy: 3, detail)
    }

    // MARK: - Colour maths

    private struct Channels {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private func channels(_ color: UIColor) -> Channels {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("colour is not representable in sRGB: \(color)")
            return Channels(red: 0, green: 0, blue: 0, alpha: 1)
        }
        return Channels(red: red, green: green, blue: blue, alpha: alpha)
    }

    private func composite(_ foreground: UIColor, over background: UIColor) -> UIColor {
        let fore = channels(foreground)
        let back = channels(background)
        let alpha = fore.alpha
        return UIColor(
            red: alpha * fore.red + (1 - alpha) * back.red,
            green: alpha * fore.green + (1 - alpha) * back.green,
            blue: alpha * fore.blue + (1 - alpha) * back.blue,
            alpha: 1
        )
    }

    private func hex(_ color: UIColor) -> String {
        let rgb = channels(color)
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.red * 255).rounded()),
            Int((rgb.green * 255).rounded()),
            Int((rgb.blue * 255).rounded())
        )
    }
}

private extension UIColor {
    func resolved(_ style: UIUserInterfaceStyle) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

private extension UIUserInterfaceStyle {
    var debugName: String {
        self == .dark ? "dark" : "light"
    }
}
