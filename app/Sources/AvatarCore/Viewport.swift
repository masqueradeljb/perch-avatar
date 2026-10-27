/// Maps page-viewport coordinates (browser automation such as Claude in Chrome) to screen points.
public enum Viewport {
    /// Tab strip + toolbar above the page in Chrome without a bookmarks bar, in points.
    public static let defaultTopInset = 87.0

    public static func toScreen(x: Double, y: Double, window: Rect, topInset: Double) -> (x: Double, y: Double) {
        (window.x + x, window.y + topInset + y)
    }
}
