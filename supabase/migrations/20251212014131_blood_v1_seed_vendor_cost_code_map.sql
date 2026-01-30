
-- blood_v1: Seed deterministic vendor↔cost code mappings (Layer 1)
-- Based on trade → cost code division mapping

INSERT INTO vendor_cost_code_map (contact_id, cost_code_id, mapping_type, confidence) VALUES
-- Malcolm Hetzer (Electrical) → 5030 primary, 7020 secondary
('a0f3a2a5-ded8-4654-9066-55968bbc61c5', '33f03f4e-cb1a-4918-b113-2bb6d8420b1a', 'primary', 1.00),
('a0f3a2a5-ded8-4654-9066-55968bbc61c5', '89cd4bd2-1678-433c-b788-fcf5f7f26d11', 'secondary', 1.00),

-- Alexander Nasr (Flooring) → 6050 primary, 6080 secondary
('b1926fac-2016-474e-b225-5ff64a9ebddd', '2a31ddcc-a1db-4fca-a5c7-adcafa09ce58', 'primary', 1.00),
('b1926fac-2016-474e-b225-5ff64a9ebddd', 'd947fd40-7ae0-4157-8005-b05192028dca', 'secondary', 1.00),

-- Flynt Treadaway (Lumber) → 3030 primary, 4020, 4030 secondary
('35ab3df2-543f-4cec-b24e-a1009254bd69', 'c3690bea-2f75-4af6-89a2-1af2a8998933', 'primary', 1.00),
('35ab3df2-543f-4cec-b24e-a1009254bd69', '7dec56f2-2b75-442d-b0a9-bc5e07fdd062', 'secondary', 1.00),
('35ab3df2-543f-4cec-b24e-a1009254bd69', '42190bdf-5d68-4a02-944a-841fd1116faf', 'secondary', 1.00),

-- Hector Ordonez (Lumber) → 3030 primary, 4020, 4030 secondary
('1edea179-ef25-4a12-a95c-34ce002269c5', 'c3690bea-2f75-4af6-89a2-1af2a8998933', 'primary', 1.00),
('1edea179-ef25-4a12-a95c-34ce002269c5', '7dec56f2-2b75-442d-b0a9-bc5e07fdd062', 'secondary', 1.00),
('1edea179-ef25-4a12-a95c-34ce002269c5', '42190bdf-5d68-4a02-944a-841fd1116faf', 'secondary', 1.00),

-- Joe Laboon III (Appliances) → 7040 primary
('3804a65f-24d1-4a89-80e0-7e34e99c48d6', 'f6467c46-2622-4429-bf92-eb998d06f61c', 'primary', 1.00),

-- Austin Atkinson (HVAC) → 5010 primary, 7030 secondary
('a7ae67a6-7d5a-4dee-a4b3-f017abc95648', '8a168ddf-8dbc-4b45-97d8-47dbd8c1e802', 'primary', 1.00),
('a7ae67a6-7d5a-4dee-a4b3-f017abc95648', 'aac4483e-e8c4-40e4-b150-50655f6a4ef3', 'secondary', 1.00),

-- Chris Gaugler (Roofing) → 4010 primary
('8feb96db-af32-46c8-b8b5-9f445d98b82f', '036ff02b-4c3c-4bbb-bde0-fb9d3e55dc93', 'primary', 1.00),

-- Randy Bryan (Plumbing) → 2080, 5020, 7010
('c78244ce-6f67-4cc2-9b8c-d052a43af2e3', '3ef60be8-f153-46e6-b084-57210bbbf87f', 'primary', 1.00),
('c78244ce-6f67-4cc2-9b8c-d052a43af2e3', '540e6b24-17ab-4ef2-85f7-55e4b7f7056a', 'primary', 1.00),
('c78244ce-6f67-4cc2-9b8c-d052a43af2e3', '88192ed4-5888-44f3-8c6f-b8a665989d30', 'secondary', 1.00),

