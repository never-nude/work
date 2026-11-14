import Foundation

// Caches and logs: things that come back on their own.

extension Rule {
    /// Well-known names in `~/Library/Caches` and `~/.cache` that are not bundle identifiers,
    /// with the apps that should be quit before emptying them.
    private static let knownCacheOwners: [String: (name: String, apps: [String])] = [
        "google": ("Google Chrome", ["com.google.Chrome", "Google Chrome"]),
        "firefox": ("Firefox", ["org.mozilla.firefox", "Firefox"]),
        "mozilla": ("Mozilla", ["org.mozilla.firefox", "Firefox"]),
        "bravesoftware": ("Brave", ["com.brave.Browser", "Brave Browser"]),
        "microsoft edge": ("Microsoft Edge", ["com.microsoft.edgemac", "Microsoft Edge"]),
        "microsoft": ("Microsoft", []),
        "jetbrains": ("JetBrains IDEs", ["com.jetbrains"]),
        "adobe": ("Adobe", []),
        "spotify": ("Spotify", ["com.spotify.client", "Spotify"]),
        "sentrycrash": ("Crash reporter data", []),
        "gopls": ("gopls", []),
        "golangci-lint": ("golangci-lint", []),
        "pre-commit": ("pre-commit", []),
        "gh": ("GitHub CLI", []),
        "turbo": ("Turborepo", []),
        "prisma": ("Prisma engines", []),
        "fontconfig": ("fontconfig", []),
        "mesa_shader_cache": ("Mesa shader cache", []),
        "node": ("Node", []),
    ]

    private static let reverseDNSPrefixes: Set<String> = [
        "com", "org", "net", "io", "dev", "app", "co", "me", "us", "uk", "de", "fr", "jp", "ca", "au",
        "ch", "nl", "se", "it", "es", "eu", "in", "ai", "md", "tv", "fm", "sh", "so", "xyz", "gg",
        "company", "design", "software", "studio", "tech", "tools", "cloud", "page", "info", "edu",
    ]

    /// True for names shaped like `com.vendor.App`, which is how apps name their cache folders.
    static func looksLikeBundleIdentifier(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, !parts.contains(where: \.isEmpty) else { return false }
        return parts.count >= 3 || reverseDNSPrefixes.contains(parts[0].lowercased())
    }

    /// Third-party app caches: every entry of `~/Library/Caches` and `~/.cache` that no
    /// specific rule owns and that does not belong to macOS.
    static let appCaches = Rule(
        id: "caches.apps",
        title: "App caches",
        blurb: "What third-party apps stash in ~/Library/Caches and ~/.cache. They rebuild it as needed.",
        tier: .safe,
        symbol: "square.stack.3d.up",
        detect: { context in
            var found: [Candidate] = []
            for parent in ["Library/Caches", ".cache"] {
                guard let root = context.directory(parent) else { continue }
                for child in context.children(of: root) {
                    guard child.stat.kind == .directory || child.stat.kind == .file else { continue }
                    guard !child.name.hasPrefix(".") else { continue }
                    let lower = child.name.lowercased()
                    if SafetyGuard.isAppleOwnedCache(child.name) || lower.hasPrefix("com.apple.dt.") { continue }
                    if context.isClaimed(parent + "/" + child.name) { continue }

                    let known = knownCacheOwners[lower]
                    // Reverse-DNS names are app bundle identifiers. Anything else is only
                    // pre-selected when it is a name we recognise.
                    let looksLikeBundleID = looksLikeBundleIdentifier(child.name)
                    var policy: SelectionPolicy = (known != nil || looksLikeBundleID) ? .always : .never
                    var caution: String?
                    if let running = context.env.runningApp(matching: [child.name] + (known?.apps ?? [])) {
                        policy = .never
                        caution = "\(known?.name ?? running) is running"
                    }
                    found.append(Candidate(
                        key: parent + "/" + child.name,
                        title: known?.name ?? child.name,
                        subtitle: context.tilde(child.path),
                        paths: [child.path],
                        action: child.stat.kind == .directory ? .deleteContents : .delete,
                        scope: .under([root]),
                        policy: policy,
                        caution: caution
                    ))
                }
            }
            return found
        }
    )

