const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const {
  checkAndDebitQuota,
  getMonthlyKey,
  resetMonthlyIfNeeded,
  QuotaError,
} = require("../lib/quota.js");

function createTx() {
  const updates = [];
  return {
    updates,
    update(ref, data) {
      updates.push({ref, data});
    },
  };
}

test("checkAndDebitQuota rejects recordings over 70 minutes", () => {
  const tx = createTx();
  const userRef = {path: "users/u1"};
  const userData = {plan: "free"};

  assert.throws(
    () => checkAndDebitQuota(tx, userRef, userData, 71),
    (err) => err instanceof QuotaError && err.reason === "per_file_cap"
  );
  assert.equal(tx.updates.length, 0);
});

test("checkAndDebitQuota rejects free plan lifetime cap", () => {
  const tx = createTx();
  const userRef = {path: "users/u1"};
  const periodStart = new Date("2024-02-01T00:00:00Z");
  const renewsAt = new Date("2024-03-01T00:00:00Z");
  const userData = {
    plan: "free",
    freeLifetimeMinutesUsed: 55,
    monthlyKey: getMonthlyKey(periodStart),
    periodStart: admin.firestore.Timestamp.fromDate(periodStart),
    renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
  };
  const now = new Date("2024-02-10T12:00:00Z");

  assert.throws(
    () => checkAndDebitQuota(tx, userRef, userData, 6, now),
    (err) =>
      err instanceof QuotaError &&
      err.reason === "free_lifetime_exceeded"
  );
  assert.equal(tx.updates.length, 0);
});

test("checkAndDebitQuota updates counters for free plan", () => {
  const tx = createTx();
  const userRef = {path: "users/u1"};
  const periodStart = new Date("2024-02-01T00:00:00Z");
  const renewsAt = new Date("2024-03-01T00:00:00Z");
  const userData = {
    plan: "free",
    freeLifetimeMinutesUsed: 10,
    monthlyMinutesUsed: 5,
    monthlyKey: getMonthlyKey(periodStart),
    periodStart: admin.firestore.Timestamp.fromDate(periodStart),
    renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
  };

  const charged = checkAndDebitQuota(
    tx,
    userRef,
    userData,
    7,
    new Date("2024-02-10T12:00:00Z")
  );

  assert.equal(charged, 7);
  assert.equal(tx.updates.length, 1);
  const update = tx.updates[0].data;
  assert.equal(update.freeLifetimeMinutesUsed, 17);
  assert.equal(update.monthlyMinutesUsed, 12);
  assert.equal(update.monthlyKey, getMonthlyKey(periodStart));
  assert.ok(update.periodStart instanceof admin.firestore.Timestamp);
  assert.ok(update.renewsAt instanceof admin.firestore.Timestamp);
});

test("checkAndDebitQuota enforces premium monthly cap", () => {
  const tx = createTx();
  const userRef = {path: "users/u1"};
  const periodStart = new Date("2024-02-01T00:00:00Z");
  const renewsAt = new Date("2024-03-01T00:00:00Z");
  const userData = {
    plan: "premium",
    monthlyMinutesUsed: 499,
    monthlyKey: getMonthlyKey(periodStart),
    periodStart: admin.firestore.Timestamp.fromDate(periodStart),
    renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
  };

  assert.throws(
    () =>
      checkAndDebitQuota(
        tx,
        userRef,
        userData,
        2,
        new Date("2024-02-10T12:00:00Z")
      ),
    (err) =>
      err instanceof QuotaError &&
      err.reason === "premium_monthly_exceeded"
  );
  assert.equal(tx.updates.length, 0);
});

test("resetMonthlyIfNeeded rolls period forward and clears usage", () => {
  const tx = createTx();
  const userRef = {path: "users/u1"};
  const periodStart = new Date("2024-02-01T00:00:00Z");
  const renewsAt = new Date("2024-03-01T00:00:00Z");
  const now = new Date("2024-04-05T00:00:00Z");
  const userData = {
    plan: "free",
    monthlyMinutesUsed: 22,
    monthlyKey: getMonthlyKey(periodStart),
    periodStart: admin.firestore.Timestamp.fromDate(periodStart),
    renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
  };

  const result = resetMonthlyIfNeeded(tx, userRef, userData, now);

  assert.equal(result.monthlyMinutesUsed, 0);
  assert.equal(result.monthlyKey, getMonthlyKey(result.periodStart));
  assert.equal(tx.updates.length, 1);
  const update = tx.updates[0].data;
  assert.equal(update.monthlyMinutesUsed, 0);
});
