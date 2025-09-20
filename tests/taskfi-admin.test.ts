import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("TaskFi Admin Contract Tests", () => {
  beforeEach(() => {
    simnet.setEpoch("3.0");
  });

  describe("Admin Management", () => {
    it("should add admin successfully", () => {
      const newAdmin = wallet1;
      const role = 1; // Admin role

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "add-admin",
        [Cl.principal(newAdmin), Cl.uint(role)],
        deployer // Contract owner
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to add admin from non-owner", () => {
      const newAdmin = wallet2;
      const role = 1;

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "add-admin",
        [Cl.principal(newAdmin), Cl.uint(role)],
        wallet1 // Not the owner
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });

    it("should remove admin successfully", () => {
      const admin = wallet1;
      const role = 1;

      // First add admin
      simnet.callPublicFn(
        "taskfi-admin",
        "add-admin",
        [Cl.principal(admin), Cl.uint(role)],
        deployer
      );

      // Then remove admin
      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "remove-admin",
        [Cl.principal(admin)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should transfer ownership successfully", () => {
      const newOwner = wallet1;

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "transfer-ownership",
        [Cl.principal(newOwner)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("Protocol Parameters", () => {
    it("should set minimum stake amount", () => {
      const newMinStake = 2000000; // 2 STX

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "set-min-stake-amount",
        [Cl.uint(newMinStake)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should set maximum task reward", () => {
      const newMaxReward = 50000000000; // 50k STX

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "set-max-task-reward",
        [Cl.uint(newMaxReward)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should set dispute fee", () => {
      const newDisputeFee = 1000000; // 1 STX

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "set-dispute-fee",
        [Cl.uint(newDisputeFee)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should set protocol fee rate", () => {
      const newFeeRate = 300; // 3%

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "set-protocol-fee-rate",
        [Cl.uint(newFeeRate)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to set parameters from non-admin", () => {
      const newMinStake = 2000000;

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "set-min-stake-amount",
        [Cl.uint(newMinStake)],
        wallet1 // Not admin
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });
  });

  describe("Protocol Control", () => {
    it("should pause protocol successfully", () => {
      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "pause-protocol",
        [],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should unpause protocol successfully", () => {
      // First pause
      simnet.callPublicFn("taskfi-admin", "pause-protocol", [], deployer);

      // Then unpause
      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "unpause-protocol",
        [],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to pause from non-admin", () => {
      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "pause-protocol",
        [],
        wallet1 // Not admin
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });
  });

  describe("Emergency Contacts", () => {
    it("should add emergency contact successfully", () => {
      const contact = wallet1;

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "add-emergency-contact",
        [Cl.principal(contact)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should remove emergency contact successfully", () => {
      const contact = wallet1;

      // First add contact
      simnet.callPublicFn(
        "taskfi-admin",
        "add-emergency-contact",
        [Cl.principal(contact)],
        deployer
      );

      // Then remove contact
      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "remove-emergency-contact",
        [Cl.principal(contact)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to add too many emergency contacts", () => {
      // Add maximum contacts (5)
      const contacts = [wallet1, wallet2, wallet3, deployer, deployer]; // Using deployer twice for simplicity
      
      contacts.forEach((contact, index) => {
        if (index < 5) {
          simnet.callPublicFn(
            "taskfi-admin",
            "add-emergency-contact",
            [Cl.principal(contact)],
            deployer
          );
        }
      });

      // Try to add one more (should fail)
      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "add-emergency-contact",
        [Cl.principal(wallet1)],
        deployer
      );

      expect(result).toBeErr(Cl.uint(400)); // ERR-INVALID-INPUT
    });
  });

  describe("Statistics", () => {
    it("should update task statistics", () => {
      const statType = "tasks-created";
      const amount = 5;

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "update-stats",
        [Cl.stringAscii(statType), Cl.uint(amount)],
        deployer // Called by core contract
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should update different types of statistics", () => {
      const stats = [
        { type: "tasks-created", amount: 10 },
        { type: "tasks-completed", amount: 8 },
        { type: "disputes-opened", amount: 2 },
        { type: "volume-processed", amount: 50000000 },
      ];

      stats.forEach((stat) => {
        const { result } = simnet.callPublicFn(
          "taskfi-admin",
          "update-stats",
          [Cl.stringAscii(stat.type), Cl.uint(stat.amount)],
          deployer
        );

        expect(result).toBeOk(Cl.bool(true));
      });
    });

    it("should fail to update stats from unauthorized caller", () => {
      const statType = "tasks-created";
      const amount = 5;

      const { result } = simnet.callPublicFn(
        "taskfi-admin",
        "update-stats",
        [Cl.stringAscii(statType), Cl.uint(amount)],
        wallet1 // Unauthorized
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      // Setup some data for read tests
      simnet.callPublicFn(
        "taskfi-admin",
        "add-admin",
        [Cl.principal(wallet1), Cl.uint(1)],
        deployer
      );
      
      simnet.callPublicFn(
        "taskfi-admin",
        "set-min-stake-amount",
        [Cl.uint(2000000)],
        deployer
      );
    });

    it("should check if address is admin", () => {
      // Check admin
      let result = simnet.callReadOnlyFn(
        "taskfi-admin",
        "is-admin",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(result).toBeBool(true);

      // Check non-admin
      result = simnet.callReadOnlyFn(
        "taskfi-admin",
        "is-admin",
        [Cl.principal(wallet2)],
        deployer
      );
      expect(result).toBeBool(false);
    });

    it("should get contract owner", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-admin",
        "get-contract-owner",
        [],
        wallet1
      );

      expect(result).toBePrincipal(deployer);
    });

    it("should check if protocol is paused", () => {
      // Initially not paused
      let result = simnet.callReadOnlyFn(
        "taskfi-admin",
        "is-protocol-paused",
        [],
        wallet1
      );
      expect(result).toBeBool(false);

      // After pausing
      simnet.callPublicFn("taskfi-admin", "pause-protocol", [], deployer);
      
      result = simnet.callReadOnlyFn(
        "taskfi-admin",
        "is-protocol-paused",
        [],
        wallet1
      );
      expect(result).toBeBool(true);
    });

    it("should get protocol parameters", () => {
      // Get minimum stake amount
      let result = simnet.callReadOnlyFn(
        "taskfi-admin",
        "get-min-stake-amount",
        [],
        wallet1
      );
      expect(result).toBeUint(2000000);

      // Get protocol fee rate
      result = simnet.callReadOnlyFn(
        "taskfi-admin",
        "get-protocol-fee-rate",
        [],
        wallet1
      );
      expect(result).toBeUint(250); // Default 2.5%
    });

    it("should get protocol statistics", () => {
      // Update some stats first
      simnet.callPublicFn(
        "taskfi-admin",
        "update-stats",
        [Cl.stringAscii("tasks-created"), Cl.uint(10)],
        deployer
      );

      const { result } = simnet.callReadOnlyFn(
        "taskfi-admin",
        "get-total-tasks-created",
        [],
        wallet1
      );

      expect(result).toBeUint(10);
    });

    it("should get emergency contacts", () => {
      // Add emergency contact
      simnet.callPublicFn(
        "taskfi-admin",
        "add-emergency-contact",
        [Cl.principal(wallet1)],
        deployer
      );

      const { result } = simnet.callReadOnlyFn(
        "taskfi-admin",
        "get-emergency-contacts",
        [],
        wallet1
      );

      expect(result).toBeList([Cl.principal(wallet1)]);
    });
  });
});
