// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title ProposalIdCodec
/// @notice Encodes and decodes proposal IDs that pack four uint64 fields:
///
///   bits 192-255: snapshotTimestamp
///   bits 128-191: startDate
///   bits  64-127: endDate
///   bits   0-63 : counter
library ProposalIdCodec {
    function encode(uint64 _snapshotTimestamp, uint64 _startDate, uint64 _endDate, uint64 _counter)
        internal
        pure
        returns (uint256)
    {
        return uint256(_snapshotTimestamp) << 192 | uint256(_startDate) << 128 | uint256(_endDate) << 64
            | uint256(_counter);
    }

    function decode(uint256 _proposalId)
        internal
        pure
        returns (uint64 counter, uint64 startDate, uint64 endDate, uint64 snapshotTimestamp)
    {
        counter = uint64(_proposalId & type(uint64).max);
        endDate = uint64(_proposalId >> 64) & type(uint64).max;
        startDate = uint64(_proposalId >> 128) & type(uint64).max;
        snapshotTimestamp = uint64(_proposalId >> 192);
    }

}
