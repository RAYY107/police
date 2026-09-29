--[[
    Evora_Police — Government hierarchy

        رئاسة الوزراء  →  الوزارات  →  القطاعات  →  الرتب

    Evora_Police does NOT create groups. Every name below must be a group that already
    exists in your server's vrp/cfg/groups.lua. This file only tells Evora_Police:
        * which ministry / sector a group belongs to
        * the seniority of the group inside its sector (first = most senior)

    A rank can be written as a plain group name, or as a table to override its label:
        "ps_officer"
        { group = "ps_officer", label = "عريف" }

    Sector keys may repeat across ministries; internally a sector id is "Ministry.Sector"
    (e.g. "Interior.PublicSecurity"). Use that id wherever a config asks for sectors.
    `order` is optional and only controls the display order.
]]

Config.Government = {

    PrimeMinistry = {
        label = "رئاسة الوزراء",
        ranks = {
            "prime_minister",
            "prime_deputy",
        },
    },

    Ministries = {

        Interior = {
            label = "وزارة الداخلية",
            order = 1,
            ranks = {
                "interior_minister",
                "interior_deputy",
            },
            sectors = {
                PublicSecurity = {
                    label = "الأمن العام",
                    order = 1,
                    ranks = {
                        "ps_commander",
                        "ps_deputy",
                        "ps_officer",
                        "ps_patrol",
                    },
                },
                Traffic = {
                    label = "المرور",
                    order = 2,
                    ranks = {
                        "traffic_commander",
                        "traffic_officer",
                    },
                },
            },
        },

        Defense = {
            label = "وزارة الدفاع",
            order = 2,
            ranks = {
                "defense_minister",
                "defense_deputy",
            },
            sectors = {
                ExampleSector = {
                    label = "قطاع عسكري",
                    order = 1,
                    ranks = {
                        "sector_commander",
                        "sector_officer",
                    },
                },
            },
        },

    },
}

Config.Hierarchy = {
    -- How a rank may manage other ranks of its OWN level (same sector, same ministry
    -- leadership or the prime ministry itself):
    --   "junior" → only ranks listed below it (default, a deputy cannot dismiss the commander)
    --   "all"    → every rank of the same container
    --   "none"   → only ranks of lower levels
    SameContainer = "junior",

    -- Allow administrators to run management actions (reset, dismiss, ...) on themselves.
    AllowSelfManagement = false,
}