    /// Chromium-family browsers. Paths are relative to `~/Library/Application Support`.
    private static let browsers: [(name: String, root: String, apps: [String])] = [
        ("Google Chrome", "Google/Chrome", ["com.google.Chrome", "Google Chrome"]),
        ("Chrome Beta", "Google/Chrome Beta", ["com.google.Chrome.beta"]),
        ("Chrome Canary", "Google/Chrome Canary", ["com.google.Chrome.canary"]),
        ("Brave", "BraveSoftware/Brave-Browser", ["com.brave.Browser", "Brave Browser"]),
        ("Microsoft Edge", "Microsoft Edge", ["com.microsoft.edgemac", "Microsoft Edge"]),
        ("Arc", "Arc/User Data", ["company.thebrowser.Browser", "Arc"]),
        ("Dia", "Dia/User Data", ["company.thebrowser.dia", "Dia"]),
        ("Chromium", "Chromium", ["org.chromium.Chromium", "Chromium"]),
        ("Vivaldi", "Vivaldi", ["com.vivaldi.Vivaldi", "Vivaldi"]),
        ("Opera", "com.operasoftware.Opera", ["com.operasoftware.Opera", "Opera"]),
    ]

    /// Folders whose presence says "this is a Chromium profile".
    private static let chromiumSignature = ["Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache"]

    /// Extra identifiers for Electron apps whose folder name is not their app name.
    private static let electronAliases: [String: [String]] = [
        "code": ["com.microsoft.VSCode", "Visual Studio Code"],
        "code - insiders": ["com.microsoft.VSCodeInsiders", "Visual Studio Code - Insiders"],
        "cursor": ["com.todesktop.230313mzl4w4u92", "Cursor"],
        "windsurf": ["com.exafunction.windsurf", "Windsurf"],
        "slack": ["com.tinyspeck.slackmacgap"],
        "discord": ["com.hnc.Discord"],
        "claude": ["com.anthropic.claudefordesktop"],
        "notion": ["notion.id"],
        "figma": ["com.figma.Desktop"],
        "obsidian": ["md.obsidian"],
        "signal": ["org.whispersystems.signal-desktop"],
        "linear": ["com.linear"],
        "postman": ["com.postmanlabs.mac"],
        "github desktop": ["com.github.GitHubClient"],
        "microsoft teams": ["com.microsoft.teams2", "com.microsoft.teams"],
    ]

    /// Apps whose folders Cull stays out of entirely, cache or not.
    private static let electronOffLimits = [
        "password", "bitwarden", "keepass", "lastpass", "dashlane", "enpass", "wallet",
        "ledger", "exodus", "electrum", "metamask", "authy", "proton",
    ]

    private static func cacheFolders(in profile: String, context: RuleContext) -> [String] {
        SafetyGuard.chromiumCacheNames.compactMap { name in
            context.directory(atPath: Posix.join(profile, name))
        }
    }

    /// Caches of Chromium browsers and Electron apps, which live in Application Support
    /// rather than in Caches.
    static let chromiumCaches = Rule(
        id: "caches.chromium",
        title: "Browser & Electron caches",
        blurb: "Web caches of Chrome-family browsers and Electron apps like VS Code, Slack and Discord. Logins and settings are not touched.",
        tier: .safe,
        symbol: "globe",
        detect: { context in
            guard let support = context.directory("Library/Application Support") else { return [] }
            var found: [Candidate] = []
            var browserVendors = Set<String>()

            for browser in browsers {
                browserVendors.insert(String(browser.root.split(separator: "/")[0]).lowercased())
                guard let root = context.directory(atPath: Posix.join(support, browser.root)) else { continue }
                var paths = cacheFolders(in: root, context: context)
                for child in context.children(of: root) where child.stat.kind == .directory {
                    let isProfile = child.name == "Default" || child.name.hasPrefix("Profile ")
                        || child.name == "Guest Profile" || child.name == "System Profile"
                    if isProfile { paths += cacheFolders(in: child.path, context: context) }
                }
                guard !paths.isEmpty else { continue }
                var policy = SelectionPolicy.always
                var caution: String?
                if context.env.runningApp(matching: browser.apps) != nil {
                    policy = .never
                    caution = "\(browser.name) is running"
                }
                found.append(Candidate(
                    key: browser.root, title: browser.name, subtitle: context.tilde(root), paths: paths,
                    action: .deleteContents, scope: .under([support]), policy: policy, caution: caution
                ))
            }

            for child in context.children(of: support) where child.stat.kind == .directory {
                let lower = child.name.lowercased()
                if child.name.hasPrefix(".") || lower.hasPrefix("com.apple.") || lower == "mobilesync" { continue }
                if browserVendors.contains(lower) { continue }
                if electronOffLimits.contains(where: { lower.contains($0) }) { continue }
                let isChromium = chromiumSignature.contains { context.isDirectory(Posix.join(child.path, $0)) }
                guard isChromium else { continue }
                let paths = cacheFolders(in: child.path, context: context)
                guard !paths.isEmpty else { continue }
                var policy = SelectionPolicy.always
                var caution: String?
                if context.env.runningApp(matching: [child.name] + (electronAliases[lower] ?? [])) != nil {
                    policy = .never
                    caution = "\(child.name) is running"
                }
                found.append(Candidate(
                    key: child.name, title: child.name, subtitle: context.tilde(child.path), paths: paths,
                    action: .deleteContents, scope: .under([support]), policy: policy, caution: caution
                ))
            }
            return found
        }
    )

