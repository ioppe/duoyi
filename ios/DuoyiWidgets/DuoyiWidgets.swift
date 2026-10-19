import SwiftUI
import WidgetKit

private let appGroupId = "group.com.duoyi.duoyi"

private let duoyiPathSegmentAllowed: CharacterSet = {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
    return allowed
}()

private struct DuoyiWidgetConfig {
    let kind: String
    let title: String
    let deepLink: String
    let accent: Color
    let primaryKey: String
    let fallback: String
    let rowKeys: [String]
    let quickActionTitle: String
    let quickActionLink: String
}

private struct DuoyiWidgetTheme {
    let primary: Color
    let background: Color
    let surface: Color
    let navBackground: Color
    let text: Color
    let mutedText: Color
    let onPrimary: Color
    let accentStart: Color
    let accentEnd: Color

    static let fallback = DuoyiWidgetTheme(
        primary: color("#FFFF6B6B"),
        background: color("#FFFFFFFF"),
        surface: color("#FFFFFFFF"),
        navBackground: color("#FFFFF6F2"),
        text: color("#FF333333"),
        mutedText: color("#FF666666"),
        onPrimary: color("#FFFFFFFF"),
        accentStart: color("#FFFF6B6B"),
        accentEnd: color("#FFFFB088")
    )

    init(defaults: UserDefaults?) {
        self.primary = Self.read(defaults, key: "widget_theme_primary", fallback: "#FFFF6B6B")
        self.background = Self.read(defaults, key: "widget_theme_background", fallback: "#FFFFFFFF")
        self.surface = Self.read(defaults, key: "widget_theme_surface", fallback: "#FFFFFFFF")
        self.navBackground = Self.read(defaults, key: "widget_theme_nav_background", fallback: "#FFFFF6F2")
        self.text = Self.read(defaults, key: "widget_theme_text", fallback: "#FF333333")
        self.mutedText = Self.read(defaults, key: "widget_theme_muted_text", fallback: "#FF666666")
        self.onPrimary = Self.read(defaults, key: "widget_theme_on_primary", fallback: "#FFFFFFFF")
        self.accentStart = Self.read(defaults, key: "widget_theme_accent_start", fallback: "#FFFF6B6B")
        self.accentEnd = Self.read(defaults, key: "widget_theme_accent_end", fallback: "#FFFFB088")
    }

    private init(
        primary: Color,
        background: Color,
        surface: Color,
        navBackground: Color,
        text: Color,
        mutedText: Color,
        onPrimary: Color,
        accentStart: Color,
        accentEnd: Color
    ) {
        self.primary = primary
        self.background = background
        self.surface = surface
        self.navBackground = navBackground
        self.text = text
        self.mutedText = mutedText
        self.onPrimary = onPrimary
        self.accentStart = accentStart
        self.accentEnd = accentEnd
    }

    private static func read(_ defaults: UserDefaults?, key: String, fallback: String) -> Color {
        color(defaults?.string(forKey: key) ?? fallback)
    }

    private static func color(_ raw: String) -> Color {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        let normalized: String
        if clean.count == 6 {
            normalized = "FF\(clean)"
        } else if clean.count == 8 {
            normalized = clean
        } else {
            normalized = "FFFF6B6B"
        }
        guard let value = UInt64(normalized, radix: 16) else {
            return Color(red: 1.0, green: 0.42, blue: 0.42)
        }
        let alpha = Double((value >> 24) & 0xFF) / 255.0
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

private struct DuoyiTodoRow: Identifiable {
    let index: Int
    let title: String
    let todoId: String

    var id: Int { index }

    var detailURL: URL? {
        guard !todoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let encodedId = todoId.addingPercentEncoding(withAllowedCharacters: duoyiPathSegmentAllowed) ?? todoId
        return URL(string: "duoyi://todo/\(encodedId)")
    }

    var completeURL: URL? {
        guard !todoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        var components = URLComponents(string: "duoyi://action/complete_todo")
        components?.queryItems = [URLQueryItem(name: "id", value: todoId)]
        return components?.url
    }
}

private struct DuoyiWidgetRow: Identifiable {
    let index: Int
    let title: String
    let target: String

    var id: Int { index }

    var url: URL? {
        let clean = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return nil
        }
        return URL(string: clean)
    }
}

private struct DuoyiWidgetEntry: TimelineEntry {
    let date: Date
    let config: DuoyiWidgetConfig
    let primary: String
    let primaryTarget: String
    let rows: [DuoyiWidgetRow]
    let todoRows: [DuoyiTodoRow]
    let brandTitle: String
    let navTodo: String
    let navHabit: String
    let navCalendar: String
    let navFocus: String
    let displayMode: String
    let habitQuickCheckId: String
    let focusTimerRunning: Bool
    let focusTimerRemainingSeconds: Int
    let focusTimerTotalSeconds: Int
    let focusTimerEndsAtMillis: Int64
    let focusTimerLabel: String
    let theme: DuoyiWidgetTheme

