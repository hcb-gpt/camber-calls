import { assertEquals } from "https://deno.land/std@0.218.0/assert/mod.ts";
import { normalizeDirection, resolveCallPartyPhones } from "./phone_direction.ts";

Deno.test("normalizeDirection maps common inbound/outbound aliases", () => {
  assertEquals(normalizeDirection("inbound"), "inbound");
  assertEquals(normalizeDirection("incoming"), "inbound");
  assertEquals(normalizeDirection("outbound"), "outbound");
  assertEquals(normalizeDirection("outgoing"), "outbound");
  assertEquals(normalizeDirection("weird"), "unknown");
});

Deno.test("resolveCallPartyPhones inbound uses to=owner and from=other_party", () => {
  const result = resolveCallPartyPhones({
    direction: "inbound",
    from_phone: "+15551230001",
    to_phone: "+15551239999",
  });

  assertEquals(result.direction, "inbound");
  assertEquals(result.ownerPhone, "+15551239999");
  assertEquals(result.otherPartyPhone, "+15551230001");
});

Deno.test("resolveCallPartyPhones inbound uses normalized phones when present", () => {
  const result = resolveCallPartyPhones({
    direction: "inbound",
    from_phone_norm: "+15551230001",
    to_phone_norm: "+15551239999",
    // Raw fields can be absent in some webhook payloads.
    from_phone: null,
    to_phone: null,
  });

  assertEquals(result.direction, "inbound");
  assertEquals(result.ownerPhone, "+15551239999");
  assertEquals(result.otherPartyPhone, "+15551230001");
});

Deno.test("resolveCallPartyPhones outbound uses from=owner and to=other_party", () => {
  const result = resolveCallPartyPhones({
    direction: "outbound",
    from_phone: "+15551239999",
    to_phone: "+15551230001",
  });

  assertEquals(result.direction, "outbound");
  assertEquals(result.ownerPhone, "+15551239999");
  assertEquals(result.otherPartyPhone, "+15551230001");
});

Deno.test("resolveCallPartyPhones respects explicit owner/other_party fields", () => {
  const result = resolveCallPartyPhones({
    direction: "inbound",
    from_phone: "+15551230001",
    to_phone: "+15551239999",
    owner_phone: "+15550000001",
    other_party_phone: "+15550000002",
  });

  assertEquals(result.ownerPhone, "+15550000001");
  assertEquals(result.otherPartyPhone, "+15550000002");
});

Deno.test("resolveCallPartyPhones prefers normalized values over raw values", () => {
  const result = resolveCallPartyPhones({
    direction: "inbound",
    from_phone_norm: "+15550000001",
    to_phone_norm: "+15550000002",
    from_phone: "+16660000001",
    to_phone: "+16660000002",
  });

  assertEquals(result.ownerPhone, "+15550000002");
  assertEquals(result.otherPartyPhone, "+15550000001");
});

Deno.test("resolveCallPartyPhones unknown direction keeps historical fallback", () => {
  const result = resolveCallPartyPhones({
    direction: "sideways",
    from_phone: "+15551239999",
    to_phone: "+15551230001",
  });

  assertEquals(result.direction, "unknown");
  assertEquals(result.ownerPhone, "+15551239999");
  assertEquals(result.otherPartyPhone, "+15551230001");
});

Deno.test("resolveCallPartyPhones falls back to contact_phone only when needed", () => {
  const result = resolveCallPartyPhones({
    direction: "inbound",
    contact_phone: "+15554443333",
  });

  assertEquals(result.ownerPhone, null);
  assertEquals(result.otherPartyPhone, "+15554443333");
});

Deno.test("resolveCallPartyPhones inbound does not swap parties when only from_phone is present", () => {
  const result = resolveCallPartyPhones({
    direction: "inbound",
    from_phone: "+15551230001",
  });

  assertEquals(result.ownerPhone, null);
  assertEquals(result.otherPartyPhone, "+15551230001");
});

Deno.test("resolveCallPartyPhones outbound does not swap parties when only to_phone is present", () => {
  const result = resolveCallPartyPhones({
    direction: "outbound",
    to_phone: "+15551230001",
  });

  assertEquals(result.ownerPhone, null);
  assertEquals(result.otherPartyPhone, "+15551230001");
});

Deno.test("resolveCallPartyPhones 20-row mixed direction matrix", () => {
  const owner = "+14155550100";
  for (let i = 1; i <= 20; i++) {
    const customer = `+1206555${String(i).padStart(4, "0")}`;
    const inbound = i % 2 === 1;
    const result = resolveCallPartyPhones({
      direction: inbound ? "inbound" : "outbound",
      from_phone: inbound ? customer : owner,
      to_phone: inbound ? owner : customer,
    });

    assertEquals(result.ownerPhone, owner, `owner mismatch at row ${i}`);
    assertEquals(result.otherPartyPhone, customer, `other party mismatch at row ${i}`);
  }
});
