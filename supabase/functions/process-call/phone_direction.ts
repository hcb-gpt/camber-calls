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
  from_phone_norm?: unknown;
  to_phone_norm?: unknown;
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
  const fromPhone = firstNonEmpty(input.from_phone_norm, input.from_phone);
  const toPhone = firstNonEmpty(input.to_phone_norm, input.to_phone);

  const ownerPhone = firstNonEmpty(
    input.owner_phone,
    direction === "inbound" ? toPhone : undefined,
    direction === "outbound" ? fromPhone : undefined,
    fromPhone,
    toPhone,
  );

  const otherPartyPhone = firstNonEmpty(
    input.other_party_phone,
    direction === "inbound" ? fromPhone : undefined,
    direction === "outbound" ? toPhone : undefined,
    toPhone,
    fromPhone,
    input.contact_phone,
  );

  return { direction, ownerPhone, otherPartyPhone };
}
