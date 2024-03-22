source .env
forge script script/OptimisticTokenVotingPlugin.s.sol --rpc-url $SEPOLIA_RPC_URL
forge script script/VetoToken.s.sol --rpc-url $TAIKO_RPC_URL