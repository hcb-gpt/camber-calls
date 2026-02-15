/**
 * Normalize phone input for contact lookup.
 * Rule: digits-only, and if longer than 10 digits keep the last 10.
 */
export function normalizePhoneForLookup(
  phone: string | null | undefined,
): string | null {
  const digits = (phone ?? "").replace(/\D/g, "");
  if (!digits) return null;
  if (digits.length > 10) return digits.slice(-10);
  return digits;
}
