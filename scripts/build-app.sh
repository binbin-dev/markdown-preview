#!/bin/zsh
# Builds build/Markdown Preview.app and signs it with a personal Apple
# Development identity.
#
# Requires zsh: run the script directly (it uses zsh path modifiers).
#
# Usage: scripts/build-app.sh [debug|release] [options]
#   debug                 Bundle id doc.md-preview.dev
#   release               Bundle id doc.md-preview (default)
#   --configuration NAME  Same as the positional argument
#   --identity NAME       Signing identity (default: MDP_CODESIGN_IDENTITY,
#                         then the first "Apple Development:" identity)
#   --team ID             Development team (default: the identity's OU)
#   --output DIR          Output directory (default: build/)
#   --clean               Clean before building
#   --open                Open the built app after verification
#
# Xcode signs the app, the embedded Quick Look extension and Sparkle helpers;
# this script does not re-sign them. It never edits project.pbxproj: the
# personal team and identity are command-line overrides only. Local builds are
# single-architecture (ONLY_ACTIVE_ARCH=YES).
#
# Exit codes: 64 usage, 69 no usable Xcode or signing identity, 70 build or
# signing verification failed, 75 the app is still running.
set -euo pipefail

script_path=${0:A}
script_dir=${script_path:h}
project_dir=${script_dir:h}
output_dir="$project_dir/build"
configuration=release
signing_identity=${MDP_CODESIGN_IDENTITY:-}
team_id=${MDP_DEVELOPMENT_TEAM:-}
clean_first=false
open_after=false
start_seconds=$SECONDS

usage() {
  /usr/bin/sed -n '2,/^[^#]/p' "$script_path" \
    | /usr/bin/sed -n '/^#/p' \
    | /usr/bin/sed 's/^# \{0,1\}//'
}

while (( $# )); do
  case "$1" in
    debug|release)
      configuration=$1
      shift
      ;;
    --configuration)
      [[ $# -ge 2 ]] || { echo "--configuration needs a value" >&2; exit 64; }
      configuration=$2
      shift 2
      ;;
    --identity)
      [[ $# -ge 2 ]] || { echo "--identity needs a value" >&2; exit 64; }
      signing_identity=$2
      shift 2
      ;;
    --team)
      [[ $# -ge 2 ]] || { echo "--team needs a value" >&2; exit 64; }
      team_id=$2
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "--output needs a value" >&2; exit 64; }
      output_dir=$2
      shift 2
      ;;
    --clean)
      clean_first=true
      shift
      ;;
    --open)
      open_after=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

case "$configuration" in
  debug)
    xcode_configuration=Debug
    ;;
  release)
    xcode_configuration=Release
    ;;
  *)
    echo "Configuration must be debug or release, got $configuration" >&2
    exit 64
    ;;
esac

if [[ -z "$output_dir" ]]; then
  echo "--output needs a non-empty directory" >&2
  exit 64
fi
output_dir=${output_dir:A}
if [[ "$output_dir" == / ]]; then
  echo "Refusing to build into /" >&2
  exit 64
fi

if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild is unavailable: Xcode must be installed and selected." >&2
  echo "Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 69
fi

available_identities=$(
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null || true
)
if [[ -z "$signing_identity" ]]; then
  signing_identity=$(
    print -r -- "$available_identities" \
      | /usr/bin/sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
      | /usr/bin/sed -n '1p'
  )
fi
if [[ -z "$signing_identity" ]] || [[ "$available_identities" != *"\"$signing_identity\""* ]]; then
  if [[ -z "$signing_identity" ]]; then
    echo "No Apple Development signing identity found." >&2
  else
    echo "No such signing identity: \"$signing_identity\"." >&2
  fi
  echo "Sign in to Xcode with the personal Apple ID that owns the certificate," >&2
  echo "or pass --identity / MDP_CODESIGN_IDENTITY." >&2
  exit 69
fi

if [[ -z "$team_id" ]]; then
  team_id=$(
    /usr/bin/security find-certificate -c "$signing_identity" -p 2>/dev/null \
      | /usr/bin/openssl x509 -noout -subject 2>/dev/null \
      | /usr/bin/sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p' \
      | /usr/bin/sed -n '1p' \
      || true
  )