-- Anthony Cottrell (Cabinetry) → 6040 primary
('a492a845-5dae-458c-bb59-9f11edb26e45', '401c57c4-2c59-4f05-8f7f-6ff2f493f2dd', 'primary', 1.00),

-- Calvin Taylor (Insulation) → 5050 primary
('f78c621f-a0b9-40cb-9db6-7a161f9f6199', '6390d90d-73b3-4e2b-9782-d405a10cb559', 'primary', 1.00),

-- Zach Givens (Landscape) → 8050 primary, 8040 secondary
('4b12395d-af47-4565-aa4c-1e49c0ce6add', 'f983734e-b13c-4aea-a7e8-18cfcd7adae6', 'primary', 1.00),
('4b12395d-af47-4565-aa4c-1e49c0ce6add', '92a74c0c-fcfc-4bdd-a873-4974298c22ab', 'secondary', 1.00),

-- Taylor Shannon (Sitework) → 2010, 2020, 2030 primary
('98aa8a91-0351-4a71-9a6d-e04a55af73c6', '6a19e01f-8cf8-4417-924d-9f5f1b9c1ccd', 'primary', 1.00),
('98aa8a91-0351-4a71-9a6d-e04a55af73c6', 'e9895904-e094-4cee-8480-2fd57be2341a', 'primary', 1.00),
('98aa8a91-0351-4a71-9a6d-e04a55af73c6', '17fcaa73-23aa-4c89-993a-ad7a9ea78748', 'primary', 1.00),

-- Luis Juarez (Masonry) → 4060 primary
('07389e46-eaa4-4f1f-b636-44d8082268bc', '25e44d5b-11cf-4d81-a974-ed248eaf782c', 'primary', 1.00),

-- Jose Araujo (Painting) → 6070 primary
('8c73bbb4-4f52-4dd3-8756-e1ef29dda603', '0d155d86-4c72-409b-b18b-d184c8bacd9b', 'primary', 1.00),

-- Bill Mayne (Tile) → 6060 primary
('abf40a65-20a0-4922-818d-3511131624bf', 'a2d4ca99-6a3c-43c1-8c20-10ca7dd11997', 'primary', 1.00),

-- Josh Mobley (Flooring) → 6050 primary, 6080 secondary
('27bb21c1-a256-40d5-9d9b-80eeb5831e34', '2a31ddcc-a1db-4fca-a5c7-adcafa09ce58', 'primary', 1.00),
('27bb21c1-a256-40d5-9d9b-80eeb5831e34', 'd947fd40-7ae0-4157-8005-b05192028dca', 'secondary', 1.00),

-- Waymon Bryan (Septic) → 2040 primary
('ae13e3d9-cf55-4ee8-8cf8-a3823451f235', 'a084d67d-2c1d-477b-bcc1-12b300db35d0', 'primary', 1.00),

-- Michael Strickland (Concrete) → 2050, 3010, 8010 primary
('729b170b-c4f1-4d6a-b612-3bb95f79d254', '5efebdab-81cc-43d3-a697-494a61cb807e', 'primary', 1.00),
('729b170b-c4f1-4d6a-b612-3bb95f79d254', '37a29650-3bcc-4eba-a065-0e2f1fd81e93', 'primary', 1.00),
('729b170b-c4f1-4d6a-b612-3bb95f79d254', '37d2dcd8-f2e9-4dcb-bbe4-8faaac286c3e', 'secondary', 1.00),

-- Brian Dove (Framing) → 3040 primary, 3030 secondary
('2ddfe289-fb9a-4152-a5b7-b41685975069', '91af6fe7-730a-4406-939a-0098b5c6fc15', 'primary', 1.00),
('2ddfe289-fb9a-4152-a5b7-b41685975069', 'c3690bea-2f75-4af6-89a2-1af2a8998933', 'secondary', 1.00),

-- Tracy Postin (Siding) → 4050 primary
('61d53b10-bfef-44a3-b0b5-c5e7533189b8', 'b1488161-244f-4849-9e27-9cb7699aeadc', 'primary', 1.00);
;
