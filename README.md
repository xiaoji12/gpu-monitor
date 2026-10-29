# GPU Monitor

macOS 菜单栏 AMD 显卡监控，显示**使用率、核心频率、显存频率、功耗、温度、风扇转速、显存占用**。

![status](https://img.shields.io/badge/platform-macOS%2011%2B-lightgrey)
![license](https://img.shields.io/badge/license-MIT-blue)

---

## 为什么需要它

macOS 上没有任何现成软件能完整显示 AMD 显卡的这些数据：

| 软件 | 实测结果 |
|---|---|
| **Stats 3.0.23** | 其 `GPU.framework` 只实现了 `Device Utilization %` 和 `Memory Clock`，功耗/温度/频率根本没有代码 |
| **iStat Menus** | GPU 传感器走 SMC 路径，黑苹果机型映射不匹配，显示为空 |
| **istats / TG Pro** | 同上，读不到 AMD 卡 |

真实的数据在 IOKit 注册表的 `PerformanceStatistics` 字典里，只有直接读它才拿得到全量。
这个工具就是干这件事的。

---

## 工作原理

```
IOAccelerator (AMDRadeonX6000_AMDNavi23GraphicsAccelerator)
  └── PerformanceStatistics 字典
        ├── Device Utilization %   GPU 使用率（实时，更新快）
        ├── GPU Activity(%)        驱动侧活动度（更新慢）
        ├── Core Clock(MHz)        核心频率
        ├── Memory Clock(MHz)      显存频率
        ├── Total Power(W)         整卡功耗
        ├── Temperature(C)         边缘温度
        ├── Fan Speed(RPM)         风扇转速
        ├── Fan Speed(%)           风扇占空比
        ├── inUseVidMemoryBytes    已用显存
        └── vramFreeBytes          空闲显存
```

用 `IOServiceMatching("IOAccelerator")` + `IORegistryEntryCreateCFProperty` 直接读取，
**单次耗时约 0.7 毫秒**，比 fork 一个 `ioreg` 进程快 300 倍。

**不需要 root 权限，不需要后台守护进程，不写任何系统文件。**

---

## 构建

需要 Xcode Command Line Tools（`xcode-select --install`）。

```bash
chmod +x build.sh

# 只编译并启动
./build.sh

# 编译 + 配置登录时自动启动
./build.sh --install
```

产物：`~/Applications/GPUMonitor.app`（约 109KB，`LSUIElement=true`，不占 Dock）

---

## 使用

菜单栏显示 `GPU 7% 51°`，点击展开：

```
GPU 状态
────────────────────────
使用率        7 %
活动度        0 %
核心频率      233 MHz
显存频率      1988 MHz
功耗          34 W
温度          51 °C
风扇          951 RPM  (35%)
显存占用      0.4 / 10 GB  4%
────────────────────────
数值由显卡驱动上报，约 15~30 秒更新一次
────────────────────────
复制当前数据             ⌘C
立即刷新                 ⌘R
刷新间隔        ▸  2 / 5 / 10 / 30 秒
────────────────────────
退出                     ⌘Q
```

命令行模式（不启动界面，打印一次就退出）：

```bash
./GPUMonitor --once
```

---

## 已知限制

这些是 macOS 驱动层的限制，不是工具的 bug：

| 限制 | 说明 |
|---|---|
| **数值有 15~30 秒延迟** | 驱动内部采样周期慢，满载结束后要等约半分钟才回落。适合看趋势，不适合当秒级示波器 |
| **只有边缘温度** | 读不到结温（junction）和显存温度，macOS 根本不对外提供这两项 |
| **功耗是估算值** | `Total Power(W)` 是整卡估算，非精确测量 |
| **深度空闲时核心频率报 0** | 驱动真的返回 0（降到最低档），不是读取失败，界面标注为「空闲降频」 |
| **显存分母约为 10GB 而非 12GB** | 驱动只报告可分配部分（`inUse + vramFree`），物理显存有一部分被系统保留 |

---

## 兼容性

在以下环境验证可用：

- macOS 26.5.1 Tahoe
- AMD Radeon RX 6700 XT 12GB（Navi 22，`0x73DF`）
- 驱动：`AMDRadeonX6000_AMDNavi23GraphicsAccelerator`

理论上前提是驱动暴露了 `PerformanceStatistics` 字典，其他 AMD 卡（RX 5000/6000 系列）大概率同样可用，
但**未经验证**。如果你的卡读不到数据，界面会显示 `GPU 无数据`。

---

## 卸载

```bash
pkill -f GPUMonitor.app
rm -rf ~/Applications/GPUMonitor.app
rm -f ~/Library/LaunchAgents/local.user.gpumonitor.plist
```

---

## 相关项目

这个工具是为 **Z790 黑苹果（macOS 26 Tahoe + RX 6700 XT）** 补显卡传感器写的，
配套的 OpenCore 配置在：[hackintosh-z790-efi](https://github.com/xiaoji12/hackintosh-z790-efi)

黑苹果环境下 AMD 卡不被官方支持，温度和功耗数据不会有任何软件主动去读，
但驱动仍然把完整数据放在 `PerformanceStatistics` 里——这也是本工具存在的原因。

---

## License

MIT
