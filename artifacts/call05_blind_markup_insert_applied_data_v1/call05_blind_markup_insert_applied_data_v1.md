# call05_blind_markup_insert_applied_data_v1

Generated UTC: 2026-02-08T22:07:40Z

## Authoritative Payload Validation (Blind Protocol)

Source payload (as-received):
- interaction_id: `c11_06E0P6KYB5V7S5VYQA8ZTRQM4W`
- canonical interaction_id: `cll_06E0P6KYB5V7S5VYQA8ZTRQM4W`
- span token 1: `0e755a04-8235-45ef-a6a2-11f3aa22ece8`
- span token 2 (confusable): `d1f8a85c-c047-422c-9951-09f4564aба3d`

Normalization outcomes:
- `c11_` -> `cll_` (digit `1` normalized to letter `l` in prefix)
- span token 2 normalized by confusable replacement:
  - Cyrillic `б` -> `6`
  - Cyrillic `а` -> `a`
  - normalized token: `d1f8a85c-c047-422c-9951-09f4564a6a3d`

Validation against operational rows:
- canonical interaction exists: `true`
- span `0e755a04-8235-45ef-a6a2-11f3aa22ece8` exists under canonical interaction: `true`
- span `d1f8a85c-c047-422c-9951-09f4564a6a3d` exists under canonical interaction: `true`

## Applied Outcomes

1. Canonical correction applied and accepted:
- receipt: `call05_canonical_correction_applied_v1`
- interaction canonical project now: `47cb7720-9495-4187-8220-a8100c3b67aa` (Moss Residence)

2. Packet CALL05 ID consistency revised:
- old packet CALL05 id: `cll_06E11WDHM1VR71PS8KA4C45M9C`
- revised packet CALL05 id: `cll_06E0P6KYB5V7S5VYQA8ZTRQM4W`
- receipt: `packet_call05_id_consistency_verified_v1`

Blind protocol note:
- No pre-filled final attribution labels were introduced in markup packet fields.
