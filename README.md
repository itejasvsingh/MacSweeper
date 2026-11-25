# MacSweeper

A free, simple Mac app that frees up storage space, removes junk files, and completely uninstalls apps you no longer need.

---

## How to Install

### Option 1: Fastest Way (Recommended — No Mac Popups)
You don't need any tech experience—just copy and paste one line:

1. Press **Command (⌘) + Space** on your keyboard to open Spotlight Search.
2. Type **Terminal** and press **Return**.
3. Copy the line below, paste it into the Terminal window, and press **Return**:

```bash
curl -fsSL [https://raw.githubusercontent.com/itejasvsingh/MacSweeper/main/install.sh](https://raw.githubusercontent.com/itejasvsingh/MacSweeper/main/install.sh) | bash
```

MacSweeper will automatically download, install into your **Applications** folder, and open for you.

---

### Option 2: Download from Your Browser
1. **[Click here to download MacSweeper](https://github.com/itejasvsingh/MacSweeper/releases/latest/download/MacSweeper.zip)**
2. Double-click the downloaded **MacSweeper.zip** file to unzip it.
3. Drag **MacSweeper** into your **Applications** folder.

> **Seeing a "MacSweeper is damaged" message?**  
> Don't worry—the app is not actually damaged! Because MacSweeper is a free, independent app (not sold on the Mac App Store), macOS blocks browser downloads by default.  
> To allow it once: open **Terminal** (press **⌘ + Space**, type **Terminal**, press **Return**), paste this line, and press **Return**:
> ```bash
> xattr -cr /Applications/MacSweeper.app
> ```
> Then open **MacSweeper** from your Applications folder normally.

---

## What MacSweeper Does
- **Frees Up "System Data":** Finds hidden cache files, old logs, and temporary data safely—with green **Safe** badges so you always know what's okay to remove.
- **Finds Large & Forgotten Files:** Scans your Downloads, Desktop, and Documents for huge files and old installers taking up space.
- **Completely Uninstalls Apps:** Deleting an app normally leaves hidden junk behind. MacSweeper removes the app *and* all its leftover files together.
- **SmartDelete:** Automatically notices when you drag an app to the Trash and offers to clean up its leftover files for you.
- **Startup Manager:** Shows background apps that launch when you turn on your Mac so you can remove ones you don't need.
- **Automatic Updates:** Checks for new versions automatically and updates itself with one click.

## Is It Safe?
Yes. MacSweeper **never permanently deletes your files**—everything you clean is moved to your regular Mac **Trash**, so you can always put something back if you change your mind.
