.DEFAULT_TARGET: help

SOLIDITY_VERSION=0.8.17
TREE_FILES=$(wildcard test/*.tree test/integration/*.tree)
MOUNTED_PATH=/data

.PHONY: help
help:
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)##\(.*\)/- \1:\t\3/p'

# SYNC TEST FILES

.PHONY: sync
sync: ##  Scaffold or sync tree files into tests
	@docker run --rm -v .:$(MOUNTED_PATH) nixos/nix nix-shell -p bulloak gnumake \
	   --command "cd $(MOUNTED_PATH) && make sync-tree"

.PHONY: sync-tree
sync-tree: $(TREE_FILES)
	@echo "Syncing tree files"
	@for file in $^; do \
		if [ ! -f $${file%.tree}.t.sol ]; then \
			echo "[Scaffold]   $${file%.tree}.t.sol" ; \
			bulloak scaffold -s $(SOLIDITY_VERSION) --vm-skip -w $$file ; \
		else \
			echo "[Sync file]  $${file%.tree}.t.sol" ; \
			bulloak check --fix $$file ; \
		fi \
	done

# CHECK TEST FILES

.PHONY: check
check: ##  Scaffold or sync tree files into tests
	@docker run --rm -it -v .:/data nixos/nix nix-shell -p bulloak gnumake \
	   --command "cd $(MOUNTED_PATH) && make check-tree"

.PHONY: check-tree
check-tree: $(TREE_FILES)
	@echo "Checking tree files"
	bulloak check $^
