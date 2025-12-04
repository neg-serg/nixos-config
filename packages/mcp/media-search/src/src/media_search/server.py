from __future__ import annotations

import hashlib
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from pdfminer.high_level import extract_text as extract_pdf_text
from PIL import Image
import pytesseract
from rapidfuzz import fuzz

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.shared.exceptions import McpError
from mcp.types import TextContent, Tool
from pydantic import BaseModel, Field, ValidationError

TEXT_EXTS = {".md", ".markdown", ".txt", ".org", ".rst", ".log"}
PDF_EXTS = {".pdf"}
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".tiff"}
MAX_SNIPPET = 320


class SearchInput(BaseModel):
    query: str = Field(..., min_length=2, description="Search string to match against docs")
    limit: int = Field(
        default=5,
        ge=1,
        le=15,
        description="Maximum number of snippets to return",
    )


class ExtractInput(BaseModel):
    doc_id: str = Field(..., description="Document identifier returned by search/list")


class ListResult(BaseModel):
    id: str
    path: str
    kind: str
    title: str | None
    size_bytes: int


class SearchResult(BaseModel):
    id: str
    path: str
    kind: str
    title: str | None
    score: float
    snippet: str


class ExtractResult(BaseModel):
    id: str
    path: str
    kind: str
    title: str | None
    text: str


@dataclass
class DocumentRecord:
    id: str
    path: Path
    kind: str
    title: str
    text: str
    size_bytes: int


class DocumentCatalog:
    def __init__(
        self,
        *,
        search_paths: Sequence[str],
        cache_dir: Path | None,
        tesseract_bin: str,
        ocr_lang: str,
    ) -> None:
        self.cache_dir = cache_dir
        if self.cache_dir:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.tesseract_bin = tesseract_bin or "tesseract"
        pytesseract.pytesseract.tesseract_cmd = self.tesseract_bin
        self.ocr_lang = ocr_lang or "eng"
        self.records = list(self._scan(search_paths))
        self._index_by_id = {record.id: record for record in self.records}

    def _scan(self, search_paths: Sequence[str]):
        unique: set[str] = set()
        for path_str in search_paths:
            path = Path(path_str).expanduser()
            if not path.exists():
                continue
            try:
                for file in path.rglob("*"):
                    if not file.is_file():
                        continue
                    suffix = file.suffix.lower()
                    if suffix not in TEXT_EXTS | PDF_EXTS | IMAGE_EXTS:
                        continue
                    real = file.resolve()
                    key = real.as_posix()
                    if key in unique:
                        continue
                    unique.add(key)
                    record = self._ingest(real)
                    if record:
                        yield record
            except PermissionError:
                continue

    def _ingest(self, file: Path) -> DocumentRecord | None:
        try:
            stat = file.stat()
        except OSError:
            return None
        text = self._load_text(file, stat)
        if not text.strip():
            return None
        doc_id = hashlib.sha1(file.as_posix().encode()).hexdigest()
        return DocumentRecord(
            id=doc_id,
            path=file,
            kind=self._classify(file),
            title=file.stem,
            text=text,
            size_bytes=stat.st_size,
        )

    def _classify(self, file: Path) -> str:
        suffix = file.suffix.lower()
        if suffix in IMAGE_EXTS:
            return "image"
        if suffix in PDF_EXTS:
            return "pdf"
        return "text"

    def _cache_path(self, file: Path, stat) -> Path | None:
        if not self.cache_dir:
            return None
        key = hashlib.sha1(f"{file}:{stat.st_mtime_ns}".encode()).hexdigest()
        return self.cache_dir / f"{key}.txt"

    def _load_text(self, file: Path, stat) -> str:
        cache_path = self._cache_path(file, stat)
        if cache_path and cache_path.exists():
            try:
                return cache_path.read_text(encoding="utf-8")
            except OSError:
                pass
        suffix = file.suffix.lower()
        if suffix in TEXT_EXTS:
            text = self._read_text_file(file)
        elif suffix in PDF_EXTS:
            text = self._read_pdf(file)
        elif suffix in IMAGE_EXTS:
            text = self._read_image(file)
        else:
            text = ""
        if cache_path and text:
            try:
                cache_path.write_text(text, encoding="utf-8")
            except OSError:
                pass
        return text

    def _read_text_file(self, file: Path) -> str:
        try:
            return file.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return ""

    def _read_pdf(self, file: Path) -> str:
        try:
            return extract_pdf_text(str(file))
        except Exception:
            return ""

    def _read_image(self, file: Path) -> str:
        try:
            with Image.open(file) as img:
                img = img.convert("RGB")
                return pytesseract.image_to_string(img, lang=self.ocr_lang)
        except Exception:
            return ""

    def list_documents(self) -> list[ListResult]:
        return [
            ListResult(
                id=record.id,
                path=record.path.as_posix(),
                kind=record.kind,
                title=record.title,
                size_bytes=record.size_bytes,
            )
            for record in self.records
        ]

    def search(self, query: str, limit: int) -> list[SearchResult]:
        lower_query = query.lower()
        results: list[SearchResult] = []
        for record in self.records:
            snippet, score = self._score_record(record, lower_query)
            if score <= 0:
                continue
            results.append(
                SearchResult(
                    id=record.id,
                    path=record.path.as_posix(),
                    kind=record.kind,
                    title=record.title,
                    score=score,
                    snippet=snippet,
                )
            )
        ordered = sorted(results, key=lambda r: r.score, reverse=True)
        return ordered[:limit]

    def _score_record(self, record: DocumentRecord, lower_query: str) -> tuple[str, float]:
        text = record.text
        lower_text = text.lower()
        idx = lower_text.find(lower_query)
        if idx != -1:
            snippet = _window(text, idx, len(lower_query))
            return snippet, 1.0
        best_score = 0.0
        best_snippet = ""
        for line in _yield_candidate_lines(text):
            score = fuzz.partial_ratio(lower_query, line.lower()) / 100.0
            if score > best_score:
                best_score = score
                best_snippet = line
        snippet = textwrap.shorten(best_snippet, width=MAX_SNIPPET, placeholder=" … ")
        return (snippet, best_score)

    def extract(self, doc_id: str) -> ExtractResult:
        record = self._index_by_id.get(doc_id)
        if not record:
            raise McpError(f"Document {doc_id} not found")
        snippet = textwrap.shorten(record.text, width=4000, placeholder=" … ")
        return ExtractResult(
            id=record.id,
            path=record.path.as_posix(),
            kind=record.kind,
            title=record.title,
            text=snippet,
        )


