#!/usr/bin/env bash
#
# release.sh - Automated release script for Loki Mode
#
# Usage:
#   ./scripts/release.sh patch|minor|major [--dry-run]
#
# This script:
#   1. Bumps version in every file CLAUDE.md's "Release Workflow" section 1
#      lists (see FILES_TO_BUMP below), except the ones documented as
#      intentionally left to the Captain.
#   2. Updates CHANGELOG.md from conventional commits
#   3. Commits and pushes (triggers GitHub Actions release workflow)
#
# Files intentionally NOT bumped by this script (left to the Captain):
#   - vscode-extension/package.json: CLAUDE.md marks this DEPRECATED since
#     v7.2.0 ("Bump only if vendoring; otherwise skip"). The extension is no
#     longer published, so this script never touches it.
#   - CHANGELOG.md: handled separately by update-changelog.sh (step 2 below),
#     which writes a new dated entry rather than a simple string replace.
#   - README.md / docs/INSTALLATION.md Docker tags / docker-compose.yml:
#     CLAUDE.md calls these out for MAJOR/MINOR bumps only, and today they
#     reference `:latest` or carry no pinned version string to replace.
#     Nothing for a version-bump regex to match.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${CYAN}[STEP]${NC} $*"; }

DRY_RUN="false"
BUMP_TYPE=""

# Parse arguments. Sets the globals DRY_RUN and BUMP_TYPE directly instead of
# echoing a return value, because a caller that wraps this in $(...) runs it
# in a subshell and any global it sets (DRY_RUN, an early `exit 0` for --help)
# is lost when the subshell exits.
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            patch|minor|major)
                BUMP_TYPE="$1"
                ;;
            --dry-run)
                DRY_RUN="true"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done

    if [[ -z "$BUMP_TYPE" ]]; then
        log_error "Bump type required: patch, minor, or major"
        usage
        exit 1
    fi
}

usage() {
    cat << EOF
Usage: $(basename "$0") <patch|minor|major> [--dry-run]

Arguments:
  patch    Bump patch version (x.y.Z)
  minor    Bump minor version (x.Y.0)
  major    Bump major version (X.0.0)

Options:
  --dry-run  Show what would be done without making changes
  -h, --help Show this help message

Examples:
  $(basename "$0") patch          # 5.8.2 -> 5.8.3
  $(basename "$0") minor          # 5.8.2 -> 5.9.0
  $(basename "$0") major          # 5.8.2 -> 6.0.0
  $(basename "$0") patch --dry-run
EOF
}

# Get current version from VERSION file
get_current_version() {
    if [[ -f "$ROOT_DIR/VERSION" ]]; then
        cat "$ROOT_DIR/VERSION" | tr -d '\n'
    else
        echo "0.0.0"
    fi
}

# Bump version based on type
bump_version() {
    local current="$1"
    local type="$2"

    IFS='.' read -r major minor patch <<< "$current"

    case "$type" in
        major)
            echo "$((major + 1)).0.0"
            ;;
        minor)
            echo "$major.$((minor + 1)).0"
            ;;
        patch)
            echo "$major.$minor.$((patch + 1))"
            ;;
    esac
}

# Apply a sed -E expression to a file in place, portably (no BSD/GNU -i
# difference), via a temp file + mv so a mid-write failure can't truncate
# the original.
apply_sed() {
    local file="$1"
    local expr="$2"
    local tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    if sed -E "$expr" "$file" > "$tmp"; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        return 1
    fi
}

# Update the version string at a specific "slot" in a file, identified by a
# sed -E expression. Never does a global literal find/replace: that would
# also rewrite unrelated version mentions in prose (CHANGELOG headings,
# SKILL.md body text like "v8.0.0", etc.) and would silently no-op on a file
# that has already drifted from $old_version (observed on wiki/*.md and
# docs/INSTALLATION.md, which sit at older versions than VERSION today).
#
# After writing, asserts the new version now appears in that exact slot, so
# a pattern that stops matching (a reformatted file, a typo in this script)
# fails the release instead of silently shipping a stale file.
update_version_slot() {
    local file="$1"
    local expr="$2"
    local assert_pattern="$3"
    local description="$4"

    if [[ ! -f "$file" ]]; then
        log_warn "File not found: $file"
        return
    fi

    if [ "$DRY_RUN" = "true" ]; then
        local diff_output
        diff_output="$(sed -E "$expr" "$file" | diff -u "$file" - || true)"
        if [[ -n "$diff_output" ]]; then
            log_info "[DRY-RUN] Would update $description ($file):"
            echo "$diff_output"
        else
            log_warn "[DRY-RUN] $description ($file): pattern did not match, no change would be made"
        fi
        return
    fi

    apply_sed "$file" "$expr"

    if ! grep -qE "$assert_pattern" "$file"; then
        log_error "Failed to update $description in $file (slot pattern no longer matches after edit)"
        exit 1
    fi

    log_success "Updated $description in $file"
}

