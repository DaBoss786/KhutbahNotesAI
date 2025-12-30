const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const {
  isEntitlementActive,
  isRevenueCatEventStale,
  resolveMonthlyMinutesUsed,
} = require("../lib/revenuecat.js");

test("resolveMonthlyMinutesUsed returns 0 for new users", () => {
  const result = resolveMonthlyMinutesUsed(null, {
    plan: "premium",
    periodStart: new Date("2024-02-01T00:00:00Z"),
    renewsAt: new Date("2024-03-01T00:00:00Z"),
  });
  assert.equal(result, 0);
});

test("isRevenueCatEventStale returns true for older events", () => {
  const existingUpdatedAt = admin.firestore.Timestamp.fromDate(
    new Date("2024-02-10T00:00:00Z")
  );
  const incomingUpdatedAt = new Date("2024-02-01T00:00:00Z");

  assert.equal(
    isRevenueCatEventStale(existingUpdatedAt, incomingUpdatedAt),
    true
  );
});

test("isEntitlementActive returns false for expiration with no expiry", () => {
  const active = isEntitlementActive("EXPIRATION", null, new Date());
  assert.equal(active, false);
});

test("expiration event keeps usage unchanged", () => {
  const periodStart = new Date("2024-02-01T00:00:00Z");
  const renewsAt = new Date("2024-03-01T00:00:00Z");
  const existing = {
    plan: "premium",
    periodStart: admin.firestore.Timestamp.fromDate(periodStart),
    renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
    monthlyMinutesUsed: 180,
  };
  const active = isEntitlementActive("EXPIRATION", null, new Date());
  const plan = active ? "premium" : "free";

  const result = resolveMonthlyMinutesUsed(existing, {
    plan,
    periodStart,
    renewsAt,
  });
  assert.equal(result, 180);
});

test("cancellation with active entitlement preserves usage", () => {
  const periodStart = new Date("2024-02-01T00:00:00Z");
  const renewsAt = new Date("2024-03-01T00:00:00Z");
  const existing = {
    plan: "premium",
    periodStart: admin.firestore.Timestamp.fromDate(periodStart),
    renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
    monthlyMinutesUsed: 210,
  };
  const active = isEntitlementActive(
    "CANCELLATION",
    new Date("2024-02-20T00:00:00Z"),
    new Date("2024-02-10T00:00:00Z")
  );
  const plan = active ? "premium" : "free";

  const result = resolveMonthlyMinutesUsed(existing, {
    plan,
    periodStart,
    renewsAt,
  });
  assert.equal(result, 210);
});

test("resolveMonthlyMinutesUsed keeps usage within same premium period", () => {
  const periodStart = new Date("2024-02-01T00:00:00Z");
  const renewsAt = new Date("2024-03-01T00:00:00Z");
  const existing = {
    plan: "premium",
    periodStart: admin.firestore.Timestamp.fromDate(periodStart),
    renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
    monthlyMinutesUsed: 120,
  };

  const result = resolveMonthlyMinutesUsed(existing, {
    plan: "premium",
    periodStart,
    renewsAt,
  });
  assert.equal(result, 120);
});

test("renewal with same period start does not reset usage", () => {
  const periodStart = new Date("2024-02-01T00:00:00Z");
  const renewsAt = new Date("2024-03-01T00:00:00Z");
  const existing = {
    plan: "premium",
    periodStart: admin.firestore.Timestamp.fromDate(periodStart),
    renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
    monthlyMinutesUsed: 95,
  };

  const result = resolveMonthlyMinutesUsed(existing, {
    plan: "premium",
    periodStart,
    renewsAt,
  });
  assert.equal(result, 95);
});

test("resolveMonthlyMinutesUsed resets when period advances", () => {
  const existing = {
    plan: "premium",
    periodStart: admin.firestore.Timestamp.fromDate(
      new Date("2024-02-01T00:00:00Z")
    ),
    renewsAt: admin.firestore.Timestamp.fromDate(
      new Date("2024-03-01T00:00:00Z")
    ),
    monthlyMinutesUsed: 320,
  };

  const result = resolveMonthlyMinutesUsed(existing, {
    plan: "premium",
    periodStart: new Date("2024-03-01T00:00:00Z"),
    renewsAt: new Date("2024-04-01T00:00:00Z"),
  });
  assert.equal(result, 0);
});

test("resolveMonthlyMinutesUsed resets when premium starts from free", () => {
  const existing = {
    plan: "free",
    periodStart: admin.firestore.Timestamp.fromDate(
      new Date("2024-02-01T00:00:00Z")
    ),
    renewsAt: admin.firestore.Timestamp.fromDate(
      new Date("2024-03-01T00:00:00Z")
    ),
    monthlyMinutesUsed: 40,
  };

  const result = resolveMonthlyMinutesUsed(existing, {
    plan: "premium",
    periodStart: new Date("2024-02-01T00:00:00Z"),
    renewsAt: new Date("2024-03-01T00:00:00Z"),
  });
  assert.equal(result, 0);
});

test("resolveMonthlyMinutesUsed preserves usage when moving to free", () => {
  const existing = {
    plan: "premium",
    periodStart: admin.firestore.Timestamp.fromDate(
      new Date("2024-02-01T00:00:00Z")
    ),
    renewsAt: admin.firestore.Timestamp.fromDate(
      new Date("2024-03-01T00:00:00Z")
    ),
    monthlyMinutesUsed: 200,
  };

  const result = resolveMonthlyMinutesUsed(existing, {
    plan: "free",
    periodStart: new Date("2024-02-01T00:00:00Z"),
    renewsAt: new Date("2024-03-01T00:00:00Z"),
  });
  assert.equal(result, 200);
});
