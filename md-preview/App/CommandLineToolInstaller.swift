//
//  CommandLineToolInstaller.swift
//  md-preview
//
//  Installs the bundled `md-preview` command line tool by writing a small
//  installer script and running it in Terminal. The script chooses a PATH
//  directory, refuses to replace anything it did not install, and asks for
//  sudo only when the chosen directory needs it. Split out of AppDelegate,
//  which had grown to hold the whole 150-line script.
//

import AppKit

enum CommandLineToolInstaller {
    /// Writes the installer script and runs it in Terminal, so the sudo
    /// prompt and the script's output stay in a real terminal window.
    static func install() throws {
        let toolURL = try bundledToolURL()
        let scriptURL = try writeInstallerScript(commandLineToolURL: toolURL)
        try runInTerminal(makeInstallCommand(scriptURL: scriptURL))
    }

    private static func makeInstallerScript(commandLineToolURL: URL) -> String {
        """
        #!/bin/sh
        set -eu
        installer_path=$0
        trap 'rm -f "$installer_path"' EXIT
        bundled_cli=\(commandLineToolURL.path.shellQuotedString)

        path_contains() {
          case ":$PATH:" in
            *":$1:"*) return 0 ;;
            *) return 1 ;;
          esac
        }

        can_install_without_sudo() {
          dir="$1"
          if [ -d "$dir" ]; then
            [ -w "$dir" ] && [ -x "$dir" ]
            return
          fi

          parent="${dir%/*}"
          [ "$parent" != "$dir" ] || parent="."
          [ -d "$parent" ] && [ -w "$parent" ] && [ -x "$parent" ]
        }

        is_safe_path_dir() {
          case "$1" in
            ""|.|/bin|/sbin|/usr/bin|/usr/sbin|/System/*) return 1 ;;
            /*) return 0 ;;
            *) return 1 ;;
          esac
        }

        choose_install_dir() {
          for dir in "$HOME/.local/bin" "$HOME/bin"; do
            if path_contains "$dir" && can_install_without_sudo "$dir"; then
              printf '%s\t%s\n' "$dir" "false"
              return 0
            fi
          done

          old_ifs=$IFS
          IFS=:
          set -- $PATH
          IFS=$old_ifs

          for dir in /usr/local/bin /opt/homebrew/bin; do
            if path_contains "$dir"; then
              if can_install_without_sudo "$dir"; then
                printf '%s\t%s\n' "$dir" "false"
              else
                printf '%s\t%s\n' "$dir" "true"
              fi
              return 0
            fi
          done

          for dir do
            if is_safe_path_dir "$dir" && can_install_without_sudo "$dir"; then
              printf '%s\t%s\n' "$dir" "false"
              return 0
            fi
          done

          for dir do
            if is_safe_path_dir "$dir"; then
              printf '%s\t%s\n' "$dir" "true"
              return 0
            fi
          done

          return 1
        }

        choice=$(choose_install_dir) || {
          echo "Could not find a usable PATH directory for Markdown Preview command line tools." >&2
          exit 1
        }

        install_dir=${choice%	*}
        needs_sudo=${choice#*	}
        primary="$install_dir/md-preview"

        is_markdown_preview_launcher() {
          path="$1"
          [ -f "$path" ] && [ ! -L "$path" ] || return 1
          if grep -q '^# Managed by Markdown Preview CLI$' "$path"; then
            return 0
          fi
          grep -q 'exec open -b "doc.md-preview"' "$path"
        }

        can_replace_primary() {
          path="$1"
          if [ ! -e "$path" ] && [ ! -L "$path" ]; then
            return 0
          fi
          is_markdown_preview_launcher "$path"
        }

        can_replace_alias() {
          alias_path="$1"
          if [ ! -e "$alias_path" ] && [ ! -L "$alias_path" ]; then
            return 0
          fi
          [ -L "$alias_path" ] || return 1
          alias_target=$(readlink "$alias_path" || true)
          [ "$alias_target" = "md-preview" ] ||
            [ "$alias_target" = "$primary" ] ||
            [ "$alias_target" = "$install_dir/md-preview" ]
        }

        refuse_existing_command() {
          echo "Refusing to replace existing command that was not installed by Markdown Preview: $1" >&2
          exit 1
        }

        can_replace_primary "$primary" || refuse_existing_command "$primary"
        for alias in mdp markdown-preview; do
          can_replace_alias "$install_dir/$alias" || refuse_existing_command "$install_dir/$alias"
        done

        if [ "$needs_sudo" = "true" ]; then
          echo "Installing Markdown Preview command line tools to $install_dir requires your password."
          sudo mkdir -p "$install_dir"
          sudo install -m 755 "$bundled_cli" "$primary"
        else
          mkdir -p "$install_dir"
          install -m 755 "$bundled_cli" "$primary"
        fi

        for alias in mdp markdown-preview; do
          alias_path="$install_dir/$alias"
          if [ "$needs_sudo" = "true" ]; then
            sudo ln -sfn "md-preview" "$alias_path"
          else
            ln -sfn "md-preview" "$alias_path"
          fi
        done

        echo
        echo "Markdown Preview CLI is ready."
        echo
        echo "Use any of these commands:"
        echo "  mdp"
        echo "  md-preview"
        echo "  markdown-preview"
        echo
        echo "Examples:"
        echo "  mdp README.md        Open a Markdown file"
        echo "  mdp .                Open the current folder"
        echo "  mdp docs             Browse a folder in Markdown Preview"
        echo
        echo "Tips:"
        echo "  Use mdp for the shortest command."
        echo "  Re-run Install CLI after updating the app to refresh these commands."
        echo "  Installed in: $install_dir"
        echo

        if command -v mdp >/dev/null 2>&1; then
          echo "Try it now: mdp ."
        else
          echo "Open a new terminal window, then try: mdp ."
        fi
        """
    }

