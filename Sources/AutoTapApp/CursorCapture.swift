import AppKit
import CoreGraphics

enum CursorCapture {
    static func currentQuartzLocation() -> CGPoint {
        quartzLocation(fromAppKitPoint: NSEvent.mouseLocation)
    }

    static func quartzLocation(fromAppKitPoint appKitPoint: CGPoint) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { screen in
            let frame = screen.frame
            return appKitPoint.x >= frame.minX && appKitPoint.x <= frame.maxX && appKitPoint.y >= frame.minY && appKitPoint.y <= frame.maxY
        }) else {
            return appKitPoint
        }

        let frame = screen.frame
        let clampedY = min(max(appKitPoint.y, frame.minY), frame.maxY)
        let localY = clampedY - frame.minY
        let quartzY = frame.maxY - localY
        return CGPoint(x: appKitPoint.x, y: quartzY)
    }
}
