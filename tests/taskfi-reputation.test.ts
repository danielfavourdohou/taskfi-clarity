import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("TaskFi Reputation Contract Tests", () => {
  beforeEach(() => {
    simnet.setEpoch("3.0");
  });

  describe("Reputation Management", () => {
    it("should add reputation successfully", () => {
      const user = wallet1;
      const amount = 50;

      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "add-reputation",
        [Cl.principal(user), Cl.uint(amount)],
        deployer // Called by core contract
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should subtract reputation successfully", () => {
      const user = wallet1;
      const addAmount = 150;
      const subtractAmount = 50;

      // First add reputation
      simnet.callPublicFn(
        "taskfi-reputation",
        "add-reputation",
        [Cl.principal(user), Cl.uint(addAmount)],
        deployer
      );

      // Then subtract
      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "subtract-reputation",
        [Cl.principal(user), Cl.uint(subtractAmount)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should not allow reputation to go below minimum", () => {
      const user = wallet1;
      const subtractAmount = 200; // More than initial reputation

      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "subtract-reputation",
        [Cl.principal(user), Cl.uint(subtractAmount)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true)); // Should succeed but cap at minimum
    });

    it("should not allow reputation to exceed maximum", () => {
      const user = wallet1;
      const addAmount = 2000; // More than max reputation

      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "add-reputation",
        [Cl.principal(user), Cl.uint(addAmount)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true)); // Should succeed but cap at maximum
    });

    it("should fail unauthorized reputation changes", () => {
      const user = wallet1;
      const amount = 50;

      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "add-reputation",
        [Cl.principal(user), Cl.uint(amount)],
        wallet2 // Unauthorized caller
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });
  });

  describe("Reputation Delegation", () => {
    beforeEach(() => {
      // Add some reputation to wallet1
      simnet.callPublicFn(
        "taskfi-reputation",
        "add-reputation",
        [Cl.principal(wallet1), Cl.uint(200)],
        deployer
      );
    });

    it("should delegate reputation successfully", () => {
      const delegator = wallet1;
      const delegatee = wallet2;
      const amount = 50;

      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "delegate-reputation",
        [Cl.principal(delegatee), Cl.uint(amount)],
        delegator
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to delegate more than available", () => {
      const delegator = wallet1;
      const delegatee = wallet2;
      const amount = 500; // More than available

      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "delegate-reputation",
        [Cl.principal(delegatee), Cl.uint(amount)],
        delegator
      );

      expect(result).toBeErr(Cl.uint(400)); // ERR-INVALID-INPUT
    });

    it("should undelegate reputation successfully", () => {
      const delegator = wallet1;
      const delegatee = wallet2;
      const amount = 50;

      // First delegate
      simnet.callPublicFn(
        "taskfi-reputation",
        "delegate-reputation",
        [Cl.principal(delegatee), Cl.uint(amount)],
        delegator
      );

      // Then undelegate
      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "undelegate-reputation",
        [Cl.principal(delegatee), Cl.uint(amount)],
        delegator
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to undelegate more than delegated", () => {
      const delegator = wallet1;
      const delegatee = wallet2;
      const delegateAmount = 50;
      const undelegateAmount = 100;

      // First delegate
      simnet.callPublicFn(
        "taskfi-reputation",
        "delegate-reputation",
        [Cl.principal(delegatee), Cl.uint(delegateAmount)],
        delegator
      );

      // Try to undelegate more
      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "undelegate-reputation",
        [Cl.principal(delegatee), Cl.uint(undelegateAmount)],
        delegator
      );

      expect(result).toBeErr(Cl.uint(400)); // ERR-INVALID-INPUT
    });
  });

  describe("Reputation Decay", () => {
    beforeEach(() => {
      // Add reputation to multiple users
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
    });

    it("should apply reputation decay successfully", () => {
      const numerator = 95; // 95%
      const denominator = 100;

      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "apply-reputation-decay",
        [Cl.uint(numerator), Cl.uint(denominator)],
        deployer // Called by admin
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail decay with invalid parameters", () => {
      const numerator = 0;
      const denominator = 100;

      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "apply-reputation-decay",
        [Cl.uint(numerator), Cl.uint(denominator)],
        deployer
      );

      expect(result).toBeErr(Cl.uint(400)); // ERR-INVALID-INPUT
    });

    it("should fail unauthorized decay", () => {
      const numerator = 95;
      const denominator = 100;

      const { result } = simnet.callPublicFn(
        "taskfi-reputation",
        "apply-reputation-decay",
        [Cl.uint(numerator), Cl.uint(denominator)],
        wallet1 // Unauthorized
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      // Setup reputation data
      simnet.callPublicFn(
        "taskfi-reputation",
        "add-reputation",
        [Cl.principal(wallet1), Cl.uint(150)],
        deployer
      );
      
      simnet.callPublicFn(
        "taskfi-reputation",
        "delegate-reputation",
        [Cl.principal(wallet2), Cl.uint(50)],
        wallet1
      );
    });

    it("should get user reputation", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-reputation",
        "get-reputation",
        [Cl.principal(wallet1)],
        wallet1
      );

      expect(result).toBeUint(250); // Initial 100 + added 150
    });

    it("should get effective reputation (including delegated)", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-reputation",
        "get-effective-reputation",
        [Cl.principal(wallet2)],
        wallet1
      );

      expect(result).toBeUint(150); // Initial 100 + delegated 50
    });

    it("should get delegation details", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-reputation",
        "get-delegation",
        [Cl.principal(wallet1), Cl.principal(wallet2)],
        wallet1
      );

      expect(result).toBeUint(50);
    });

    it("should check if user meets minimum reputation", () => {
      const minReputation = 200;

      // wallet1 should meet requirement
      let result = simnet.callReadOnlyFn(
        "taskfi-reputation",
        "meets-minimum-reputation",
        [Cl.principal(wallet1), Cl.uint(minReputation)],
        wallet1
      );
      expect(result).toBeBool(true);

      // wallet3 (no added reputation) should not meet requirement
      result = simnet.callReadOnlyFn(
        "taskfi-reputation",
        "meets-minimum-reputation",
        [Cl.principal(wallet3), Cl.uint(minReputation)],
        wallet1
      );
      expect(result).toBeBool(false);
    });

    it("should get reputation history", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-reputation",
        "get-reputation-history",
        [Cl.principal(wallet1)],
        wallet1
      );

      // Should return some history data
      expect(result).toBeSome();
    });

    it("should get total reputation in system", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-reputation",
        "get-total-reputation",
        [],
        wallet1
      );

      // Should be sum of all user reputations
      expect(result).toBeUint(); // Just check it returns a uint
    });

    it("should get reputation rank", () => {
      // Add different amounts to create ranking
      simnet.callPublicFn(
        "taskfi-reputation",
        "add-reputation",
        [Cl.principal(wallet2), Cl.uint(300)],
        deployer
      );

      const { result } = simnet.callReadOnlyFn(
        "taskfi-reputation",
        "get-reputation-rank",
        [Cl.principal(wallet1)],
        wallet1
      );

      expect(result).toBeUint(); // Should return a rank
    });

    it("should return initial reputation for new users", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-reputation",
        "get-reputation",
        [Cl.principal(wallet3)], // New user
        wallet1
      );

      expect(result).toBeUint(100); // Initial reputation
    });
  });

  describe("Reputation Thresholds", () => {
    it("should check various reputation levels", () => {
      const levels = [
        { user: wallet1, added: 0, expected: 100 }, // Initial only
        { user: wallet2, added: 100, expected: 200 }, // Initial + 100
        { user: wallet3, added: 900, expected: 1000 }, // Max reputation
      ];

      levels.forEach((level) => {
        if (level.added > 0) {
          simnet.callPublicFn(
            "taskfi-reputation",
            "add-reputation",
            [Cl.principal(level.user), Cl.uint(level.added)],
            deployer
          );
        }

        const { result } = simnet.callReadOnlyFn(
          "taskfi-reputation",
          "get-reputation",
          [Cl.principal(level.user)],
          wallet1
        );

        expect(result).toBeUint(level.expected);
      });
    });
  });
});
