---
name: documents
description: "Document conversion (pandoc), PDF manipulation, and spreadsheet/CSV processing via CLI tools"
---

# Document Tools

Use CLI tools instead of MCP pandoc, pdf, and spreadsheet servers.

## Pandoc — Document Conversion

### Common conversions

```bash
# Markdown to PDF
pandoc input.md -o output.pdf --pdf-engine=xelatex

# Markdown to DOCX
pandoc input.md -o output.docx

# DOCX to Markdown
pandoc input.docx -o output.md -t markdown

# HTML to Markdown
pandoc input.html -o output.md

# Markdown to reveal.js slides
pandoc input.md -t revealjs -s -o slides.html

# EPUB to Markdown
pandoc input.epub -o output.md
```

### With bibliography

```bash
pandoc input.md --bibliography=refs.bib --citeproc -o output.pdf
```

### Templates & metadata

```bash
pandoc input.md -o output.pdf --template=mytemplate.latex --metadata title="My Title"
```

## PDF Manipulation

### Merge PDFs

```bash
pdftk a.pdf b.pdf cat output merged.pdf
qpdf --empty --pages a.pdf b.pdf -- merged.pdf
```

### Split pages

```bash
pdftk input.pdf burst
qpdf --split-pages=2 input.pdf output_%d.pdf
```

### Extract text

```bash
pdftotext input.pdf output.txt
```

### Rotate

```bash
pdftk input.pdf rotate 1-endeast output rotated.pdf
```

### Compress

```bash
gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook -dNOPAUSE -dQUIET -dBATCH -sOutputFile=compressed.pdf input.pdf
```

## Spreadsheet / CSV

### csvkit

```bash
# View CSV
csvlook data.csv

# Query with SQL
csvsql --query "SELECT name, count(*) FROM data GROUP BY name" data.csv

# Convert Excel to CSV
in2csv file.xlsx > file.csv

# CSV stats
csvstat data.csv
```

### xsv

```bash
# Select columns
xsv select name,age data.csv

# Filter rows
xsv search -s name "John" data.csv

# Sort
xsv sort -s age data.csv

# Join CSVs
xsv join name a.csv name b.csv
```
