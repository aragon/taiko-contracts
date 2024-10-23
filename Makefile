.DEFAULT_TARGET: help

SOLIDITY_VERSION=0.8.17
SOURCE_FILES=$(wildcard test/*.t.yaml test/integration/*.t.yaml)
TREE_FILES = $(SOURCE_FILES:.t.yaml=.tree)
TARGET_TEST_FILES = $(SOURCE_FILES:.tree=.t.sol)
MOUNTED_PATH=/data
MAKE_TEST_TREE=deno run ./test/script/make-test-tree.ts
TEST_TREE_MARKDOWN=TEST_TREE.md

.PHONY: help
help:
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)##\(.*\)/- make \1  \3/p'

# External targets (running docker)

.PHONY: sync
sync: ##     Scaffold or sync tree files into solidity tests
	@docker run --rm -v .:$(MOUNTED_PATH) nixos/nix nix-shell -p bulloak gnumake deno \
	   --command "cd $(MOUNTED_PATH) && make sync-tree"

.PHONY: check
check: ##    Checks if solidity files are out of sync
	@docker run --rm -v .:/data nixos/nix nix-shell -p bulloak gnumake deno \
	   --command "cd $(MOUNTED_PATH) && make check-tree"

markdown: $(TEST_TREE_MARKDOWN) ## Generates a markdown file with the test definitions rendered as a tree

# Internal targets (run within docker)

# Scaffold or add missing tests
sync-tree: $(TREE_FILES) $(TEST_TREE_MARKDOWN)
	@for file in $^; do \
		if [ ! -f $${file%.tree}.t.sol ]; then \
			echo "[Scaffold]   $${file%.tree}.t.sol" ; \
			# bulloak scaffold -s $(SOLIDITY_VERSION) --vm-skip -w $$file ; \
			bulloak scaffold -s $(SOLIDITY_VERSION) -w $$file ; \
		else \
			echo "[Sync file]  $${file%.tree}.t.sol" ; \
			bulloak check --fix $$file ; \
		fi \
	done

# Check if there are missing tests
.PHONY: check-tree
check-tree: $(TREE_FILES)
	bulloak check $^

# Generate a markdown file with the test trees
$(TEST_TREE_MARKDOWN): $(TREE_FILES)
	@echo "[markdown]   TEST_TREE.md"
	@echo "# Test tree definitions" > $@
	@echo "" >> $@
	@echo "Below is the graphical definition of the contract tests implemented on [the test folder](./test)" >> $@
	@echo "" >> $@

	@for file in $^; do \
		echo "\`\`\`" >> $@ ; \
		cat $$file >> $@ ; \
		echo "\`\`\`" >> $@ ; \
		echo "" >> $@ ; \
	done

# Internal dependencies and transformations

$(TREE_FILES): $(SOURCE_FILES)

%.tree:%.t.yaml
	@for file in $^; do \
	    echo "[Convert]    $$file" ; \
		cat $$file | $(MAKE_TEST_TREE) > $${file%.t.yaml}.tree ; \
	done

.PHONY: clean
clean: ##    Clean the intermediary tree files
	rm -f $(TREE_FILES)
	rm -f $(TEST_TREE_MARKDOWN)
