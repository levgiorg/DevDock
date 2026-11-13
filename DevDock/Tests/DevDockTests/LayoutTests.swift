import AppKit
import SwiftUI
import Testing
@testable import DevDock

/// Measure the row itself under the popover proposal. An outer fixed-width
/// frame would hide oversized child content and miss the original clipping bug.
@MainActor
struct LayoutTests {
    private final class Measurement { var size = CGSize.zero }
    private struct ProposedWidth: Layout {
        let width: CGFloat
        let measurement: Measurement
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let size = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            measurement.size = size
            return size
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }

    private func fixture(stopped: Bool, warning: String? = nil, port: Int = 54333) -> Server {
        var container = ContainerInfo(id: String(repeating: "a", count: 60) + String(format: "%04x", port), name: "database-\(port)", image: "registry.example.com/team/a-very-long-database-image-name:latest", runtime: .dockerDesktop(), publishedPorts: [port], composeProject: "demo-project")
        container.isRunning = !stopped
        return Server(port: port, pid: 12345, rootPid: 12345, processName: "database", addresses: ["127.0.0.1"],
                      cwd: "/tmp/project", cwdExists: true, project: ProjectInfo(name: String(repeating: "long-project-", count: 8)),
                      container: container, controlWarning: warning, processes: [], processStarts: [:], pauseTargets: [:],
                      memory: 0, cpu: 0, connections: 0, history: [], lastActive: Date(), isProtected: true, isPaused: false)
    }

    @Test func stoppedContainerAndLongContextFitBeforeAndDuringHover() {
        let monitor = ServerMonitor()
        let width = Theme.popoverWidth - 12
        for stopped in [false, true] {
            for warning in [nil, String(repeating: "Shared service must be managed in its terminal. ", count: 8)] as [String?] {
                var sizes: [CGSize] = []
                for hovered in [false, true] {
                    let measured = Measurement()
                    let row = ServerRow(server: fixture(stopped: stopped, warning: warning), monitor: monitor, open: {}, isHovered: hovered)
                    let host = NSHostingView(rootView: ProposedWidth(width: width, measurement: measured) { row })
                    host.frame = CGRect(x: 0, y: 0, width: width, height: 60)
                    host.layoutSubtreeIfNeeded()
                    _ = host.fittingSize
                    #expect(measured.size.width <= width + 0.5, "Row content must not push either edge outside the menu-bar popover")
                    #expect(measured.size.width > 0)
                    sizes.append(measured.size)
                }
                #expect(abs(sizes[0].width - sizes[1].width) < 0.5, "Hover must not move or widen the row")
                #expect(abs(sizes[0].height - sizes[1].height) < 0.5)
            }
        }
        if let directory = ProcessInfo.processInfo.environment["DEVDOCK_UI_EVIDENCE"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let fixtureMonitor = ServerMonitor(initialServers: (0..<8).map { fixture(stopped: true, port: 54330 + $0) })
            let app = NSApplication.shared
            app.appearance = NSAppearance(named: .darkAqua)
            let view = ServersView(monitor: fixtureMonitor, openServer: { _ in }, openSettings: {})
                .frame(width: Theme.popoverWidth)
                .background(Theme.popoverBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            let height = NSHostingView(rootView: view).fittingSize.height
            let file = output.appendingPathComponent("stopped-containers.png")
            SnapshotRenderer.renderWindow(view, size: CGSize(width: Theme.popoverWidth, height: height), to: file, styleMask: .borderless)
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func onboardingContainsOnlyLocalSetupAndPrivacySteps() {
        #expect(OnboardingStep.allCases == [.welcome, .leaks, .tools, .terminal, .usage, .done])
        #expect(OnboardingStep(rawValue: OnboardingStep.tools.rawValue + 1) == .terminal)
    }
}
