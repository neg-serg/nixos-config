// 2026 Russian Production Calendar
// Structure: holidays = [{day: 1..31, label: "Name", type: "holiday"|"shortday"}]
// type "holiday" = non-working day, "shortday" = working 1 hour less

function getHolidays(year, month) {
    // Month is 0-indexed (0=January)
    var all = {
        0: [  // January
            {day:1, label:"Новый год", type:"holiday"},
            {day:2, label:"Новогодние каникулы", type:"holiday"},
            {day:3, label:"Новогодние каникулы", type:"holiday"},
            {day:4, label:"Новогодние каникулы", type:"holiday"},
            {day:5, label:"Новогодние каникулы", type:"holiday"},
            {day:6, label:"Новогодние каникулы", type:"holiday"},
            {day:7, label:"Рождество Христово", type:"holiday"},
            {day:8, label:"Новогодние каникулы", type:"holiday"}
        ],
        1: [  // February
            {day:23, label:"День защитника Отечества", type:"holiday"},
            {day:21, label:"Сокращённый день", type:"shortday"}
        ],
        2: [  // March
            {day:8, label:"Международный женский день", type:"holiday"},
            {day:7, label:"Сокращённый день", type:"shortday"},
            {day:9, label:"Перенос с 8 марта (вс)", type:"holiday"}
        ],
        3: [  // April
            // No national holidays in April 2026
        ],
        4: [  // May
            {day:1, label:"Праздник Весны и Труда", type:"holiday"},
            {day:9, label:"День Победы", type:"holiday"},
            {day:8, label:"Сокращённый день", type:"shortday"}
        ],
        5: [  // June
            {day:12, label:"День России", type:"holiday"},
            {day:11, label:"Сокращённый день", type:"shortday"}
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
            {day:4, label:"День народного единства", type:"holiday"},
            {day:3, label:"Сокращённый день", type:"shortday"}
        ],
        11: [ // December
            {day:31, label:"Сокращённый день", type:"shortday"}
        ]
    }

    return all[month] || []
}
