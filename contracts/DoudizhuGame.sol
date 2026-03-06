// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title DoudizhuGame - On-chain betting + leaderboard for Doudizhu
/// @notice On Arc Testnet, USDC is the native gas token (18 decimals), using payable + msg.value
contract DoudizhuGame {
    struct Game {
        address host;
        address[3] players;
        uint8 playerCount;
        uint256 betAmount;
        bool settled;
        address winner;
        uint256 createdAt;
    }

    struct PlayerStats {
        uint256 wins;
        uint256 losses;
        uint256 totalEarnings;
        uint256 totalGames;
    }

    uint256 public nextGameId;
    mapping(uint256 => Game) public games;
    mapping(address => PlayerStats) public playerStats;

    // Leaderboard: maintain top 20 players
    address[] public topPlayers;
    uint256 public constant MAX_TOP = 20;

    uint256 public constant BET_AMOUNT = 1 ether; // Fixed 1 USDC
    uint256 public constant TIMEOUT = 1 minutes;   // Timeout refund period

    event GameCreated(uint256 indexed gameId, address indexed host, uint256 betAmount);
    event PlayerJoined(uint256 indexed gameId, address indexed player, uint8 slot);
    event GameSettled(uint256 indexed gameId, address indexed winner, uint256 prize);
    event GameCancelled(uint256 indexed gameId, address indexed host, uint256 refundTotal);

    /// @notice Host creates a game, fixed bet 1 USDC
    function createGame() external payable returns (uint256 gameId) {
        require(msg.value == BET_AMOUNT, "Must bet exactly 1 USDC");
        gameId = nextGameId++;
        Game storage g = games[gameId];
        g.host = msg.sender;
        g.players[0] = msg.sender;
        g.playerCount = 1;
        g.betAmount = BET_AMOUNT;
        g.createdAt = block.timestamp;
        emit GameCreated(gameId, msg.sender, BET_AMOUNT);
    }

    /// @notice Player joins a game, fixed bet 1 USDC
    function joinGame(uint256 gameId) external payable {
        Game storage g = games[gameId];
        require(g.host != address(0), "Game not found");
        require(!g.settled, "Game already settled");
        require(g.playerCount < 3, "Game full");
        require(msg.value == BET_AMOUNT, "Must bet exactly 1 USDC");
        require(msg.sender != g.players[0] && msg.sender != g.players[1], "Already joined");

        g.players[g.playerCount] = msg.sender;
        g.playerCount++;
        emit PlayerJoined(gameId, msg.sender, g.playerCount);
    }

    /// @notice Host cancels game, refund all players
    function cancelGame(uint256 gameId) external {
        Game storage g = games[gameId];
        require(msg.sender == g.host, "Only host can cancel");
        require(!g.settled, "Already settled");

        g.settled = true;
        uint256 refundTotal = g.betAmount * g.playerCount;

        // Refund each player
        for (uint8 i = 0; i < g.playerCount; i++) {
            (bool ok, ) = g.players[i].call{value: g.betAmount}("");
            require(ok, "Refund failed");
        }

        emit GameCancelled(gameId, msg.sender, refundTotal);
    }

    /// @notice Timeout refund: any participant can trigger refund after timeout
    function claimTimeout(uint256 gameId) external {
        Game storage g = games[gameId];
        require(!g.settled, "Already settled");
        require(block.timestamp >= g.createdAt + TIMEOUT, "Not timed out yet");

        // Verify caller is a participant
        bool isPlayer = false;
        for (uint8 i = 0; i < g.playerCount; i++) {
            if (g.players[i] == msg.sender) { isPlayer = true; break; }
        }
        require(isPlayer, "Not a player");

        g.settled = true;

        // Refund each player
        for (uint8 i = 0; i < g.playerCount; i++) {
            (bool ok, ) = g.players[i].call{value: g.betAmount}("");
            require(ok, "Refund failed");
        }

        emit GameCancelled(gameId, msg.sender, g.betAmount * g.playerCount);
    }

    /// @notice Host reports winner, contract transfers prize pool to winner
    function settleGame(uint256 gameId, address winner) external {
        Game storage g = games[gameId];
        require(msg.sender == g.host, "Only host can settle");
        require(!g.settled, "Already settled");
        require(g.playerCount >= 2, "Not enough players");

        // Verify winner is a participant
        bool validWinner = false;
        for (uint8 i = 0; i < g.playerCount; i++) {
            if (g.players[i] == winner) {
                validWinner = true;
                break;
            }
        }
        require(validWinner, "Winner not in game");

        g.settled = true;
        g.winner = winner;

        uint256 prize = g.betAmount * g.playerCount;

        // Update stats
        for (uint8 i = 0; i < g.playerCount; i++) {
            address p = g.players[i];
            playerStats[p].totalGames++;
            if (p == winner) {
                playerStats[p].wins++;
                playerStats[p].totalEarnings += prize - g.betAmount; // Net earnings
            } else {
                playerStats[p].losses++;
            }
            _updateLeaderboard(p);
        }

        // Transfer prize pool to winner
        (bool ok, ) = winner.call{value: prize}("");
        require(ok, "Transfer failed");

        emit GameSettled(gameId, winner, prize);
    }

    /// @notice Query player stats
    function getPlayerStats(address player) external view returns (
        uint256 wins, uint256 losses, uint256 totalEarnings, uint256 totalGames
    ) {
        PlayerStats storage s = playerStats[player];
        return (s.wins, s.losses, s.totalEarnings, s.totalGames);
    }

    /// @notice Get top N leaderboard
    function getTopPlayers() external view returns (
        address[] memory addresses,
        uint256[] memory wins,
        uint256[] memory earnings
    ) {
        uint256 len = topPlayers.length;
        addresses = new address[](len);
        wins = new uint256[](len);
        earnings = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            addresses[i] = topPlayers[i];
            wins[i] = playerStats[topPlayers[i]].wins;
            earnings[i] = playerStats[topPlayers[i]].totalEarnings;
        }
    }

    /// @notice Get game info
    function getGame(uint256 gameId) external view returns (
        address host, uint8 playerCount, uint256 betAmount, bool settled, address winner
    ) {
        Game storage g = games[gameId];
        return (g.host, g.playerCount, g.betAmount, g.settled, g.winner);
    }

    // Internal: update leaderboard
    function _updateLeaderboard(address player) internal {
        // Check if already on board
        for (uint256 i = 0; i < topPlayers.length; i++) {
            if (topPlayers[i] == player) {
                _sortLeaderboard();
                return;
            }
        }
        // Not on board: add directly if not full
        if (topPlayers.length < MAX_TOP) {
            topPlayers.push(player);
            _sortLeaderboard();
            return;
        }
        // Full: check if better than last place
        uint256 lastIdx = topPlayers.length - 1;
        if (playerStats[player].wins > playerStats[topPlayers[lastIdx]].wins) {
            topPlayers[lastIdx] = player;
            _sortLeaderboard();
        }
    }

    // Simple bubble sort (max 20 elements)
    function _sortLeaderboard() internal {
        uint256 len = topPlayers.length;
        for (uint256 i = 0; i < len; i++) {
            for (uint256 j = i + 1; j < len; j++) {
                if (playerStats[topPlayers[j]].wins > playerStats[topPlayers[i]].wins) {
                    (topPlayers[i], topPlayers[j]) = (topPlayers[j], topPlayers[i]);
                }
            }
        }
    }
}
