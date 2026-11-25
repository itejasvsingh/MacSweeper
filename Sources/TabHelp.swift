import Foundation

struct TabHelpInfo {
    let title: String
    let message: String

    static func info(for tabTitle: String) -> TabHelpInfo {
        switch tabTitle {
        case "System Data":
            return TabHelpInfo(
                title: "What is System Data?",
                message: "macOS stores hidden app caches, old logs, temporary files, and Time Machine snapshots under 'System Data'. Items marked with a green 'Safe' badge can be trashed safely—your apps will simply rebuild what they need."
            )
        case "Large & Old Files":
            return TabHelpInfo(
                title: "What is Large & Old Files?",
                message: "Scans your Downloads, Desktop, and Documents folders for files over 100 MB, forgotten .dmg app installers, and old .zip archives that are quietly taking up space."
            )
        case "Homebrew":
            return TabHelpInfo(
                title: "What is Homebrew?",
                message: "Homebrew is a developer tool used to install command-line apps on Mac. Here you can see what's installed, remove packages you no longer need, and run 'brew cleanup' to clear old download caches."
            )
        case "Docker":
            return TabHelpInfo(
                title: "What is Docker?",
                message: "Docker runs virtual containers for software development, which can eat up tens of gigabytes in unused images and build caches. Use this tab to see Docker's disk usage and safely prune unused data."
            )
        case "Startup Items":
            return TabHelpInfo(
                title: "What are Startup Items?",
                message: "Background helper apps (LaunchAgents and LaunchDaemons) that start automatically when you turn on your Mac. Removing ones you don't recognize or need can speed up login and save battery."
            )
        case "App Uninstaller":
            return TabHelpInfo(
                title: "What is App Uninstaller?",
                message: "Dragging an app to the Trash normally leaves behind hidden support files and caches in your Library folder. This tab removes the app AND all its hidden leftovers together."
            )
        case "Duplicates":
            return TabHelpInfo(
                title: "What is Duplicate Finder?",
                message: "Compares file sizes and SHA-256 hashes across Downloads, Desktop, and Documents to find exact duplicate files over 1 MB so you can safely trash extra copies."
            )
        case "RAM & CPU":
            return TabHelpInfo(
                title: "What is RAM & CPU?",
                message: "Shows the top apps and background processes using your Mac's memory or processor right now, with one-click Quit and Force Quit buttons."
            )
        case "Space Lens":
            return TabHelpInfo(
                title: "What is Space Lens?",
                message: "Visualizes your largest folders with proportional bars so you can click into folders and quickly spot where gigabytes are hiding."
            )
        case "Browser Cleaner":
            return TabHelpInfo(
                title: "What is Browser Cleaner?",
                message: "Clears heavy temporary caches from Chrome, Safari, Arc, Brave, Firefox, and Edge without deleting your saved passwords, bookmarks, or logins."
            )
        case "Orphaned Leftovers":
            return TabHelpInfo(
                title: "What are Orphaned Leftovers?",
                message: "Finds large folders left behind in your Library by apps you already deleted in the past, so you can reclaim that wasted space."
            )
        default:
            return TabHelpInfo(
                title: tabTitle,
                message: "Everything you clean in MacSweeper is moved safely to your Mac Trash first, so you can always put it back if needed."
            )
        }
    }
}
