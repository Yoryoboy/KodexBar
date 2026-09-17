import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    property var entries: []
    property string errorMessage: ""
    property string errorDetail: ""
    property string generatedAt: ""
    property bool loading: false
    property bool costLoading: false
    property string costErrorMessage: ""
    property var costSummaries: ({})
    property string codexbarCommand: Plasmoid.configuration.codexbarCommand || "codexbar"
    property string selectedProvider: Plasmoid.configuration.provider || "detect"
    property string selectedSource: Plasmoid.configuration.source || "detect"
    property string activeProvider: selectedProvider
    property string activeSource: selectedSource
    property var pendingCandidates: []
    property var failedCandidates: []
    property bool showCreditsInPanel: Plasmoid.configuration.showCreditsInPanel === undefined ? true : Plasmoid.configuration.showCreditsInPanel
    property bool showUsedPercentInPanel: Plasmoid.configuration.showUsedPercentInPanel === undefined ? true : Plasmoid.configuration.showUsedPercentInPanel
    property bool showProviderInPanel: Plasmoid.configuration.showProviderInPanel === undefined ? true : Plasmoid.configuration.showProviderInPanel
    property bool showEmailInWidget: Plasmoid.configuration.showEmailInWidget === undefined ? false : Plasmoid.configuration.showEmailInWidget
    property bool includeStatus: Plasmoid.configuration.includeStatus === undefined ? false : Plasmoid.configuration.includeStatus
    property bool showCostSummary: Plasmoid.configuration.showCostSummary === undefined ? true : Plasmoid.configuration.showCostSummary
    property int refreshSeconds: Math.max(10, Plasmoid.configuration.refreshInterval || 60)
    property string selectedEntryKey: ""

    preferredRepresentation: compactRepresentation
    toolTipMainText: "KodexBar"
    toolTipSubText: {
        if (errorMessage.length > 0) {
            return errorMessage
        }
        if (entries.length > 0 && entries[0].signedOut) {
            return entries[0].errorMessage
        }
        return panelText()
    }

    function entryKey(entry) {
        if (!entry) {
            return ""
        }
        return String(entry.provider || "provider") + "|" + String(entry.account || "") + "|" + String(entry.source || "")
    }

    function selectedEntry() {
        for (var i = 0; i < entries.length; i++) {
            if (entryKey(entries[i]) === selectedEntryKey) {
                return entries[i]
            }
        }
        return entries.length > 0 ? entries[0] : null
    }

    function keepSelectionValid() {
        if (entries.length === 0) {
            selectedEntryKey = ""
            return
        }
        for (var i = 0; i < entries.length; i++) {
            if (entryKey(entries[i]) === selectedEntryKey) {
                return
            }
        }
        selectedEntryKey = entryKey(entries[0])
    }

    function paceText(entry) {
        var pace = entry && entry.pace
        if (!pace || typeof pace !== "object") {
            return ""
        }
        var parts = []
        if (pace.willLastToReset === true) {
            parts.push(i18n("On track"))
        } else if (pace.willLastToReset === false) {
            parts.push(i18n("May exhaust before reset"))
        } else if (typeof pace.headroomRatio === "number" && isFinite(pace.headroomRatio)) {
            parts.push(pace.headroomRatio >= 1 ? i18n("On track") : i18n("May exhaust before reset"))
        }
        if (typeof pace.headroomRatio === "number" && isFinite(pace.headroomRatio)) {
            parts.push(i18n("%1× headroom", Number(pace.headroomRatio).toLocaleString(Qt.locale(), "f", 1)))
        }
        if (typeof pace.expectedUsage === "number" && isFinite(pace.expectedUsage)) {
            parts.push(i18n("Expected usage %1%", Math.round(Math.max(0, pace.expectedUsage) * 100)))
        }
        if (typeof pace.reserve === "number" && isFinite(pace.reserve)) {
            parts.push(i18n("Reserve %1%", Math.round(Math.max(0, pace.reserve) * 100)))
        }
        if (typeof pace.exhaustionEstimate === "string" && pace.exhaustionEstimate.length > 0) {
            parts.push(i18n("Estimated exhaustion %1", pace.exhaustionEstimate))
        }
        return parts.join(" · ")
    }

    function humanWindowTitle(title) {
        var value = String(title || "")
        return value.replace(/[-_]+/g, " ").replace(/\b\w/g, function(letter) { return letter.toUpperCase() })
    }

    function cardRows(entry) {
        if (!entry || entry.errorMessage) {
            return []
        }
        var provider = String(entry.provider || "").toLowerCase()
        if (provider === "deepseek") {
            return entry.creditsRemaining !== null && entry.creditsRemaining !== undefined
                ? [{ label: i18n("Balance"), value: formatCurrency(entry.creditsRemaining, entry.creditsCurrencyCode || "USD"), color: Kirigami.Theme.textColor }]
                : []
        }
        var rows = []
        function add(label, left) {
            if (left !== null && left !== undefined && !isNaN(left)) {
                rows.push({ label: label, value: Math.round(root.usedPercent(left)) + "%", color: root.usageAccent(left) })
            }
        }
        add(i18n("5h"), entry.primaryPercentLeft)
        add(i18n("Weekly"), entry.secondaryPercentLeft)
        if (provider === "opencode" || provider === "opencodego") {
            add(i18n("Monthly"), entry.tertiaryPercentLeft)
        }
        return rows
    }

    function cardSummary(entry) {
        var rows = cardRows(entry)
        var values = []
        for (var i = 0; i < rows.length; i++) values.push(rows[i].label + " " + rows[i].value)
        return values.join(" · ")
    }

    function windowTitle(window, fallback) {
        if (window && typeof window.windowMinutes === "number") {
            if (window.windowMinutes === 300) return i18n("5-hour")
            if (window.windowMinutes === 10080) return i18n("Weekly")
            if (window.windowMinutes === 43200) return i18n("Monthly")
        }
        return fallback
    }

    function metadataChips(entry) {
        var chips = []
        if (entry && entry.provider) chips.push(i18n("Provider: %1", entry.name || entry.provider))
        if (entry && entry.resetCredits && typeof entry.resetCredits.availableCount === "number") {
            var count = entry.resetCredits.availableCount
            chips.push(count === 1 ? i18n("1 reset credit") : i18n("%1 reset credits", formatCredits(count)))
        }
        if (entry && entry.plan) chips.push(i18n("Login: %1", entry.plan))
        if (entry && entry.source) chips.push(i18n("Source: %1", entry.source))
        if (entry && entry.confidence && entry.confidence !== "unknown") chips.push(i18n("Confidence: %1", humanWindowTitle(entry.confidence)))
        return chips
    }

    function panelText() {
        if (entries.length === 0) {
            return loading ? i18n("Loading") : i18n("No data")
        }
        var first = selectedEntry()
        if (first && (first.errorMessage || !first.rows || first.rows.length === 0)) {
            first = null
            for (var i = 0; i < entries.length; i++) {
                if (!entries[i].errorMessage && entries[i].rows.length > 0) {
                    first = entries[i]
                    break
                }
            }
        }
        if (first === null) {
            first = entries[0]
        }
        var parts = []
        if (showProviderInPanel) {
            parts.push(first.name || "Codex")
        }
        if (first.errorMessage) {
            parts.push(first.signedOut ? i18n("Sign in") : i18n("Error"))
            return parts.join(" ")
        }
        var displayedUsed = usedPercent(first.primaryPercentLeft)
        if (displayedUsed !== null && showUsedPercentInPanel) {
            parts.push(Math.round(displayedUsed) + "%")
        }
        if (first.creditsRemaining !== null && first.creditsRemaining !== undefined && showCreditsInPanel) {
            parts.push(formatCredits(first.creditsRemaining))
        }
        return parts.join(" ")
    }

    function formatNumber(value) {
        if (value === null || value === undefined || isNaN(value)) {
            return ""
        }
        if (Math.abs(value) >= 1000) {
            return Number(value).toLocaleString(Qt.locale(), "f", 0)
        }
        return Number(value).toLocaleString(Qt.locale(), "f", 1)
    }

    function formatCurrency(value, currencyCode) {
        if (value === null || value === undefined || isNaN(value)) {
            return ""
        }
        var prefix = currencyCode === "USD" ? "$" : ((currencyCode || "") + " ")
        return prefix + Number(value).toLocaleString(Qt.locale(), "f", 2)
    }

    function formatTokenCount(value) {
        if (value === null || value === undefined || isNaN(value)) {
            return ""
        }
        var absolute = Math.abs(Number(value))
        if (absolute >= 1000000000) {
            return Number(value / 1000000000).toLocaleString(Qt.locale(), "f", absolute >= 10000000000 ? 0 : 1) + "B"
        }
        if (absolute >= 1000000) {
            return Number(value / 1000000).toLocaleString(Qt.locale(), "f", absolute >= 10000000 ? 0 : 1) + "M"
        }
        if (absolute >= 1000) {
            return Number(value / 1000).toLocaleString(Qt.locale(), "f", absolute >= 10000 ? 0 : 1) + "K"
        }
        return Number(value).toLocaleString(Qt.locale(), "f", 0)
    }

    function localDayKey(date) {
        function pad(value) {
            return value < 10 ? "0" + value : String(value)
        }
        return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
    }

    function formatCredits(value) {
        if (value === null || value === undefined || isNaN(value)) {
            return ""
        }
        var formatted = Number(value).toLocaleString(Qt.locale(), "f", 2)
        var decimalPoint = Qt.locale().decimalPoint || "."
        while (formatted.indexOf(decimalPoint) !== -1 && formatted.endsWith("0")) {
            formatted = formatted.slice(0, -1)
        }
        if (formatted.endsWith(decimalPoint)) {
            formatted = formatted.slice(0, -decimalPoint.length)
        }
        return formatted
    }

    function usedPercent(percentLeft) {
        if (percentLeft === null || percentLeft === undefined || isNaN(percentLeft)) {
            return null
        }
        return Math.max(0, Math.min(100, 100 - percentLeft))
    }

    function formatUsedPercent(percentLeft, usageKnown) {
        if (usageKnown === false) {
            return i18n("Reset only")
        }
        var used = usedPercent(percentLeft)
        if (used === null) {
            return i18n("Unavailable")
        }
        return i18n("%1% used", Math.round(used))
    }

    function formatResetTime(value) {
        if (!value) {
            return ""
        }
        var reset = new Date(value)
        var timestamp = reset.getTime()
        if (isNaN(timestamp)) {
            return ""
        }
        var diff = Math.max(0, timestamp - Date.now())
        var minutes = Math.round(diff / 60000)
        if (minutes < 1) {
            return i18n("Resets now")
        }
        var hours = Math.floor(minutes / 60)
        var days = Math.floor(hours / 24)
        if (days > 0) {
            return i18n("Resets in %1d %2h", days, hours % 24)
        }
        if (hours > 0) {
            return i18n("Resets in %1h %2m", hours, minutes % 60)
        }
        return i18n("Resets in %1m", minutes)
    }

    function resetTimeFromDescription(value) {
        if (!value) {
            return null
        }

        var text = String(value).trim()
        var direct = new Date(text)
        if (!isNaN(direct.getTime())) {
            return direct.toISOString()
        }

        var relative = /(\d+)\s*([dhm])\b/ig
        var match = null
        var minutes = 0
        while ((match = relative.exec(text)) !== null) {
            var amount = parseInt(match[1], 10)
            var unit = match[2].toLowerCase()
            if (unit === "d") {
                minutes += amount * 24 * 60
            } else if (unit === "h") {
                minutes += amount * 60
            } else {
                minutes += amount
            }
        }
        if (minutes > 0) {
            return new Date(Date.now() + minutes * 60000).toISOString()
        }

        var clock = text.match(/(?:resets?\s*)?(\d{1,2}):(\d{2})\s*(AM|PM)?/i)
        if (!clock) {
            return null
        }

        var hour = parseInt(clock[1], 10)
        var minute = parseInt(clock[2], 10)
        var meridiem = clock[3] ? clock[3].toUpperCase() : ""
        if (meridiem === "PM" && hour < 12) {
            hour += 12
        } else if (meridiem === "AM" && hour === 12) {
            hour = 0
        }

        var candidate = new Date()
        candidate.setHours(hour, minute, 0, 0)
        if (candidate.getTime() < Date.now()) {
            candidate.setDate(candidate.getDate() + 1)
        }
        return candidate.toISOString()
    }

    function commandLine(provider, source) {
        var command = shellQuote(codexbarCommand) + " usage --format json --json-only"
        if (provider && provider !== "detect") {
            command += " --provider " + shellQuote(provider)
        }
        if (source && source !== "detect") {
            command += " --source " + shellQuote(source)
        }
        if (includeStatus) {
            command += " --status"
        }
        return command
    }

    function costCommandLine() {
        var command = shellQuote(codexbarCommand) + " cost --format json --json-only"
        if (selectedProvider && selectedProvider !== "detect") {
            command += " --provider " + shellQuote(selectedProvider)
        }
        return command
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function refresh() {
        loading = true
        errorMessage = ""
        errorDetail = ""
        failedCandidates = []
        pendingCandidates = candidateList()
        executable.connectedSources = []
        refreshCost()
        tryNextCandidate()
    }

    function refreshCost() {
        costErrorMessage = ""
        if (!showCostSummary) {
            costLoading = false
            costSummaries = ({})
            applyCostSummaries()
            return
        }
        costLoading = true
        costExecutable.connectedSources = []
        costExecutable.connectSource(costCommandLine())
    }

    function candidateList() {
        var provider = selectedProvider || "detect"
        var source = selectedSource || "detect"
        var sources = source === "detect" || source === "auto" ? ["cli", "oauth", "api", "auto"] : [source]
        var result = []

        if (provider === "detect" && source === "detect") {
            result.push({ provider: "", source: "" })
        }

        if (provider !== "detect" && provider !== "all") {
            for (var i = 0; i < sources.length; i++) {
                result.push({ provider: provider, source: sources[i] })
            }
            return result
        }

        if (provider === "all" && source !== "detect") {
            return [{ provider: "all", source: source }]
        }

        return [
            { provider: "codex", source: "cli" },
            { provider: "codex", source: "oauth" },
            { provider: "codex", source: "api" },
            { provider: "claude", source: "cli" },
            { provider: "claude", source: "oauth" },
            { provider: "claude", source: "api" },
            { provider: "openai", source: "api" },
            { provider: "gemini", source: "api" },
            { provider: "copilot", source: "api" },
            { provider: "kilo", source: "cli" },
            { provider: "kilo", source: "api" },
            { provider: "kimi", source: "api" },
            { provider: "kimik2", source: "api" },
            { provider: "zai", source: "api" },
            { provider: "minimax", source: "api" },
            { provider: "kiro", source: "cli" },
            { provider: "vertexai", source: "oauth" },
            { provider: "warp", source: "api" },
            { provider: "openrouter", source: "api" },
            { provider: "elevenlabs", source: "api" },
            { provider: "ollama", source: "api" },
            { provider: "deepseek", source: "api" },
            { provider: "moonshot", source: "api" },
            { provider: "doubao", source: "api" },
            { provider: "codebuff", source: "api" },
            { provider: "crof", source: "api" },
            { provider: "venice", source: "api" },
            { provider: "bedrock", source: "api" },
            { provider: "groq", source: "api" },
            { provider: "llmproxy", source: "api" },
            { provider: "deepgram", source: "api" }
        ]
    }

    function tryNextCandidate() {
        if (pendingCandidates.length === 0) {
            loading = false
            entries = failedCandidates
            generatedAt = new Date().toLocaleString(Qt.locale(), Locale.ShortFormat)
            if (entries.length === 0) {
                errorMessage = i18n("No usable CodexBar provider found")
                errorDetail = i18n("Configure a Linux-capable provider or choose a specific provider/source.")
            }
            return
        }

        var candidate = pendingCandidates.shift()
        activeProvider = candidate.provider
        activeSource = candidate.source
        executable.connectedSources = []
        executable.connectSource(commandLine(activeProvider, activeSource))
    }

    function hasUsableEntries(normalized) {
        for (var i = 0; i < normalized.length; i++) {
            if (!normalized[i].errorMessage
                    && ((normalized[i].rows && normalized[i].rows.length > 0)
                        || normalized[i].creditsRemaining !== null
                        || normalized[i].codeReviewRemainingPercent !== null)) {
                return true
            }
        }
        return false
    }

    function appendFailedEntries(normalized) {
        var existing = failedCandidates
        for (var i = 0; i < normalized.length; i++) {
            if (normalized[i].errorMessage) {
                existing.push(normalized[i])
            }
        }
        failedCandidates = existing
    }

    function isCodexAuthenticationError(entry) {
        if (!entry || String(entry.provider || "").toLowerCase() !== "codex" || !entry.errorMessage) {
            return false
        }
        var message = String(entry.errorMessage).toLowerCase()
        return message.indexOf("authentication required") !== -1
            || message.indexOf("account authentication") !== -1
            || message.indexOf("not logged in") !== -1
            || message.indexOf("not signed in") !== -1
            || message.indexOf("login required") !== -1
            || message.indexOf("sign in required") !== -1
            || message.indexOf("signed out") !== -1
    }

    function stopForCodexAuthentication(normalized) {
        for (var i = 0; i < normalized.length; i++) {
            if (!isCodexAuthenticationError(normalized[i])) {
                continue
            }
            var entry = normalized[i]
            entry.signedOut = true
            entry.errorKind = "authentication"
            entry.errorMessage = i18n("Codex is installed, but the client is signed out. Run \"codex login\" in a terminal, then refresh.")
            loading = false
            errorMessage = ""
            errorDetail = ""
            generatedAt = new Date().toLocaleString(Qt.locale(), Locale.ShortFormat)
            entries = [withCostSummary(entry)]
            return true
        }
        return false
    }

    function parsePayload(text) {
        if (!text || text.length === 0) {
            return {
                ok: false,
                error: i18n("No output from CodexBar CLI"),
                detail: ""
            }
        }
        try {
            var raw = JSON.parse(text)
            var rawEntries = raw instanceof Array ? raw : [raw]
            var normalized = []
            for (var i = 0; i < rawEntries.length; i++) {
                if (rawEntries[i] && typeof rawEntries[i] === "object") {
                    normalized.push(normalizeEntry(rawEntries[i]))
                }
            }
            return {
                ok: true,
                entries: normalized,
                usable: hasUsableEntries(normalized)
            }
        } catch (error) {
            return {
                ok: false,
                error: i18n("Invalid CodexBar CLI response"),
                detail: String(error)
            }
        }
    }

    function parseCostPayload(text) {
        if (!text || text.length === 0) {
            return {
                ok: false,
                error: i18n("No output from CodexBar cost")
            }
        }
        try {
            var raw = JSON.parse(text)
            var rawEntries = raw instanceof Array ? raw : [raw]
            var summaries = {}
            for (var i = 0; i < rawEntries.length; i++) {
                var summary = normalizeCostSummary(rawEntries[i])
                if (summary !== null) {
                    summaries[String(summary.provider).toLowerCase()] = summary
                }
            }
            return {
                ok: true,
                summaries: summaries
            }
        } catch (error) {
            return {
                ok: false,
                error: i18n("Invalid CodexBar cost response") + ": " + String(error)
            }
        }
    }

    function normalizeCostSummary(entry) {
        if (!entry || typeof entry !== "object" || !entry.provider) {
            return null
        }
        var todayCost = typeof entry.sessionCostUSD === "number" ? entry.sessionCostUSD : null
        var todayTokens = typeof entry.sessionTokens === "number" ? entry.sessionTokens : null
        var dayKey = localDayKey(new Date())
        var daily = entry.daily instanceof Array ? entry.daily : []
        for (var i = 0; i < daily.length; i++) {
            if (daily[i] && daily[i].date === dayKey) {
                if (typeof daily[i].totalCost === "number") {
                    todayCost = daily[i].totalCost
                }
                if (typeof daily[i].totalTokens === "number") {
                    todayTokens = daily[i].totalTokens
                }
                break
            }
        }
        var totalCost = typeof entry.last30DaysCostUSD === "number"
            ? entry.last30DaysCostUSD
            : (entry.totals && typeof entry.totals.totalCost === "number" ? entry.totals.totalCost : null)
        var totalTokens = typeof entry.last30DaysTokens === "number"
            ? entry.last30DaysTokens
            : (entry.totals && typeof entry.totals.totalTokens === "number" ? entry.totals.totalTokens : null)
        if (todayCost === null && todayTokens === null && totalCost === null && totalTokens === null) {
            return null
        }
        return {
            provider: entry.provider,
            source: entry.source || "",
            currencyCode: entry.currencyCode || "USD",
            historyDays: typeof entry.historyDays === "number" ? entry.historyDays : 30,
            todayCost: todayCost,
            todayTokens: todayTokens,
            totalCost: totalCost,
            totalTokens: totalTokens,
            updatedAt: entry.updatedAt || ""
        }
    }

    function costSummaryRows(summary) {
        if (!summary) {
            return []
        }
        var rows = []
        var days = summary.historyDays || 30
        if (summary.totalTokens !== null && summary.totalTokens !== undefined) {
            rows.push({ label: i18np("1-day tokens", "%1-day tokens", days), value: formatTokenCount(summary.totalTokens) })
        }
        if (summary.totalCost !== null && summary.totalCost !== undefined) {
            rows.push({ label: i18np("1-day estimated cost", "%1-day estimated cost", days), value: formatCurrency(summary.totalCost, summary.currencyCode) })
        }
        return rows
    }

    function formatCostAndTokens(cost, tokens, currencyCode) {
        var parts = []
        if (cost !== null && cost !== undefined && !isNaN(cost)) {
            parts.push(formatCurrency(cost, currencyCode || "USD"))
        }
        if (tokens !== null && tokens !== undefined && !isNaN(tokens)) {
            parts.push(i18n("%1 tokens", formatTokenCount(tokens)))
        }
        return parts.join(" - ")
    }

    function withCostSummary(entry) {
        if (!entry || typeof entry !== "object") {
            return entry
        }
        var key = String(entry.provider || "").toLowerCase()
        var copy = {}
        for (var prop in entry) {
            copy[prop] = entry[prop]
        }
        copy.costSummary = costSummaries[key] || null
        return copy
    }

    function applyCostSummaries() {
        if (!entries || entries.length === 0) {
            return
        }
        var updated = []
        for (var i = 0; i < entries.length; i++) {
            updated.push(withCostSummary(entries[i]))
        }
        entries = updated
    }

    function providerName(raw) {
        var key = String(raw || "").toLowerCase()
        var names = {
            "abacus": "Abacus AI",
            "alibaba": "Alibaba Coding Plan",
            "alibabatokenplan": "Alibaba Token Plan",
            "amp": "Amp",
            "antigravity": "Antigravity",
            "augment": "Augment",
            "bedrock": "AWS Bedrock",
            "codex": "Codex",
            "claude": "Claude",
            "openai": "OpenAI API",
            "azureopenai": "Azure OpenAI",
            "cursor": "Cursor",
            "opencode": "OpenCode",
            "opencodego": "OpenCode Go",
            "factory": "Droid",
            "devin": "Devin",
            "zai": "z.ai",
            "minimax": "MiniMax",
            "manus": "Manus",
            "kimi": "Kimi",
            "kiro": "Kiro",
            "vertexai": "Vertex AI",
            "jetbrains": "JetBrains AI",
            "kimik2": "Kimi K2",
            "moonshot": "Moonshot",
            "synthetic": "Synthetic",
            "t3chat": "T3 Chat",
            "warp": "Warp",
            "elevenlabs": "ElevenLabs",
            "windsurf": "Windsurf",
            "perplexity": "Perplexity",
            "mimo": "Xiaomi MiMo",
            "doubao": "Doubao",
            "mistral": "Mistral",
            "deepseek": "DeepSeek",
            "codebuff": "Codebuff",
            "crof": "Crof",
            "venice": "Venice",
            "commandcode": "Command Code",
            "stepfun": "StepFun",
            "grok": "Grok",
            "groq": "GroqCloud",
            "openrouter": "OpenRouter",
            "deepgram": "Deepgram",
            "llmproxy": "LLM Proxy",
            "copilot": "Copilot",
            "gemini": "Gemini",
            "kilo": "Kilo Code",
            "ollama": "Ollama"
        }
        return names[key] || (raw ? String(raw).charAt(0).toUpperCase() + String(raw).slice(1) : i18n("Provider"))
    }

    function providerIconSource(raw) {
        var key = String(raw || "").toLowerCase()
        var icons = {
            "abacus": "abacus",
            "alibaba": "alibaba",
            "alibabatokenplan": "alibabatokenplan",
            "amp": "amp",
            "antigravity": "antigravity",
            "augment": "augment",
            "bedrock": "bedrock",
            "codex": "codex",
            "claude": "claude",
            "openai": "openai",
            "azureopenai": "azureopenai",
            "cursor": "cursor",
            "opencode": "opencode",
            "opencodego": "opencodego",
            "factory": "factory",
            "devin": "devin",
            "zai": "zai",
            "minimax": "minimax",
            "manus": "manus",
            "kimi": "kimi",
            "kiro": "kiro",
            "vertexai": "vertexai",
            "jetbrains": "jetbrains",
            "kimik2": "kimik2",
            "moonshot": "moonshot",
            "synthetic": "synthetic",
            "t3chat": "t3chat",
            "warp": "warp",
            "elevenlabs": "elevenlabs",
            "windsurf": "windsurf",
            "perplexity": "perplexity",
            "mimo": "mimo",
            "doubao": "doubao",
            "mistral": "mistral",
            "deepseek": "deepseek",
            "codebuff": "codebuff",
            "crof": "crof",
            "venice": "venice",
            "commandcode": "commandcode",
            "stepfun": "stepfun",
            "grok": "grok",
            "groq": "groq",
            "openrouter": "openrouter",
            "deepgram": "deepgram",
            "llmproxy": "llmproxy",
            "copilot": "copilot",
            "gemini": "gemini",
            "kilo": "kilo",
            "ollama": "ollama"
        }
        return Qt.resolvedUrl("../icons/providers/" + (icons[key] || "codex") + ".svg")
    }

    function percentLeft(window) {
        if (!window || typeof window !== "object") {
            return null
        }
        if (typeof window.remainingPercent === "number") {
            return Math.max(0, Math.min(100, window.remainingPercent))
        }
        if (typeof window.usedPercent === "number") {
            return Math.max(0, Math.min(100, 100 - window.usedPercent))
        }
        return null
    }

    function displayPercentLeft(provider, primary, secondary) {
        var primaryLeft = percentLeft(primary)
        if (primaryLeft !== null || String(provider || "").toLowerCase() !== "codex") {
            return primaryLeft
        }

        return percentLeft(secondary)
    }

    function resetAt(window) {
        if (!window || typeof window !== "object") {
            return null
        }

        var fields = ["resetsAt", "resetAt", "resetTime", "resetDate"]
        for (var i = 0; i < fields.length; i++) {
            if (window[fields[i]]) {
                return window[fields[i]]
            }
        }

        if (typeof window.resetTimestamp === "number") {
            var timestamp = window.resetTimestamp < 10000000000
                ? window.resetTimestamp * 1000
                : window.resetTimestamp
            return new Date(timestamp).toISOString()
        }

        return resetTimeFromDescription(window.resetDescription || window.resetsIn || "")
    }

    function windowDetail(window, usageKnown) {
        if (!window || typeof window !== "object") {
            return ""
        }
        var parts = []
        if (usageKnown === false) {
            parts.push(i18n("Usage not reported"))
        }
        if (window.resetDescription) {
            parts.push(window.resetDescription)
        }
        if (typeof window.nextRegenPercent === "number" && window.nextRegenPercent > 0) {
            parts.push(i18n("+%1% next regen", Math.round(window.nextRegenPercent)))
        }
        return parts.join(" - ")
    }

    function providerCostRow(cost) {
        if (!cost || typeof cost !== "object" || typeof cost.used !== "number" || typeof cost.limit !== "number" || cost.limit <= 0) {
            return null
        }
        var used = Math.max(0, Math.min(100, cost.used / cost.limit * 100))
        var detail = formatCurrency(cost.used, cost.currencyCode) + " / " + formatCurrency(cost.limit, cost.currencyCode)
        if (typeof cost.nextRegenAmount === "number" && cost.nextRegenAmount > 0) {
            detail += " - " + i18n("+%1 next regen", formatNumber(cost.nextRegenAmount))
        }
        return {
            title: cost.period || i18n("Spend"),
            percentLeft: Math.max(0, 100 - used),
            resetsAt: cost.resetsAt || null,
            detail: detail,
            usageKnown: true
        }
    }

    function dashboardSummary(dashboard) {
        if (!dashboard || typeof dashboard !== "object") {
            return []
        }
        var summary = []
        if (typeof dashboard.codeReviewRemainingPercent === "number") {
            summary.push(i18n("Code review: %1% remaining", Math.round(dashboard.codeReviewRemainingPercent)))
        }
        if (dashboard.accountPlan) {
            summary.push(i18n("Plan: %1", dashboard.accountPlan))
        }
        if (dashboard.creditEvents && dashboard.creditEvents.length > 0) {
            summary.push(i18np("%1 credit event", "%1 credit events", dashboard.creditEvents.length))
        }
        if (dashboard.dailyBreakdown && dashboard.dailyBreakdown.length > 0) {
            summary.push(i18np("%1 credit-history day", "%1 credit-history days", dashboard.dailyBreakdown.length))
        }
        if (dashboard.usageBreakdown && dashboard.usageBreakdown.length > 0) {
            summary.push(i18np("%1 usage-breakdown day", "%1 usage-breakdown days", dashboard.usageBreakdown.length))
        }
        return summary
    }

    function normalizeEntry(entry) {
        var usage = entry.usage && typeof entry.usage === "object" ? entry.usage : {}
        var identity = usage.identity && typeof usage.identity === "object" ? usage.identity : {}
        var credits = entry.credits && typeof entry.credits === "object" ? entry.credits : null
        var dashboard = entry.openaiDashboard && typeof entry.openaiDashboard === "object" ? entry.openaiDashboard : {}
        var error = entry.error && typeof entry.error === "object" ? entry.error : null
        var primary = usage.primary
        var secondary = usage.secondary
        var tertiary = usage.tertiary
        var providerCost = usage.providerCost && typeof usage.providerCost === "object" ? usage.providerCost : null
        var status = entry.status && typeof entry.status === "object" ? entry.status : null
        var rows = []
        var additionalRows = []
        var providerKey = String(entry.provider || "").toLowerCase()
        var windows = providerKey === "deepseek" ? []
            : (providerKey === "opencode" || providerKey === "opencodego")
            ? [{ title: windowTitle(primary, i18n("Primary")), data: primary }, { title: windowTitle(secondary, i18n("Weekly")), data: secondary }, { title: windowTitle(tertiary, i18n("Monthly")), data: tertiary }]
            : [{ title: windowTitle(primary, i18n("5-hour")), data: primary }, { title: windowTitle(secondary, i18n("Weekly")), data: secondary }]

        for (var i = 0; i < windows.length; i++) {
            var left = percentLeft(windows[i].data)
            if (left !== null) {
                rows.push({
                    title: windows[i].title,
                    percentLeft: left,
                    resetsAt: resetAt(windows[i].data),
                    detail: windowDetail(windows[i].data, true),
                    usageKnown: true
                })
            }
        }
        var extraRateWindows = usage.extraRateWindows && usage.extraRateWindows.length ? usage.extraRateWindows : []
        for (var j = 0; j < extraRateWindows.length; j++) {
            var extra = extraRateWindows[j]
            if (!extra || !extra.window) {
                continue
            }
            var extraTitle = extra.title || i18n("Extra")
            var normalizedExtraTitle = String(extraTitle).toLowerCase()
            if (normalizedExtraTitle === "session" || normalizedExtraTitle === "5-hour" || normalizedExtraTitle === "primary"
                    || normalizedExtraTitle === "weekly" || normalizedExtraTitle === "monthly" || normalizedExtraTitle === "tertiary") {
                continue
            }
            var extraLeft = percentLeft(extra.window)
            if (extraLeft !== null || resetAt(extra.window)) {
                additionalRows.push({
                    title: extraTitle,
                    percentLeft: extra.usageKnown === false ? null : extraLeft,
                    resetsAt: resetAt(extra.window),
                    detail: windowDetail(extra.window, extra.usageKnown),
                    usageKnown: extra.usageKnown !== false
                })
            }
        }
        var costRow = providerCostRow(providerCost)
        return {
            provider: entry.provider,
            name: providerName(entry.provider),
            version: entry.version,
            source: entry.source,
            account: entry.account || usage.accountEmail || identity.accountEmail || "",
            plan: usage.loginMethod || identity.loginMethod || dashboard.accountPlan || "",
            primaryPercentLeft: providerKey === "deepseek" ? null : displayPercentLeft(entry.provider, primary, secondary),
            primaryResetsAt: providerKey === "deepseek" ? null : resetAt(primary),
            secondaryPercentLeft: providerKey === "deepseek" ? null : percentLeft(secondary),
            secondaryResetsAt: providerKey === "deepseek" ? null : resetAt(secondary),
            tertiaryPercentLeft: providerKey === "deepseek" ? null : percentLeft(tertiary),
            creditsRemaining: credits ? credits.remaining : (typeof dashboard.creditsRemaining === "number" ? dashboard.creditsRemaining : null),
            codeReviewRemainingPercent: typeof dashboard.codeReviewRemainingPercent === "number" ? dashboard.codeReviewRemainingPercent : null,
            dashboardSummary: dashboardSummary(dashboard),
            pace: usage.pace && typeof usage.pace === "object" ? usage.pace
                : (usage.paceData && typeof usage.paceData === "object" ? usage.paceData
                : (primary && primary.pace && typeof primary.pace === "object" ? primary.pace
                : (secondary && secondary.pace && typeof secondary.pace === "object" ? secondary.pace
                : (entry.pace && typeof entry.pace === "object" ? entry.pace : null)))),

            resetCredits: usage.codexResetCredits && typeof usage.codexResetCredits === "object" ? usage.codexResetCredits : null,
            confidence: usage.dataConfidence || entry.dataConfidence || usage.confidence || entry.confidence || (entry.meta && entry.meta.confidence) || "",
            creditsCurrencyCode: credits && credits.currencyCode ? credits.currencyCode : (usage.currencyCode || "USD"),
            rows: rows,
            additionalRows: providerKey === "deepseek" ? [] : additionalRows,
            providerCostRow: costRow,
            updatedAt: usage.updatedAt || entry.updatedAt || "",
            status: entry.status,
            statusIndicator: status ? (status.indicator || "unknown") : "",
            statusDescription: status ? (status.description || "") : "",
            statusURL: status ? (status.url || "") : "",
            errorMessage: error ? (error.message || i18n("Provider returned an error")) : "",
            errorKind: error ? (error.kind || "") : "",
            signedOut: false
        }
    }

    function barColor(value) {
        if (value === null || value === undefined || isNaN(value)) {
            return Kirigami.Theme.disabledTextColor
        }
        if (value < 15) {
            return Kirigami.Theme.negativeTextColor
        }
        if (value < 35) {
            return Kirigami.Theme.neutralTextColor
        }
        return Kirigami.Theme.positiveTextColor
    }

    function usageAccent(percentLeft) {
        if (percentLeft === null || percentLeft === undefined || isNaN(percentLeft)) {
            return Kirigami.Theme.disabledTextColor
        }
        if (percentLeft < 15) {
            return Kirigami.Theme.negativeTextColor
        }
        if (percentLeft < 35) {
            return Kirigami.Theme.neutralTextColor
        }
        return Kirigami.Theme.highlightColor
    }

    function statusText(indicator, description) {
        if (!indicator) {
            return ""
        }
        var labels = {
            "none": i18n("Operational"),
            "minor": i18n("Partial outage"),
            "major": i18n("Major outage"),
            "critical": i18n("Critical issue"),
            "maintenance": i18n("Maintenance"),
            "unknown": i18n("Status unknown")
        }
        var label = labels[indicator] || indicator
        return description ? label + ": " + description : label
    }

    function statusColor(indicator) {
        if (indicator === "none") {
            return Kirigami.Theme.positiveTextColor
        }
        if (indicator === "minor" || indicator === "maintenance") {
            return Kirigami.Theme.neutralTextColor
        }
        if (indicator === "major" || indicator === "critical") {
            return Kirigami.Theme.negativeTextColor
        }
        return Kirigami.Theme.disabledTextColor
    }

    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: root.providerIconSource(root.entries.length > 0 ? root.entries[0].provider : "codex")
                isMask: true
                color: Kirigami.Theme.textColor
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.Label {
                text: root.panelText()
                visible: text.length > 0
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.maximumWidth: Kirigami.Units.gridUnit * 8
            }
        }
    }

    fullRepresentation: Item {
        id: full
        readonly property int popupMargin: Kirigami.Units.largeSpacing * 2
        readonly property int maxPopupHeight: Kirigami.Units.gridUnit * 44

        readonly property int maxCardRows: {
            var rows = 0
            for (var i = 0; i < root.entries.length; i++) {
                rows = Math.max(rows, root.cardRows(root.entries[i]).length)
            }
            return rows
        }
        readonly property int accountCardHeight: Kirigami.Units.iconSizes.small
            + Kirigami.Theme.defaultFont.pixelSize * (2 + (root.showEmailInWidget ? 1 : 0) + maxCardRows)
            + Kirigami.Units.smallSpacing * (3 + (root.showEmailInWidget ? 1 : 0) + maxCardRows)

        Layout.minimumWidth: Kirigami.Units.gridUnit * 30
        Layout.minimumHeight: 0
        Layout.preferredWidth: Kirigami.Units.gridUnit * 34
        Layout.preferredHeight: Math.min(content.implicitHeight + popupMargin * 2, maxPopupHeight)

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: full.popupMargin
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: full.accountCardHeight
                    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AsNeeded
                    QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff

                    Row {
                        id: accountCards
                        spacing: Kirigami.Units.smallSpacing
                        height: full.accountCardHeight

                        Repeater {
                            model: root.entries
                            delegate: Rectangle {
                                readonly property bool selected: root.entryKey(modelData) === root.selectedEntryKey
                                readonly property real used: root.usedPercent(modelData.primaryPercentLeft) || 0
                                width: Kirigami.Units.gridUnit * 6.2
                                height: full.accountCardHeight
                                radius: Kirigami.Units.cornerRadius
                                color: selected ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.16) : Kirigami.Theme.backgroundColor
                                border.width: selected ? 1 : 0
                                border.color: Kirigami.Theme.highlightColor
                                opacity: modelData.errorMessage ? 0.62 : 1

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.selectedEntryKey = root.entryKey(modelData)
                                    cursorShape: Qt.PointingHandCursor
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing / 2
                                    Kirigami.Icon {
                                        source: root.providerIconSource(modelData.provider)
                                        isMask: true
                                        color: Kirigami.Theme.textColor
                                        implicitWidth: Kirigami.Units.iconSizes.small
                                        implicitHeight: Kirigami.Units.iconSizes.small
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    PlasmaComponents.Label {
                                        text: modelData.name || modelData.provider
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        font.weight: selected ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents.Label {
                                        text: root.showEmailInWidget && modelData.account ? modelData.account : ""
                                        visible: text.length > 0
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Kirigami.Theme.disabledTextColor
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Repeater {
                                        model: root.cardRows(modelData)
                                        delegate: RowLayout {
                                            spacing: Kirigami.Units.smallSpacing / 2
                                            Layout.fillWidth: true
                                            PlasmaComponents.Label { text: modelData.label; color: Kirigami.Theme.disabledTextColor; font.pointSize: Kirigami.Theme.smallFont.pointSize; Layout.fillWidth: true }
                                            PlasmaComponents.Label { text: modelData.value; color: modelData.color; font.pointSize: Kirigami.Theme.smallFont.pointSize; font.weight: Font.DemiBold }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

            }

            Kirigami.Separator {
                visible: root.entries.length > 0
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: root.errorMessage.length > 0
                text: root.errorDetail.length > 0 ? root.errorMessage + "\n" + root.errorDetail : root.errorMessage
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                visible: root.errorMessage.length === 0 && root.entries.length === 0
                text: root.loading ? i18n("Loading usage...") : i18n("No usage data available")
                color: Kirigami.Theme.disabledTextColor
                Layout.fillWidth: true
            }

            QQC2.ScrollView {
                id: scrollView
                visible: root.entries.length > 0
                clip: true
                Layout.fillWidth: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: Math.min(contentList.implicitHeight, Kirigami.Units.gridUnit * 32)

                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                QQC2.ScrollBar.vertical.policy: contentList.implicitHeight > scrollView.height
                    ? QQC2.ScrollBar.AsNeeded
                    : QQC2.ScrollBar.AlwaysOff

                ColumnLayout {
                    id: contentList
                    width: scrollView.availableWidth
                    spacing: Kirigami.Units.largeSpacing

                    Repeater {
                        model: root.selectedEntry() ? [root.selectedEntry()] : []

                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Icon {
                                    source: root.providerIconSource(modelData.provider)
                                    isMask: true
                                    color: Kirigami.Theme.textColor
                                    implicitWidth: Kirigami.Units.iconSizes.medium
                                    implicitHeight: Kirigami.Units.iconSizes.medium
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Kirigami.Heading {
                                        text: modelData.name || modelData.provider
                                        level: 2
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents.Label {
                                        text: root.showEmailInWidget && modelData.account ? modelData.account : ""
                                        visible: text.length > 0
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents.Label {
                                        text: root.statusText(modelData.statusIndicator, modelData.statusDescription)
                                        visible: text.length > 0
                                        color: root.statusColor(modelData.statusIndicator)
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents.Label {
                                        text: root.paceText(modelData)
                                        visible: text.length > 0 && String(modelData.provider || "").toLowerCase() !== "deepseek"
                                        color: root.usageAccent(modelData.primaryPercentLeft)
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing / 2
                                visible: root.metadataChips(modelData).length > 0
                                Repeater {
                                    model: root.metadataChips(modelData)
                                    delegate: Rectangle {
                                        width: chipText.implicitWidth + Kirigami.Units.smallSpacing * 2
                                        height: chipText.implicitHeight + Kirigami.Units.smallSpacing
                                        radius: Kirigami.Units.cornerRadius
                                        color: Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.10)
                                        border.width: 1
                                        border.color: Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.22)
                                        PlasmaComponents.Label {
                                            id: chipText
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: Kirigami.Theme.disabledTextColor
                                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        }
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: String(modelData.provider || "").toLowerCase() === "opencode" || String(modelData.provider || "").toLowerCase() === "opencodego" ? 3 : 2
                                columnSpacing: Kirigami.Units.smallSpacing
                                rowSpacing: Kirigami.Units.smallSpacing
                                Repeater {
                                    model: modelData.rows || []

                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: Kirigami.Units.gridUnit * 8
                                        color: Kirigami.Theme.backgroundColor
                                        border.width: 1
                                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                                        radius: Kirigami.Units.cornerRadius
                                        implicitHeight: panelContent.implicitHeight + Kirigami.Units.smallSpacing * 2

                                        ColumnLayout {
                                            id: panelContent
                                            anchors.fill: parent
                                            anchors.margins: Kirigami.Units.smallSpacing
                                            spacing: Kirigami.Units.smallSpacing

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing

                                        Kirigami.Heading {
                                            text: modelData.title
                                            level: 4
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        PlasmaComponents.Label {
                                            text: root.formatResetTime(modelData.resetsAt)
                                            color: Kirigami.Theme.disabledTextColor
                                            visible: text.length > 0
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: Kirigami.Units.gridUnit * 9
                                        }

                                        PlasmaComponents.Label {
                                            text: root.formatUsedPercent(modelData.percentLeft, modelData.usageKnown)
                                            color: root.usageAccent(modelData.percentLeft)
                                        }
                                    }

                                    Rectangle {
                                        readonly property real used: root.usedPercent(modelData.percentLeft) || 0
                                        visible: modelData.usageKnown !== false
                                            && modelData.percentLeft !== null
                                            && modelData.percentLeft !== undefined
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 8
                                        radius: height / 2
                                        color: Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.24)
                                        clip: true

                                        Rectangle {
                                            width: Math.max(parent.height, parent.width * parent.used / 100)
                                            height: parent.height
                                            radius: parent.radius
                                            color: root.usageAccent(modelData.percentLeft)
                                        }
                                    }

                                    PlasmaComponents.Label {
                                        visible: modelData.detail && modelData.detail.length > 0
                                        text: modelData.detail || ""
                                        color: Kirigami.Theme.disabledTextColor
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                visible: modelData.additionalRows && modelData.additionalRows.length > 0
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Heading { text: i18n("Additional limits"); level: 4; Layout.fillWidth: true }
                                Repeater {
                                    model: modelData.additionalRows || []
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        PlasmaComponents.Label { text: modelData.title; Layout.fillWidth: true }
                                        PlasmaComponents.Label { text: root.formatUsedPercent(modelData.percentLeft, modelData.usageKnown); color: root.usageAccent(modelData.percentLeft) }
                                    }
                                }
                            }

                            PlasmaComponents.Label {
                                visible: modelData.errorMessage && modelData.errorMessage.length > 0
                                text: modelData.errorKind && modelData.errorKind.length > 0 && !modelData.signedOut
                                    ? modelData.errorKind + ": " + modelData.errorMessage
                                    : modelData.errorMessage
                                color: Kirigami.Theme.negativeTextColor
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.showCostSummary
                                    && modelData.costSummary
                                    && root.costSummaryRows(modelData.costSummary).length > 0
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Heading {
                                    text: i18n("Usage insights")
                                    level: 4
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents.Label {
                                    text: i18n("Additional usage data from CLI")
                                    color: Kirigami.Theme.disabledTextColor
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    Layout.fillWidth: true
                                }

                                Repeater {
                                    model: root.costSummaryRows(modelData.costSummary)

                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing

                                        PlasmaComponents.Label {
                                            text: modelData.label
                                            color: Kirigami.Theme.textColor
                                            Layout.fillWidth: true
                                        }

                                        PlasmaComponents.Label {
                                            text: modelData.value
                                            color: Kirigami.Theme.disabledTextColor
                                            horizontalAlignment: Text.AlignRight
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: Kirigami.Units.gridUnit * 16
                                        }
                                    }
                                }

                                PlasmaComponents.Label {
                                    visible: modelData.costSummary
                                    text: modelData.costSummary && modelData.costSummary.source === "local"
                                        ? i18n("Provider-level list-price estimate; not account-attributed")
                                        : (modelData.costSummary && modelData.costSummary.source
                                            ? i18n("Provider-level list-price estimate; source: %1", modelData.costSummary.source)
                                            : i18n("Provider-level list-price estimate; not account-attributed"))
                                    color: Kirigami.Theme.disabledTextColor
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: modelData.creditsRemaining !== null
                                    && modelData.creditsRemaining !== undefined

                                ColumnLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Layout.fillWidth: true

                                    Kirigami.Heading {
                                        text: String(modelData.provider || "").toLowerCase() === "deepseek" ? i18n("Balance") : i18n("Credits")
                                        level: 4
                                        Layout.fillWidth: true
                                    }

                                    PlasmaComponents.Label {
                                        visible: root.showEmailInWidget && modelData.account
                                        text: modelData.account || ""
                                        color: Kirigami.Theme.disabledTextColor
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                PlasmaComponents.Label {
                                    text: String(modelData.provider || "").toLowerCase() === "deepseek"
                                        ? root.formatCurrency(modelData.creditsRemaining, modelData.creditsCurrencyCode || "USD")
                                        : root.formatCredits(modelData.creditsRemaining)
                                    font.weight: Font.DemiBold
                                    Layout.alignment: Qt.AlignTop
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: String(modelData.provider || "").toLowerCase() !== "deepseek"
                                    && modelData.dashboardSummary && modelData.dashboardSummary.length > 0
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Heading {
                                    text: i18n("Dashboard")
                                    level: 4
                                    Layout.fillWidth: true
                                }

                                Repeater {
                                    model: modelData.dashboardSummary || []

                                    delegate: PlasmaComponents.Label {
                                        text: modelData
                                        color: Kirigami.Theme.disabledTextColor
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            PlasmaComponents.Label {
                                visible: root.showCostSummary
                                    && root.costErrorMessage.length > 0
                                    && (!modelData.costSummary)
                                text: root.costErrorMessage
                                color: Kirigami.Theme.disabledTextColor
                                wrapMode: Text.WordWrap
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                Layout.fillWidth: true
                            }

                            Kirigami.Separator {
                                visible: false
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                visible: root.entries.length === 0
                text: root.generatedAt.length > 0 ? i18n("Updated %1", root.generatedAt) : ""
                color: Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: root.generatedAt.length > 0 ? i18n("Updated %1", root.generatedAt) : ""
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    elide: Text.ElideLeft
                }
                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Refresh")
                    enabled: !root.loading
                    onClicked: root.refresh()
                }
            }
        }
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            if (data["exit code"] && data["exit code"] !== 0 && !(data.stdout || "").length) {
                var errorEntry = root.normalizeEntry({
                    provider: root.activeProvider,
                    source: root.activeSource,
                    error: {
                        kind: "runtime",
                        message: data.stderr || i18n("Exit code %1", data["exit code"])
                    }
                })
                if (root.stopForCodexAuthentication([errorEntry])) {
                    return
                }
                root.appendFailedEntries([errorEntry])
                root.tryNextCandidate()
                return
            }
            var result = root.parsePayload(data.stdout || "")
            if (!result.ok) {
                var parseErrorEntry = root.normalizeEntry({
                    provider: root.activeProvider,
                    source: root.activeSource,
                    error: { kind: "runtime", message: result.error + (result.detail ? ": " + result.detail : "") }
                })
                root.appendFailedEntries([parseErrorEntry])
                root.tryNextCandidate()
                return
            }
            if (!result.usable && root.stopForCodexAuthentication(result.entries)) {
                return
            }
            if (!result.usable && root.pendingCandidates.length > 0) {
                root.appendFailedEntries(result.entries)
                root.tryNextCandidate()
                return
            }
            root.loading = false
            root.errorMessage = ""
            root.errorDetail = ""
            root.generatedAt = new Date().toLocaleString(Qt.locale(), Locale.ShortFormat)
            var updatedEntries = []
            for (var i = 0; i < result.entries.length; i++) {
                updatedEntries.push(root.withCostSummary(result.entries[i]))
            }
            root.entries = updatedEntries
        }
    }

    Plasma5Support.DataSource {
        id: costExecutable
        engine: "executable"
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            root.costLoading = false
            if (data["exit code"] && data["exit code"] !== 0 && !(data.stdout || "").length) {
                root.costErrorMessage = data.stderr || i18n("Cost scan failed with exit code %1", data["exit code"])
                root.costSummaries = ({})
                root.applyCostSummaries()
                return
            }
            var result = root.parseCostPayload(data.stdout || "")
            if (!result.ok) {
                root.costErrorMessage = result.error
                root.costSummaries = ({})
                root.applyCostSummaries()
                return
            }
            root.costErrorMessage = ""
            root.costSummaries = result.summaries
            root.applyCostSummaries()
        }
    }

    Timer {
        id: refreshTimer
        interval: root.refreshSeconds * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    onEntriesChanged: keepSelectionValid()

    onRefreshSecondsChanged: {
        refreshTimer.restart()
        refresh()
    }

    onCodexbarCommandChanged: refresh()
    onSelectedProviderChanged: refresh()
    onSelectedSourceChanged: refresh()
    onShowCostSummaryChanged: refreshCost()
    onShowCreditsInPanelChanged: panelText()
    onShowUsedPercentInPanelChanged: panelText()
    onShowProviderInPanelChanged: panelText()
}
