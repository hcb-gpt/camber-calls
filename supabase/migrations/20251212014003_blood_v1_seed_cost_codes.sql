
-- blood_v1: Seed cost codes from Heartwood SSoT

INSERT INTO cost_codes (cost_code_number, cost_code_name, division, phase_sequence, cost_code_keywords) VALUES
-- Division 0: Overhead
('0000', 'OVERHEAD & JOBSITE SUPPORT', 'OVERHEAD', 0, '[]'::jsonb),
('0010', 'Jobsite Support', 'OVERHEAD', 1, '["jobsite maintenance", "jobsite protection", "building systems", "bookkeeping", "accounting", "technology", "software", "subscriptions", "overhead", "office admin", "safety equipment", "PPE", "small tools", "general overhead"]'::jsonb),

-- Division 1: Pre-Construction
('1000', 'PRE-CONSTRUCTION & GENERAL REQUIREMENTS', 'PRE-CONSTRUCTION', 10, '[]'::jsonb),
('1010', 'Plans & Engineering', 'PRE-CONSTRUCTION', 11, '["plans", "blueprints", "drawings", "construction plans", "engineering", "structural design", "architect", "engineer", "CAD", "truss design", "structural calculations", "permit drawings"]'::jsonb),
('1020', 'Permits & Regulatory Fees', 'PRE-CONSTRUCTION', 12, '["permits", "permit fees", "building permit", "impact fees", "plan review", "zoning fee", "building department", "inspection fee", "sewer tap fee", "water tap fee", "HOA design", "review fee", "compaction tests", "geotech visits", "structural special inspections", "blower door", "duct tests", "septic perc tests", "site evaluation", "Environmental Health", "perc test", "DPH"]'::jsonb),
('1030', 'Land Surveying', 'PRE-CONSTRUCTION', 13, '["land survey", "boundary survey", "staking", "site layout", "building corners", "property lines", "survey stakes", "topo survey", "topographic survey", "plat", "ALTA survey"]'::jsonb),
('1040', 'Site Supervision & Management', 'PRE-CONSTRUCTION', 14, '["superintendent", "site supervision", "project manager", "field management", "general conditions", "jobsite meetings", "scheduling", "coordination", "daily reports", "office time", "preconstruction", "general requirements", "project management", "admin", "office", "overhead", "supervision", "site logistics", "mobilization"]'::jsonb),
('1050', 'Temporary Utilities & Site Stabilization', 'PRE-CONSTRUCTION', 15, '["temporary power", "temp electric", "temp water", "porta potty", "portable toilet", "dumpster", "trash removal", "rolloff", "construction cleanup", "utility setup", "temp lighting", "temporary heat", "weather protection", "plastic poly sheeting", "dehumidifiers", "tenting", "tarping"]'::jsonb),
('1060', 'Equipment Rental', 'PRE-CONSTRUCTION', 16, '["equipment rental", "excavator rental", "skid steer rental", "lift rental", "tool rental", "generator rental", "trencher rental", "fuel", "grease", "equipment maintenance", "delivery fee"]'::jsonb),
('1070', 'Utility Coordination', 'PRE-CONSTRUCTION', 17, '["utility coordination", "gas company", "electric company", "power company", "water company", "meter set", "service order", "utility scheduling", "utility application", "service upgrade"]'::jsonb),

