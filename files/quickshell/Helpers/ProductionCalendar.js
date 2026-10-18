// 2026 Russian Production Calendar
// Structure: holidays = [{day: 1..31, label: "Name", type: "holiday"|"shortday"}]
// type "holiday" = non-working day, "shortday" = working 1 hour less

function getHolidays(year, month) {
    // Month is 0-indexed (0=January)
    var all = {
        0: [  // January
            {day:1, label:"New Year", type:"holiday"},
            {day:2, label:"New Year holidays", type:"holiday"},
            {day:3, label:"New Year holidays", type:"holiday"},
            {day:4, label:"New Year holidays", type:"holiday"},
            {day:5, label:"New Year holidays", type:"holiday"},
            {day:6, label:"New Year holidays", type:"holiday"},
            {day:7, label:"Orthodox Christmas", type:"holiday"},
            {day:8, label:"New Year holidays", type:"holiday"}
        ],
        1: [  // February
            {day:23, label:"Defender of the Fatherland Day", type:"holiday"},
            {day:21, label:"Shortened working day", type:"shortday"}
        ],
        2: [  // March
            {day:8, label:"International Women's Day", type:"holiday"},
            {day:7, label:"Shortened working day", type:"shortday"},
            {day:9, label:"Day off moved from March 8 (Sun)", type:"holiday"}
        ],
        3: [  // April
            // No national holidays in April 2026
        ],
        4: [  // May
            {day:1, label:"Spring and Labour Day", type:"holiday"},
            {day:9, label:"Victory Day", type:"holiday"},
            {day:8, label:"Shortened working day", type:"shortday"}
        ],
        5: [  // June
            {day:12, label:"Russia Day", type:"holiday"},
            {day:11, label:"Shortened working day", type:"shortday"}
        ],
        6: [  // July
            // No national holidays in July 2026
        ],
        7: [  // August
            // No national holidays in August 2026
        ],
        8: [  // September
            // No national holidays in September 2026
        ],
        9: [  // October
            // No national holidays in October 2026
        ],
        10: [ // November
            {day:4, label:"Unity Day", type:"holiday"},
            {day:3, label:"Shortened working day", type:"shortday"}
        ],
        11: [ // December
            {day:31, label:"Shortened working day", type:"shortday"}
        ]
    }

    return all[month] || []
}
