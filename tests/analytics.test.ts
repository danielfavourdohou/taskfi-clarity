import { describe, expect, it, beforeEach } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("Analytics Contract Tests", () => {
  beforeEach(() => {
    simnet.deployContract("analytics", "contracts/analytics.clar", null, deployer);
  });

  describe("Contract Initialization", () => {
    it("should initialize with zero metrics", () => {
      const { result } = simnet.callReadOnlyFn("analytics", "get-global-metrics", [], deployer);
      expect(result).toBeOk({
        "total-bookings": 0n,
        "total-users": 0n,
        "total-credits-issued": 0n,
        "total-hours-worked": 0n,
        "total-disputes": 0n,
        "platform-fee-collected": 0n
      });
    });

    it("should have correct contract owner", () => {
      const { result } = simnet.callReadOnlyFn("analytics", "get-contract-owner", [], deployer);
      expect(result).toBePrincipal(deployer);
    });
  });

  describe("Booking Analytics", () => {
    it("should record booking creation", () => {
      const { result } = simnet.callPublicFn(
        "analytics",
        "record-booking-created",
        [types.principal(wallet1), types.principal(wallet2), types.uint(100)],
        deployer
      );
      expect(result).toBeOk(true);

      // Check updated metrics
      const metrics = simnet.callReadOnlyFn("analytics", "get-global-metrics", [], deployer);
      expect(metrics.result).toBeOk({
        "total-bookings": 1n,
        "total-users": 0n,
        "total-credits-issued": 0n,
        "total-hours-worked": 0n,
        "total-disputes": 0n,
        "platform-fee-collected": 0n
      });
    });

    it("should record booking completion", () => {
      // First create a booking
      simnet.callPublicFn(
        "analytics",
        "record-booking-created",
        [types.principal(wallet1), types.principal(wallet2), types.uint(100)],
        deployer
      );

      // Then complete it
      const { result } = simnet.callPublicFn(
        "analytics",
        "record-booking-completed",
        [types.uint(1), types.uint(8), types.uint(10)],
        deployer
      );
      expect(result).toBeOk(true);

      // Check updated metrics
      const metrics = simnet.callReadOnlyFn("analytics", "get-global-metrics", [], deployer);
      expect(metrics.result).toBeOk({
        "total-bookings": 1n,
        "total-users": 0n,
        "total-credits-issued": 0n,
        "total-hours-worked": 8n,
        "total-disputes": 0n,
        "platform-fee-collected": 10n
      });
    });

    it("should only allow authorized users to record metrics", () => {
      const { result } = simnet.callPublicFn(
        "analytics",
        "record-booking-created",
        [types.principal(wallet1), types.principal(wallet2), types.uint(100)],
        wallet1
      );
      expect(result).toBeErr(700n); // ERR_UNAUTHORIZED
    });
  });

  describe("User Analytics", () => {
    it("should record user registration", () => {
      const { result } = simnet.callPublicFn(
        "analytics",
        "record-user-registered",
        [types.principal(wallet1)],
        deployer
      );
      expect(result).toBeOk(true);

      // Check updated metrics
      const metrics = simnet.callReadOnlyFn("analytics", "get-global-metrics", [], deployer);
      expect(metrics.result).toBeOk({
        "total-bookings": 0n,
        "total-users": 1n,
        "total-credits-issued": 0n,
        "total-hours-worked": 0n,
        "total-disputes": 0n,
        "platform-fee-collected": 0n
      });
    });

    it("should track user activity", () => {
      // Record user activity
      const { result } = simnet.callPublicFn(
        "analytics",
        "record-user-activity",
        [types.principal(wallet1), types.uint(1)], // ACTIVITY_TYPE_BOOKING_CREATED
        deployer
      );
      expect(result).toBeOk(true);

      // Check user activity
      const activity = simnet.callReadOnlyFn(
        "analytics",
        "get-user-activity",
        [types.principal(wallet1)],
        deployer
      );
      expect(activity.result).toBeSome({
        "bookings-created": 1n,
        "bookings-completed": 0n,
        "disputes-raised": 0n,
        "last-activity": types.uint(simnet.blockHeight)
      });
    });
  });

  describe("Skill Analytics", () => {
    it("should track skill popularity", () => {
      const { result } = simnet.callPublicFn(
        "analytics",
        "record-skill-booking",
        [types.uint(1)], // skill-id
        deployer
      );
      expect(result).toBeOk(true);

      // Check skill popularity
      const popularity = simnet.callReadOnlyFn(
        "analytics",
        "get-skill-popularity",
        [types.uint(1)],
        deployer
      );
      expect(popularity.result).toBeUint(1n);
    });
  });

  describe("Dispute Analytics", () => {
    it("should record dispute creation", () => {
      const { result } = simnet.callPublicFn(
        "analytics",
        "record-dispute",
        [types.uint(1), types.principal(wallet1)],
        deployer
      );
      expect(result).toBeOk(true);

      // Check updated metrics
      const metrics = simnet.callReadOnlyFn("analytics", "get-global-metrics", [], deployer);
      expect(metrics.result).toBeOk({
        "total-bookings": 0n,
        "total-users": 0n,
        "total-credits-issued": 0n,
        "total-hours-worked": 0n,
        "total-disputes": 1n,
        "platform-fee-collected": 0n
      });
    });
  });

  describe("Administrative Functions", () => {
    it("should allow owner to set new owner", () => {
      const { result } = simnet.callPublicFn(
        "analytics",
        "set-contract-owner",
        [types.principal(wallet1)],
        deployer
      );
      expect(result).toBeOk(true);

      // Verify new owner
      const owner = simnet.callReadOnlyFn("analytics", "get-contract-owner", [], deployer);
      expect(owner.result).toBePrincipal(wallet1);
    });

    it("should not allow non-owner to set new owner", () => {
      const { result } = simnet.callPublicFn(
        "analytics",
        "set-contract-owner",
        [types.principal(wallet2)],
        wallet1
      );
      expect(result).toBeErr(700n); // ERR_UNAUTHORIZED
    });
  });

  describe("Read-Only Functions", () => {
    it("should return correct total bookings", () => {
      // Create some bookings
      simnet.callPublicFn(
        "analytics",
        "record-booking-created",
        [types.principal(wallet1), types.principal(wallet2), types.uint(100)],
        deployer
      );
      simnet.callPublicFn(
        "analytics",
        "record-booking-created",
        [types.principal(wallet2), types.principal(wallet1), types.uint(200)],
        deployer
      );

      const { result } = simnet.callReadOnlyFn("analytics", "get-total-bookings", [], deployer);
      expect(result).toBeUint(2n);
    });

    it("should return correct total users", () => {
      // Register some users
      simnet.callPublicFn("analytics", "record-user-registered", [types.principal(wallet1)], deployer);
      simnet.callPublicFn("analytics", "record-user-registered", [types.principal(wallet2)], deployer);

      const { result } = simnet.callReadOnlyFn("analytics", "get-total-users", [], deployer);
      expect(result).toBeUint(2n);
    });
  });
});