# Bump every file CLAUDE.md's "Release Workflow > 1. Version Bump - ALL
# Files" section requires, each at its own format-specific slot. Kept as a
# flat sequence of calls (not an associative array) for bash 3.2
# compatibility (macOS ships 3.2; `declare -A` is bash 4+).
#
# Deliberately excludes:
#   - vscode-extension/package.json (DEPRECATED, see header comment)
#   - CHANGELOG.md (handled by update-changelog.sh in step 2)
bump_all_version_files() {
    local new="$1"
    local digits='[0-9]+\.[0-9]+\.[0-9]+'

    update_version_slot "$ROOT_DIR/VERSION" \
        "s/^${digits}\$/${new}/" \
        "^${new}\$" \
        "VERSION"

    update_version_slot "$ROOT_DIR/package.json" \
        "s/^(  \"version\": \")${digits}(\",?)\$/\\1${new}\\2/" \
        "^  \"version\": \"${new}\"" \
        "package.json version"

    update_version_slot "$ROOT_DIR/SKILL.md" \
        "s/^(# Loki Mode v)${digits}\$/\\1${new}/" \
        "^# Loki Mode v${new}\$" \
        "SKILL.md header"

    update_version_slot "$ROOT_DIR/SKILL.md" \
        "s/^(\*\*v)${digits}( \|)/\\1${new}\\2/" \
        "^\*\*v${new} \|" \
        "SKILL.md footer"

    update_version_slot "$ROOT_DIR/Dockerfile" \
        "s/^(LABEL version=\")${digits}(\")\$/\\1${new}\\2/" \
        "^LABEL version=\"${new}\"\$" \
        "Dockerfile LABEL version"

    update_version_slot "$ROOT_DIR/Dockerfile" \
        "s/^(LABEL org\.opencontainers\.image\.version=\")${digits}(\")\$/\\1${new}\\2/" \
        "^LABEL org\.opencontainers\.image\.version=\"${new}\"\$" \
        "Dockerfile LABEL org.opencontainers.image.version"

    update_version_slot "$ROOT_DIR/Dockerfile.sandbox" \
        "s/^(LABEL version=\")${digits}(\")\$/\\1${new}\\2/" \
        "^LABEL version=\"${new}\"\$" \
        "Dockerfile.sandbox LABEL version"

    update_version_slot "$ROOT_DIR/Dockerfile.sandbox" \
        "s/^(LABEL org\.opencontainers\.image\.version=\")${digits}(\")\$/\\1${new}\\2/" \
        "^LABEL org\.opencontainers\.image\.version=\"${new}\"\$" \
        "Dockerfile.sandbox LABEL org.opencontainers.image.version"

    update_version_slot "$ROOT_DIR/plugins/loki-mode/.claude-plugin/plugin.json" \
        "s/^(  \"version\": \")${digits}(\",?)\$/\\1${new}\\2/" \
        "^  \"version\": \"${new}\"" \
        "plugin.json version"

    # server.json has two version slots: top-level (2-space indent) and
    # packages[loki-mode].version (6-space indent in the current layout).
    update_version_slot "$ROOT_DIR/server.json" \
        "s/^(  \"version\": \")${digits}(\",?)\$/\\1${new}\\2/" \
        "^  \"version\": \"${new}\"" \
        "server.json top-level version"

    update_version_slot "$ROOT_DIR/server.json" \
        "s/^(      \"version\": \")${digits}(\",?)\$/\\1${new}\\2/" \
        "^      \"version\": \"${new}\"" \
        "server.json packages[].version"

    update_version_slot "$ROOT_DIR/CLAUDE.md" \
        "s/^(- Current: v)${digits}( )/\\1${new}\\2/" \
        "^- Current: v${new} " \
        "CLAUDE.md Version Numbering"

    update_version_slot "$ROOT_DIR/dashboard/__init__.py" \
        "s/^(__version__ = \")${digits}(\")\$/\\1${new}\\2/" \
        "^__version__ = \"${new}\"\$" \
        "dashboard/__init__.py __version__"

    update_version_slot "$ROOT_DIR/mcp/__init__.py" \
        "s/^(__version__ = ')${digits}(')\$/\\1${new}\\2/" \
        "^__version__ = '${new}'\$" \
        "mcp/__init__.py __version__"

    update_version_slot "$ROOT_DIR/docs/INSTALLATION.md" \
        "s/^(\*\*Version:\*\* v)${digits}\$/\\1${new}/" \
        "^\*\*Version:\*\* v${new}\$" \
        "docs/INSTALLATION.md version header"

    update_version_slot "$ROOT_DIR/wiki/Home.md" \
        "s/^(Current Version: \*\*)${digits}(\*\*)/\\1${new}\\2/" \
        "^Current Version: \*\*${new}\*\*" \
        "wiki/Home.md current version"

    update_version_slot "$ROOT_DIR/wiki/_Sidebar.md" \
        "s/^(\*\*Version:\*\* )${digits}\$/\\1${new}/" \
        "^\*\*Version:\*\* ${new}\$" \
        "wiki/_Sidebar.md version"

    update_version_slot "$ROOT_DIR/wiki/API-Reference.md" \
        "s/^(  \"version\": \")${digits}(\",?)\$/\\1${new}\\2/" \
        "^  \"version\": \"${new}\"" \
        "wiki/API-Reference.md example version"
}

