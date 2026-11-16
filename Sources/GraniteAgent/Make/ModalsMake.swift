//  WHAT: `make: modals`: ModalService (sheets, alerts, toasts, travelling panels, Mac windows), its host views, and
//        `modalHosted()` made real, so the root view that applies it presents them. With `toasts: window` the toasts
//        show on iOS in a window of their own one level above alerts; without it the files are as they were.

import Foundation

struct ModalsMake {
    let input: GraniteAppAgent.Input
    let workspace: Workspace

    func plan() throws -> Plan {
        guard workspace.project != nil else {
            throw GraniteError.refused(["modals are an app's: call it in the folder with the app's .xcodeproj"])
        }
        if input.toastDesign != nil && input.toasts != .window {
            throw GraniteError.refused(["`toastDesign` is the type of the toasts' own window: add `toasts: window`, or leave it out"])
        }
        let index = ProjectIndex(root: workspace.root)
        let layout = AppLayout.detect(workspace)
        var plan = Plan()
        let windowed = input.toasts == .window
        for (path, text) in ModalTemplates.service {
            var text = text
            if windowed {
                switch path {
                case "ModalService.swift": text = ModalTemplates.windowModalService
                case "Models/ModalToast.swift": text = ModalTemplates.windowToast
                case "Views/ModalToastView.swift": text = ModalTemplates.windowToastView(design: input.toastDesign)
                default: break
                }
            }
            plan.write(layout.services.appendingPathComponent("ModalService/\(path)"), text)
        }
        let hosting = index.swiftFiles.first { url in
            (try? String(contentsOf: url, encoding: .utf8))?.contains("func modalHosted()") == true
        } ?? layout.utility.appendingPathComponent("ModalHosting.swift")
        plan.write(hosting, windowed ? ModalTemplates.windowHosting : ModalTemplates.hosting)
        if let (folder, module) = try workspace.unitTests() {
            plan.write(folder.appendingPathComponent("ModalOpsTests.swift"), ModalTemplates.tests(module: module), role: .tests)
        }
        if !index.hasRelayClock { plan.write(layout.utility.appendingPathComponent("RelayClock.swift"), UtilityTemplates.relayClock) }
        if let (file, text) = workspace.rootAdding("ModalService", as: "modals", index: index, plan: plan) { plan.write(file, text) }

        plan.types = ["ModalService", "ModalHosting", "ModalSheetHost", "ModalAlertHost", "ModalToastView", "ModalPanelView"]
            + (windowed ? ["ModalToastStack", "ModalToastWindow"] : [])
        if windowed {
            plan.notes.append("on iOS the toasts show in a window of their own one level above alerts (`.alert + 1`), over every sheet and alert, "
                              + "and a touch anywhere but on a toast passes through to the app; the Mac keeps them over the root view. Each toast is a card as wide "
                              + "as the screen, its style's symbol at 22 beside the message (headline) over its subtitle (caption, secondary) in "
                              + (input.toastDesign.map { "the \($0.rawValue) design" } ?? "the system's design") + ", on the ultra-thin material, rounded at 24, "
                              + "sliding in from the top on `.spring(response: 0.4, dampingFraction: 0.8)`; the four styles: success `checkmark.circle.fill` green, "
                              + "error `xmark.circle.fill` red, warning `exclamationmark.triangle.fill` orange, info `info.circle.fill` blue. "
                              + "`modals.toast(\"Category created!\", subtitle: \"And assigned to your note\", style: .success)` gives the second line")
        }
        plan.notes.append("present from any page or service: `modals.sheet(id: \"compose\", detents: [.medium, .large]) { … }`, `modals.alert(ModalAlert(title: …))`, `modals.toast(\"Saved\", style: .success)`, `modals.travel(id: \"draft\", title: \"Draft\") { … }`, and on the Mac `modals.window(id:title:) { … }`")
        if !(index.swiftFiles.contains { (try? String(contentsOf: $0, encoding: .utf8))?.contains(".modalHosted()") == true }) {
            plan.notes.append("no view applies `.modalHosted()` yet: the root view applies it once, so the modals show")
        }
        return plan
    }
}
