import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("TaskFi Governance Contract Tests", () => {
  beforeEach(() => {
    simnet.setEpoch("3.0");
    
    // Setup voting power for test wallets
    simnet.callPublicFn(
      "taskfi-governance",
      "update-voting-power",
      [Cl.principal(wallet1), Cl.uint(10000000)], // 10 STX voting power
      deployer // Simulated call from staking contract
    );
    
    simnet.callPublicFn(
      "taskfi-governance",
      "update-voting-power",
      [Cl.principal(wallet2), Cl.uint(5000000)], // 5 STX voting power
      deployer
    );
  });

  describe("Proposal Creation", () => {
    it("should create a proposal successfully", () => {
      const title = "Test Proposal";
      const description = "This is a test governance proposal";
      const proposalType = 1; // PROPOSAL-TYPE-PARAMETER

      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "create-proposal",
        [
          Cl.stringAscii(title),
          Cl.stringAscii(description),
          Cl.uint(proposalType),
          Cl.none(),
          Cl.none(),
          Cl.none(),
        ],
        wallet1
      );

      expect(result).toBeOk(Cl.uint(1));
    });

    it("should fail to create proposal with empty title", () => {
      const title = "";
      const description = "This is a test governance proposal";
      const proposalType = 1;

      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "create-proposal",
        [
          Cl.stringAscii(title),
          Cl.stringAscii(description),
          Cl.uint(proposalType),
          Cl.none(),
          Cl.none(),
          Cl.none(),
        ],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(400)); // ERR-INVALID-INPUT
    });

    it("should fail to create proposal with insufficient stake", () => {
      const title = "Test Proposal";
      const description = "This is a test governance proposal";
      const proposalType = 1;

      // Use wallet3 which has no voting power
      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "create-proposal",
        [
          Cl.stringAscii(title),
          Cl.stringAscii(description),
          Cl.uint(proposalType),
          Cl.none(),
          Cl.none(),
          Cl.none(),
        ],
        wallet3
      );

      expect(result).toBeErr(Cl.uint(413)); // ERR-INSUFFICIENT-STAKE
    });

    it("should create different types of proposals", () => {
      const proposals = [
        { type: 1, name: "Parameter Change" },
        { type: 2, name: "Contract Upgrade" },
        { type: 3, name: "Emergency Pause" },
        { type: 4, name: "Treasury Action" },
      ];

      proposals.forEach((proposal, index) => {
        const { result } = simnet.callPublicFn(
          "taskfi-governance",
          "create-proposal",
          [
            Cl.stringAscii(proposal.name),
            Cl.stringAscii(`Description for ${proposal.name}`),
            Cl.uint(proposal.type),
            Cl.none(),
            Cl.none(),
            Cl.none(),
          ],
          wallet1
        );

        expect(result).toBeOk(Cl.uint(index + 1));
      });
    });
  });

  describe("Voting", () => {
    beforeEach(() => {
      // Create a proposal for voting tests
      simnet.callPublicFn(
        "taskfi-governance",
        "create-proposal",
        [
          Cl.stringAscii("Test Proposal"),
          Cl.stringAscii("Test Description"),
          Cl.uint(1),
          Cl.none(),
          Cl.none(),
          Cl.none(),
        ],
        wallet1
      );
    });

    it("should cast vote successfully", () => {
      const proposalId = 1;
      const vote = true; // Vote yes

      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(proposalId), Cl.bool(vote)],
        wallet2
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to vote twice on same proposal", () => {
      const proposalId = 1;
      const vote = true;

      // First vote should succeed
      simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(proposalId), Cl.bool(vote)],
        wallet2
      );

      // Second vote should fail
      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(proposalId), Cl.bool(vote)],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(412)); // ERR-ALREADY-VOTED
    });

    it("should fail to vote on non-existent proposal", () => {
      const proposalId = 999;
      const vote = true;

      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(proposalId), Cl.bool(vote)],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(404)); // ERR-NOT-FOUND
    });

    it("should fail to vote with no voting power", () => {
      const proposalId = 1;
      const vote = true;

      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(proposalId), Cl.bool(vote)],
        wallet3 // No voting power
      );

      expect(result).toBeErr(Cl.uint(413)); // ERR-INSUFFICIENT-STAKE
    });

    it("should allow both yes and no votes", () => {
      const proposalId = 1;

      // Vote yes
      let result = simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(proposalId), Cl.bool(true)],
        wallet1
      );
      expect(result).toBeOk(Cl.bool(true));

      // Vote no
      result = simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(proposalId), Cl.bool(false)],
        wallet2
      );
      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("Proposal Finalization", () => {
    beforeEach(() => {
      // Create and vote on a proposal
      simnet.callPublicFn(
        "taskfi-governance",
        "create-proposal",
        [
          Cl.stringAscii("Test Proposal"),
          Cl.stringAscii("Test Description"),
          Cl.uint(1),
          Cl.none(),
          Cl.none(),
          Cl.none(),
        ],
        wallet1
      );

      // Cast votes
      simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(1), Cl.bool(true)],
        wallet1
      );
      
      simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(1), Cl.bool(true)],
        wallet2
      );
    });

    it("should fail to finalize before voting period ends", () => {
      const proposalId = 1;

      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "finalize-proposal",
        [Cl.uint(proposalId)],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(411)); // ERR-VOTING-ACTIVE
    });

    it("should finalize proposal after voting period", () => {
      const proposalId = 1;

      // Advance blocks to end voting period
      simnet.mineEmptyBlocks(2016); // VOTING-PERIOD

      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "finalize-proposal",
        [Cl.uint(proposalId)],
        wallet1
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to finalize non-existent proposal", () => {
      const proposalId = 999;

      // Advance blocks
      simnet.mineEmptyBlocks(2016);

      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "finalize-proposal",
        [Cl.uint(proposalId)],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(404)); // ERR-NOT-FOUND
    });
  });

  describe("Proposal Execution", () => {
    beforeEach(() => {
      // Create, vote on, and finalize a proposal
      simnet.callPublicFn(
        "taskfi-governance",
        "create-proposal",
        [
          Cl.stringAscii("Test Proposal"),
          Cl.stringAscii("Test Description"),
          Cl.uint(1),
          Cl.none(),
          Cl.none(),
          Cl.none(),
        ],
        wallet1
      );

      // Cast votes
      simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(1), Cl.bool(true)],
        wallet1
      );
      
      simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(1), Cl.bool(true)],
        wallet2
      );

      // Advance blocks and finalize
      simnet.mineEmptyBlocks(2016);
      simnet.callPublicFn(
        "taskfi-governance",
        "finalize-proposal",
        [Cl.uint(1)],
        wallet1
      );
    });

    it("should fail to execute before execution delay", () => {
      const proposalId = 1;

      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "execute-proposal",
        [Cl.uint(proposalId)],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(411)); // ERR-VOTING-ACTIVE (reused for execution delay)
    });

    it("should execute proposal after execution delay", () => {
      const proposalId = 1;

      // Advance blocks for execution delay
      simnet.mineEmptyBlocks(1440); // EXECUTION-DELAY

      const { result } = simnet.callPublicFn(
        "taskfi-governance",
        "execute-proposal",
        [Cl.uint(proposalId)],
        wallet1
      );

      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      // Create a proposal for read tests
      simnet.callPublicFn(
        "taskfi-governance",
        "create-proposal",
        [
          Cl.stringAscii("Test Proposal"),
          Cl.stringAscii("Test Description"),
          Cl.uint(1),
          Cl.none(),
          Cl.none(),
          Cl.none(),
        ],
        wallet1
      );
    });

    it("should get proposal details", () => {
      const proposalId = 1;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-governance",
        "get-proposal",
        [Cl.uint(proposalId)],
        wallet1
      );

      expect(result).toBeSome();
    });

    it("should return none for non-existent proposal", () => {
      const proposalId = 999;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-governance",
        "get-proposal",
        [Cl.uint(proposalId)],
        wallet1
      );

      expect(result).toBeNone();
    });

    it("should get voting power", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-governance",
        "get-voting-power",
        [Cl.principal(wallet1)],
        wallet1
      );

      expect(result).toBeUint(10000000);
    });

    it("should get total voting power", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-governance",
        "get-total-voting-power",
        [],
        wallet1
      );

      expect(result).toBeUint(15000000); // wallet1 + wallet2
    });

    it("should get proposal counter", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-governance",
        "get-proposal-counter",
        [],
        wallet1
      );

      expect(result).toBeUint(1);
    });

    it("should check if user has voted", () => {
      const proposalId = 1;

      // Before voting
      let result = simnet.callReadOnlyFn(
        "taskfi-governance",
        "has-voted",
        [Cl.uint(proposalId), Cl.principal(wallet1)],
        wallet1
      );
      expect(result).toBeBool(false);

      // After voting
      simnet.callPublicFn(
        "taskfi-governance",
        "cast-vote",
        [Cl.uint(proposalId), Cl.bool(true)],
        wallet1
      );

      result = simnet.callReadOnlyFn(
        "taskfi-governance",
        "has-voted",
        [Cl.uint(proposalId), Cl.principal(wallet1)],
        wallet1
      );
      expect(result).toBeBool(true);
    });

    it("should check if proposal can be executed", () => {
      const proposalId = 1;

      // Before finalization
      let result = simnet.callReadOnlyFn(
        "taskfi-governance",
        "can-execute-proposal",
        [Cl.uint(proposalId)],
        wallet1
      );
      expect(result).toBeBool(false);

      // After full process (would need to complete voting and delays)
      // This is a simplified test - full execution readiness requires more setup
    });
  });
});
