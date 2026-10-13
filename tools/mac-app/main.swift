// Chums.app: the Mac side's one identity for permissions.
//
//   Open it (double-click)            a window that asks macOS for everything the agents need, once: Allow All
//   Chums <program> [args...]         runs the program (the hub, an agent) as Chums: what it and everything it starts
//                                     ask for (files, screenshots, accessibility, controlling apps) belongs to Chums
//   Chums --check <what> [--ask]      what's granted (bin/chums-permissions check, bin/chums-doctor); see check()
//
// macOS charges a permission to the "responsible" process. An app opened from Finder or started by launchd is
// responsible for itself and what it starts; a program started from a terminal belongs to the terminal. So with
// arguments, Chums first starts a copy of itself that disclaims its parent, and that copy runs the program. Both pass
// SIGTERM, SIGINT, SIGHUP and SIGQUIT on and exit the way the program exited (launchd's KeepAlive and bootout work).
import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import ScreenCaptureKit
import SwiftUI

// MARK: - running a program as Chums

var childPID: pid_t = 0
func passOn(_ sig: Int32) { if childPID > 0 { kill(childPID, sig) } }

func spawn(_ argv: [String], disclaimingParent: Bool) -> Int32 {
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    var none = sigset_t()
    posix_spawnattr_setsigmask(&attr, &none)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSIGMASK))
    if disclaimingParent {
        // responsibility_spawnattrs_setdisclaim: in libsystem since macOS 10.14, not in the public headers
        typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") {
            _ = unsafeBitCast(sym, to: Disclaim.self)(&attr, 1)
        } else {
            FileHandle.standardError.write("Chums: can't disclaim; permissions will go to the parent\n".data(using: .utf8)!)
        }
    }
    var cargs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
    defer { cargs.forEach { free($0) } }
    let err = posix_spawnp(&childPID, cargs[0], nil, &attr, &cargs, environ)
    if err != 0 {
        FileHandle.standardError.write("Chums: can't start \(argv[0]): \(String(cString: strerror(err)))\n".data(using: .utf8)!)
        return 127
    }
    var status: Int32 = 0
    while waitpid(childPID, &status, 0) < 0 && errno == EINTR {}
    let sig = status & 0x7f
    return sig == 0 ? (status >> 8) & 0xff : 128 + sig
}

// MARK: - what's granted

let home = FileManager.default.homeDirectoryForCurrentUser
let controlled: [(id: String, name: String)] = [
    ("com.apple.finder", "Finder"), ("com.apple.systemevents", "System Events"), ("com.apple.Safari", "Safari"),
    ("com.google.Chrome", "Google Chrome"), ("com.apple.mail", "Mail"), ("com.apple.iCal", "Calendar"),
    ("com.apple.reminders", "Reminders"), ("com.apple.Notes", "Notes"), ("com.apple.MobileSMS", "Messages"),
    ("com.apple.Music", "Music"), ("com.apple.Terminal", "Terminal"), ("com.apple.AddressBook", "Contacts"),
    ("com.openai.sky.CUAService", "Codex Computer Use"),
]
/// an app with no window (System Events, Codex Computer Use): opening it to ask shows nothing, so Chums does
func windowless(_ id: String) -> Bool {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), let info = Bundle(url: url)?.infoDictionary else { return false }
    return (info["LSUIElement"] as? Bool) == true || (info["LSBackgroundOnly"] as? Bool) == true
        || (info["LSUIElement"] as? String) == "1" || (info["LSBackgroundOnly"] as? String) == "1"
}
func installed(_ id: String) -> Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil }

func fullDiskAccess() -> Bool {
    (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/Safari").path)) != nil
}
func screenRecording() -> Bool { CGPreflightScreenCaptureAccess() }
func accessibility(ask: Bool = false) -> Bool {
    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: ask] as CFDictionary)
}
/// granted, denied, not-asked or not-running (asking needs the app running)
func automation(_ id: String, ask: Bool = false) -> String {
    var target = AEAddressDesc()
    let status: OSStatus = id.withCString { p in
        _ = AECreateDesc(typeApplicationBundleID, p, strlen(p), &target)
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
    }
    switch status {
    case noErr: return "granted"
    case OSStatus(errAEEventNotPermitted): return "denied"
    case OSStatus(errAEEventWouldRequireUserConsent): return "not-asked"
    case OSStatus(procNotFound): return "not-running"
    default: return "unknown(\(status))"
    }
}
/// reading the folder is what asks ("Chums would like to access files in your Desktop folder")
func folder(_ name: String) -> Bool {
    (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(name).path)) != nil
}

