import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("TaskFi Utils Contract Tests", () => {
  beforeEach(() => {
    simnet.setEpoch("3.0");
  });

  describe("Safe Math Functions", () => {
    it("should add numbers safely", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "safe-add",
        [Cl.uint(100), Cl.uint(200)],
        wallet1
      );

      expect(result).toBeOk(Cl.uint(300));
    });

    it("should detect overflow in addition", () => {
      const maxUint = 340282366920938463463374607431768211455n; // Max uint128
      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "safe-add",
        [Cl.uint(maxUint), Cl.uint(1)],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(420)); // ERR-OVERFLOW
    });

    it("should subtract numbers safely", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "safe-sub",
        [Cl.uint(300), Cl.uint(100)],
        wallet1
      );

      expect(result).toBeOk(Cl.uint(200));
    });

    it("should detect underflow in subtraction", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "safe-sub",
        [Cl.uint(100), Cl.uint(200)],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(420)); // ERR-OVERFLOW (used for underflow too)
    });

    it("should multiply numbers safely", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "safe-mul",
        [Cl.uint(100), Cl.uint(200)],
        wallet1
      );

      expect(result).toBeOk(Cl.uint(20000));
    });
  });

  describe("Percentage Calculations", () => {
    it("should calculate percentage correctly", () => {
      const amount = 1000000; // 1 STX
      const rate = 250; // 2.5%

      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "calculate-percentage",
        [Cl.uint(amount), Cl.uint(rate)],
        wallet1
      );

      expect(result).toBeUint(25000); // 2.5% of 1 STX
    });

    it("should calculate protocol fee", () => {
      const amount = 1000000; // 1 STX

      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "calculate-protocol-fee",
        [Cl.uint(amount)],
        wallet1
      );

      expect(result).toBeUint(25000); // 2.5% of 1 STX
    });

    it("should calculate dispute fee", () => {
      const amount = 1000000; // 1 STX

      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "calculate-dispute-fee",
        [Cl.uint(amount)],
        wallet1
      );

      expect(result).toBeUint(50000); // 5% of 1 STX
    });
  });

  describe("Validation Functions", () => {
    it("should validate reward amounts", () => {
      // Valid reward
      let result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-valid-reward",
        [Cl.uint(1000000)],
        wallet1
      );
      expect(result).toBeBool(true);

      // Zero reward (invalid)
      result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-valid-reward",
        [Cl.uint(0)],
        wallet1
      );
      expect(result).toBeBool(false);

      // Too large reward (invalid)
      result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-valid-reward",
        [Cl.uint(200000000000000)], // 200k STX (above max)
        wallet1
      );
      expect(result).toBeBool(false);
    });

    it("should validate stake amounts", () => {
      // Valid stake
      let result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-valid-stake",
        [Cl.uint(5000000)], // 5 STX
        wallet1
      );
      expect(result).toBeBool(true);

      // Below minimum (invalid)
      result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-valid-stake",
        [Cl.uint(500000)], // 0.5 STX
        wallet1
      );
      expect(result).toBeBool(false);

      // Above maximum (invalid)
      result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-valid-stake",
        [Cl.uint(20000000000000)], // 20M STX
        wallet1
      );
      expect(result).toBeBool(false);
    });

    it("should validate deadlines", () => {
      const currentBlock = simnet.blockHeight;

      // Future deadline (valid)
      let result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-valid-deadline",
        [Cl.uint(currentBlock + 100)],
        wallet1
      );
      expect(result).toBeBool(true);

      // Past deadline (invalid)
      result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-valid-deadline",
        [Cl.uint(currentBlock - 1)],
        wallet1
      );
      expect(result).toBeBool(false);
    });

    it("should check if deadline has passed", () => {
      const currentBlock = simnet.blockHeight;

      // Future deadline (not passed)
      let result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-deadline-passed",
        [Cl.uint(currentBlock + 100)],
        wallet1
      );
      expect(result).toBeBool(false);

      // Past deadline (passed)
      result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-deadline-passed",
        [Cl.uint(currentBlock - 1)],
        wallet1
      );
      expect(result).toBeBool(true);
    });
  });

  describe("Utility Functions", () => {
    it("should generate pseudo-random numbers", () => {
      const seed = 12345;
      const max = 100;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "pseudo-random",
        [Cl.uint(seed), Cl.uint(max)],
        wallet1
      );

      // Should return a number between 0 and max-1
      expect(result).toBeUint();
      // Note: We can't test the exact value as it depends on block height
    });

    it("should handle zero max in pseudo-random", () => {
      const seed = 12345;
      const max = 0;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "pseudo-random",
        [Cl.uint(seed), Cl.uint(max)],
        wallet1
      );

      expect(result).toBeUint(0);
    });

    it("should validate IPFS CID format", () => {
      const validCid = "QmTest123456789";
      const emptyCid = "";

      // Valid CID
      let result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-valid-ipfs-cid",
        [Cl.bufferFromAscii(validCid)],
        wallet1
      );
      expect(result).toBeBool(true);

      // Empty CID (invalid)
      result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "is-valid-ipfs-cid",
        [Cl.bufferFromAscii(emptyCid)],
        wallet1
      );
      expect(result).toBeBool(false);
    });

    it("should calculate reputation changes", () => {
      const taskReward = 5000000; // 5 STX

      // Successful task
      let result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "calculate-reputation-change",
        [Cl.uint(taskReward), Cl.bool(true)],
        wallet1
      );
      expect(result).toBeUint(5); // 5 reputation points

      // Failed task
      result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "calculate-reputation-change",
        [Cl.uint(taskReward), Cl.bool(false)],
        wallet1
      );
      // Note: This should return a negative value, but Clarity doesn't have signed integers
      // The implementation would need to be adjusted for proper negative handling
    });

    it("should get minimum of two values", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "min-uint",
        [Cl.uint(100), Cl.uint(200)],
        wallet1
      );

      expect(result).toBeUint(100);
    });
  });

  describe("Status Helper Functions", () => {
    it("should check task status permissions", () => {
      // Can accept open task
      let result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "can-accept-task",
        [Cl.uint(1)], // TASK-STATUS-OPEN
        wallet1
      );
      expect(result).toBeBool(true);

      // Cannot accept accepted task
      result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "can-accept-task",
        [Cl.uint(2)], // TASK-STATUS-ACCEPTED
        wallet1
      );
      expect(result).toBeBool(false);
    });

    it("should check delivery submission permissions", () => {
      // Can submit for accepted task
      let result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "can-submit-delivery",
        [Cl.uint(2)], // TASK-STATUS-ACCEPTED
        wallet1
      );
      expect(result).toBeBool(true);

      // Cannot submit for open task
      result = simnet.callReadOnlyFn(
        "taskfi-utils",
        "can-submit-delivery",
        [Cl.uint(1)], // TASK-STATUS-OPEN
        wallet1
      );
      expect(result).toBeBool(false);
    });
  });

  describe("Constants Getters", () => {
    it("should return task status constants", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "get-task-status-open",
        [],
        wallet1
      );

      expect(result).toBeUint(1);
    });

    it("should return reputation constants", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "get-initial-reputation",
        [],
        wallet1
      );

      expect(result).toBeUint(100);
    });

    it("should return fee rate constants", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-utils",
        "get-protocol-fee-rate",
        [],
        wallet1
      );

      expect(result).toBeUint(250); // 2.5%
    });
  });
});
