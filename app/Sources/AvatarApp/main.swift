import AppKit
import AvatarCore

/// Usage: Perch [--pack <dir>] [--ppp <points per image pixel, default 0.2>]
func argValue(_ flag: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let perchHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".perch")
let bundledPack = Bundle.main.resourceURL?.appendingPathComponent("packs/\(PackResolver.bundledId)")
guard let packURL = PackResolver.resolve(explicit: argValue("--pack"), home: perchHome, bundled: bundledPack) else {
    fputs("Perch: no pack found (looked in ~/.perch/config.json, ~/.perch/packs, and the app bundle)\n", stderr)
    let alert = NSAlert()
    alert.messageText = "Perch can't find a character pack"
    alert.informativeText = "Reinstall Perch, or put a pack in ~/.perch/packs and select it in ~/.perch/config.json."
    alert.runModal()
    exit(1)
}
let pointsPerPixel = argValue("--ppp").flatMap(Double.init) ?? 0.2

let app = NSApplication.shared
let controller = AppController(packDir: packURL, pointsPerPixel: pointsPerPixel)
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
