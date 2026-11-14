import AppKit

// TapCopy — BLACK EYE internal utility.
// Pure AppKit startup: no storyboards, no SwiftUI, no Electron.
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
