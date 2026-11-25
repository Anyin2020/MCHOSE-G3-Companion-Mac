# MCHOSE G3 Companion for macOS

原生 macOS 桌面小组件与鼠标设置工具，专为 **迈从（MCHOSE）G3** 无线鼠标打造（支持 2.4G 接收器 `0x258a:0x0138` 与有线连接 `0x258a:0x0136`）。

## 主要特性

- **原生桌面毛玻璃小组件**：贴合桌面层（无顶部菜单栏图标、无 Dock 图标、不进 `Cmd+Tab`），支持深浅色模式自适应，可自由拖动摆放并自动记忆位置。
- **实时电量与状态监控**：通过 IOKit HID 原生协议实时读取鼠标电量百分比、在线/休眠/充电/有线状态，电量 `≤ 20%` 时发送 macOS 系统通知提醒。
- **鼠标板载参数设置**：悬停卡片点击齿轮或右键菜单打开设置面板，支持直接读取和写入板载配置：
  - 回报率：`125 / 250 / 500 / 1000 Hz`
  - 休眠时间：`1–30 分钟`
  - 按键消抖：`1–14 ms`
  - 运动处理：直线修正（Angle Snapping）、波纹控制（Ripple Control）
  - DPI 档位：支持 `1–6` 档位数量、`100–12000 DPI`（步长 100）及每档自定义 RGB 指示灯颜色

## 系统要求

- macOS 15.0+（仅需系统自带 Xcode Command Line Tools 的 `swiftc`，无需安装完整 Xcode）
- 迈从（MCHOSE）G3 鼠标（2.4G 接收器或有线连接）

## 构建与安装

```bash
chmod +x build.sh
./build.sh
open "/Applications/G3 Companion.app"
```

### 权限说明（输入监控）

由于该鼠标的厂商控制接口与键盘 HID 集合共用同一个 USB 接口，首次运行打开设备时会请求 **输入监控（Input Monitoring）** 权限：
1. 打开 **系统设置 → 隐私与安全性 → 输入监控**；
2. 勾选启用 **`G3 Companion`**。

*(注：若在本地重新编译覆盖了临时签名的 `.app`，请在该列表中选中旧条目点 `-` 删除后，再点 `+` 重新添加一次即可恢复权限识别。)*

## 致谢与协议

- 鼠标 USB HID 通信协议参考自开源项目 [SsenNChan/G3-Companion](https://github.com/SsenNChan/G3-Companion)（GPL-3.0）。
- 本项目同样采用 **GNU General Public License v3.0 (GPL-3.0)** 开源协议，详见 [LICENSE](LICENSE)。