-- Division 2: Site Development & Foundation
('2000', 'SITE DEVELOPMENT & FOUNDATION', 'SITE & FOUNDATION', 20, '[]'::jsonb),
('2010', 'Site Clearing & Demolition', 'SITE & FOUNDATION', 21, '["clearing", "grubbing", "demolition", "tree removal", "stump grinding", "structure demo", "haul off", "debris removal", "brush clearing", "demolition permit", "erosion control", "BMPs", "silt fence", "construction entrance", "inlet protection", "erosion matting", "wheat straw"]'::jsonb),
('2020', 'Site Excavation & Backfill', 'SITE & FOUNDATION', 22, '["excavation", "digging", "trenching", "basement dig", "footing dig", "overdig", "backfill", "compacting", "soil removal", "grading at foundation", "excavation equipment"]'::jsonb),
('2030', 'Earth Hauling & Grading', 'SITE & FOUNDATION', 23, '["hauling", "dump fees", "fill dirt", "topsoil haul", "export soil", "import soil", "rough grading", "skid steer grading", "driveway rough grade", "haul truck"]'::jsonb),
('2040', 'Permanent Utility Connections', 'SITE & FOUNDATION', 24, '["water service", "sewer line", "septic connection", "gas line", "electric lateral", "trenching utilities", "conduit", "power trench", "utility tap", "meter pit", "service line install"]'::jsonb),
('2050', 'Footings & Foundation Walls', 'SITE & FOUNDATION', 25, '["footings", "foundation walls", "concrete walls", "rebar", "anchor bolts", "forms", "form rental", "wall pour", "footing pour", "footing inspection", "stem wall"]'::jsonb),
('2060', 'Waterproofing & Drainage', 'SITE & FOUNDATION', 26, '["waterproofing", "dampproofing", "tar spray", "foundation coating", "footing drains", "french drain", "drain tile", "sump line", "dimple board", "foundation drain", "gravel backfill"]'::jsonb),
('2070', 'Termite Protection', 'SITE & FOUNDATION', 27, '["termite treatment", "soil treatment", "pest control", "termite pre-treat", "borate", "chemical barrier", "termite warranty", "termite inspection"]'::jsonb),
('2080', 'Underground Plumbing', 'SITE & FOUNDATION', 28, '["underground plumbing", "under slab plumbing", "DWV", "drain line", "sewer line", "water line", "sleeve", "rough plumbing slab", "inspection", "cleanout", "test plugs"]'::jsonb),

-- Division 3: Framing & Rough Structure
('3000', 'FRAMING & ROUGH STRUCTURE', 'FRAMING', 30, '[]'::jsonb),
('3010', 'Concrete Slabs & Flatwork', 'FRAMING', 31, '["concrete slab", "basement slab", "garage slab", "flatwork", "porch slab", "vapor barrier", "rebar", "wire mesh", "control joints", "pump truck", "power trowel"]'::jsonb),
('3020', 'Structural Steel', 'FRAMING', 32, '["structural steel", "steel beam", "I-beam", "steel column", "lally column", "steel lintel", "steel post", "hanger", "base plate", "weld plates", "steel fabrication"]'::jsonb),
('3030', 'Framing Material Package', 'FRAMING', 33, '["framing lumber", "studs", "joists", "I-joists", "LVL", "trusses", "sheathing", "OSB", "Advantech", "Zip", "nails", "screws", "adhesives", "fasteners", "hangers", "simpson hardware"]'::jsonb),
('3040', 'Framing Labor', 'FRAMING', 34, '["framing labor", "wall framing", "floor framing", "roof framing", "rough opening", "blocking", "coffered ceiling framing", "stair framing", "deck framing", "sheathing install"]'::jsonb),

-- Division 4: Exterior Enclosure
('4000', 'EXTERIOR ENCLOSURE', 'EXTERIOR', 40, '[]'::jsonb),
('4010', 'Roofing System', 'EXTERIOR', 41, '["roofing", "shingles", "asphalt shingle", "metal roof", "underlayment", "synthetic felt", "ice and water shield", "flashing", "ridge vent", "roof vents", "drip edge", "roof labor"]'::jsonb),
('4020', 'Windows & Skylights', 'EXTERIOR', 42, '["windows", "skylights", "window units", "vinyl window", "clad window", "wood window", "egress window", "window install", "window flashing", "window wrap", "nailing flanges"]'::jsonb),
('4030', 'Exterior Doors', 'EXTERIOR', 43, '["exterior door", "entry door", "patio door", "slider", "french door", "garage man door", "threshold", "weatherstrip", "exterior hardware", "sill pan"]'::jsonb),
('4040', 'Garage Doors & Openers', 'EXTERIOR', 44, '["garage door", "overhead door", "sectional door", "tracks", "torsion spring", "opener", "remote", "keypad", "insulated door", "weather seal"]'::jsonb),
('4050', 'Exterior Siding & Trim', 'EXTERIOR', 45, '["siding", "vinyl siding", "fiber cement", "Hardie", "wood siding", "soffit", "fascia", "trim boards", "housewrap", "exterior caulk", "joint flashing", "corner boards"]'::jsonb),
('4060', 'Exterior Masonry & Stone', 'EXTERIOR', 46, '["brick", "stone veneer", "masonry", "chimney", "columns", "mortar", "ties", "weeps", "stone install", "brick install", "brick soldier course", "masonry labor"]'::jsonb),
('4070', 'Gutters & Downspouts', 'EXTERIOR', 47, '["gutters", "downspouts", "gutter guards", "extensions", "splash blocks", "aluminum gutter", "seamless gutter", "rainwater control", "miters", "outlets", "hangers"]'::jsonb),