    private static let appleContainerNames: [String: String] = [
        "com.apple.safari": "Safari", "com.apple.music": "Music", "com.apple.podcasts": "Podcasts",
        "com.apple.tv": "TV", "com.apple.news": "News", "com.apple.maps": "Maps",
    ]

    /// Caches of sandboxed apps, which live in each app's container.
    static let containerCaches = Rule(
        id: "caches.containers",
        title: "Sandboxed app caches",
        blurb: "Caches of App Store apps and Safari, kept inside each app's container.",
        tier: .safe,
        symbol: "shippingbox",
        needsFullDiskAccess: true,
        detect: { context in
            guard let containers = context.directory("Library/Containers") else { return [] }
            var found: [Candidate] = []
            for child in context.children(of: containers) where child.stat.kind == .directory {
                let lower = child.name.lowercased()
                // Extension containers are named by UUID; only apps have reverse-DNS names.
                guard child.name.split(separator: ".").count >= 2, UUID(uuidString: child.name) == nil else { continue }
                if lower.hasPrefix("com.apple."), !SafetyGuard.appleContainersAllowed.contains(lower) { continue }
                guard let caches = context.directory(atPath: child.path + "/Data/Library/Caches") else { continue }
                var policy = SelectionPolicy.always
                var caution: String?
                if context.env.runningApp(matching: [child.name]) != nil {
                    policy = .never
                    caution = "The app is running"
                }
                found.append(Candidate(
                    key: child.name, title: appleContainerNames[lower] ?? child.name,
                    subtitle: context.tilde(caches), paths: [caches],
                    action: .deleteContents, scope: .under([containers]), policy: policy, caution: caution
                ))
            }
            return found
        }
    )

    /// Caches of the package managers and build tools a developer machine collects.
    static let packageCaches = Rule.locations(
        id: "caches.packages",
        title: "Package manager caches",
        blurb: "Downloads kept by npm, Yarn, pip, Homebrew, SwiftPM and friends. Each re-fetches what it needs.",
        tier: .safe,
        symbol: "archivebox",
        [
            Location(label: "npm", paths: [".npm/_cacache", ".npm/_npx", ".npm/_logs"]),
            Location(label: "Yarn", paths: ["Library/Caches/Yarn", ".yarn/berry/cache", ".cache/yarn"]),
            Location(label: "pnpm metadata", paths: ["Library/Caches/pnpm"]),
            Location(label: "Bun", paths: [".bun/install/cache"]),
            Location(label: "Deno", paths: ["Library/Caches/deno"]),
            Location(label: "node-gyp", paths: ["Library/Caches/node-gyp"]),
            Location(label: "Corepack", paths: ["Library/Caches/node/corepack", ".cache/node/corepack"]),
            Location(label: "TypeScript", paths: ["Library/Caches/typescript"]),
            Location(label: "Electron downloads", paths: ["Library/Caches/electron", "Library/Caches/electron-builder"]),
            Location(label: "pip", paths: ["Library/Caches/pip", ".cache/pip"]),
            Location(label: "uv", paths: ["Library/Caches/uv", ".cache/uv"]),
            Location(label: "Poetry", paths: ["Library/Caches/pypoetry/cache", "Library/Caches/pypoetry/artifacts"]),
            Location(label: "Homebrew downloads", paths: ["Library/Caches/Homebrew"]),
            Location(label: "SwiftPM", paths: ["Library/Caches/org.swift.swiftpm"]),
            Location(label: "CocoaPods", paths: ["Library/Caches/CocoaPods"]),
            Location(label: "Carthage", paths: ["Library/Caches/org.carthage.CarthageKit", "Library/Caches/carthage"]),
            Location(label: "Go build cache", paths: ["Library/Caches/go-build"]),
            Location(label: "Cargo registry", paths: [".cargo/registry/cache", ".cargo/registry/src"]),
            Location(label: "Composer", paths: ["Library/Caches/composer"]),
        ]
    )