def _yield_candidate_lines(text: str):
    for block in text.splitlines():
        chunk = block.strip()
        if chunk:
            yield chunk


def _window(text: str, index: int, length: int) -> str:
    start = max(index - MAX_SNIPPET // 2, 0)
    end = min(index + length + MAX_SNIPPET // 2, len(text))
    excerpt = text[start:end].strip()
    if start > 0:
        excerpt = "… " + excerpt
    if end < len(text):
        excerpt = excerpt + " …"
    return excerpt


async def serve(
    *,
    search_paths: Sequence[str],
    cache_dir: Path | None,
    tesseract_bin: str,
    ocr_lang: str,
) -> None:
    if not search_paths:
        raise McpError("No search paths provided (set MCP_MEDIA_SEARCH_PATHS or --paths)")
    catalog = DocumentCatalog(
        search_paths=search_paths,
        cache_dir=cache_dir,
        tesseract_bin=tesseract_bin,
        ocr_lang=ocr_lang,
    )

    server = Server("media-search")
    schemas = {
        "search": SearchInput.model_json_schema(),
        "extract": ExtractInput.model_json_schema(),
    }

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="list_documents",
                description="List documents that are currently indexed",
            ),
            Tool(
                name="search_snippets",
                description="Search indexed text and return context snippets",
                inputSchema=schemas["search"],
            ),
            Tool(
                name="extract_document",
                description="Return the best-effort text for a given document id",
                inputSchema=schemas["extract"],
            ),
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> Sequence[TextContent]:
        try:
            if name == "list_documents":
                payload = catalog.list_documents()
            elif name == "search_snippets":
                data = SearchInput.model_validate(arguments)
                payload = catalog.search(data.query, data.limit)
            elif name == "extract_document":
                data = ExtractInput.model_validate(arguments)
                payload = catalog.extract(data.doc_id)
            else:
                raise McpError(f"Unknown tool: {name}")
            text = (
                payload.model_dump_json(indent=2)
                if isinstance(payload, BaseModel)
                else _dump_list(payload)
            )
            return [TextContent(type="text", text=text)]
        except ValidationError as exc:
            raise McpError(str(exc)) from exc
        except McpError:
            raise
        except Exception as exc:
            raise McpError(str(exc)) from exc

    async with stdio_server() as (read_stream, write_stream):
        options = server.create_initialization_options()
        await server.run(read_stream, write_stream, options)


def _dump_list(obj) -> str:
    if isinstance(obj, list):
        return "[\n" + ",\n".join(item.model_dump_json(indent=2) for item in obj) + "\n]"
    return str(obj)
