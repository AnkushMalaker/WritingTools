//
//  DoubleTapMonitor.swift
//  WritingTools
//
//  Detects a quick double-tap of a single modifier key (e.g. ⌥⌥) anywhere in
//  the system and fires a callback. This complements the KeyboardShortcuts
//  chord recorder, which cannot capture a double-tap gesture.
//
//  Requires Accessibility / Input Monitoring permission (already needed by the
//  app for selection capture).
//

import AppKit

extension Notification.Name {
    /// Posted when the double-tap enable flag or chosen modifier changes.
    static let doubleTapPreferenceDidChange = Notification.Name("doubleTapPreferenceDidChange")
}

/// Watches `.flagsChanged` events for two clean presses of a single modifier
/// key within `interval` seconds and invokes `onDoubleTap`.
final class DoubleTapMonitor {

    /// keyCode of the modifier to watch. Defaults to Left Option (58).
    var modifierKeyCode: Int = 58
    /// Maximum gap between the two taps.
    var interval: TimeInterval = 0.3
    /// Called on the main thread when a double-tap is detected.
    var onDoubleTap: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastTapTimestamp: TimeInterval = 0

    // MARK: - Lifecycle

    func start() {
        stop()
        // Global monitor: fires when another app is frontmost.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown]
        ) { [weak self] event in
            self?.handle(event)
        }
        // Local monitor: fires when our own windows are frontmost.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        lastTapTimestamp = 0
    }

    deinit { stop() }

    // MARK: - Detection

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // Any real keypress breaks a pending double-tap sequence so that
            // "⌥ + type + ⌥" does not register.
            lastTapTimestamp = 0

        case .flagsChanged:
            guard Int(event.keyCode) == modifierKeyCode else {
                // A different modifier changed → cancel the sequence so combos
                // like ⌘⌥ never count as a tap.
                lastTapTimestamp = 0
                return
            }
            let mask = Self.flagMask(forKeyCode: modifierKeyCode)
            let active = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Count only the *press* of exactly this modifier with nothing else held.
            guard active == mask else { return }

            let now = event.timestamp
            if now - lastTapTimestamp <= interval {
                lastTapTimestamp = 0
                let callback = onDoubleTap
                DispatchQueue.main.async { callback?() }
            } else {
                lastTapTimestamp = now
            }

        default:
            break
        }
    }

    /// Maps a modifier keyCode to its device-independent flag.
    static func flagMask(forKeyCode code: Int) -> NSEvent.ModifierFlags {
        switch code {
        case 56, 60: return .shift     // left / right shift
        case 59, 62: return .control   // left / right control
        case 58, 61: return .option    // left / right option
        case 54, 55: return .command   // right / left command
        case 63, 179: return .function // fn / globe
        default: return []
        }
    }

    /// Human-readable labels for the modifiers we allow selecting.
    static let selectableModifiers: [(name: String, keyCode: Int)] = [
        ("Left Option (⌥)", 58),
        ("Right Option (⌥)", 61),
        ("Left Command (⌘)", 55),
        ("Right Command (⌘)", 54),
        ("Left Control (⌃)", 59),
        ("Right Control (⌃)", 62),
        ("Left Shift (⇧)", 56),
        ("Right Shift (⇧)", 60),
    ]
}
