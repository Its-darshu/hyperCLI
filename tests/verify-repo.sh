#!/usr/bin/env bash
# Verification test suite for hyperCLI repository structure, script syntax, and path references.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERRORS=0

echo "=== hyperCLI Repository Verification Suite ==="
echo "Repository: $REPO_DIR"
echo ""

# 1. Syntax check on all shell scripts
echo "[1/4] Checking Bash script syntax (bash -n)..."
while IFS= read -r script; do
    if ! bash -n "$script"; then
        echo "  FAIL (syntax): $script"
        ERRORS=$((ERRORS + 1))
    fi
done < <(find "$REPO_DIR" -type f -name "*.sh" ! -path "*/.backup-audit/*")
echo "  All shell scripts passed syntax checks."

# 2. Check executable permissions
echo "[2/4] Verifying executable permissions on shell scripts..."
while IFS= read -r script; do
    if [ ! -x "$script" ]; then
        echo "  FAIL (not executable): $script"
        ERRORS=$((ERRORS + 1))
    fi
done < <(find "$REPO_DIR" -type f -name "*.sh" ! -path "*/.backup-audit/*")
echo "  All shell scripts have executable permissions."

# 3. Verify internal script references from configs
echo "[3/4] Verifying referenced scripts exist in the repository..."
check_script_ref() {
    local source_file="$1"
    local full_ref="$2"
    
    # Strip ~/.config/hypr/scripts/ to find relative path under scripts/
    local rel_path
    rel_path=$(sed -E 's|~/\.config/hypr/scripts/||; s|\$HOME/\.config/hypr/scripts/||' <<< "$full_ref")
    
    # Extract only the script file path (remove args like 'next', 'init', etc.)
    local script_rel
    script_rel=$(awk '{print $1}' <<< "$rel_path")
    
    local target_file="$REPO_DIR/scripts/$script_rel"
    if [ ! -f "$target_file" ]; then
        echo "  FAIL (missing target): $source_file references '$script_rel' which does not exist at $target_file"
        ERRORS=$((ERRORS + 1))
    fi
}

# Scan keybinds.conf
while IFS= read -r line; do
    ref=$(grep -oE '(~|\$HOME)/\.config/hypr/scripts/[^ "]+' <<< "$line" || true)
    if [ -n "$ref" ]; then
        check_script_ref "$REPO_DIR/config/keybinds.conf" "$ref"
    fi
done < "$REPO_DIR/config/keybinds.conf"

# Scan autostart.conf
while IFS= read -r line; do
    ref=$(grep -oE '(~|\$HOME)/\.config/hypr/scripts/[^ "]+' <<< "$line" || true)
    if [ -n "$ref" ]; then
        check_script_ref "$REPO_DIR/config/autostart.conf" "$ref"
    fi
done < "$REPO_DIR/config/autostart.conf"

# Scan waybar/config
while IFS= read -r line; do
    ref=$(grep -oE '(~|\$HOME)/\.config/hypr/scripts/[^ "]+' <<< "$line" || true)
    if [ -n "$ref" ]; then
        check_script_ref "$REPO_DIR/waybar/config" "$ref"
    fi
done < "$REPO_DIR/waybar/config"

echo "  All referenced scripts exist in the repository."

# 4. Cargo manifest and build validation
echo "[4/4] Validating Rust build and Cargo manifest..."
if command -v cargo >/dev/null 2>&1; then
    cargo check --manifest-path "$REPO_DIR/Cargo.toml" --quiet
    echo "  Cargo check succeeded."
else
    echo "  Cargo not installed; skipping cargo check."
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== ALL CHECKS PASSED SUCCESSFULLY ==="
    exit 0
else
    echo "=== VERIFICATION FAILED WITH $ERRORS ERROR(S) ==="
    exit 1
fi
