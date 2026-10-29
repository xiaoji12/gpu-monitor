import Cocoa
import IOKit

// MARK: - 数据读取

struct GPUStats {
    var utilization: Int = 0
    var activity: Int = 0
    var coreClock: Int = 0
    var memClock: Int = 0
    var power: Int = 0
    var temp: Int = 0
    var fanRPM: Int = 0
    var fanPct: Int = 0
    var vramUsed: Int64 = 0
    var vramFree: Int64 = 0
    var valid = false
}

enum GPUReader {
    static func read() -> GPUStats {
        var s = GPUStats()
        guard let matching = IOServiceMatching("IOAccelerator") else { return s }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return s
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            if let raw = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {

                func i(_ key: String) -> Int? {
                    guard let n = raw[key] as? NSNumber else { return nil }
                    return n.intValue
                }
                func l(_ key: String) -> Int64? {
                    guard let n = raw[key] as? NSNumber else { return nil }
                    return n.int64Value
                }

                if let v = i("Device Utilization %") { s.utilization = v; s.valid = true }
                if let v = i("GPU Activity(%)") { s.activity = v }
                if let v = i("Core Clock(MHz)") { s.coreClock = v }
                if let v = i("Memory Clock(MHz)") { s.memClock = v }
                if let v = i("Total Power(W)") { s.power = v }
                if let v = i("Temperature(C)") { s.temp = v }
                if let v = i("Fan Speed(RPM)") { s.fanRPM = v }
                if let v = i("Fan Speed(%)") { s.fanPct = v }
                if let v = l("inUseVidMemoryBytes") { s.vramUsed = v }
                if let v = l("vramFreeBytes") { s.vramFree = v }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iter)
        }
        return s
    }
}

