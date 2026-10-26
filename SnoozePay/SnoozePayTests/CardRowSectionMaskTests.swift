import UIKit
import XCTest
@testable import SnoozePay

/// Exercise UIKit's section mask, which isolated row renders cannot observe (#739).
@MainActor
final class CardRowSectionMaskTests: XCTestCase {
    private var windows: [UIWindow] = []
    private let heights: [CGFloat] = [44, 52, 80]
    private let styles: [UIUserInterfaceStyle] = [.light, .dark]

    override func tearDown() {
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
        super.tearDown()
    }

    func testDefaultRowsKeepProductionHairlineAndCircularCorners() throws {
        for style in styles {
            for (height, radius) in [(CGFloat(44), CGFloat(22)), (52, 26), (80, 28)] {
                let fixture = section(rows: 3, height: height, style: style)
                for index in 0..<3 {
                    let row = try fixture.row(index)
                    let stroke = try outline(of: row)
                    XCTAssertEqual(row.layer.cornerRadius, radius)
                    XCTAssertEqual(row.layer.cornerCurve, .circular)
                    XCTAssertEqual(stroke.lineWidth, row.hairlineWidth, accuracy: 0.0001)
                    XCTAssertEqual(UIColor(cgColor: try XCTUnwrap(stroke.strokeColor)),
                                   AppColors.stroke1.resolvedColor(with: row.traitCollection))
                    let position = CardRowPosition.resolve(row: index, totalRows: 3)
                    XCTAssertEqual(row.layer.maskedCorners, position.maskedCorners)
                }
            }
        }
    }

    func testSingleRowOutlineSurvivesTheRealSectionMaskInBothThemes() throws {
        for style in styles {
            for height in heights {
                try assertOutlineSurvives(rows: 1, height: height, style: style)
            }
        }
    }

    func testCapAndMiddleOutlinesSurviveTheRealSectionMaskInBothThemes() throws {
        for style in styles {
            for height in heights {
                try assertOutlineSurvives(rows: 3, height: height, style: style)
            }
        }
    }

    func testTwelvePointNegativeControlDetectsAnActiveSectionMask() throws {
        for style in styles {
            let fixture = section(rows: 3, height: 80, style: style, radius: 12)
            for index in [0, 2] {
                let row = try fixture.row(index)
                try installProbe(on: row)
            }
            let tableImage = try render(fixture.window)
            for index in [0, 2] {
                let row = try fixture.row(index)
                let actual = try crop(tableImage, to: row.convert(row.bounds, to: fixture.window))
                let control = try unmaskedControl(for: row, position: index == 0 ? .first : .last, style: style)
                let regions = cornerRegions(of: row.bounds, radius: 12, position: index == 0 ? .first : .last)
                for region in regions {
                    let actualInk = try ink(in: actual, region: region)
                    let controlInk = try ink(in: control, region: region)
                    XCTAssertGreaterThan(controlInk, 1, "negative control must contain a visible arc")
                    let ratio = actualInk / max(controlInk, 0.001)
                    let detail = measurement(row, style: style, actual: actualInk, control: controlInk, ratio: ratio)
                    if ratio >= 0.75 {
                        attach(actual: actual, control: control, name: "negative-\(index)-\(style.rawValue)")
                    }
                    XCTAssertLessThan(ratio, 0.75, "the fixture did not expose the old clipped arc: \(detail)")
                }
            }
        }
    }

    private func assertOutlineSurvives(rows: Int, height: CGFloat, style: UIUserInterfaceStyle) throws {
        let fixture = section(rows: rows, height: height, style: style)
        for index in 0..<rows { try installProbe(on: fixture.row(index)) }
        let tableImage = try render(fixture.window)
        for index in 0..<rows {
            let row = try fixture.row(index)
            let position = CardRowPosition.resolve(row: index, totalRows: rows)
            let actual = try crop(tableImage, to: row.convert(row.bounds, to: fixture.window))
            let control = try unmaskedControl(for: row, position: position, style: style)
            var regions = cornerRegions(of: row.bounds, radius: row.layer.cornerRadius, position: position)
            regions += [CGRect(x: 0, y: height / 3, width: 3, height: height / 3),
                        CGRect(x: row.bounds.width - 3, y: height / 3, width: 3, height: height / 3)]
            for region in regions {
                let actualInk = try ink(in: actual, region: region)
                let controlInk = try ink(in: control, region: region)
                XCTAssertGreaterThan(controlInk, 1, "unmasked control must contain visible outline ink")
                let ratio = actualInk / max(controlInk, 0.001)
                let detail = measurement(row, style: style, actual: actualInk, control: controlInk, ratio: ratio)
                if ratio < 0.90 {
                    attach(actual: actual, control: control, name: "\(position)-\(height)-\(style.rawValue)")
                }
                XCTAssertGreaterThanOrEqual(ratio, 0.90, "section mask clipped the outline: \(detail)")
            }
        }
    }

    private func section(rows: Int, height: CGFloat, style: UIUserInterfaceStyle,
                         radius: CGFloat? = nil) -> CardRowMaskSection {
        let fixture = CardRowMaskSection(rows: rows, height: height, style: style, radius: radius)
        windows.append(fixture.window)
        return fixture
    }

