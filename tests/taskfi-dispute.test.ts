import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("TaskFi Dispute Contract Tests", () => {
  beforeEach(() => {
    simnet.setEpoch("3.0");
    
    // Setup reputation for jurors
    simnet.callPublicFn(
      "taskfi-reputation",
      "add-reputation",
      [Cl.principal(wallet1), Cl.uint(200)],
      deployer
    );
    
    simnet.callPublicFn(
      "taskfi-reputation",
      "add-reputation",
      [Cl.principal(wallet2), Cl.uint(150)],
      deployer
    );
    
    simnet.callPublicFn(
      "taskfi-reputation",
      "add-reputation",
      [Cl.principal(wallet3), Cl.uint(100)],
      deployer
    );
  });

  describe("Dispute Creation", () => {
    it("should open dispute successfully", () => {
      const taskId = 1;

      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "open-dispute",
        [Cl.uint(taskId)],
        deployer // Called by core contract
      );

      expect(result).toBeOk(Cl.uint(1)); // Returns dispute ID
    });

    it("should fail to open dispute for same task twice", () => {
      const taskId = 1;

      // First dispute should succeed
      simnet.callPublicFn(
        "taskfi-dispute",
        "open-dispute",
        [Cl.uint(taskId)],
        deployer
      );

      // Second dispute for same task should fail
      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "open-dispute",
        [Cl.uint(taskId)],
        deployer
      );

      expect(result).toBeErr(Cl.uint(409)); // ERR-ALREADY-EXISTS
    });

    it("should fail unauthorized dispute creation", () => {
      const taskId = 1;

      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "open-dispute",
        [Cl.uint(taskId)],
        wallet1 // Unauthorized caller
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });

    it("should create multiple disputes for different tasks", () => {
      const taskIds = [1, 2, 3];

      taskIds.forEach((taskId, index) => {
        const { result } = simnet.callPublicFn(
          "taskfi-dispute",
          "open-dispute",
          [Cl.uint(taskId)],
          deployer
        );

        expect(result).toBeOk(Cl.uint(index + 1));
      });
    });
  });

  describe("Juror Voting", () => {
    beforeEach(() => {
      // Create a dispute for voting tests
      simnet.callPublicFn(
        "taskfi-dispute",
        "open-dispute",
        [Cl.uint(1)],
        deployer
      );
    });

    it("should cast vote successfully", () => {
      const disputeId = 1;
      const vote = true; // Vote for requester

      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "vote-dispute",
        [Cl.uint(disputeId), Cl.bool(vote)],
        wallet1 // Juror
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should allow multiple jurors to vote", () => {
      const disputeId = 1;

      // Multiple jurors vote
      const votes = [
        { juror: wallet1, vote: true },
        { juror: wallet2, vote: false },
        { juror: wallet3, vote: true },
      ];

      votes.forEach((voteData) => {
        const { result } = simnet.callPublicFn(
          "taskfi-dispute",
          "vote-dispute",
          [Cl.uint(disputeId), Cl.bool(voteData.vote)],
          voteData.juror
        );

        expect(result).toBeOk(Cl.bool(true));
      });
    });

    it("should fail to vote twice", () => {
      const disputeId = 1;
      const vote = true;

      // First vote should succeed
      simnet.callPublicFn(
        "taskfi-dispute",
        "vote-dispute",
        [Cl.uint(disputeId), Cl.bool(vote)],
        wallet1
      );

      // Second vote should fail
      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "vote-dispute",
        [Cl.uint(disputeId), Cl.bool(vote)],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(418)); // ERR-ALREADY-VOTED
    });

    it("should fail to vote on non-existent dispute", () => {
      const disputeId = 999;
      const vote = true;

      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "vote-dispute",
        [Cl.uint(disputeId), Cl.bool(vote)],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(404)); // ERR-NOT-FOUND
    });

    it("should fail to vote after voting period ends", () => {
      const disputeId = 1;
      const vote = true;

      // Advance blocks to end voting period
      simnet.mineEmptyBlocks(432); // DISPUTE-VOTING-PERIOD

      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "vote-dispute",
        [Cl.uint(disputeId), Cl.bool(vote)],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(417)); // ERR-VOTING-ENDED
    });
  });

  describe("Dispute Resolution", () => {
    beforeEach(() => {
      // Create dispute and cast votes
      simnet.callPublicFn(
        "taskfi-dispute",
        "open-dispute",
        [Cl.uint(1)],
        deployer
      );

      // Cast some votes
      simnet.callPublicFn(
        "taskfi-dispute",
        "vote-dispute",
        [Cl.uint(1), Cl.bool(true)],
        wallet1
      );
      
      simnet.callPublicFn(
        "taskfi-dispute",
        "vote-dispute",
        [Cl.uint(1), Cl.bool(true)],
        wallet2
      );
      
      simnet.callPublicFn(
        "taskfi-dispute",
        "vote-dispute",
        [Cl.uint(1), Cl.bool(false)],
        wallet3
      );
    });

    it("should fail to resolve before voting period ends", () => {
      const disputeId = 1;

      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "resolve-dispute",
        [Cl.uint(disputeId)],
        deployer
      );

      expect(result).toBeErr(Cl.uint(411)); // ERR-VOTING-ACTIVE
    });

    it("should resolve dispute after voting period", () => {
      const disputeId = 1;

      // Advance blocks to end voting period
      simnet.mineEmptyBlocks(432);

      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "resolve-dispute",
        [Cl.uint(disputeId)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to resolve non-existent dispute", () => {
      const disputeId = 999;

      // Advance blocks
      simnet.mineEmptyBlocks(432);

      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "resolve-dispute",
        [Cl.uint(disputeId)],
        deployer
      );

      expect(result).toBeErr(Cl.uint(404)); // ERR-NOT-FOUND
    });

    it("should fail unauthorized resolution", () => {
      const disputeId = 1;

      // Advance blocks
      simnet.mineEmptyBlocks(432);

      const { result } = simnet.callPublicFn(
        "taskfi-dispute",
        "resolve-dispute",
        [Cl.uint(disputeId)],
        wallet1 // Unauthorized
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });
  });

  describe("Juror Selection", () => {
    it("should select jurors for dispute", () => {
      const taskId = 1;
      const jurorCount = 3;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "select-jurors",
        [Cl.uint(taskId), Cl.uint(jurorCount)],
        wallet1
      );

      expect(result).toBeList(); // Should return a list of jurors
    });

    it("should handle juror selection with insufficient jurors", () => {
      const taskId = 1;
      const jurorCount = 100; // More than available

      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "select-jurors",
        [Cl.uint(taskId), Cl.uint(jurorCount)],
        wallet1
      );

      expect(result).toBeList(); // Should return available jurors
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      // Create and vote on a dispute
      simnet.callPublicFn(
        "taskfi-dispute",
        "open-dispute",
        [Cl.uint(1)],
        deployer
      );

      simnet.callPublicFn(
        "taskfi-dispute",
        "vote-dispute",
        [Cl.uint(1), Cl.bool(true)],
        wallet1
      );
    });

    it("should get dispute details", () => {
      const disputeId = 1;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "get-dispute",
        [Cl.uint(disputeId)],
        wallet1
      );

      expect(result).toBeSome();
    });

    it("should return none for non-existent dispute", () => {
      const disputeId = 999;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "get-dispute",
        [Cl.uint(disputeId)],
        wallet1
      );

      expect(result).toBeNone();
    });

    it("should get vote details", () => {
      const disputeId = 1;
      const juror = wallet1;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "get-vote",
        [Cl.uint(disputeId), Cl.principal(juror)],
        wallet1
      );

      expect(result).toBeSome();
    });

    it("should check if juror has voted", () => {
      const disputeId = 1;

      // Check voted juror
      let result = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "has-voted",
        [Cl.uint(disputeId), Cl.principal(wallet1)],
        wallet1
      );
      expect(result).toBeBool(true);

      // Check non-voted juror
      result = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "has-voted",
        [Cl.uint(disputeId), Cl.principal(wallet2)],
        wallet1
      );
      expect(result).toBeBool(false);
    });

    it("should get dispute counter", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "get-dispute-counter",
        [],
        wallet1
      );

      expect(result).toBeUint(1);
    });

    it("should get voting results", () => {
      const disputeId = 1;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "get-voting-results",
        [Cl.uint(disputeId)],
        wallet1
      );

      expect(result).toBeSome();
    });

    it("should check if dispute is active", () => {
      const disputeId = 1;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "is-dispute-active",
        [Cl.uint(disputeId)],
        wallet1
      );

      expect(result).toBeBool(true);
    });

    it("should get dispute by task ID", () => {
      const taskId = 1;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "get-dispute-by-task",
        [Cl.uint(taskId)],
        wallet1
      );

      expect(result).toBeSome();
    });
  });

  describe("Dispute Statistics", () => {
    beforeEach(() => {
      // Create multiple disputes with different outcomes
      const disputes = [
        { taskId: 1, votes: [true, true, false] }, // Requester wins
        { taskId: 2, votes: [false, false, true] }, // Worker wins
        { taskId: 3, votes: [true, false] }, // Ongoing
      ];

      disputes.forEach((dispute, index) => {
        simnet.callPublicFn(
          "taskfi-dispute",
          "open-dispute",
          [Cl.uint(dispute.taskId)],
          deployer
        );

        dispute.votes.forEach((vote, voteIndex) => {
          const juror = [wallet1, wallet2, wallet3][voteIndex];
          simnet.callPublicFn(
            "taskfi-dispute",
            "vote-dispute",
            [Cl.uint(index + 1), Cl.bool(vote)],
            juror
          );
        });

        // Resolve first two disputes
        if (index < 2) {
          simnet.mineEmptyBlocks(432);
          simnet.callPublicFn(
            "taskfi-dispute",
            "resolve-dispute",
            [Cl.uint(index + 1)],
            deployer
          );
        }
      });
    });

    it("should get total disputes count", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "get-total-disputes",
        [],
        wallet1
      );

      expect(result).toBeUint(3);
    });

    it("should get active disputes count", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "get-active-disputes-count",
        [],
        wallet1
      );

      expect(result).toBeUint(1); // Only dispute 3 is still active
    });

    it("should get resolved disputes count", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-dispute",
        "get-resolved-disputes-count",
        [],
        wallet1
      );

      expect(result).toBeUint(2); // Disputes 1 and 2 are resolved
    });
  });
});