// MARK: - 应用

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var interval: TimeInterval = 5

    private var stats = GPUStats()

    // 详情行（固定顺序，只更新文字，不重建菜单，避免闪烁）
    private struct Row { let key: String; let label: String }
    private let rows: [Row] = [
        Row(key: "util",  label: "使用率"),
        Row(key: "act",   label: "活动度"),
        Row(key: "core",  label: "核心频率"),
        Row(key: "mem",   label: "显存频率"),
        Row(key: "power", label: "功耗"),
        Row(key: "temp",  label: "温度"),
        Row(key: "fan",   label: "风扇"),
        Row(key: "vram",  label: "显存占用"),
    ]
    private var rowItems: [String: NSMenuItem] = [:]
    private var intervalItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.imagePosition = .imageLeading
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            btn.title = "GPU --"
        }

        buildMenu()
        refresh()
        schedule()
    }

    // MARK: 菜单构建

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let title = NSMenuItem(title: "GPU 状态", action: nil, keyEquivalent: "")
        title.isEnabled = false
        title.attributedTitle = NSAttributedString(
            string: "GPU 状态",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        menu.addItem(title)
        menu.addItem(.separator())

        for row in rows {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = detailText(row.label, "--")
            rowItems[row.key] = item
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let hint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        hint.attributedTitle = NSAttributedString(
            string: "数值由显卡驱动上报，约 15~30 秒更新一次",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        menu.addItem(hint)

        let copy = NSMenuItem(title: "复制当前数据", action: #selector(copyStats), keyEquivalent: "c")
        copy.target = self
        menu.addItem(copy)

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        // 刷新间隔
        let intervalRoot = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (secs, label) in [(2.0, "2 秒"), (5.0, "5 秒"), (10.0, "10 秒"), (30.0, "30 秒")] {
            let it = NSMenuItem(title: label, action: #selector(setInterval(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = secs
            it.state = (secs == interval) ? .on : .off
            sub.addItem(it)
            intervalItems.append(it)
        }
        intervalRoot.submenu = sub
        menu.addItem(intervalRoot)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// 左列标签灰、右列数值白，用 tab stop 对齐
    private func detailText(_ label: String, _ value: String) -> NSAttributedString {
        let s = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .left, location: 96, options: [:])]
        para.defaultTabInterval = 96

        s.append(NSAttributedString(
            string: label + "\t",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: para,
            ]
        ))
        s.append(NSAttributedString(
            string: value,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
        ))
        return s
    }

    // MARK: 刷新

    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func refreshNow() { refresh() }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? TimeInterval else { return }
        interval = secs
        for it in intervalItems { it.state = (it === sender) ? .on : .off }
        schedule()
        refresh()
    }

    private func refresh() {
        stats = GPUReader.read()
        updateStatusTitle()
        updateRows()
    }

    private func updateStatusTitle() {
        guard let btn = statusItem.button else { return }
        guard stats.valid else {
            btn.title = "GPU 无数据"
            return
        }
        let util = stats.utilization
        if stats.temp > 0 {
            btn.title = "GPU \(util)% \(stats.temp)°"
        } else {
            btn.title = "GPU \(util)%"
        }
    }

    private func updateRows() {
        guard stats.valid else {
            rowItems["util"]?.attributedTitle = detailText("使用率", "读取失败")
            return
        }
        rowItems["util"]?.attributedTitle = detailText("使用率", "\(stats.utilization) %")
        rowItems["act"]?.attributedTitle = detailText("活动度", "\(stats.activity) %")
        rowItems["core"]?.attributedTitle = detailText(
            "核心频率", stats.coreClock > 0 ? "\(stats.coreClock) MHz" : "0 MHz  空闲降频")
        rowItems["mem"]?.attributedTitle = detailText("显存频率", "\(stats.memClock) MHz")
        rowItems["power"]?.attributedTitle = detailText("功耗", "\(stats.power) W")
        rowItems["temp"]?.attributedTitle = detailText("温度", "\(stats.temp) °C")

        if stats.fanRPM > 0 {
            rowItems["fan"]?.attributedTitle = detailText(
                "风扇", "\(stats.fanRPM) RPM  (\(stats.fanPct)%)")
        } else {
            rowItems["fan"]?.attributedTitle = detailText("风扇", "停转")
        }

        let usedGB = Double(stats.vramUsed) / 1_073_741_824.0
        let allocGB = Double(stats.vramUsed + stats.vramFree) / 1_073_741_824.0
        let pct = allocGB > 0 ? Int(usedGB / allocGB * 100) : 0
        rowItems["vram"]?.attributedTitle = detailText(
            "显存占用", String(format: "%.1f / %.0f GB  %d%%", usedGB, allocGB, pct))
    }

    // 菜单打开时立刻刷新一次
    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc private func copyStats() {
        let text = """
        GPU 使用率: \(stats.utilization)%
        活动度: \(stats.activity)%
        核心频率: \(stats.coreClock) MHz
        显存频率: \(stats.memClock) MHz
        功耗: \(stats.power) W
        温度: \(stats.temp) °C
        风扇: \(stats.fanRPM) RPM (\(stats.fanPct)%)
        显存: \(String(format: "%.2f", Double(stats.vramUsed) / 1_073_741_824.0)) / \(String(format: "%.0f", Double(stats.vramUsed + stats.vramFree) / 1_073_741_824.0)) GB
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - 入口

// --once：命令行打印一次数据后退出，便于验证
if CommandLine.arguments.contains("--once") {
    let s = GPUReader.read()
    guard s.valid else {
        print("读取失败：未找到 IOAccelerator")
        exit(1)
    }
    print("使用率      \(s.utilization) %")
    print("活动度      \(s.activity) %")
    print("核心频率    \(s.coreClock) MHz")
    print("显存频率    \(s.memClock) MHz")
    print("功耗        \(s.power) W")
    print("温度        \(s.temp) °C")
    print("风扇        \(s.fanRPM) RPM (\(s.fanPct)%)")
    print(String(format: "显存        %.2f / %.0f GB",
                 Double(s.vramUsed) / 1_073_741_824.0,
                 Double(s.vramUsed + s.vramFree) / 1_073_741_824.0))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
