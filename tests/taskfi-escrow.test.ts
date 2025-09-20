import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("TaskFi Escrow Contract Tests", () => {
  beforeEach(() => {
    simnet.setEpoch("3.0");
  });

  describe("Deposit Reward", () => {
    it("should deposit reward successfully", () => {
      const taskId = 1;
      const amount = 1000000; // 1 STX

      // First transfer STX to the wallet for deposit
      simnet.transferSTX(amount, wallet1, deployer);

      const { result } = simnet.callPublicFn(
        "taskfi-escrow",
        "deposit-reward",
        [Cl.principal(wallet1), Cl.uint(taskId), Cl.uint(amount)],
        deployer // Called by core contract (simulated as deployer)
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to deposit with zero amount", () => {
      const taskId = 1;
      const amount = 0;

      const { result } = simnet.callPublicFn(
        "taskfi-escrow",
        "deposit-reward",
        [Cl.principal(wallet1), Cl.uint(taskId), Cl.uint(amount)],
        deployer
      );

      expect(result).toBeErr(Cl.uint(400)); // ERR-INVALID-INPUT
    });

    it("should fail to deposit for same task twice", () => {
      const taskId = 1;
      const amount = 1000000;

      simnet.transferSTX(amount * 2, wallet1, deployer);

      // First deposit should succeed
      simnet.callPublicFn(
        "taskfi-escrow",
        "deposit-reward",
        [Cl.principal(wallet1), Cl.uint(taskId), Cl.uint(amount)],
        deployer
      );

      // Second deposit for same task should fail
      const { result } = simnet.callPublicFn(
        "taskfi-escrow",
        "deposit-reward",
        [Cl.principal(wallet1), Cl.uint(taskId), Cl.uint(amount)],
        deployer
      );

      expect(result).toBeErr(Cl.uint(409)); // ERR-ALREADY-EXISTS
    });

    it("should fail unauthorized deposit", () => {
      const taskId = 1;
      const amount = 1000000;

      const { result } = simnet.callPublicFn(
        "taskfi-escrow",
        "deposit-reward",
        [Cl.principal(wallet1), Cl.uint(taskId), Cl.uint(amount)],
        wallet1 // Unauthorized caller
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });
  });

  describe("Release Funds", () => {
    beforeEach(() => {
      // Setup: deposit funds for testing
      const taskId = 1;
      const amount = 1000000;
      simnet.transferSTX(amount, wallet1, deployer);

      simnet.callPublicFn(
        "taskfi-escrow",
        "deposit-reward",
        [Cl.principal(wallet1), Cl.uint(taskId), Cl.uint(amount)],
        deployer
      );
    });

    it("should release funds successfully", () => {
      const taskId = 1;
      const recipient = wallet2;

      const { result } = simnet.callPublicFn(
        "taskfi-escrow",
        "release-funds",
        [Cl.uint(taskId), Cl.principal(recipient)],
        deployer // Called by core contract
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to release non-existent escrow", () => {
      const taskId = 999;
      const recipient = wallet2;

      const { result } = simnet.callPublicFn(
        "taskfi-escrow",
        "release-funds",
        [Cl.uint(taskId), Cl.principal(recipient)],
        deployer
      );

      expect(result).toBeErr(Cl.uint(404)); // ERR-NOT-FOUND
    });

    it("should fail unauthorized release", () => {
      const taskId = 1;
      const recipient = wallet2;

      const { result } = simnet.callPublicFn(
        "taskfi-escrow",
        "release-funds",
        [Cl.uint(taskId), Cl.principal(recipient)],
        wallet1 // Unauthorized caller
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });
  });

  describe("Refund", () => {
    beforeEach(() => {
      // Setup: deposit funds for testing
      const taskId = 1;
      const amount = 1000000;
      simnet.transferSTX(amount, wallet1, deployer);

      simnet.callPublicFn(
        "taskfi-escrow",
        "deposit-reward",
        [Cl.principal(wallet1), Cl.uint(taskId), Cl.uint(amount)],
        deployer
      );
    });

    it("should refund successfully", () => {
      const taskId = 1;

      const { result } = simnet.callPublicFn(
        "taskfi-escrow",
        "refund",
        [Cl.uint(taskId)],
        deployer // Called by core contract
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to refund non-existent escrow", () => {
      const taskId = 999;

      const { result } = simnet.callPublicFn(
        "taskfi-escrow",
        "refund",
        [Cl.uint(taskId)],
        deployer
      );

      expect(result).toBeErr(Cl.uint(404)); // ERR-NOT-FOUND
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      // Setup: deposit funds for testing
      const taskId = 1;
      const amount = 1000000;
      simnet.transferSTX(amount, wallet1, deployer);

      simnet.callPublicFn(
        "taskfi-escrow",
        "deposit-reward",
        [Cl.principal(wallet1), Cl.uint(taskId), Cl.uint(amount)],
        deployer
      );
    });

    it("should get escrow details", () => {
      const taskId = 1;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-escrow",
        "get-escrow",
        [Cl.uint(taskId)],
        wallet1
      );

      expect(result).toBeSome();
    });

    it("should return none for non-existent escrow", () => {
      const taskId = 999;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-escrow",
        "get-escrow",
        [Cl.uint(taskId)],
        wallet1
      );

      expect(result).toBeNone();
    });

    it("should get depositor balance", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-escrow",
        "get-depositor-balance",
        [Cl.principal(wallet1)],
        wallet1
      );

      expect(result).toBeUint(1000000);
    });

    it("should get total escrowed", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-escrow",
        "get-total-escrowed",
        [],
        wallet1
      );

      expect(result).toBeUint(1000000);
    });
  });
});