    var focusTimerEndDate: Date? {
        guard focusTimerEndsAtMillis > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(focusTimerEndsAtMillis) / 1000)
    }
}

private struct DuoyiWidgetProvider: TimelineProvider {
    let config: DuoyiWidgetConfig

    func placeholder(in context: Context) -> DuoyiWidgetEntry {
        DuoyiWidgetEntry(
            date: Date(),
            config: config,
            primary: config.fallback,
            primaryTarget: config.deepLink,
            rows: config.rowKeys.enumerated().map {
                DuoyiWidgetRow(index: $0.offset + 2, title: config.fallback, target: config.deepLink)
            },
            todoRows: [],
            brandTitle: "多仪",
            navTodo: "待办",
            navHabit: "习惯",
            navCalendar: "日历",
            navFocus: "专注",
            displayMode: "standard",
            habitQuickCheckId: "",
            focusTimerRunning: false,
            focusTimerRemainingSeconds: 0,
            focusTimerTotalSeconds: 0,
            focusTimerEndsAtMillis: 0,
            focusTimerLabel: "专注倒计时",
            theme: .fallback
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DuoyiWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DuoyiWidgetEntry>) -> Void) {
        let current = entry()
        let refreshMinutes = current.focusTimerRunning ? 1 : 15
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date()) ?? Date()
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry() -> DuoyiWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let todoRows = readTodoRows(defaults)
        let primary: String
        let primaryTarget: String
        let rows: [DuoyiWidgetRow]
        if config.kind == "DuoyiTodoWidget" {
            primary = todoRows.first?.title ?? config.fallback
            primaryTarget = todoRows.first?.detailURL?.absoluteString ?? config.deepLink
            rows = []
        } else {
            let primarySource = readPrimary(defaults)
            primary = primarySource.title
            primaryTarget = primarySource.target
            rows = readRows(defaults, excluding: primarySource.sourceKey)
        }
        return DuoyiWidgetEntry(
            date: Date(),
            config: config,
            primary: primary,
            primaryTarget: primaryTarget,
            rows: rows,
            todoRows: todoRows,
            brandTitle: readString(defaults, key: "brand_app_title", fallback: "多仪"),
            navTodo: readString(defaults, key: "nav_todo", fallback: "待办"),
            navHabit: readString(defaults, key: "nav_habit", fallback: "习惯"),
            navCalendar: readString(defaults, key: "nav_calendar", fallback: "日历"),
            navFocus: readString(defaults, key: "nav_focus", fallback: "专注"),
            displayMode: readString(defaults, key: "widget_display_mode", fallback: "standard"),
            habitQuickCheckId: readString(defaults, key: "habit_quick_check_id", fallback: ""),
            focusTimerRunning: readBool(defaults, key: "focus_timer_running"),
            focusTimerRemainingSeconds: readInt(defaults, key: "focus_timer_remaining_seconds"),
            focusTimerTotalSeconds: readInt(defaults, key: "focus_timer_total_seconds"),
            focusTimerEndsAtMillis: readInt64(defaults, key: "focus_timer_ends_at_millis"),
            focusTimerLabel: readString(defaults, key: "focus_timer_label", fallback: "专注倒计时"),
            theme: DuoyiWidgetTheme(defaults: defaults)
        )
    }

    private func readString(_ defaults: UserDefaults?, key: String, fallback: String) -> String {
        guard let value = defaults?.string(forKey: key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return value
    }

    private func readPrimary(_ defaults: UserDefaults?) -> (title: String, target: String, sourceKey: String) {
        var title = readString(defaults, key: config.primaryKey, fallback: config.fallback)
        var target = readString(defaults, key: "\(config.primaryKey)_id", fallback: config.deepLink)
        var sourceKey = config.primaryKey

        if config.kind == "DuoyiAnniversaryWidget" {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle == config.fallback {
                let memorialTitle = readString(defaults, key: "memorial_highlight_1", fallback: "")
                let trimmedMemorialTitle = memorialTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedMemorialTitle.isEmpty && trimmedMemorialTitle != config.fallback {
                    title = memorialTitle
                    target = readString(defaults, key: "memorial_highlight_1_id", fallback: config.deepLink)
                    sourceKey = "memorial_highlight_1"
                }
            }
        }

        return (title, target, sourceKey)
    }

    private func readBool(_ defaults: UserDefaults?, key: String) -> Bool {
        defaults?.bool(forKey: key) ?? false
    }

    private func readInt(_ defaults: UserDefaults?, key: String) -> Int {
        defaults?.integer(forKey: key) ?? 0
    }

    private func readInt64(_ defaults: UserDefaults?, key: String) -> Int64 {
        guard let value = defaults?.object(forKey: key) else {
            return 0
        }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let string = value as? String {
            return Int64(string) ?? 0
        }
        return 0
    }

    private func readTodoRows(_ defaults: UserDefaults?) -> [DuoyiTodoRow] {
        guard config.kind == "DuoyiTodoWidget" else {
            return []
        }
        return (1...3).compactMap { index in
            let title = readString(defaults, key: "todo_top3_\(index)", fallback: "")
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return DuoyiTodoRow(
                index: index,
                title: title,
                todoId: readString(defaults, key: "todo_top3_\(index)_id", fallback: "")
            )
        }
    }

    private func readRows(_ defaults: UserDefaults?, excluding excludedKey: String? = nil) -> [DuoyiWidgetRow] {
        return config.rowKeys.enumerated().compactMap { offset, key in
            if let excludedKey = excludedKey, key == excludedKey {
                return nil
            }
            let title = readString(defaults, key: key, fallback: "")
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return DuoyiWidgetRow(
                index: offset + 2,
                title: title,
                target: readString(defaults, key: "\(key)_id", fallback: config.deepLink)
            )
        }
    }
}

