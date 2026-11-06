import AppKit
import CoreGraphics
import Foundation

final class FunctionKeyMonitor {
    var onPress: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var functionKeyIsDown = false
    private let stateLock = NSLock()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() -> Bool {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return true
        }
        let hasAccess = CGPreflightListenEventAccess() || CGRequestListenEventAccess()
        guard hasAccess else { return false }

        let mask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<FunctionKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: context
        ) {
            eventTap = tap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
            CGEvent.tapEnable(tap: tap, enable: true)
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
            if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
            return true
        }

        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                if event.keyCode == 63 { self?.observeFunctionKey(event.modifierFlags.contains(.function)) }
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                if event.keyCode == 63 { self?.observeFunctionKey(event.modifierFlags.contains(.function)) }
                return event
            }
        }
        return eventTap != nil || globalMonitor != nil || localMonitor != nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            observeFunctionKey(false)
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        } else if type == .flagsChanged,
                  event.getIntegerValueField(.keyboardEventKeycode) == 63 {
            let isDown = event.flags.contains(.maskSecondaryFn)
            observeFunctionKey(isDown)
        }
        return Unmanaged.passUnretained(event)
    }

    private func observeFunctionKey(_ isDown: Bool) {
        stateLock.lock()
        let pressed = isDown && !functionKeyIsDown
        functionKeyIsDown = isDown
        stateLock.unlock()
        if pressed { DispatchQueue.main.async { [weak self] in self?.onPress?() } }
    }
}
