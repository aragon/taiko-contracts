default: help
import 'lib/just-foundry/justfile'

[private]
get var:
    #!/usr/bin/env bash
    source {{ENV_RESOLVE_LIB}} && env_load_network
    V={{var}}
    echo "${!V}"

# Deploy fresh DAO on L1 + L2 and generate configure proposal
[group('deploy')]
deploy-all l1-network l2-network:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "=== Step 1/3: Deploy L1 ({{l1-network}}) ==="
    just switch {{l1-network}}
    just run script/deploy/01-DeployL1.s.sol
    export VETO_RECEIVER_ADDRESS=$(jq -r '.vetoReceiver' deployments/deploy/01-DeployL1.s.sol/$(just get CHAIN_ID)/deployment-latest.json)

    echo ""
    echo "=== Step 2/3: Deploy L2 ({{l2-network}}) ==="
    just switch {{l2-network}}
    just run script/deploy/02-DeployL2.s.sol
    export VETO_AGGREGATOR_ADDRESS=$(jq -r '.l2VetoAggregator' deployments/deploy/02-DeployL2.s.sol/$(just get CHAIN_ID)/deployment-latest.json)

    echo ""
    echo "=== Step 3/3: Encode proposal ({{l1-network}}) ==="
    just switch {{l1-network}}
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
    export VETO_RECEIVER_ADDRESS=$(jq -r '.l2VetoReceiver' deployments/upgrade/01-DeployL1.s.sol/$(just get CHAIN_ID)/deployment-latest.json)
    export UPGRADE_FACTORY_ADDRESS=$(jq -r '.upgradeFactory' deployments/upgrade/01-DeployL1.s.sol/$(just get CHAIN_ID)/deployment-latest.json)

    echo ""
    echo "=== Step 2/3: Deploy L2 ({{l2-network}}) ==="
    just switch {{l2-network}}
    just run script/upgrade/02-DeployL2.s.sol
    export VETO_AGGREGATOR_ADDRESS=$(jq -r '.l2VetoAggregator' deployments/upgrade/02-DeployL2.s.sol/$(just get CHAIN_ID)/deployment-latest.json)

    echo ""
    echo "=== Step 3/3: Encode proposal ({{l1-network}}) ==="
    just switch {{l1-network}}
    just simulate script/upgrade/03-EncodeProposal.s.sol

    echo ""
    echo "Done. Submit the proposal JSON to the DAO."
