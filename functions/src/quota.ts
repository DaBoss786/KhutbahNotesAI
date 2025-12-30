import * as admin from "firebase-admin";

export type UserData = {
  plan?: string;
  monthlyKey?: string;
  monthlyMinutesUsed?: number;
  freeLifetimeMinutesUsed?: number;
  periodStart?: admin.firestore.Timestamp | admin.firestore.FieldValue;
  renewsAt?: admin.firestore.Timestamp | admin.firestore.FieldValue;
};

/**
 * Error to represent quota violations with a structured reason.
 */
export class QuotaError extends Error {
  reason: string;

  /**
   * @param {string} message Human-readable message.
   * @param {string} reason Machine-readable reason code.
   */
  constructor(message: string, reason: string) {
    super(message);
    this.name = "QuotaError";
    this.reason = reason;
  }
}

/**
 * Compute a YYYY-MM-DD key for a billing period anchor date.
 *
 * @param {Date} date Anchor date.
 * @return {string} Period key.
 */
export function getMonthlyKey(date: Date): string {
  return [
    date.getFullYear(),
    `${date.getMonth() + 1}`.padStart(2, "0"),
    `${date.getDate()}`.padStart(2, "0"),
  ].join("-");
}

/**
 * Add one month to a date, preserving the day when possible.
 *
 * @param {Date} date Input date.
 * @return {Date} New date one month later.
 */
export function addOneMonth(date: Date): Date {
  const next = new Date(date.getTime());
  next.setMonth(next.getMonth() + 1);
  return next;
}

/**
 * Convert a Firestore timestamp into a JS Date.
 *
 * @param {unknown} value Candidate timestamp.
 * @return {Date|null} Converted date or null.
 */
function toDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  return null;
}

/**
 * Reset the user's monthly counters when crossing the renew date.
 *
 * For premium, the cycle is anchored to periodStart/renewsAt (subscription
 * anniversary). For free, it still honors periodStart if present; otherwise it
 * starts from "now".
 *
 * @param {FirebaseFirestore.Transaction} tx Firestore transaction.
 * @param {FirebaseFirestore.DocumentReference} userRef User document ref.
 * @param {UserData} userData User snapshot data.
 * @param {Date} now Current time.
 * @return {{
 *   monthlyKey: string,
 *   monthlyMinutesUsed: number,
 *   periodStart: Date,
 *   renewsAt: Date,
 * }} Updated period info.
 */
export function resetMonthlyIfNeeded(
  tx: FirebaseFirestore.Transaction,
  userRef: FirebaseFirestore.DocumentReference,
  userData: UserData,
  now: Date = new Date()
): {
  monthlyKey: string;
  monthlyMinutesUsed: number;
  periodStart: Date;
  renewsAt: Date;
} {
  const plan = userData.plan === "premium" ? "premium" : "free";

  const snapshotMonthlyUsed =
    typeof userData.monthlyMinutesUsed === "number" ?
      userData.monthlyMinutesUsed :
      0;

  let periodStart =
    toDate(userData.periodStart) ??
    (plan === "premium" ? now : now);

  let renewsAt =
    toDate(userData.renewsAt) ?? addOneMonth(periodStart);

  let monthlyMinutesUsed = snapshotMonthlyUsed;

  // Advance periodStart/renewsAt if we're past the current renew window.
  while (now >= renewsAt) {
    periodStart = renewsAt;
    renewsAt = addOneMonth(periodStart);
    monthlyMinutesUsed = 0;
  }

  const monthlyKey = getMonthlyKey(periodStart);

  const needsUpdate =
    monthlyKey !== userData.monthlyKey ||
    monthlyMinutesUsed !== snapshotMonthlyUsed ||
    !toDate(userData.periodStart) ||
    !toDate(userData.renewsAt);

  if (needsUpdate) {
    tx.update(userRef, {
      monthlyKey,
      monthlyMinutesUsed,
      periodStart: admin.firestore.Timestamp.fromDate(periodStart),
      renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
    });
  }

  return {monthlyKey, monthlyMinutesUsed, periodStart, renewsAt};
}

/**
 * Enforce per-recording and plan quotas, then debit within the transaction.
 *
 * @param {FirebaseFirestore.Transaction} tx Firestore transaction.
 * @param {FirebaseFirestore.DocumentReference} userRef User document ref.
 * @param {UserData} userData User snapshot data.
 * @param {number} durationMinutes Rounded minutes of the recording.
 * @param {Date} now Current time.
 * @return {number} Charged minutes (equals durationMinutes if successful).
 */
export function checkAndDebitQuota(
  tx: FirebaseFirestore.Transaction,
  userRef: FirebaseFirestore.DocumentReference,
  userData: UserData,
  durationMinutes: number,
  now: Date = new Date()
): number {
  if (durationMinutes > 70) {
    throw new QuotaError(
      "Recording exceeds 70-minute per-file cap.",
      "per_file_cap"
    );
  }

  const plan = userData.plan === "premium" ? "premium" : "free";

  const {
    monthlyMinutesUsed,
    monthlyKey,
    periodStart,
    renewsAt,
  } = resetMonthlyIfNeeded(tx, userRef, userData, now);

  if (plan === "free") {
    const lifetimeUsed =
      typeof userData.freeLifetimeMinutesUsed === "number" ?
        userData.freeLifetimeMinutesUsed :
        0;
    const newLifetimeTotal = lifetimeUsed + durationMinutes;

    if (newLifetimeTotal > 60) {
      throw new QuotaError(
        "Free plan lifetime minutes exceeded.",
        "free_lifetime_exceeded"
      );
    }

    const newMonthlyTotal = monthlyMinutesUsed + durationMinutes;

    tx.update(userRef, {
      plan,
      freeLifetimeMinutesUsed: newLifetimeTotal,
      monthlyMinutesUsed: newMonthlyTotal,
      monthlyKey,
      periodStart: admin.firestore.Timestamp.fromDate(periodStart),
      renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
    });

    return durationMinutes;
  }

  // Premium path
  const newMonthlyTotal = monthlyMinutesUsed + durationMinutes;
  if (newMonthlyTotal > 500) {
    throw new QuotaError(
      "Premium monthly minutes exceeded.",
      "premium_monthly_exceeded"
    );
  }

  tx.update(userRef, {
    plan,
    monthlyMinutesUsed: newMonthlyTotal,
    monthlyKey,
    periodStart: admin.firestore.Timestamp.fromDate(periodStart),
    renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
  });

  return durationMinutes;
}
