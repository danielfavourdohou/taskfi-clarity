import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("TaskFi Core Contract Tests", () => {
  beforeEach(() => {
    // Reset simnet state before each test
    simnet.setEpoch("3.0");
  });

  describe("Task Creation", () => {
    it("should create a new task successfully", () => {
      const title = "Test Task";
      const description = "This is a test task description";
      const reward = 1000000; // 1 STX
      const deadline = simnet.blockHeight + 100;
      const minReputation = 50;

      const { result } = simnet.callPublicFn(
        "taskfi-core",
        "create-task",
        [
          Cl.stringAscii(title),
          Cl.stringAscii(description),
          Cl.uint(reward),
          Cl.uint(deadline),
          Cl.uint(minReputation),
        ],
        wallet1
      );

      expect(result).toBeOk(Cl.uint(1));
    });

    it("should fail to create task with invalid deadline", () => {
      const title = "Test Task";
      const description = "This is a test task description";
      const reward = 1000000;
      const deadline = simnet.blockHeight - 1; // Past deadline
      const minReputation = 50;

      const { result } = simnet.callPublicFn(
        "taskfi-core",
        "create-task",
        [
          Cl.stringAscii(title),
          Cl.stringAscii(description),
          Cl.uint(reward),
          Cl.uint(deadline),
          Cl.uint(minReputation),
        ],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(410)); // ERR-DEADLINE-PASSED
    });

    it("should fail to create task with zero reward", () => {
      const title = "Test Task";
      const description = "This is a test task description";
      const reward = 0;
      const deadline = simnet.blockHeight + 100;
      const minReputation = 50;

      const { result } = simnet.callPublicFn(
        "taskfi-core",
        "create-task",
        [
          Cl.stringAscii(title),
          Cl.stringAscii(description),
          Cl.uint(reward),
          Cl.uint(deadline),
          Cl.uint(minReputation),
        ],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(400)); // ERR-INVALID-INPUT
    });
  });

  describe("Task Acceptance", () => {
    beforeEach(() => {
      // Create a task for acceptance tests
      simnet.callPublicFn(
        "taskfi-core",
        "create-task",
        [
          Cl.stringAscii("Test Task"),
          Cl.stringAscii("Test Description"),
          Cl.uint(1000000),
          Cl.uint(simnet.blockHeight + 100),
          Cl.uint(50),
        ],
        wallet1
      );
    });

    it("should accept a task successfully", () => {
      const { result } = simnet.callPublicFn(
        "taskfi-core",
        "accept-task",
        [Cl.uint(1)],
        wallet2
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to accept non-existent task", () => {
      const { result } = simnet.callPublicFn(
        "taskfi-core",
        "accept-task",
        [Cl.uint(999)],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(404)); // ERR-NOT-FOUND
    });

    it("should fail to accept own task", () => {
      const { result } = simnet.callPublicFn(
        "taskfi-core",
        "accept-task",
        [Cl.uint(1)],
        wallet1 // Same wallet that created the task
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR-UNAUTHORIZED
    });
  });

  describe("Task Delivery", () => {
    beforeEach(() => {
      // Create and accept a task
      simnet.callPublicFn(
        "taskfi-core",
        "create-task",
        [
          Cl.stringAscii("Test Task"),
          Cl.stringAscii("Test Description"),
          Cl.uint(1000000),
          Cl.uint(simnet.blockHeight + 100),
          Cl.uint(50),
        ],
        wallet1
      );

      simnet.callPublicFn("taskfi-core", "accept-task", [Cl.uint(1)], wallet2);
    });

    it("should submit delivery successfully", () => {
      const deliveryCid = "QmTest123456789";

      const { result } = simnet.callPublicFn(
        "taskfi-core",
        "submit-delivery",
        [Cl.uint(1), Cl.bufferFromAscii(deliveryCid)],
        wallet2
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to submit delivery for unaccepted task", () => {
      // Create another task but don't accept it
      simnet.callPublicFn(
        "taskfi-core",
        "create-task",
        [
          Cl.stringAscii("Another Task"),
          Cl.stringAscii("Another Description"),
          Cl.uint(1000000),
          Cl.uint(simnet.blockHeight + 100),
          Cl.uint(50),
        ],
        wallet1
      );

      const deliveryCid = "QmTest123456789";

      const { result } = simnet.callPublicFn(
        "taskfi-core",
        "submit-delivery",
        [Cl.uint(2), Cl.bufferFromAscii(deliveryCid)],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(412)); // ERR-TASK-NOT-ACCEPTED
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      // Create a task for read tests
      simnet.callPublicFn(
        "taskfi-core",
        "create-task",
        [
          Cl.stringAscii("Test Task"),
          Cl.stringAscii("Test Description"),
          Cl.uint(1000000),
          Cl.uint(simnet.blockHeight + 100),
          Cl.uint(50),
        ],
        wallet1
      );
    });

    it("should get task details", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-core",
        "get-task",
        [Cl.uint(1)],
        wallet1
      );

      expect(result).toBeSome();
    });

    it("should return none for non-existent task", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-core",
        "get-task",
        [Cl.uint(999)],
        wallet1
      );

      expect(result).toBeNone();
    });

    it("should get task counter", () => {
      const { result } = simnet.callReadOnlyFn(
        "taskfi-core",
        "get-task-counter",
        [],
        wallet1
      );

      expect(result).toBeUint(1);
    });
  });
});
