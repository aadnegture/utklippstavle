import Cocoa
import SwiftUI

// Main App
@main
struct ClipboardHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusBarItem: NSStatusItem!
    var preferencesWindow: NSWindow?
    var clipboardHistory: [ClipboardItem] = []
    var popover: NSPopover!
    let maximumHistoryItems = 20
    var monitor: Any?
    var lastChangeCount: Int = 0
    var preferences: AppPreferences = AppPreferences.load()

    func setupPreferencesMenu() {
        // Create a menu
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: "App", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        
        // Create a menu item for preferences
        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(togglePreferencesWindow),
            keyEquivalent: ","
        )
        preferencesItem.keyEquivalentModifierMask = .command
        
        // Add menu items
        appMenu.addItem(preferencesItem)
        appMenu.addItem(NSMenuItem.separator())
        
        // Add quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        appMenu.addItem(quitItem)
        
        // Set up menu structure
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    @objc func togglePreferencesWindow() {
        if let window = preferencesWindow {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                // Update the view with current preferences
                if let contentView = window.contentView as? NSHostingView<PreferencesView> {
                    let newView = PreferencesView(
                        preferences: preferences,
                        onSave: { [weak self] newPrefs in
                            guard let self = self else { return }
                            self.preferences = newPrefs
                            self.preferences.save()
                            window.orderOut(nil)
                            // Update clipboard view with new preferences
                            self.updatePopoverContent()
                        }
                    )
                    contentView.rootView = newView
                }
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            // Create the window
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 150),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Preferences"
            window.center()
            
            let prefsView = PreferencesView(
                preferences: preferences,
                onSave: { [weak self] newPrefs in
                    guard let self = self else { return }
                    self.preferences = newPrefs
                    self.preferences.save()
                    window.orderOut(nil)
                    // Update clipboard view with new preferences
                    self.updatePopoverContent()
                }
            )
            
            window.contentView = NSHostingView(rootView: prefsView)
            window.makeKeyAndOrderFront(nil)
            preferencesWindow = window
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupPreferencesMenu()
        // Setup status bar icon
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard History")
            
            // Left click shows clipboard history
            button.action = #selector(showPopover)
            
            // Right click menu has preferences
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(togglePreferencesWindow), keyEquivalent: ","))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            
            statusBarItem.menu = menu
        }
        
        // Setup popover
        let contentView = ClipboardHistoryView(clipboardItems: .constant(clipboardHistory), preferences: preferences, onItemSelected: { item in
            self.copyToClipboard(item.text)
            self.closePopover()
        })
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Register for clipboard changes
        lastChangeCount = NSPasteboard.general.changeCount
        Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(checkForPasteboardChanges), userInfo: nil, repeats: true)
        
        // Register global hotkey (Command+Shift+V)
        setupGlobalHotkey()
    }
    
    func setupGlobalHotkey() {
        print("Setting up global hotkey monitor")
        
        // Request permission
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("Accessibility permissions enabled: \(accessEnabled)")
        
        // Set up monitor
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.control) && event.keyCode == 9 { // 9 is 'V'
                print("Global hotkey detected!")
                DispatchQueue.main.async {
                    self?.showPopover() // Directly call showPopover instead of togglePopover
                }
                // Global monitor can't return nil, but it will prevent further processing
            }
        }

        // Modify your local monitor to be absolutely sure it consumes the event:
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.control) && event.keyCode == 9 {
                print("Local hotkey detected!")
                DispatchQueue.main.async {
                    self?.showPopover() // Directly call showPopover instead of togglePopover
                }
                return nil // This explicitly consumes the event
            }
            return event // Pass all other events through
        }
    }
    
    @objc func checkForPasteboardChanges() {
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            if pasteboard.changeCount != lastChangeCount {
                lastChangeCount = pasteboard.changeCount
                
                // Add new item to history (don't add duplicates)
                if !clipboardHistory.contains(where: { $0.text == string }) {
                    let newItem = ClipboardItem(id: UUID(), text: string, timestamp: Date())
                    clipboardHistory.insert(newItem, at: 0)
                    
                    // Limit history size
                    if clipboardHistory.count > preferences.maximumHistoryItems {
                        clipboardHistory.removeLast()
                    }
                    
                    // Update the view
                    updatePopoverContent()
                }
            }
        }
    }
    
    func updatePopoverContent() {
        print("Function called: \(#function)")
        if let contentController = popover.contentViewController as? NSHostingController<ClipboardHistoryView> {
            contentController.rootView = ClipboardHistoryView(clipboardItems: .constant(clipboardHistory), preferences: preferences, onItemSelected: { item in
                self.copyToClipboard(item.text)
                self.closePopover()
            })
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        // For right clicks, the menu will be handled automatically by macOS
        // We only need to handle left clicks to show the popover
        
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            return  // Do nothing, system will show the menu
        }
        
        // Left click - toggle the popover
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    @objc func showPopover() {
        print("Function called: \(#function)")
        if let button = statusBarItem.button {
            updatePopoverContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        }
    }
    
    func closePopover() {
        print("Function called: \(#function)")
        popover.performClose(nil)
    }
    
    func copyToClipboard(_ text: String) {
        print("Function called: \(#function)")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// Clipboard item data model
struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// Add after your ClipboardItem struct
struct AppPreferences {
    var maximumHistoryItems: Int = 20
    var itemLineLimit: Int = 10
    
    // Load from UserDefaults
    static func load() -> AppPreferences {
        let defaults = UserDefaults.standard
        var prefs = AppPreferences()
        
        if defaults.object(forKey: "maximumHistoryItems") != nil {
            prefs.maximumHistoryItems = defaults.integer(forKey: "maximumHistoryItems")
        }
        
        if defaults.object(forKey: "itemLineLimit") != nil {
            prefs.itemLineLimit = defaults.integer(forKey: "itemLineLimit")
        }
        
        return prefs
    }
    
    // Save to UserDefaults
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(maximumHistoryItems, forKey: "maximumHistoryItems")
        defaults.set(itemLineLimit, forKey: "itemLineLimit")
    }
}

struct PreferencesView: View {
    @State private var localPreferences: AppPreferences
    let onSave: (AppPreferences) -> Void
    
    init(preferences: AppPreferences, onSave: @escaping (AppPreferences) -> Void) {
        _localPreferences = State(initialValue: preferences)
        self.onSave = onSave
    }
    
    var body: some View {
        Form {
            Section(header: Text("Clipboard History")) {
                Stepper("Maximum items: \(localPreferences.maximumHistoryItems)", 
                    value: $localPreferences.maximumHistoryItems, in: 5...100)
                Stepper("Line limit per item: \(localPreferences.itemLineLimit)", 
                    value: $localPreferences.itemLineLimit, in: 1...20)
            }
            
            Button("Save") {
                onSave(localPreferences)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top)
        }
        .padding()
        .frame(width: 350, height: 150)
    }
}

struct ClipboardHistoryView: View {
    @Binding var clipboardItems: [ClipboardItem]
    let preferences: AppPreferences
    let onItemSelected: (ClipboardItem) -> Void
    
    // Track when view appears for keyboard focus
    @State private var isViewActive = false
    
    var body: some View {
        VStack {
            Text("Clipboard History")
                .font(.headline)
                .padding()
            
            if clipboardItems.isEmpty {
                Text("No clipboard history yet")
                    .foregroundColor(.gray)
                    .padding()
                Spacer()
            } else {
                Text("Press ⌘1-⌘9 to select items or click an item")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 5)
                
                List {
                    ForEach(Array(clipboardItems.prefix(9).enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading) {
                            HStack {
                                Text("\(index + 1)")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 20)
                                
                                Text(item.text)
                                    .lineLimit(preferences.itemLineLimit)
                                    .truncationMode(.tail)
                            }
                            
                            Text(formatDate(item.timestamp))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onItemSelected(item)
                        }
                    }
                }
                .id(UUID())
                .listStyle(.plain)
            }
        }
        .frame(width: 400, height: 400)
        .onAppear {
            isViewActive = true
        }
        .onDisappear {
            isViewActive = false
        }
        // Add keyboard shortcut handling
        .background(KeyboardShortcutHandler(isActive: isViewActive, items: clipboardItems, onItemSelected: onItemSelected))
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Helper view to handle keyboard shortcuts
struct KeyboardShortcutHandler: NSViewRepresentable {
    var isActive: Bool
    var items: [ClipboardItem]
    var onItemSelected: (ClipboardItem) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = ShortcutView()
        view.isActive = isActive
        view.items = items
        view.onItemSelected = onItemSelected
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? ShortcutView {
            view.isActive = isActive
            view.items = items
            view.onItemSelected = onItemSelected
        }
    }
    
    class ShortcutView: NSView {
        var isActive = false
        var items: [ClipboardItem] = []
        var onItemSelected: ((ClipboardItem) -> Void)?
        var keyMonitor: Any?
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                setupKeyMonitor()
            } else {
                removeKeyMonitor()
            }
        }
        
        func setupKeyMonitor() {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isActive else { return event }
                
                // Check if it's a command key
                if event.modifierFlags.contains(.command) {
                    // Check if it's a number key (1-9)
                    if event.keyCode >= 18 && event.keyCode <= 26 {
                        let index = Int(event.keyCode) - 18 // 18 is keycode for 1
                        if index < self.items.count {
                            DispatchQueue.main.async {
                                self.onItemSelected?(self.items[index])
                            }
                            return nil // Consume the event
                        }
                    }
                }
                return event
            }
        }
        
        func removeKeyMonitor() {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        
        deinit {
            removeKeyMonitor()
        }
    }
}