fi
if [[ ! "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Could not read a 10-character team id from \"$signing_identity\"." >&2
  echo "Pass --team / MDP_DEVELOPMENT_TEAM with the personal team id." >&2
  exit 69
fi

mkdir -p "$output_dir"
derived_data="$output_dir/DerivedData"
app_path="$output_dir/Markdown Preview.app"

in_git_repo=false
if /usr/bin/git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  in_git_repo=true
fi
project_state_before=""
if $in_git_repo; then
  project_state_before=$(
    /usr/bin/git -C "$project_dir" status --porcelain -- md-preview.xcodeproj/project.pbxproj \
      || true
  )
fi

staging_root=$(/usr/bin/mktemp -d "$output_dir/.mdp-build.XXXXXX")
trap '/bin/rm -rf "$staging_root"' EXIT
staging_app="$staging_root/Markdown Preview.app"

xcode_actions=(build)
if $clean_first; then
  xcode_actions=(clean build)
fi

echo "Building $xcode_configuration with $signing_identity (team $team_id)…" >&2
if ! /usr/bin/xcodebuild \
  -project "$project_dir/md-preview.xcodeproj" \
  -scheme md-preview \
  -configuration "$xcode_configuration" \
  -derivedDataPath "$derived_data" \
  -destination 'platform=macOS' \
  DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  ONLY_ACTIVE_ARCH=YES \
  -allowProvisioningUpdates \
  -quiet \
  "${xcode_actions[@]}" >&2; then
  echo "xcodebuild failed." >&2
  echo "Provisioning is the usual cause: Xcode must be signed in with the" >&2
  echo "personal Apple ID, and the team needs App Groups and App Sandbox." >&2
  exit 70
fi

built_app="$derived_data/Build/Products/$xcode_configuration/Markdown Preview.app"
if [[ ! -d "$built_app" ]]; then
  echo "xcodebuild succeeded but did not produce $built_app" >&2
  exit 70
fi

/usr/bin/ditto "$built_app" "$staging_app"
/usr/bin/xattr -cr "$staging_app"

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$staging_app" >&2; then
  echo "The built app did not pass codesign verification." >&2
  exit 70
fi
/usr/bin/plutil -lint "$staging_app/Contents/Info.plist" >&2

origin=$(/usr/bin/codesign -dv --verbose=4 "$staging_app" 2>&1 | /usr/bin/sed -n 's/^Authority=//p' | /usr/bin/sed -n '1p')
if [[ "$origin" != "$signing_identity" ]]; then
  echo "Expected $signing_identity, but the app is signed by: ${origin:-none}" >&2
  exit 70
fi

designated_requirement=$(/usr/bin/codesign -dr - "$staging_app" 2>&1)
if [[ "$designated_requirement" == *"cdhash"* ]]; then
  echo "Signing is not stable across builds: $designated_requirement" >&2
  exit 70
fi

if $in_git_repo; then
  project_state_after=$(
    /usr/bin/git -C "$project_dir" status --porcelain -- md-preview.xcodeproj/project.pbxproj \
      || true
  )
  if [[ "$project_state_before" != "$project_state_after" ]]; then
    echo "xcodebuild changed project.pbxproj; refusing to install the app." >&2
    echo "Restore the project file before rebuilding." >&2
    exit 70
  fi
fi

running_processes=$(/bin/ps -axo comm= || true)
if [[ "$running_processes" == *"$app_path/Contents/MacOS/"* ]]; then
  echo "Markdown Preview is running from $app_path; asking it to quit." >&2
  /usr/bin/osascript -e "tell application \"$app_path\" to quit" >/dev/null 2>&1 || true
  for _ in {1..50}; do
    running_processes=$(/bin/ps -axo comm= || true)
    [[ "$running_processes" == *"$app_path/Contents/MacOS/"* ]] || break
    /bin/sleep 0.1
  done
  if [[ "$running_processes" == *"$app_path/Contents/MacOS/"* ]]; then
    echo "Markdown Preview is still running; quit it and rebuild." >&2
    exit 75
  fi
fi

if [[ "$configuration" == debug ]]; then
  # Development builds are rebuilt all day and use the .dev bundle id, so the
  # previous one is not worth keeping.
  /bin/rm -rf "$app_path"
elif [[ -e "$app_path" ]]; then
  backup_path="$output_dir/Markdown Preview.previous.app"
  /bin/rm -rf "$backup_path"
  /bin/mv "$app_path" "$backup_path"
  echo "Previous app preserved at $backup_path" >&2
fi
/bin/mv "$staging_app" "$app_path"

/usr/bin/codesign -dv --verbose=4 "$app_path" >&2
echo "Built in $(( SECONDS - start_seconds ))s" >&2
echo "$app_path"

if $open_after; then
  /usr/bin/open "$app_path"
fi