func check(_ args: [String]) -> Int32 {
    let ask = args.contains("--ask")
    let word: String
    switch args.first {
    case "fda": word = fullDiskAccess() ? "granted" : "denied"
    case "screen": word = screenRecording() ? "granted" : "denied"
    case "accessibility": word = accessibility(ask: ask) ? "granted" : "denied"
    case "automation" where args.count > 1: word = automation(args[1], ask: ask)
    case "apps":
        // each installed app in the list: granted, denied, not-asked, or not-open (macOS can't tell until it is)
        for app in controlled where installed(app.id) {
            let st = automation(app.id)
            print("\(st == "not-running" ? "not-open" : st)\t\(app.name)")
        }
        return 0
    default:
        print("usage: Chums --check fda | screen | accessibility [--ask] | automation <bundle id> [--ask] | apps")
        return 64
    }
    print(word)
    return word == "granted" ? 0 : 1
}

// MARK: - the window

/// Finder and System Events are always asked (System Events starts with no window; with Accessibility it is how agents
/// click and type anywhere). Any other listed app is asked too when it's open right now; nothing is opened just to
/// ask, and an app that isn't open asks once, as Chums, the first time an agent uses it.
let required = ["com.apple.finder", "com.apple.systemevents"]
func appsToAsk() -> [(id: String, name: String)] {
    controlled.filter { required.contains($0.id) || (installed($0.id) && windowless($0.id))
        || !NSRunningApplication.runningApplications(withBundleIdentifier: $0.id).isEmpty }
}

enum Step { case folders, apps, accessibility, screen }

