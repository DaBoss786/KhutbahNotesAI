import * as admin from "firebase-admin";

export type ExistingBillingState = {
  plan?: string | null;
  periodStart?: admin.firestore.Timestamp | null;
  renewsAt?: admin.firestore.Timestamp | null;
  monthlyMinutesUsed?: number | null;
};

export type IncomingBillingState = {
  plan: "premium" | "free";
  periodStart: Date;
  renewsAt: Date;
};

/**
 * Convert Firestore timestamp to epoch millis.
 *
 * @param {admin.firestore.Timestamp | null | undefined} value Timestamp.
 * @return {number | null} Milliseconds since epoch, or null.
 */
function toMillis(
  value: admin.firestore.Timestamp | null | undefined
): number | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toMillis();
  }
  return null;
}

/**
 * Check if an incoming RC event is stale compared to stored update time.
 *
 * @param {unknown} existingUpdatedAt Stored rcUpdatedAt value.
 * @param {Date} incomingUpdatedAt Incoming update time.
 * @return {boolean} True if the incoming event is stale.
 */
export function isRevenueCatEventStale(
  existingUpdatedAt: unknown,
  incomingUpdatedAt: Date
): boolean {
  if (existingUpdatedAt instanceof admin.firestore.Timestamp) {
    return existingUpdatedAt.toMillis() >= incomingUpdatedAt.getTime();
  }
  return false;
}

/**
 * Determine if the entitlement is currently active.
 *
 * @param {string | null} eventType RevenueCat event type.
 * @param {Date | null} expiresAt Expiration date.
 * @param {Date} now Current time.
 * @return {boolean} True if active.
 */
export function isEntitlementActive(
  eventType: string | null,
  expiresAt: Date | null,
  now: Date
): boolean {
  if (eventType && eventType.toUpperCase() === "EXPIRATION") {
    return false;
  }

  if (expiresAt) {
    return expiresAt.getTime() > now.getTime();
  }

  return true;
}

/**
 * Decide whether to preserve or reset monthly usage for RC events.
 *
 * @param {ExistingBillingState | null} existing Current stored billing data.
 * @param {IncomingBillingState} incoming Incoming billing window and plan.
 * @return {number} Monthly minutes used to persist.
 */
export function resolveMonthlyMinutesUsed(
  existing: ExistingBillingState | null,
  incoming: IncomingBillingState
): number {
  const existingUsed =
    typeof existing?.monthlyMinutesUsed === "number" ?
      existing.monthlyMinutesUsed :
      0;

  const existingPeriodStart = toMillis(existing?.periodStart);
  const existingRenewsAt = toMillis(existing?.renewsAt);
  if (existingPeriodStart === null || existingRenewsAt === null) {
    return 0;
  }

  if (incoming.plan !== "premium") {
    return existingUsed;
  }

  const existingPlan = existing?.plan === "premium" ? "premium" : "free";
  if (existingPlan !== "premium") {
    return 0;
  }

  if (
    incoming.periodStart.getTime() > existingPeriodStart ||
    incoming.renewsAt.getTime() > existingRenewsAt
  ) {
    return 0;
  }

  return existingUsed;
}
