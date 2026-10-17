//
//  AppDelegate.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import AppKit

/// 应用级 AppKit 回调。
///
/// 目前只负责给 **DEBUG（测试）构建** 换一个带「测」标记的 Dock 图标：测试版与发布版
/// 使用不同的 bundle identifier 可以共存，但两者的图标若完全一样，很容易点错——点错的
/// 结果就是调试数据写进生产容器。Release 构建不会进入这段代码，正式图标保持不变。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
            NSApp.applicationIconImage = NSImage(resource: .appIconDev)
        #endif
    }
}
