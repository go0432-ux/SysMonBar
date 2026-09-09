import AppKit

enum MenuBarLabelImage {
    struct Metric {
        let name: String
        let symbol: String
        let usage: Double
    }

    static func make(metrics: [Metric]) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let height: CGFloat = 22
        let iconWidth: CGFloat = 20
        let iconGap: CGFloat = 2
        let metricGap: CGFloat = 5
        // Size each value to its content; do not leave a blank digit before 11%.
        let values = metrics.map { String(format: "%.0f%%", $0.usage) as NSString }
        let valueWidths = values.map { ceil($0.size(withAttributes: attributes).width) }
        let width = valueWidths.reduce(0, +) + CGFloat(metrics.count) * (iconWidth + iconGap)
            + CGFloat(max(0, metrics.count - 1)) * metricGap
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (index, metric) in metrics.enumerated() {
                if let symbol = NSImage(systemSymbolName: metric.symbol, accessibilityDescription: metric.name)?
                    .withSymbolConfiguration(.init(pointSize: 16, weight: .medium)) {
                    let scale = min(iconWidth / symbol.size.width, height / symbol.size.height)
                    let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                    symbol.draw(in: NSRect(x: x + (iconWidth - size.width) / 2,
                                          y: (height - size.height) / 2,
                                          width: size.width, height: size.height))
                }
                let value = values[index]
                let size = value.size(withAttributes: attributes)
                value.draw(at: NSPoint(x: x + iconWidth + iconGap,
                                       y: (height - size.height) / 2), withAttributes: attributes)
                x += iconWidth + iconGap + valueWidths[index] + metricGap
            }
            return true
        }
        // macOS tints the label for light/dark menu bars and selection.
        image.isTemplate = true
        return image
    }
}
