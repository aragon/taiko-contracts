# Include the base Makefile from foundry-env
include lib/foundry-env/base.mk

# PROJECT-SPECIFIC CONSTANTS

SOLIDITY_VERSION=0.8.17
TEST_TREE_MARKDOWN=TEST_TREE.md
SOURCE_FILES=$(wildcard test/*.t.yaml test/integration/*.t.yaml)
TREE_FILES = $(SOURCE_FILES:.t.yaml=.tree)
TARGET_TEST_FILES = $(SOURCE_FILES:.tree=.t.sol)
MAKE_TEST_TREE=deno run ./test/script/make-test-tree.ts

## Test tree management (bulloak):

.PHONY: sync-tests
sync-tests: $(TREE_FILES) ## Scaffold or sync tree files into solidity tests
	@for file in $^; do \
		if [ ! -f $${file%.tree}.t.sol ]; then \
			echo "[Scaffold]   $${file%.tree}.t.sol" ; \
			bulloak scaffold -s $(SOLIDITY_VERSION) --vm-skip -w $$file ; \
		else \
			echo "[Sync file]  $${file%.tree}.t.sol" ; \
			bulloak check --fix $$file ; \
		fi \
	done

.PHONY: check-tests
check-tests: $(TREE_FILES) ## Check if solidity test files are out of sync
	bulloak check $^

.PHONY: markdown-tests
markdown-tests: $(TEST_TREE_MARKDOWN) ## Generate markdown file with test tree definitions

# Internal targets for test tree generation

$(TEST_TREE_MARKDOWN): $(TREE_FILES)
	@echo "[Markdown]   TEST_TREE.md"
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

$(TREE_FILES): $(SOURCE_FILES)

%.tree: %.t.yaml
	@for file in $^; do \
	  echo "[Convert]    $$file -> $${file%.t.yaml}.tree" ; \
		cat $$file | $(MAKE_TEST_TREE) > $${file%.t.yaml}.tree ; \
	done

.PHONY: check-deps
check-deps: ## Check if bulloak and deno are installed
	@which deno > /dev/null && echo "Deno: available" || echo "Install Deno:  curl -fsSL https://deno.land/install.sh | sh"
	@which bulloak > /dev/null && echo "bulloak: available" || echo "Install bulloak:  cargo install bulloak"