private struct DuoyiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DuoyiWidgetEntry

    @ViewBuilder
    var body: some View {
        if isAccessoryFamily {
            accessoryContent
                .widgetURL(URL(string: entry.config.deepLink))
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                header
                content
                Spacer(minLength: 0)
                if family != .systemSmall {
                    footer
                }
            }
            .padding(padding)
            .duoyiWidgetBackground(entry.theme)
            .widgetURL(URL(string: entry.config.deepLink))
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(entry.theme.primary)
                .frame(width: 8, height: 8)
            Text(entry.config.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(entry.theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Text(entry.brandTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(entry.theme.mutedText)
                .lineLimit(1)
                .truncationMode(.tail)
            if let quickURL {
                Link(destination: quickURL) {
                    Text(entry.config.quickActionTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(entry.theme.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if entry.config.kind == "DuoyiTodoWidget" {
            todoContent
        } else if entry.config.kind == "DuoyiFocusWidget" {
            focusContent
        } else {
            defaultContent
        }
    }

    private var focusContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.focusTimerRunning, let endDate = entry.focusTimerEndDate, endDate > Date() {
                Text(endDate, style: .timer)
                    .font(.system(size: primarySize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.78)
                    .foregroundColor(entry.theme.primary)
                Text(entry.focusTimerLabel)
                    .font(.system(size: rowSize, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(entry.theme.mutedText)
            } else {
                linkedText(entry.primary, target: entry.primaryTarget, primary: true)
            }
            ForEach(visibleRows) { row in
                linkedText(row.title, target: row.target, primary: false)
            }
        }
    }

    private var defaultContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            linkedText(entry.primary, target: entry.primaryTarget, primary: true)
            ForEach(visibleRows) { row in
                linkedText(row.title, target: row.target, primary: false)
            }
        }
    }

    private func linkedText(_ title: String, target: String, primary: Bool) -> some View {
        Group {
            if let url = URL(string: target), !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Link(destination: url) {
                    rowText(title, primary: primary)
                }
            } else {
                rowText(title, primary: primary)
            }
        }
    }

    private func rowText(_ title: String, primary: Bool) -> some View {
        Text(cleanRow(title))
            .font(.system(size: primary ? primarySize : rowSize, weight: primary ? .semibold : .regular))
            .lineLimit(primary ? primaryLines : 1)
            .truncationMode(.tail)
            .foregroundColor(primary ? entry.theme.text : entry.theme.mutedText)
    }

    private var todoContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let first = entry.todoRows.first {
                todoRow(first, primary: true)
            } else {
                Text(entry.primary)
                    .font(.system(size: primarySize, weight: .semibold))
                    .lineLimit(primaryLines)
                    .truncationMode(.tail)
                    .foregroundColor(entry.theme.text)
            }
            ForEach(visibleTodoRows) { row in
                todoRow(row, primary: false)
            }
        }
    }

    private func todoRow(_ row: DuoyiTodoRow, primary: Bool) -> some View {
        HStack(spacing: 6) {
            if let detailURL = row.detailURL {
                Link(destination: detailURL) {
                    todoText(row.title, primary: primary)
                }
            } else {
                todoText(row.title, primary: primary)
            }
            Spacer(minLength: 0)
            if let completeURL = row.completeURL {
                Link(destination: completeURL) {
                    Text("o")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(entry.theme.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private func todoText(_ title: String, primary: Bool) -> some View {
        Text(cleanRow(title))
            .font(.system(size: primary ? primarySize : rowSize, weight: primary ? .semibold : .regular))
            .lineLimit(primary ? primaryLines : 1)
            .truncationMode(.tail)
            .foregroundColor(primary ? entry.theme.text : entry.theme.mutedText)
    }

    @ViewBuilder
    private var accessoryContent: some View {
        if #available(iOSApplicationExtension 16.0, *) {
            switch family {
            case .accessoryInline:
                Text("\(entry.config.title) \(accessoryPrimaryText)")
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 2) {
                        Text(accessorySymbol)
                            .font(.system(size: 18, weight: .bold))
                        Text(accessoryShortText)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.7)
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.config.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(accessoryPrimaryText)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let row = accessorySecondaryText {
                        Text(row)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            default:
                Text(accessoryPrimaryText)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Text(accessoryPrimaryText)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            navLink(entry.navTodo, "duoyi://todo")
            navLink(entry.navHabit, "duoyi://habit")
            navLink(entry.navCalendar, "duoyi://calendar")
            navLink(entry.navFocus, "duoyi://focus")
        }
    }

    private func navLink(_ text: String, _ urlString: String) -> some View {
        Group {
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    navText(text)
                }
            } else {
                navText(text)
            }
        }
    }

    private func navText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(entry.theme.mutedText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var visibleRows: [DuoyiWidgetRow] {
        let limit: Int
        switch family {
        case .systemSmall:
            limit = entry.displayMode == "detailed" ? 2 : 1
        case .systemMedium:
            limit = entry.displayMode == "compact" ? 2 : 3
        default:
            limit = entry.displayMode == "compact" ? 3 : 5
        }
        return Array(entry.rows.prefix(limit))
    }

    private var visibleTodoRows: [DuoyiTodoRow] {
        let limit: Int
        switch family {
        case .systemSmall:
            limit = entry.displayMode == "detailed" ? 1 : 0
        case .systemMedium:
            limit = entry.displayMode == "compact" ? 1 : 2
        default:
            limit = entry.displayMode == "compact" ? 2 : 2
        }
        return Array(entry.todoRows.dropFirst().prefix(limit))
    }

    private func cleanRow(_ row: String) -> String {
        row.replacingOccurrences(of: "· ", with: "")
    }

    private var spacing: CGFloat {
        family == .systemSmall ? 7 : 9
    }

    private var padding: CGFloat {
        family == .systemSmall ? 12 : 14
    }

    private var primarySize: CGFloat {
        family == .systemSmall ? 15 : 17
    }

    private var primaryLines: Int {
        family == .systemSmall ? 2 : 3
    }

    private var rowSize: CGFloat {
        family == .systemSmall ? 11 : 12
    }

    private var isAccessoryFamily: Bool {
        if #available(iOSApplicationExtension 16.0, *) {
            switch family {
            case .accessoryInline, .accessoryCircular, .accessoryRectangular:
                return true
            default:
                return false
            }
        }
        return false
    }

    private var accessoryPrimaryText: String {
        if entry.config.kind == "DuoyiTodoWidget", let first = entry.todoRows.first {
            return cleanRow(first.title)
        }
        if entry.config.kind == "DuoyiFocusWidget",
           entry.focusTimerRunning,
           entry.focusTimerRemainingSeconds > 0 {
            return formatMinutes(entry.focusTimerRemainingSeconds)
        }
        return cleanRow(entry.primary)
    }

    private var accessorySecondaryText: String? {
        if entry.config.kind == "DuoyiTodoWidget" {
            return entry.todoRows.dropFirst().first.map { cleanRow($0.title) }
        }
        return visibleRows.first.map { cleanRow($0.title) }
    }

    private var accessoryShortText: String {
        let text = accessoryPrimaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return entry.config.title
        }
        return String(text.prefix(4))
    }

    private var accessorySymbol: String {
        switch entry.config.kind {
        case "DuoyiTodoWidget":
            return "待"
        case "DuoyiFocusWidget":
            return "专"
        case "DuoyiHabitWidget":
            return "习"
        case "DuoyiCalendarWidget", "DuoyiScheduleWidget":
            return "历"
        case "DuoyiGoalWidget":
            return "目"
        case "DuoyiCourseWidget":
            return "课"
        case "DuoyiNoteWidget":
            return "记"
        case "DuoyiAnniversaryWidget":
            return "念"
        default:
            return "多"
        }
    }

    private func formatMinutes(_ seconds: Int) -> String {
        let minutes = max(1, (seconds + 59) / 60)
        return "\(minutes)分"
    }

    private var quickURL: URL? {
        if entry.config.kind == "DuoyiHabitWidget" {
            let id = entry.habitQuickCheckId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                return URL(string: entry.config.quickActionLink)
            }
            var components = URLComponents(string: "duoyi://action/checkin_habit")
            components?.queryItems = [URLQueryItem(name: "id", value: id)]
            return components?.url
        }
        return URL(string: entry.config.quickActionLink)
    }
}

private let todoConfig = DuoyiWidgetConfig(
    kind: "DuoyiTodoWidget",
    title: "今日待办",
    deepLink: "duoyi://todo",
    accent: .blue,
    primaryKey: "todo_top3_1",
    fallback: "今天没有未完成待办",
    rowKeys: ["todo_top3_2", "todo_top3_3"],
    quickActionTitle: "+ 添加",
    quickActionLink: "duoyi://action/quick_todo"
)

private let focusConfig = DuoyiWidgetConfig(
    kind: "DuoyiFocusWidget",
    title: "专注",
    deepLink: "duoyi://action/start_pomodoro",
    accent: .red,
    primaryKey: "next_focus_label",
    fallback: "25 分钟专注",
    rowKeys: ["focus_summary", "streak_summary"],
    quickActionTitle: "开始",
    quickActionLink: "duoyi://action/start_pomodoro"
)

private let habitConfig = DuoyiWidgetConfig(
    kind: "DuoyiHabitWidget",
    title: "习惯",
    deepLink: "duoyi://habit",
    accent: .green,
    primaryKey: "habit_summary",
    fallback: "今日习惯待打卡",
    rowKeys: ["habit_quick_check_label", "streak_summary"],
    quickActionTitle: "打卡",
    quickActionLink: "duoyi://habit"
)

private let calendarConfig = DuoyiWidgetConfig(
    kind: "DuoyiCalendarWidget",
    title: "月历",
    deepLink: "duoyi://calendar",
    accent: .indigo,
    primaryKey: "calendar_month_summary",
    fallback: "本月日期 · 今日已标记",
    rowKeys: ["today_event_summary", "schedule_highlight_2"],
    quickActionTitle: "打开",
    quickActionLink: "duoyi://calendar"
)

private let scheduleConfig = DuoyiWidgetConfig(
    kind: "DuoyiScheduleWidget",
    title: "今日日程",
    deepLink: "duoyi://calendar",
    accent: .cyan,
    primaryKey: "today_event_summary",
    fallback: "今日没有日程",
    rowKeys: ["schedule_highlight_1", "schedule_highlight_2", "schedule_highlight_3"],
    quickActionTitle: "打开",
    quickActionLink: "duoyi://calendar"
)

private let goalConfig = DuoyiWidgetConfig(
    kind: "DuoyiGoalWidget",
    title: "目标",
    deepLink: "duoyi://goal",
    accent: .orange,
    primaryKey: "goal_highlight_1",
    fallback: "暂无进行中目标",
    rowKeys: ["goal_highlight_2", "goal_highlight_3"],
    quickActionTitle: "查看",
    quickActionLink: "duoyi://goal"
)

private let courseConfig = DuoyiWidgetConfig(
    kind: "DuoyiCourseWidget",
    title: "课程表",
    deepLink: "duoyi://course",
    accent: .yellow,
    primaryKey: "course_highlight_1",
    fallback: "今日暂无课程",
    rowKeys: ["course_highlight_2", "today_event_summary"],
    quickActionTitle: "课表",
    quickActionLink: "duoyi://course"
)

private let noteConfig = DuoyiWidgetConfig(
    kind: "DuoyiNoteWidget",
    title: "随手记",
    deepLink: "duoyi://note",
    accent: .purple,
    primaryKey: "note_highlight_1",
    fallback: "暂无随手记",
    rowKeys: ["note_highlight_2", "note_highlight_3"],
    quickActionTitle: "记录",
    quickActionLink: "duoyi://note"
)

private let anniversaryConfig = DuoyiWidgetConfig(
    kind: "DuoyiAnniversaryWidget",
    title: "纪念日",
    deepLink: "duoyi://anniversary",
    accent: .pink,
    primaryKey: "anniversary_highlight_1",
    fallback: "暂无近期纪念日",
    rowKeys: ["anniversary_highlight_2", "memorial_highlight_1", "memorial_highlight_2", "memorial_highlight_3"],
    quickActionTitle: "查看",
    quickActionLink: "duoyi://anniversary"
)

private struct DuoyiAnyWidget: Widget {
    let config: DuoyiWidgetConfig

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: config.kind, provider: DuoyiWidgetProvider(config: config)) { entry in
            DuoyiWidgetView(entry: entry)
        }
        .configurationDisplayName(config.title)
        .description("多仪 \(config.title) 小组件")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if #available(iOSApplicationExtension 15.0, *) {
            families.append(.systemExtraLarge)
        }
        if #available(iOSApplicationExtension 16.0, *) {
            families.append(contentsOf: [.accessoryInline, .accessoryCircular, .accessoryRectangular])
        }
        return families
    }
}

private extension View {
    @ViewBuilder
    func duoyiWidgetBackground(_ theme: DuoyiWidgetTheme) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                duoyiWidgetBackgroundView(theme)
            }
        } else {
            self.background(duoyiWidgetBackgroundView(theme))
        }
    }

    private func duoyiWidgetBackgroundView(_ theme: DuoyiWidgetTheme) -> some View {
        LinearGradient(
            colors: [theme.background, theme.surface, theme.accentEnd.opacity(0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

@main
struct DuoyiWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DuoyiAnyWidget(config: todoConfig)
        DuoyiAnyWidget(config: focusConfig)
        DuoyiAnyWidget(config: habitConfig)
        DuoyiAnyWidget(config: calendarConfig)
        DuoyiAnyWidget(config: scheduleConfig)
        DuoyiAnyWidget(config: goalConfig)
        DuoyiAnyWidget(config: courseConfig)
        DuoyiAnyWidget(config: noteConfig)
        DuoyiAnyWidget(config: anniversaryConfig)
    }
}