/// Asks a fresh copy of Chums. A running process keeps the Screen Recording answer it started with (its connection to
/// the window server), so the window would never see that switch flipped. The copy is Chums too: the answer is Chums's.
func fresh(_ what: String) -> Bool {
    let p = Process()
    p.executableURL = Bundle.main.executableURL
    p.arguments = ["--check", what]
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

final class Permissions: ObservableObject {
    // folders and apps that aren't open can't be read without asking: their last answer is remembered, and every
    // Allow reads them again (a granted folder or app asks nothing; a refused one shows up as refused)
    @Published var folders = UserDefaults.standard.bool(forKey: "folders")
    @Published var allowedApps = Set(UserDefaults.standard.stringArray(forKey: "apps") ?? [])
    @Published var refusedApps: [String: String] = [:]          // bundle id: name
    @Published var accessible = false
    @Published var screen = false
    @Published var disk = false
    @Published var step: Step?          // a step whose macOS dialogs are up
    @Published var waiting: Step?       // a System Settings switch it waits for
    @Published var restarting = false
    @Published var restartedOnce = false
    private var timer: Timer?
    private var skipped = false
    private var refreshing = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        // Allow All restarts the agents at the end; if macOS quit Chums before that (Quit & Reopen), it does it now
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if UserDefaults.standard.bool(forKey: "pendingRestart") && self.allDone {
                UserDefaults.standard.set(false, forKey: "pendingRestart"); self.restartAgents()
            }
        }
    }

    var busy: Bool { step != nil || waiting != nil }
    /// Full Disk Access covers Desktop, Documents and Downloads (and more)
    var foldersDone: Bool { folders || disk }
    var appsDone: Bool { required.allSatisfy(allowedApps.contains) && refusedApps.isEmpty }
    var allDone: Bool { foldersDone && appsDone && accessible && screen }

    /// the switches, read by fresh copies off the main thread; open apps read in place
    func refresh() {
        if refreshing || waiting != nil { return }
        refreshing = true
        let (ka, ks, kd) = (accessible, screen, disk)
        DispatchQueue.global(qos: .utility).async {
            let a = ka || fresh("accessibility"), sc = ks || fresh("screen"), d = kd || fresh("fda")
            DispatchQueue.main.async {
                if self.accessible != a { self.accessible = a }
                if self.screen != sc { self.screen = sc }
                if self.disk != d { self.disk = d }
                if self.step != .apps { for app in appsToAsk() { self.note(app, automation(app.id)) } }
                self.refreshing = false
            }
        }
    }

    /// keeps what macOS says about an app: granted, or refused (only the Automation pane undoes a refusal)
    private func note(_ app: (id: String, name: String), _ state: String) {
        if state == "granted" {
            if !allowedApps.contains(app.id) { allowedApps.insert(app.id); save() }
            if refusedApps[app.id] != nil { refusedApps[app.id] = nil }
        } else if state == "denied" {
            if allowedApps.contains(app.id) { allowedApps.remove(app.id); save() }
            if refusedApps[app.id] == nil { refusedApps[app.id] = app.name }
        } else if state == "not-asked" {                       // asked before, now not: its permissions were reset
            if allowedApps.contains(app.id) { allowedApps.remove(app.id); save() }
            if refusedApps[app.id] != nil { refusedApps[app.id] = nil }
        }
    }
    private func save() { UserDefaults.standard.set(Array(allowedApps), forKey: "apps") }

    /// Desktop, Documents, Downloads: reading each is what asks (once); it waits for the answer
    func askFolders(then next: (() -> Void)? = nil) {
        if disk { next?(); return }
        step = .folders
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = ["Desktop", "Documents", "Downloads"].map(folder).allSatisfy { $0 }
            DispatchQueue.main.async {
                self.folders = ok; UserDefaults.standard.set(ok, forKey: "folders"); self.step = nil
                if !ok { self.openPane("Privacy_FilesAndFolders") }
                next?()
            }
        }
    }

    /// "Chums wants access to control <app>": a dialog for each app not answered yet, each waiting for the answer
    func askApps(then next: (() -> Void)? = nil) {
        step = .apps
        let list = appsToAsk()
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [((id: String, name: String), String)] = []
            for app in list {
                var state = automation(app.id)
                if state == "not-running", windowless(app.id),
                   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) {
                    let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false
                    NSWorkspace.shared.openApplication(at: url, configuration: cfg)
                    for _ in 0..<20 where state == "not-running" { Thread.sleep(forTimeInterval: 0.25); state = automation(app.id) }
                }
                if state == "not-asked" { state = automation(app.id, ask: true) }
                results.append((app, state))
            }
            DispatchQueue.main.async {
                for (app, state) in results { self.note(app, state) }
                self.step = nil
                if !self.refusedApps.isEmpty { self.openPane("Privacy_Automation") }
                next?()
            }
        }
    }

    /// macOS's own alert, which also puts Chums in the Accessibility list; then waits for the switch
    func askAccessibility(then next: (() -> Void)? = nil) {
        if fresh("accessibility") { accessible = true; next?(); return }
        _ = accessibility(ask: true)
        waitFor(.accessibility, until: { fresh("accessibility") }, then: next)
    }

    /// Asking isn't what puts an app in the Screen Recording list: trying to capture is. This does (macOS shows its
    /// alert, and Chums is in the list), then waits for the switch.
    func askScreen(then next: (() -> Void)? = nil) {
        if fresh("screen") { screen = true; captureOnce(); next?(); return }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { _, _ in }
        waitFor(.screen, until: { fresh("screen") }) { if self.screen { self.captureOnce() }; next?() }
    }

    /// macOS 15 and later ask a second question ("Chums is requesting to bypass the system private window picker")
    /// the first time a screenshot is actually taken, not when access is asked for. One screenshot here, the way the
    /// agents take them, so that question comes now, while you're at the Mac. Once answered, it asks nothing.
    func captureOnce() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chums-first-capture.png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", file.path]
        p.terminationHandler = { _ in try? FileManager.default.removeItem(at: file) }
        try? p.run()
    }

    /// every step in order; what's allowed already passes without a dialog. At the end the agents restart once, so
    /// one that was refused something before starts again with everything.
    func allowAll() {
        UserDefaults.standard.set(true, forKey: "pendingRestart")
        askFolders { self.askApps { self.askAccessibility { self.askScreen {
            if self.allDone { UserDefaults.standard.set(false, forKey: "pendingRestart"); self.restartAgents() }
            self.refresh()
        } } } }
    }

    /// waits for a System Settings switch: checks by a fresh copy, off the main thread, until it's on (or Skip)
    private func waitFor(_ s: Step, until granted: @escaping () -> Bool, then next: (() -> Void)?) {
        waiting = s; skipped = false
        func poll() {
            DispatchQueue.global(qos: .userInitiated).async {
                let on = granted()
                DispatchQueue.main.async {
                    if on || self.skipped {
                        if s == .accessibility { self.accessible = on } else { self.screen = on }
                        self.waiting = nil; next?(); return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: poll)
                }
            }
        }
        poll()
    }

    func skip() { skipped = true }
    func openWaitingPane() { openPane(waiting == .screen ? "Privacy_ScreenCapture" : "Privacy_Accessibility") }
    func showInFinder() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    func openFullDisk() { openPane("Privacy_AllFiles"); showInFinder() }
    func openPane(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    /// starts the hub and the agents again (the watch's conversation is cut for a moment)
    func restartAgents() {
        let config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent(".chums/config.json")))) as? [String: Any]
        let prefix = (config?["launchdPrefix"] as? String) ?? "dev.chums"
        let dir = home.appendingPathComponent("Library/LaunchAgents")
        let labels = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix("\(prefix).hub.") || $0.hasPrefix("\(prefix).agent.") }
            .map { String($0.dropLast(".plist".count)) }
        for label in labels {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            p.arguments = ["kickstart", "-k", "gui/\(getuid())/\(label)"]
            try? p.run()
        }
        restarting = true; restartedOnce = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.restarting = false }
    }
}