-- Division 5: Systems Rough-In & Insulation
('5000', 'SYSTEMS ROUGH-IN & INSULATION', 'ROUGH-INS', 50, '[]'::jsonb),
('5010', 'Rough HVAC', 'ROUGH-INS', 51, '["HVAC rough-in", "furnace", "air handler", "ductwork", "trunk line", "branch duct", "refrigerant line", "bath fan vent", "dryer vent", "return air", "plenum", "line set", "ERV", "Energy Recovery Ventilator"]'::jsonb),
('5020', 'Rough Plumbing', 'ROUGH-INS', 52, '["plumbing rough-in", "water lines", "PEX", "copper", "PVC", "DWV", "fittings", "elbows", "tees", "barb", "crimp ring", "tub set", "shower valve", "risers", "pressure test"]'::jsonb),
('5030', 'Rough Electrical', 'ROUGH-INS', 53, '["electrical rough-in", "wiring", "romex", "panel", "breaker", "circuits", "outlets", "switches", "can lights", "low voltage", "data", "TV", "240V", "smoke wiring", "arc-fault"]'::jsonb),
('5040', 'Fireplaces & Chimneys', 'ROUGH-INS', 54, '["fireplace", "firebox", "gas fireplace", "wood fireplace", "insert", "chimney", "flue", "vent pipe", "chase", "hearth rough", "direct vent", "B-vent"]'::jsonb),
('5050', 'Insulation', 'ROUGH-INS', 55, '["insulation", "fiberglass batts", "blown insulation", "spray foam", "attic insulation", "wall insulation", "sound batts", "air sealing", "caulk", "foam", "baffles", "vapor barrier"]'::jsonb),
('5060', 'Fire Sprinklers', 'ROUGH-INS', 56, '[]'::jsonb),

-- Division 6: Interior Finishes
('6000', 'INTERIOR FINISHES', 'INTERIOR', 60, '[]'::jsonb),
('6010', 'Drywall & Texture', 'INTERIOR', 61, '["drywall", "sheetrock", "hanging", "taping", "mudding", "finishing", "texture", "skim coat", "moisture resistant board", "green board", "level 4", "level 5", "corner bead"]'::jsonb),
('6020', 'Interior Trim & Millwork', 'INTERIOR', 62, '["interior trim", "millwork", "baseboard", "casing", "crown molding", "window stool", "apron", "closet shelving", "built-ins", "mudroom bench", "shiplap", "nails", "fasteners", "staples"]'::jsonb),
('6030', 'Interior Doors', 'INTERIOR', 63, '["interior doors", "passage doors", "closet doors", "prehung door", "bifold", "barn door", "pocket door", "door slabs", "hinges", "door hardware", "stops"]'::jsonb),
('6040', 'Cabinetry & Countertops', 'INTERIOR', 64, '["cabinets", "kitchen cabinets", "vanities", "bath cabinets", "pantry cabinets", "cabinet crown", "pulls", "knobs", "soft close", "countertops", "template", "quartz", "granite", "laminate top"]'::jsonb),
('6050', 'Hard Flooring (Wood/Laminate)', 'INTERIOR', 65, '["hardwood floor", "engineered wood", "LVP", "laminate flooring", "underlayment", "nail-down", "glue-down", "floating floor", "sanding", "stain", "finish coat", "transitions"]'::jsonb),
('6060', 'Tile & Stone', 'INTERIOR', 66, '["tile", "ceramic tile", "porcelain tile", "floor tile", "wall tile", "shower tile", "backsplash", "thinset", "grout", "cement board", "Schluter", "Kerdi", "shower pan"]'::jsonb),
('6070', 'Interior Painting', 'INTERIOR', 67, '["interior paint", "primer", "wall paint", "ceiling paint", "trim paint", "repaint", "touchup", "spray finish", "roller covers", "brushes", "caulk", "stain blocking"]'::jsonb),
('6080', 'Carpet & Soft Flooring', 'INTERIOR', 68, '["carpet", "pad", "stair carpet", "runner", "tack strip", "carpet install", "stretch", "seam", "binding", "area rug", "carpet tile"]'::jsonb),
('6090', 'Shower Glass, Mirrors & Accessories', 'INTERIOR', 69, '["shower doors", "frameless glass", "bath accessories", "mirrors"]'::jsonb),

