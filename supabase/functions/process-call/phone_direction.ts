export type CallDirection = "inbound" | "outbound" | "unknown";

function firstNonEmpty(...values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value !== "string") continue;
    const trimmed = value.trim();
    if (trimmed.length > 0) return trimmed;
  }
  return null;
}

export function normalizeDirection(direction: unknown): CallDirection {
  const value = String(direction || "").trim().toLowerCase();
  if (value === "inbound" || value === "incoming" || value === "in") {
    return "inbound";
  }
  if (value === "outbound" || value === "outgoing" || value === "out") {
    return "outbound";
  }
  return "unknown";
}

type ResolveCallPartyPhonesInput = {
  direction?: unknown;
  from_phone?: unknown;
  to_phone?: unknown;
  owner_phone?: unknown;
  other_party_phone?: unknown;
  contact_phone?: unknown;
};

type ResolveCallPartyPhonesResult = {
  direction: CallDirection;
  ownerPhone: string | null;
  otherPartyPhone: string | null;
};

export function resolveCallPartyPhones(
  input: ResolveCallPartyPhonesInput,
): ResolveCallPartyPhonesResult {
  const direction = normalizeDirection(input.direction);
  const fromPhone = firstNonEmpty(input.from_phone);
  const toPhone = firstNonEmpty(input.to_phone);

  let ownerPhone: string | null = null;
  let otherPartyPhone: string | null = null;

  if (direction === "inbound") {
    // Only trust the direction-aligned mapping to avoid swapping parties when only one side is present.
    ownerPhone = firstNonEmpty(input.owner_phone, toPhone);
    otherPartyPhone = firstNonEmpty(
      input.other_party_phone,
      fromPhone,
      input.contact_phone,
    );
  } else if (direction === "outbound") {
    ownerPhone = firstNonEmpty(input.owner_phone, fromPhone);
    otherPartyPhone = firstNonEmpty(
      input.other_party_phone,
      toPhone,
      input.contact_phone,
    );
  } else {
    // Unknown direction: retain historical fallback behavior (best-effort).
    ownerPhone = firstNonEmpty(input.owner_phone, fromPhone, toPhone);
    otherPartyPhone = firstNonEmpty(
      input.other_party_phone,
      toPhone,
      fromPhone,
      input.contact_phone,
    );
  }

  return { direction, ownerPhone, otherPartyPhone };
}