# Files staged into the release commit. Kept as its own list, sourced from
# the same set bump_all_version_files touches, so the commit can never ship
# a partially-bumped tree (some files updated on disk but left unstaged).
RELEASE_COMMIT_FILES="VERSION package.json SKILL.md Dockerfile Dockerfile.sandbox plugins/loki-mode/.claude-plugin/plugin.json server.json CLAUDE.md dashboard/__init__.py mcp/__init__.py docs/INSTALLATION.md wiki/Home.md wiki/_Sidebar.md wiki/API-Reference.md CHANGELOG.md"

# Check for uncommitted changes
check_git_status() {
    if [[ -n "$(git status --porcelain)" ]]; then
        log_warn "You have uncommitted changes:"
        git status --short
        echo ""
        read -r -p "Continue anyway? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Aborted"
            exit 1
        fi
    fi
}

# Main release process
main() {
    cd "$ROOT_DIR"

    parse_args "$@"

    local current_version
    current_version=$(get_current_version)

    local new_version
    new_version=$(bump_version "$current_version" "$BUMP_TYPE")

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Loki Mode Release${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "  Current version: ${YELLOW}$current_version${NC}"
    echo -e "  New version:     ${GREEN}$new_version${NC}"
    echo -e "  Bump type:       ${BLUE}$BUMP_TYPE${NC}"
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "  Mode:            ${YELLOW}DRY RUN${NC}"
    fi
    echo ""

    if [ "$DRY_RUN" != "true" ]; then
        read -r -p "Proceed with release? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Aborted"
            exit 1
        fi
    else
        log_info "[DRY-RUN] Would proceed with release"
    fi

    # Check git status
    log_step "Checking git status..."
    if [ "$DRY_RUN" != "true" ]; then
        check_git_status
    else
        log_info "[DRY-RUN] Skipping git status check"
    fi

    # Step 1: Update version files
    log_step "Updating version files..."
    bump_all_version_files "$new_version"
    log_warn "Not bumped (intentionally, see script header): vscode-extension/package.json (deprecated)"

    # Step 2: Update changelog
    log_step "Updating CHANGELOG.md..."
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would run: ./scripts/update-changelog.sh $new_version"
    else
        "$SCRIPT_DIR/update-changelog.sh" "$new_version"
    fi

    # Step 3: Git commit
    log_step "Creating git commit..."
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would commit: release: v$new_version"
        log_info "[DRY-RUN] Would stage: $RELEASE_COMMIT_FILES"
    else
        # shellcheck disable=SC2086
        git add $RELEASE_COMMIT_FILES
        git commit -m "release: v$new_version"
    fi

    # Step 4: Push
    log_step "Pushing to remote..."
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would push to origin main"
    else
        git push origin main
    fi

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Release v$new_version initiated!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "GitHub Actions will now:"
    echo "  1. Create git tag v$new_version"
    echo "  2. Create GitHub Release"
    echo "  3. Publish to npm"
    echo "  4. Build and push Docker image"
    echo "  5. Update Homebrew tap"
    echo ""
    echo "Watch progress:"
    echo "  gh run list --workflow=Release --limit 1"
    echo "  gh run watch"
    echo ""
}

# Allow this script to be sourced (e.g. by tests) without running main.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
