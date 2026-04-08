default: help
import 'lib/just-foundry/justfile'

SOLIDITY_VERSION := "0.8.17"

## Test tree management (bulloak):

# Scaffold or sync tree files into Solidity tests
[group('bulloak')]
sync-tests:
    #!/usr/bin/env bash
    set -euo pipefail
    for yaml in test/*.t.yaml test/integration/*.t.yaml; do
        [ -f "$yaml" ] || continue
        tree="${yaml%.t.yaml}.tree"
        echo "[Convert]    $yaml -> $tree"
        cat "$yaml" | deno run ./test/script/make-test-tree.ts > "$tree"
        sol="${yaml%.t.yaml}.t.sol"
        if [ ! -f "$sol" ]; then
            echo "[Scaffold]   $sol"
            bulloak scaffold -s {{SOLIDITY_VERSION}} --vm-skip -w "$tree"
        else
            echo "[Sync file]  $sol"
            bulloak check --fix "$tree"
        fi
    done

# Check if Solidity test files are out of sync with tree definitions
[group('bulloak')]
check-tests:
    #!/usr/bin/env bash
    set -euo pipefail
    trees=()
    for yaml in test/*.t.yaml test/integration/*.t.yaml; do
        [ -f "$yaml" ] || continue
        tree="${yaml%.t.yaml}.tree"
        echo "[Convert]    $yaml -> $tree"
        cat "$yaml" | deno run ./test/script/make-test-tree.ts > "$tree"
        trees+=("$tree")
    done
    [ ${#trees[@]} -gt 0 ] && bulloak check "${trees[@]}"

# Generate markdown file with test tree definitions
[group('bulloak')]
markdown-tests:
    #!/usr/bin/env bash
    set -euo pipefail
    out="TEST_TREE.md"
    echo "# Test tree definitions" > "$out"
    echo "" >> "$out"
    echo "Below is the graphical definition of the contract tests implemented on [the test folder](./test)" >> "$out"
    echo "" >> "$out"
    for yaml in test/*.t.yaml test/integration/*.t.yaml; do
        [ -f "$yaml" ] || continue
        tree="${yaml%.t.yaml}.tree"
        cat "$yaml" | deno run ./test/script/make-test-tree.ts > "$tree"
        echo '```' >> "$out"
        cat "$tree" >> "$out"
        echo '```' >> "$out"
        echo "" >> "$out"
    done
    echo "[Markdown]   $out"

# Check if bulloak and deno are installed
[group('bulloak')]
check-deps:
    @which deno > /dev/null && echo "Deno: available" || echo "Install Deno:  curl -fsSL https://deno.land/install.sh | sh"
    @which bulloak > /dev/null && echo "bulloak: available" || echo "Install bulloak:  cargo install bulloak"