struct Row: View {
    let symbol: String, title: String, detail: String
    let done: Bool, busy: Bool, action: String, locked: Bool
    let run: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20)).frame(width: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if done {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(action, action: run).disabled(locked)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct PermissionsView: View {
    @StateObject var p = Permissions()

    var appsDetail: String {
        if !p.refusedApps.isEmpty {
            return "\(p.refusedApps.values.sorted().joined(separator: ", ")) refused. Switch Chums on for it in Settings › Automation."
        }
        let others = p.allowedApps.subtracting(required).count
        if p.appsDone {
            return "Finder, System Events\(others > 0 ? " and \(others) more" : ""). Other apps ask once, the first time an agent uses them."
        }
        return "Finder, System Events and the apps you have open. Other apps ask once, the first time an agent uses them."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chums").font(.title2.weight(.semibold))
                    Text("Allow these once. Then your agents don't stop on a dialog on this Mac when you ask from the watch.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 0) {
                Row(symbol: "folder", title: "Your folders",
                    detail: p.disk && !p.folders ? "Desktop, Documents and Downloads: covered by Full Disk Access" : "Desktop, Documents and Downloads",
                    done: p.foldersDone, busy: p.step == .folders, action: "Allow", locked: p.busy, run: { p.askFolders() })
                Divider()
                Row(symbol: "macwindow.on.rectangle", title: "Apps", detail: appsDetail,
                    done: p.appsDone, busy: p.step == .apps, action: p.refusedApps.isEmpty ? "Allow" : "Open Settings", locked: p.busy,
                    run: { p.refusedApps.isEmpty ? p.askApps() : p.openPane("Privacy_Automation") })
                Divider()
                Row(symbol: "accessibility", title: "Accessibility", detail: "Clicking and typing in other apps",
                    done: p.accessible, busy: p.waiting == .accessibility, action: "Allow", locked: p.busy, run: { p.askAccessibility() })
                Divider()
                Row(symbol: "rectangle.dashed.badge.record", title: "Screen Recording", detail: "Screenshots when you ask for one",
                    done: p.screen, busy: p.waiting == .screen, action: "Allow", locked: p.busy, run: { p.askScreen() })
                Divider()
                Row(symbol: "externaldrive", title: "Full Disk Access (optional)", detail: "Also Mail, Messages and Safari data, iCloud Drive, other disks",
                    done: p.disk, busy: false, action: "Open Settings", locked: p.busy, run: p.openFullDisk)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))

            if let w = p.waiting {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Now switch on Chums in System Settings › Privacy & Security › \(w == .screen ? "Screen & System Audio Recording" : "Accessibility").")
                        .font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Text("This window sees the switch and goes on by itself."
                         + (w == .screen ? " If macOS offers Quit & Reopen, click Later. Then macOS asks once more, about bypassing the private window picker: click Allow." : "")
                         + " If Chums is already on there, switch it off and on again: Chums was signed again since. If it isn't in the list, click + and pick it: Show Chums in Finder points to it.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
            } else {
                Text(p.allDone
                     ? (p.restartedOnce ? "All set. The agents started again with these." : "All set. Agents started before this may be refused once: Restart Agents starts them again.")
                     : "Click Allow All, then answer each macOS dialog with Allow or OK.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if p.waiting != nil {
                    Button("Skip", action: p.skip)
                    Button("Show Chums in Finder", action: p.showInFinder)
                    Spacer()
                    Button("Open System Settings", action: p.openWaitingPane).keyboardShortcut(.defaultAction)
                } else {
                    Button(p.restarting ? "Restarting…" : "Restart Agents", action: p.restartAgents).disabled(p.restarting || p.busy)
                    Spacer()
                    if p.allDone {
                        Button("Done") { NSApp.terminate(nil) }.keyboardShortcut(.defaultAction)
                    } else {
                        Button("Allow All", action: p.allowAll).keyboardShortcut(.defaultAction).disabled(p.busy)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ note: Notification) {
        let menu = NSMenu(), item = NSMenuItem()
        item.submenu = NSMenu()
        item.submenu?.addItem(withTitle: "Quit Chums", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(item)
        NSApp.mainMenu = menu
        // a hosting controller sizes the window to the view, also when the waiting box appears
        window = NSWindow(contentViewController: NSHostingController(rootView: PermissionsView()))
        window.styleMask = [.titled, .closable]
        window.title = "Chums"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

// MARK: - main

// A program to run starts with a path or a name; anything else that starts with "-" (macOS adds launch arguments when
// it reopens an app, e.g. after Quit & Reopen) means the window.
let given = Array(CommandLine.arguments.dropFirst())
let args = given.first.map { $0 == "--check" || $0 == "--snapshot" || !$0.hasPrefix("-") } == true ? given : []
// The window opened from Finder, `open` or a relaunch has launchd as its parent and is Chums's. Started from a
// terminal it would be the terminal's, so it starts a copy of itself that disclaims the terminal.
if args.isEmpty && getppid() != 1 && getenv("CHUMS_RESPONSIBLE") == nil {
    setenv("CHUMS_RESPONSIBLE", "1", 1)
    exit(spawn([Bundle.main.executablePath ?? CommandLine.arguments[0], "--window"], disclaimingParent: true))
}
if args.isEmpty { unsetenv("CHUMS_RESPONSIBLE") }
if args.first == "--snapshot", args.count > 1 {
    // the window as a picture, for the docs: Chums --snapshot out.png
    _ = NSApplication.shared
    let view = NSHostingView(rootView: PermissionsView().background(Color(nsColor: .windowBackgroundColor)))
    view.frame = NSRect(origin: .zero, size: view.fittingSize)
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[1]))
    exit(0)
}
if args.isEmpty {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
} else if getenv("CHUMS_RESPONSIBLE") == nil {
    signal(SIGTERM, passOn); signal(SIGINT, passOn); signal(SIGHUP, passOn); signal(SIGQUIT, passOn)
    // first a copy of this executable, responsible for itself, so what follows is Chums's even from a terminal
    setenv("CHUMS_RESPONSIBLE", "1", 1)
    exit(spawn([Bundle.main.executablePath ?? CommandLine.arguments[0]] + args, disclaimingParent: true))
} else {
    signal(SIGTERM, passOn); signal(SIGINT, passOn); signal(SIGHUP, passOn); signal(SIGQUIT, passOn)
    unsetenv("CHUMS_RESPONSIBLE")
    exit(args[0] == "--check" ? check(Array(args.dropFirst())) : spawn(args, disclaimingParent: false))
}
