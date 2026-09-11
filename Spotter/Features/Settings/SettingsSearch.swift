import Foundation

// Index only shipped setting labels; never search saved secrets or user content.
enum SettingsSearch {
    static func matches(_ query: String, title: String, summary: String = "", key: String) -> Bool {
        let haystack = [title, summary, terms[key] ?? ""].joined(separator: " ")
        return query.split(whereSeparator: { $0.isWhitespace }).allSatisfy {
            haystack.localizedStandardContains(String($0))
        }
    }

    static let terms: [String: String] = [
        "general": "Launch at login Show in menu bar Dock Remember Window Position Lock Input Method English Pop to Root Search Welcome Guide Terminal Compact Favorites Follow cursor displays Hyper Key Include Shift Quick Press Launcher Sections Active Apps Applications System Settings Commands Search Scopes Learned ranking Reset Updates Check Automatically 通用 开机启动 菜单栏 输入法 快捷键 搜索范围 更新",
        "permissions": "Accessibility App Automation Calendar Events Screen Recording Location Granted Denied Restricted 权限 辅助功能 自动化 日历 录屏 定位",
        "backup": "Export Import Settings File Folder Automatic Sync Notes API keys private content 备份 导入 导出 同步 密钥",
        "diagnostics": "log Recent Events Copy Clear Show Finder 诊断 日志",
        "about": "version website GitHub license 版本 关于",
        "coffee": "Keep Display On Keep Disks Spinning 防休眠",
        "calendar-schedule": "Calendar Access Account All-Day Events Unavailable 日历 账户 全天",
        "change-case": "Preferred Input Selected Text Clipboard Primary Action Paste Copy Preserve Casing Punctuation Exceptions Prefix Suffix Cases 大小写 前缀 后缀",
        "clipboard": "Keep history retention Disabled Applications Clear 剪贴板 历史 保留",
        "commands": "Custom Commands shell environment confirmation 命令 确认",
        "currency-conversion": "Download Exchange Rates Update 汇率 货币",
        "emoji-symbols": "Skin Tone 肤色 表情",
        "file-search": "Home Folder Never Searched Filenames Spotlight 文件 搜索",
        "image-modification": "Output Created Image Format 图片 格式 输出",
        "kill-process": "Sort Memory CPU Group Applications Search Paths PIDs Prioritize Apps Show PID Path Refresh Interval 进程 刷新",
        "mole": "Binary Path Homebrew executable 路径",
        "note": "Stored Locally Notes Folder Sync Markdown 笔记 同步 文件夹",
        "quicklinks": "Link Open With Pin 快捷链接",
        "screenshot": "Rounded Corners Resolution Hide Spotter Thumbnail Duration Window Shadow Saving File Format 截图 缩略图 阴影",
        "text-replacement": "Snippets Expansion Prefix Keyword 文本片段 展开 前缀",
        "translate": "API Key Google Cloud Connection Target Languages 翻译 语言 密钥",
        "uptime": "Keyboard Counting Today Counts Reset 统计 按键",
        "window-management": "Gap Cycle Repeat 窗口 间距",
        "world-clock": "City Cities Time Zone 世界时钟 城市 时区"
    ]
}