    private static func bundledToolURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "markdown-preview",
                                        withExtension: nil,
                                        subdirectory: "bin") else {
            throw CommandLineToolInstallError.bundledToolMissing
        }
        return url
    }

    private static func writeInstallerScript(commandLineToolURL: URL) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("install-markdown-preview-cli-\(UUID().uuidString).sh")

        do {
            try makeInstallerScript(commandLineToolURL: commandLineToolURL)
                .write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                  ofItemAtPath: url.path)
            return url
        } catch {
            throw CommandLineToolInstallError.installerScriptWriteFailed(error.localizedDescription)
        }
    }

    private static func makeInstallCommand(scriptURL: URL) -> String {
        "/bin/sh \(scriptURL.path.shellQuotedString)"
    }

    private static func runInTerminal(_ command: String) throws {
        let source = """
        tell application "Terminal"
            activate
            do script \(command.appleScriptQuotedString)
        end tell
        """

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw CommandLineToolInstallError.terminalAutomationFailed(nil)
        }

        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? errorInfo.description
            throw CommandLineToolInstallError.terminalAutomationFailed(message)
        }
    }
}

private enum CommandLineToolInstallError: LocalizedError {
    case terminalAutomationFailed(String?)
    case installerScriptWriteFailed(String)
    case bundledToolMissing

    var errorDescription: String? {
        switch self {
        case .terminalAutomationFailed(let message):
            if let message, !message.isEmpty {
                return String(
                    format: NSLocalizedString(
                        "Terminal automation failed: %@",
                        comment: "CLI installer error"
                    ),
                    message
                )
            }
            return NSLocalizedString("Terminal automation failed.", comment: "CLI installer error")
        case .installerScriptWriteFailed(let message):
            return String(
                format: NSLocalizedString(
                    "Failed to write CLI installer script: %@",
                    comment: "CLI installer error"
                ),
                message
            )
        case .bundledToolMissing:
            return NSLocalizedString(
                "The bundled Markdown Preview CLI could not be found.",
                comment: "CLI installer error"
            )
        }
    }
}

private extension String {
    var appleScriptQuotedString: String {
        let escaped = replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    var shellQuotedString: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
