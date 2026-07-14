---
name: spreadsheet
description: "CSV, TSV, Excel, and tabular data processing via csvkit, xsv, and Python"
---

# Spreadsheet & Tabular Data

Use CLI tools instead of MCP spreadsheet server.

## csvkit

### Inspection

```bash
# Pretty print
csvlook data.csv

# Column names
csvcut -n data.csv

# Statistics
csvstat data.csv
```

### Selection & Filtering

```bash
# Select columns
csvcut -c name,age,email data.csv

# Filter with SQL
csvsql --query "SELECT * FROM data WHERE age > 18" data.csv
```

### Conversion

```bash
# Excel to CSV
in2csv file.xlsx > file.csv

# CSV to JSON
csvjson data.csv > data.json

# CSV to Excel
csvformat data.csv | in2csv -f xlsx > file.xlsx
```

### Join & Merge

```bash
csvjoin -c id a.csv b.csv > merged.csv
csvstack a.csv b.csv > combined.csv
```

## xsv

```bash
# Frequency tables
xsv frequency -s category data.csv

# Sample rows
xsv sample 10 data.csv

# Search
xsv search -s name "Smith" data.csv

# Sort
xsv sort -s age -R data.csv

# Flatten nested
xsv flatten data.json

# Transpose
xsv table data.csv
```

## Python (pandas) for complex operations

```bash
python3 -c "
import pandas as pd
df = pd.read_csv('data.csv')
print(df.describe())
print(df.groupby('category').size())
df.to_excel('output.xlsx', index=False)
"
```

## Quick inline processing

```bash
# Column arithmetic with awk
awk -F',' '{sum+=$3} END {print sum}' data.csv

# Count unique values
awk -F',' '{counts[$2]++} END {for (k in counts) print k, counts[k]}' data.csv

# Filter rows
awk -F',' '$3 > 100' data.csv
```
