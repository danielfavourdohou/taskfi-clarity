import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("TaskFi Staking Contract Tests", () => {
  beforeEach(() => {
    simnet.setEpoch("3.0");
  });

  describe("Staking", () => {
    it("should stake successfully", () => {
      const staker = wallet1;
      const amount = 5000000; // 5 STX

      // Transfer STX to staker first
      simnet.transferSTX(amount, staker, deployer);

      const { result } = simnet.callPublicFn(
        "taskfi-staking",
        "stake",
        [Cl.principal(staker), Cl.uint(amount)],
        staker
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to stake below minimum amount", () => {
      const staker = wallet1;
      const amount = 500000; // 0.5 STX (below minimum)

      simnet.transferSTX(amount, staker, deployer);

      const { result } = simnet.callPublicFn(
        "taskfi-staking",
        "stake",
        [Cl.principal(staker), Cl.uint(amount)],
        staker
      );

      expect(result).toBeErr(Cl.uint(400)); // ERR-INVALID-INPUT
    });

    it("should fail to stake above maximum amount", () => {
      const staker = wallet1;
      const amount = 20000000000000; // 20M STX (above maximum)

      const { result } = simnet.callPublicFn(
        "taskfi-staking",
        "stake",
        [Cl.principal(staker), Cl.uint(amount)],
        staker
      );

      expect(result).toBeErr(Cl.uint(400)); // ERR-INVALID-INPUT
    });

    it("should allow adding to existing stake", () => {
      const staker = wallet1;
      const initialAmount = 5000000; // 5 STX
      const additionalAmount = 2000000; // 2 STX

      // Transfer STX to staker
      simnet.transferSTX(initialAmount + additionalAmount, staker, deployer);

      // Initial stake
      simnet.callPublicFn(
        "taskfi-staking",
        "stake",
        [Cl.principal(staker), Cl.uint(initialAmount)],
        staker
      );

      // Additional stake
      const { result } = simnet.callPublicFn(
        "taskfi-staking",
        "stake",
        [Cl.principal(staker), Cl.uint(additionalAmount)],
        staker
      );

      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("Unstaking", () => {
    beforeEach(() => {
      // Setup: stake some tokens
      const staker = wallet1;
      const amount = 5000000;
      simnet.transferSTX(amount, staker, deployer);

      simnet.callPublicFn(
        "taskfi-staking",
        "stake",
        [Cl.principal(staker), Cl.uint(amount)],
        staker
      );
    });

    it("should request unstaking successfully", () => {
      const staker = wallet1;

      const { result } = simnet.callPublicFn(
        "taskfi-staking",
        "request-unstake",
        [Cl.principal(staker)],
        staker
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to request unstaking for non-existent stake", () => {
      const staker = wallet2; // No stake

      const { result } = simnet.callPublicFn(
        "taskfi-staking",
        "request-unstake",
        [Cl.principal(staker)],
        staker
      );

      expect(result).toBeErr(Cl.uint(404)); // ERR-NOT-FOUND
    });

    it("should complete unstaking after timelock", () => {
      const staker = wallet1;

      // Request unstaking
      simnet.callPublicFn(
        "taskfi-staking",
        "request-unstake",
        [Cl.principal(staker)],
        staker
      );

      // Advance blocks to pass timelock
      simnet.mineEmptyBlocks(1008); // UNSTAKE-TIMELOCK-BLOCKS

      const { result } = simnet.callPublicFn(
        "taskfi-staking",
        "complete-unstake",
        [Cl.principal(staker)],
        staker
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to complete unstaking before timelock", () => {
      const staker = wallet1;

      // Request unstaking
      simnet.callPublicFn(
        "taskfi-staking",
        "request-unstake",
        [Cl.principal(staker)],
        staker
      );

      // Try to complete immediately (before timelock)
      const { result } = simnet.callPublicFn(
        "taskfi-staking",
        "complete-unstake",
        [Cl.principal(staker)],
        staker
      );

      expect(result).toBeErr(Cl.uint(400)); // ERR-INVALID-INPUT
    });
  });

  describe("Slashing", () => {
    beforeEach(() => {
      // Setup: stake some tokens
      const staker = wallet1;
      const amount = 5000000;
      simnet.transferSTX(amount, staker, deployer);

      simnet.callPublicFn(
        "taskfi-staking",
        "stake",
        [Cl.principal(staker), Cl.uint(amount)],
        staker
      );
    });

    it("should slash stake successfully", () => {
      const staker = wallet1;

      const { result } = simnet.callPublicFn(
        "taskfi-staking",
        "slash-stake",
        [Cl.principal(staker)],
        deployer // Called by dispute contract (simulated as deployer)
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail unauthorized slashing", () => {
      const staker = wallet1;

      const { result } = simnet.callPublicFn(
        "taskfi-staking",
        "slash-stake",
        [Cl.principal(staker)],
        wallet2 // Unauthorized caller
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      // Setup: stake some tokens
      const staker = wallet1;
      const amount = 5000000;
      simnet.transferSTX(amount, staker, deployer);

      simnet.callPublicFn(
        "taskfi-staking",
        "stake",
        [Cl.principal(staker), Cl.uint(amount)],
        staker
      );
    });

    it("should get stake details", () => {
      const staker = wallet1;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-staking",
        "get-stake",
        [Cl.principal(staker)],
        wallet1
      );

      expect(result).toBeSome();
    });

    it("should return none for non-existent stake", () => {
      const staker = wallet2; // No stake

      const { result } = simnet.callReadOnlyFn(
        "taskfi-staking",
        "get-stake",
        [Cl.principal(staker)],
        wallet1
      );

      expect(result).toBeNone();
    });

    it("should check if staker is active", () => {
      const staker = wallet1;

      const { result } = simnet.callReadOnlyFn(
        "taskfi-staking",
        "is-active-staker",
        [Cl.principal(staker)],
        wallet1
      );

      expect(result).toBeBool(true);
    });

    it("should get total staked amount", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-staking",
        "get-total-staked",
        [],
        wallet1
      );

      expect(result).toBeUint(5000000);
    });

    it("should get active stakers list", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-staking",
        "get-active-stakers",
        [],
        wallet1
      );

      expect(result).toBeList([Cl.principal(wallet1)]);
    });
  });
});