-- Division 7: Systems Finish & Appliances
('7000', 'SYSTEMS FINISH & APPLIANCES', 'SYSTEMS FINISH', 70, '[]'::jsonb),
('7010', 'Finish Plumbing', 'SYSTEMS FINISH', 71, '["finish plumbing", "toilet", "lav faucet", "kitchen faucet", "tub trim", "shower valve trim", "shower head", "sink install", "water heater hookup", "disposal", "supply lines", "traps"]'::jsonb),
('7020', 'Finish Electrical', 'SYSTEMS FINISH', 72, '["finish electrical", "light fixtures", "recessed lights", "chandeliers", "fans", "dimmers", "switches", "receptacle covers", "smoke detectors", "CO detectors", "doorbell", "occupancy sensor"]'::jsonb),
('7030', 'Finish HVAC', 'SYSTEMS FINISH', 73, '["finish HVAC", "condenser", "AC unit", "heat pump", "mini-split", "registers", "grilles", "thermostat", "startup", "refrigerant charge", "balancing", "commissioning"]'::jsonb),
('7040', 'Appliances', 'SYSTEMS FINISH', 74, '["appliances", "refrigerator", "range", "cooktop", "oven", "microwave", "dishwasher", "hood", "washer", "dryer", "delivery", "install", "haul away", "gas hookup", "cord kit"]'::jsonb),

-- Division 8: Exterior Finish & Site Completion
('8000', 'EXTERIOR FINISH & SITE COMPLETION', 'SITE FINISH', 80, '[]'::jsonb),
('8010', 'Concrete Flatwork & Driveways', 'SITE FINISH', 81, '["driveway", "concrete drive", "asphalt drive", "sidewalk", "walkway", "patio", "broom finish", "stamped concrete", "expansion joint", "flatwork", "apron", "control joints"]'::jsonb),
('8020', 'Decks & Porches', 'SITE FINISH', 82, '["deck", "porch", "composite decking", "treated lumber", "deck boards", "railings", "balusters", "posts", "stairs", "porch ceiling", "handrail", "joist tape"]'::jsonb),
('8030', 'Fencing & Gates', 'SITE FINISH', 83, '["fence", "fencing", "gates", "wood fence", "vinyl fence", "aluminum fence", "posts", "panels", "hardware", "latch", "fence stain"]'::jsonb),
('8040', 'Irrigation System', 'SITE FINISH', 84, '["irrigation", "sprinkler system", "zones", "heads", "controller", "timer", "rain sensor", "backflow preventer", "valve box", "drip line", "poly pipe", "irrigation startup"]'::jsonb),
('8050', 'Landscaping', 'SITE FINISH', 85, '["landscaping", "topsoil", "sod", "seed", "straw", "mulch", "shrubs", "trees", "plants", "bed edging", "final grading", "landscape fabric", "rock mulch"]'::jsonb),
('8060', 'Swimming Pool', 'SITE FINISH', 86, '["swimming pool", "pool shell", "gunite", "liner pool", "pool equipment", "pump", "filter", "heater", "pool deck", "coping", "pool startup", "pool fencing"]'::jsonb),

-- Division 9: Closeout, Fees & Financials
('9000', 'CLOSEOUT, FEES & FINANCIALS', 'CLOSEOUT', 90, '[]'::jsonb),
('9010', 'Final Cleaning', 'CLOSEOUT', 91, '["final clean", "construction clean", "maid service", "window cleaning", "floor cleaning", "cabinet wipeout", "detail clean", "trash removal", "move-in ready", "post-construction clean"]'::jsonb),
('9020', 'Punch List & Walkthrough', 'CLOSEOUT', 92, '["punch list", "touchup", "warranty work", "small repairs", "caulk touchup", "paint touchup", "hardware adjust", "door adjust", "blue tape", "spray bottle cleaning"]'::jsonb),
('9030', 'Builder Fee', 'CLOSEOUT', 93, '["builder fee", "overhead", "profit", "management fee", "GC fee", "markup", "contractor fee", "percentage fee", "fixed fee", "construction management"]'::jsonb),
('9040', 'Insurance & Warranty', 'CLOSEOUT', 94, '["insurance", "builders risk", "liability insurance", "general liability", "workers comp surcharge", "warranty enrollment", "home warranty", "2-10 warranty", "policy premium", "renewal"]'::jsonb),
('9050', 'Contingency Reserve', 'CLOSEOUT', 95, '["contingency", "reserve", "allowance", "unforeseen conditions", "extras", "overrun", "change funds", "miscellaneous", "slush", "hidden condition", "scope gap"]'::jsonb),
('9060', 'Change Order Administration', 'CLOSEOUT', 96, '["change order", "CO fee", "admin fee", "revision", "owner change", "scope change", "paperwork", "processing", "documentation", "change approval", "change log"]'::jsonb);
;
