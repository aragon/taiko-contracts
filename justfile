default: help
import 'lib/just-foundry/justfile'

ENV_LAST := "deployments/.env.last"

# Deploy fresh DAO on L1 + L2 and generate configure proposal
[group('deploy')]
deploy-all l1-network l2-network:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "=== Step 1/3: Deploy L1 ({{l1-network}}) ==="
    just switch {{l1-network}}
    just run script/deploy/01-DeployL1.s.sol

    echo ""
    echo "=== Step 2/3: Deploy L2 ({{l2-network}}) ==="
    just switch {{l2-network}}
    source {{ENV_LAST}}
    just run script/deploy/02-DeployL2.s.sol

    echo ""
    echo "=== Step 3/3: Encode proposal ({{l1-network}}) ==="
    just switch {{l1-network}}
    source {{ENV_LAST}}
    just simulate script/deploy/03-EncodeProposal.s.sol

    echo ""
    echo "Done. Submit the proposal JSON to the DAO."

# Upgrade existing DAO: deploy on L1 + L2 and generate upgrade proposal
[group('deploy')]
upgrade-all l1-network l2-network:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "=== Step 1/3: Deploy L1 ({{l1-network}}) ==="
    just switch {{l1-network}}
    just run script/upgrade/01-DeployL1.s.sol

    echo ""
    echo "=== Step 2/3: Deploy L2 ({{l2-network}}) ==="
    just switch {{l2-network}}
    source {{ENV_LAST}}
    just run script/upgrade/02-DeployL2.s.sol

    echo ""
    echo "=== Step 3/3: Encode proposal ({{l1-network}}) ==="
    just switch {{l1-network}}
    source {{ENV_LAST}}
    just simulate script/upgrade/03-EncodeProposal.s.sol

    echo ""
    echo "Done. Submit the proposal JSON to the DAO."
