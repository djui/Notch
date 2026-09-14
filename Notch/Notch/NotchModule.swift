import SwiftUI

@MainActor
protocol NotchModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var symbolName: String { get }
    func expandedView() -> AnyView
}
