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
    var clipboardHistory: [ClipboardItem] = []
    var popover: NSPopover!
    let maximumHistoryItems = 20
    var monitor: Any?
    var lastChangeCount: Int = 0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Setup status bar icon
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard History")
            button.action = #selector(togglePopover(_:))
        }
        
        // Setup popover
        let contentView = ClipboardHistoryView(clipboardItems: .constant(clipboardHistory), onItemSelected: { item in
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
                    if clipboardHistory.count > maximumHistoryItems {
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
            contentController.rootView = ClipboardHistoryView(clipboardItems: .constant(clipboardHistory), onItemSelected: { item in
                self.copyToClipboard(item.text)
                self.closePopover()
            })
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        print("Function called: \(#function)")
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    func showPopover() {
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

// Clipboard history view
struct ClipboardHistoryView: View {
    @Binding var clipboardItems: [ClipboardItem]
    let onItemSelected: (ClipboardItem) -> Void
    
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
                List {
                    ForEach(clipboardItems) { item in
                        VStack(alignment: .leading) {
                            Text(item.text)
                                .lineLimit(10)
                                .truncationMode(.tail)
                            
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
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
