import { describe, expect, it, beforeEach } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("Governance Contract Tests", () => {
  beforeEach(() => {
    // Deploy dependencies first
    simnet.deployContract("reputation", "contracts/reputation.clar", null, deployer);
    simnet.deployContract("governance", "contracts/governance.clar", null, deployer);
  });

  describe("Contract Initialization", () => {
    it("should initialize with correct owner", () => {
      const { result } = simnet.callReadOnlyFn("governance", "get-contract-owner", [], deployer);
      expect(result).toBePrincipal(deployer);
    });

    it("should initialize with governance inactive", () => {
      const { result } = simnet.callReadOnlyFn("governance", "is-governance-active", [], deployer);
      expect(result).toBeBool(false);
    });

    it("should return correct governance parameters", () => {
      const { result } = simnet.callReadOnlyFn("governance", "get-governance-parameters", [], deployer);
      expect(result).toBeOk({
        "min-reputation-to-propose": 100n,
        "min-reputation-to-vote": 10n,
        "voting-period": 1008n,
        "execution-delay": 144n,
        "quorum-threshold": 20n,
        "approval-threshold": 60n,
        "governance-active": false
      });
    });
  });

  describe("Administrative Functions", () => {
    it("should allow owner to activate governance", () => {
      const { result } = simnet.callPublicFn("governance", "activate-governance", [], deployer);
      expect(result).toBeOk(true);

      const active = simnet.callReadOnlyFn("governance", "is-governance-active", [], deployer);
      expect(active.result).toBeBool(true);
    });

    it("should not allow non-owner to activate governance", () => {
      const { result } = simnet.callPublicFn("governance", "activate-governance", [], wallet1);
      expect(result).toBeErr(800n); // ERR_UNAUTHORIZED
    });

    it("should allow owner to set new owner", () => {
      const { result } = simnet.callPublicFn(
        "governance",
        "set-contract-owner",
        [types.principal(wallet1)],
        deployer
      );
      expect(result).toBeOk(true);

      const owner = simnet.callReadOnlyFn("governance", "get-contract-owner", [], deployer);
      expect(owner.result).toBePrincipal(wallet1);
    });
  });

  describe("Proposal Creation", () => {
    beforeEach(() => {
      // Activate governance
      simnet.callPublicFn("governance", "activate-governance", [], deployer);
      
      // Give wallet1 sufficient reputation to create proposals
      simnet.callPublicFn(
        "reputation",
        "add-rating",
        [
          types.principal(wallet1),
          types.uint(1),
          types.uint(5),
          types.ascii("Great work!")
        ],
        wallet2
      );
      // Add more ratings to reach minimum reputation
      for (let i = 2; i <= 25; i++) {
        simnet.callPublicFn(
          "reputation",
          "add-rating",
          [
            types.principal(wallet1),
            types.uint(i),
            types.uint(5),
            types.ascii("Excellent!")
          ],
          wallet3
        );
      }
    });

    it("should allow user with sufficient reputation to create proposal", () => {
      const { result } = simnet.callPublicFn(
        "governance",
        "create-proposal",
        [
          types.ascii("Test Proposal"),
          types.ascii("This is a test proposal for parameter changes"),
          types.uint(1) // PROPOSAL_TYPE_PARAMETER
        ],
        wallet1
      );
      expect(result).toBeOk(1n); // First proposal ID

      // Check proposal was created
      const proposal = simnet.callReadOnlyFn(
        "governance",
        "get-proposal",
        [types.uint(1)],
        deployer
      );
      expect(proposal.result).toBeSome({
        proposer: wallet1,
        title: "Test Proposal",
        description: "This is a test proposal for parameter changes",
        "proposal-type": 1n,
        "created-at": types.uint(simnet.blockHeight),
        "voting-ends-at": types.uint(simnet.blockHeight + 1008),
        "execution-available-at": types.uint(simnet.blockHeight + 1008 + 144),
        "yes-votes": 0n,
        "no-votes": 0n,
        "total-voting-power": 0n,
        executed: false,
        cancelled: false
      });
    });

    it("should not allow user with insufficient reputation to create proposal", () => {
      const { result } = simnet.callPublicFn(
        "governance",
        "create-proposal",
        [
          types.ascii("Test Proposal"),
          types.ascii("This should fail"),
          types.uint(1)
        ],
        wallet2 // wallet2 has no reputation
      );
      expect(result).toBeErr(806n); // ERR_INSUFFICIENT_REPUTATION
    });

    it("should not allow proposal creation when governance is inactive", () => {
      // Deactivate governance by deploying fresh contract
      simnet.deployContract("governance", "contracts/governance.clar", null, deployer);

      const { result } = simnet.callPublicFn(
        "governance",
        "create-proposal",
        [
          types.ascii("Test Proposal"),
          types.ascii("This should fail"),
          types.uint(1)
        ],
        wallet1
      );
      expect(result).toBeErr(800n); // ERR_UNAUTHORIZED
    });

    it("should increment proposal ID for each new proposal", () => {
      // Create first proposal
      const result1 = simnet.callPublicFn(
        "governance",
        "create-proposal",
        [
          types.ascii("Proposal 1"),
          types.ascii("First proposal"),
          types.uint(1)
        ],
        wallet1
      );
      expect(result1.result).toBeOk(1n);

      // Create second proposal
      const result2 = simnet.callPublicFn(
        "governance",
        "create-proposal",
        [
          types.ascii("Proposal 2"),
          types.ascii("Second proposal"),
          types.uint(2)
        ],
        wallet1
      );
      expect(result2.result).toBeOk(2n);

      // Check next proposal ID
      const nextId = simnet.callReadOnlyFn("governance", "get-next-proposal-id", [], deployer);
      expect(nextId.result).toBeUint(3n);
    });
  });

  describe("Voting", () => {
    beforeEach(() => {
      // Activate governance
      simnet.callPublicFn("governance", "activate-governance", [], deployer);
      
      // Give users reputation
      for (let i = 1; i <= 25; i++) {
        simnet.callPublicFn(
          "reputation",
          "add-rating",
          [types.principal(wallet1), types.uint(i), types.uint(5), types.ascii("Great!")],
          wallet2
        );
        simnet.callPublicFn(
          "reputation",
          "add-rating",
          [types.principal(wallet2), types.uint(i + 25), types.uint(4), types.ascii("Good!")],
          wallet1
        );
      }

      // Create a proposal
      simnet.callPublicFn(
        "governance",
        "create-proposal",
        [
          types.ascii("Test Proposal"),
          types.ascii("Test proposal for voting"),
          types.uint(1)
        ],
        wallet1
      );
    });

    it("should allow user with sufficient reputation to vote", () => {
      const { result } = simnet.callPublicFn(
        "governance",
        "vote-on-proposal",
        [types.uint(1), types.bool(true)], // Vote YES
        wallet2
      );
      expect(result).toBeOk(true);

      // Check vote was recorded
      const vote = simnet.callReadOnlyFn(
        "governance",
        "get-vote",
        [types.uint(1), types.principal(wallet2)],
        deployer
      );
      expect(vote.result).toBeSome({
        vote: true,
        "voting-power": 100n, // 25 ratings * 4 points each
        "voted-at": types.uint(simnet.blockHeight)
      });
    });

    it("should not allow user with insufficient reputation to vote", () => {
      const { result } = simnet.callPublicFn(
        "governance",
        "vote-on-proposal",
        [types.uint(1), types.bool(true)],
        wallet3 // wallet3 has no reputation
      );
      expect(result).toBeErr(806n); // ERR_INSUFFICIENT_REPUTATION
    });

    it("should not allow double voting", () => {
      // First vote
      simnet.callPublicFn(
        "governance",
        "vote-on-proposal",
        [types.uint(1), types.bool(true)],
        wallet2
      );

      // Second vote should fail
      const { result } = simnet.callPublicFn(
        "governance",
        "vote-on-proposal",
        [types.uint(1), types.bool(false)],
        wallet2
      );
      expect(result).toBeErr(805n); // ERR_ALREADY_VOTED
    });

    it("should update proposal vote counts correctly", () => {
      // Vote YES
      simnet.callPublicFn(
        "governance",
        "vote-on-proposal",
        [types.uint(1), types.bool(true)],
        wallet2
      );

      // Vote NO
      simnet.callPublicFn(
        "governance",
        "vote-on-proposal",
        [types.uint(1), types.bool(false)],
        wallet1
      );

      // Check updated proposal
      const proposal = simnet.callReadOnlyFn(
        "governance",
        "get-proposal",
        [types.uint(1)],
        deployer
      );
      
      const proposalData = proposal.result.expectSome();
      expect(proposalData["yes-votes"]).toBeUint(100n); // wallet2's reputation
      expect(proposalData["no-votes"]).toBeUint(125n); // wallet1's reputation
      expect(proposalData["total-voting-power"]).toBeUint(225n);
    });
  });

  describe("Edge Cases", () => {
    it("should handle non-existent proposal", () => {
      const { result } = simnet.callReadOnlyFn(
        "governance",
        "get-proposal",
        [types.uint(999)],
        deployer
      );
      expect(result).toBeNone();
    });

    it("should handle voting on non-existent proposal", () => {
      simnet.callPublicFn("governance", "activate-governance", [], deployer);
      
      const { result } = simnet.callPublicFn(
        "governance",
        "vote-on-proposal",
        [types.uint(999), types.bool(true)],
        wallet1
      );
      expect(result).toBeErr(801n); // ERR_PROPOSAL_NOT_FOUND
    });
  });
});