    /// Tools and models that were downloaded once and take a deliberate step to get back.
    static let toolDownloads = Rule(
        id: "tools.downloads",
        title: "Downloaded tools & models",
        blurb: "Test browsers, package stores and model weights. Culling one means running its installer or download again.",
        tier: .rebuildable,
        symbol: "arrow.down.circle",
        claims: [
            "Library/Caches/ms-playwright", "Library/Caches/Cypress", ".cache/puppeteer", "Library/pnpm/store",
            ".gradle/caches", ".cache/huggingface", ".cache/torch", ".cache/whisper", ".cache/lm-studio",
        ],
        detect: { context in
            let fixed: [(String, String)] = [
                ("Playwright browsers", "Library/Caches/ms-playwright"),
                ("Cypress binary", "Library/Caches/Cypress"),
                ("Puppeteer browsers", ".cache/puppeteer"),
                ("pnpm store", "Library/pnpm/store"),
                ("Gradle caches", ".gradle/caches"),
                ("PyTorch hub", ".cache/torch"),
                ("Whisper models", ".cache/whisper"),
            ]
            var found: [Candidate] = fixed.compactMap { label, relative in
                guard let path = context.directory(relative) else { return nil }
                return Candidate(
                    key: relative, title: label, subtitle: context.tilde(path), paths: [path],
                    action: .deleteContents, scope: .under([Posix.parent(of: path)]), policy: .never
                )
            }
            // One row per Hugging Face repository: they are large and chosen one by one.
            if let hub = context.directory(".cache/huggingface/hub") {
                for child in context.children(of: hub) where child.stat.kind == .directory {
                    guard !child.name.hasPrefix(".") else { continue }
                    let pretty = child.name
                        .replacingOccurrences(of: "models--", with: "")
                        .replacingOccurrences(of: "datasets--", with: "dataset ")
                        .replacingOccurrences(of: "--", with: "/")
                    found.append(Candidate(
                        key: "huggingface/" + child.name, title: "Hugging Face · \(pretty)",
                        subtitle: context.tilde(child.path), paths: [child.path],
                        action: .delete, scope: .under([hub]), policy: .never
                    ))
                }
            }
            return found
        }
    )

    static let userLogs = Rule(
        id: "logs.user",
        title: "Logs & crash reports",
        blurb: "Log files and diagnostic reports apps have written to ~/Library/Logs.",
        tier: .safe,
        symbol: "doc.text",
        detect: { context in
            guard let logs = context.directory("Library/Logs") else { return [] }
            return context.children(of: logs).compactMap { child in
                guard child.stat.kind == .directory || child.stat.kind == .file else { return nil }
                guard !child.name.hasPrefix("."), !context.isClaimed("Library/Logs/" + child.name) else { return nil }
                return Candidate(
                    key: child.name, title: child.name, subtitle: context.tilde(child.path), paths: [child.path],
                    action: child.stat.kind == .directory ? .deleteContents : .delete,
                    scope: .under([logs])
                )
            }
        }
    )

    static let firmware = Rule.locations(
        id: "ios.firmware",
        title: "iOS firmware downloads",
        blurb: "IPSW installers left over from updating or restoring a device through Finder.",
        tier: .safe,
        symbol: "iphone.and.arrow.forward",
        [
            Location(label: "iPhone software updates", paths: ["Library/iTunes/iPhone Software Updates"]),
            Location(label: "iPad software updates", paths: ["Library/iTunes/iPad Software Updates"]),
            Location(label: "iPod software updates", paths: ["Library/iTunes/iPod Software Updates"]),
        ]
    )
}