    private func outline(of row: UIView) throws -> CAShapeLayer {
        try XCTUnwrap(row.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first { $0.strokeColor != nil })
    }

    /// Colour and width amplify geometry only; the production-weight test runs before this fixture mutation.
    private func installProbe(on row: CardRowBackgroundView) throws {
        let stroke = try outline(of: row)
        stroke.strokeColor = UIColor.red.cgColor
        stroke.lineWidth = 2
        row.setNeedsLayout()
        row.layoutIfNeeded()
    }

    private func unmaskedControl(for row: CardRowBackgroundView, position: CardRowPosition,
                                 style: UIUserInterfaceStyle) throws -> UIImage {
        let window = CardRowMaskSection.window(size: row.bounds.size, style: style)
        windows.append(window)
        let control = CardRowBackgroundView(position: position, cornerRadius: row.layer.cornerRadius)
        control.frame = window.bounds
        window.addSubview(control)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try installProbe(on: control)
        return try render(window)
    }

    private func cornerRegions(of bounds: CGRect, radius: CGFloat, position: CardRowPosition) -> [CGRect] {
        var regions: [CGRect] = []
        if position == .first || position == .single {
            regions += [CGRect(x: 0, y: 0, width: radius, height: radius),
                        CGRect(x: bounds.width - radius, y: 0, width: radius, height: radius)]
        }
        if position == .last || position == .single {
            regions += [CGRect(x: 0, y: bounds.height - radius, width: radius, height: radius),
                        CGRect(x: bounds.width - radius, y: bounds.height - radius, width: radius, height: radius)]
        }
        return regions
    }

    private func render(_ window: UIWindow) throws -> UIImage {
        window.layoutIfNeeded()
        CATransaction.flush()
        var rendered = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered, "the real window hierarchy must render before comparing masks")
        return image
    }

    private func crop(_ image: UIImage, to rect: CGRect) throws -> UIImage {
        let scaled = CGRect(x: rect.minX * image.scale, y: rect.minY * image.scale,
                            width: rect.width * image.scale, height: rect.height * image.scale)
        let bitmap = try XCTUnwrap(try XCTUnwrap(image.cgImage).cropping(to: scaled))
        return UIImage(cgImage: bitmap, scale: image.scale, orientation: .up)
    }

    /// Integrated excess-red isolates the diagnostic outline from either theme's neutral fill/shadows.
    /// Summing a corner region tolerates subpixel alignment without ignoring a missing stretch of arc.
    private func ink(in image: UIImage, region: CGRect) throws -> Double {
        let bitmap = try XCTUnwrap(try crop(image, to: region).cgImage)
        let count = bitmap.width * bitmap.height
        var rgba = [UInt8](repeating: 0, count: count * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        }
        var sum = 0.0
        for pixel in 0..<count {
            let offset = pixel * 4
            sum += Double(max(0, Int(rgba[offset]) - Int(max(rgba[offset + 1], rgba[offset + 2])))) / 255
        }
        return sum / Double(image.scale * image.scale)
    }

    private func measurement(_ row: UIView, style: UIUserInterfaceStyle,
                             actual: Double, control: Double, ratio: Double) -> String {
        "style=\(style.rawValue) bounds=\(row.bounds) radius=\(row.layer.cornerRadius) "
            + "actualInk=\(actual) controlInk=\(control) ratio=\(ratio)"
    }

    private func attach(actual: UIImage, control: UIImage, name: String) {
        for (suffix, image) in [("actual", actual), ("control", control)] {
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(name)-\(suffix)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

@MainActor
private final class CardRowMaskSection: NSObject, UITableViewDataSource, UITableViewDelegate {
    let window: UIWindow
    private let table: UITableView
    private let rows: Int
    private let radius: CGFloat?

    init(rows: Int, height: CGFloat, style: UIUserInterfaceStyle, radius: CGFloat?) {
        self.rows = rows
        self.radius = radius
        window = Self.window(size: CGSize(width: 390, height: CGFloat(rows) * height + 80), style: style)
        table = UITableView(frame: window.bounds, style: .insetGrouped)
        super.init()
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.backgroundColor = AppColors.bg0
        controller.view.addSubview(table)
        table.frame = controller.view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.contentInsetAdjustmentBehavior = .never
        table.rowHeight = height
        table.estimatedRowHeight = 0
        table.sectionHeaderHeight = 24
        table.sectionFooterHeight = 24
        table.sectionHeaderTopPadding = 0
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        window.makeKeyAndVisible()
        table.reloadData()
        window.layoutIfNeeded()
        table.layoutIfNeeded()
    }

    func row(_ index: Int) throws -> CardRowBackgroundView {
        let cell = try XCTUnwrap(table.cellForRow(at: IndexPath(row: index, section: 0)))
        return try XCTUnwrap(cell.backgroundView as? CardRowBackgroundView)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.contentView.backgroundColor = .clear
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let position = CardRowPosition.resolve(row: indexPath.row, totalRows: rows)
        if let radius {
            cell.styleAsCardRow(position: position, cornerRadius: radius)
        } else {
            cell.styleAsCardRow(position: position)
        }
    }

    static func window(size: CGSize, style: UIUserInterfaceStyle) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = style
        window.backgroundColor = AppColors.bg0
        return window
    }
}
