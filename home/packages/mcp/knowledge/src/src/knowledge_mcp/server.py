from __future__ import annotations

import hashlib
import json
import textwrap
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

import numpy as np
from pdfminer.high_level import extract_text as extract_pdf_text
from sentence_transformers import SentenceTransformer

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.shared.exceptions import McpError
from mcp.types import TextContent, Tool
from pydantic import BaseModel, Field, ValidationError

TEXT_EXTS = {
    ".md",
    ".markdown",
    ".txt",
    ".org",
    ".rst",
    ".log",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".py",
    ".rs",
    ".go",
    ".ts",
    ".tsx",
    ".js",
    ".jsx",
    ".java",
    ".c",
    ".h",
    ".cpp",
    ".hpp",
}
PDF_EXTS = {".pdf"}
MAX_CHUNK_CHARS = 400


class SearchInput(BaseModel):
    query: str = Field(..., min_length=2)
    limit: int = Field(default=5, ge=1, le=20)


class AddSnippetInput(BaseModel):
    title: str = Field(..., min_length=1)
    text: str = Field(..., min_length=1)
    path_hint: str | None = Field(
        default=None,
        description="Optional virtual path/tag to help citations",
    )


class DocumentSummary(BaseModel):
    doc_id: str
    path: str
    title: str
    chunk_count: int


class SearchResult(BaseModel):
    doc_id: str
    chunk_id: str
    path: str
    title: str
    snippet: str
    score: float


class SnippetResult(BaseModel):
    id: str
    doc_id: str
    title: str
    path: str


@dataclass
class Chunk:
    doc_id: str
    chunk_id: str
    path: str
    title: str
    text: str
    signature: str


class KnowledgeCatalog:
    def __init__(
        self,
        *,
        paths: list[str],
        include_globs: list[str],
        cache_dir: Path | None,
        model_name: str,
    ) -> None:
        self.paths = paths
        self.include_globs = include_globs
        self.cache_dir = cache_dir
        self.model_name = model_name
        if self.cache_dir:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.metadata_path = self.cache_dir / "metadata.json" if self.cache_dir else None
        self.vectors_path = self.cache_dir / "vectors.npy" if self.cache_dir else None
        self.manual_snippets_path = (
            self.cache_dir / "manual-snippets.json" if self.cache_dir else None
        )
        self.model = SentenceTransformer(model_name)
        self.chunks: list[Chunk] = []
        self.embeddings: np.ndarray | None = None
        self._load_chunks()

    def _load_chunks(self) -> None:
        cached = self._try_load_cache()
        if cached:
            self.chunks, self.embeddings = cached
            return
        files = self._collect_files()
        chunks: list[Chunk] = []
        for file in files:
            chunks.extend(self._chunk_file(file))
        chunks.extend(self._load_manual_snippets())
        texts = [chunk.text for chunk in chunks]
        if not texts:
            self.chunks = []
            self.embeddings = None
            return
        vectors = self._embed(texts)
        self.chunks = chunks
        self.embeddings = vectors
        self._persist_cache()

    def _collect_files(self) -> list[Path]:
        files: list[Path] = []
        seen: set[str] = set()
        patterns = [pattern.strip() for pattern in self.include_globs if pattern.strip()]
        for root in self.paths:
            path = Path(root).expanduser()
            if not path.exists():
                continue
            if path.is_file():
                files.append(path)
                continue
            for file in path.rglob("*"):
                if not file.is_file():
                    continue
                suffix = file.suffix.lower()
                if suffix in TEXT_EXTS or suffix in PDF_EXTS:
                    key = str(file.resolve())
                    if key not in seen:
                        seen.add(key)
                        files.append(file)
                elif patterns:
                    rel = file.name
                    if any(file.match(glob) or rel == glob for glob in patterns):
                        key = str(file.resolve())
                        if key not in seen:
                            seen.add(key)
                            files.append(file)
        return files

    def _chunk_file(self, file: Path) -> list[Chunk]:
        text = self._read_file(file)
        if not text.strip():
            return []
        doc_id = hashlib.sha1(file.as_posix().encode()).hexdigest()
        segments = _segment_text(text)
        chunks: list[Chunk] = []
        for idx, segment in enumerate(segments):
            signature = _chunk_signature(file, idx)
            chunk = Chunk(
                doc_id=doc_id,
                chunk_id=f"{doc_id}:{idx}",
                path=file.as_posix(),
                title=file.stem,
                text=segment,
                signature=signature,
            )
            chunks.append(chunk)
        return chunks

    def _load_manual_snippets(self) -> list[Chunk]:
        if not self.manual_snippets_path or not self.manual_snippets_path.exists():
            return []
        try:
            payload = json.loads(self.manual_snippets_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return []
        chunks: list[Chunk] = []
        for entry in payload if isinstance(payload, list) else []:
            text = entry.get("text", "")
            if not text:
                continue
            chunk = Chunk(
                doc_id=entry.get("doc_id", "manual"),
                chunk_id=entry.get("chunk_id", f"manual:{uuid.uuid4()}"),
                path=entry.get("path", "manual"),
                title=entry.get("title", "Manual Snippet"),
                text=text,
                signature=entry.get("signature", chunk.chunk_id if "chunk" in locals() else ""),
            )
            chunk.signature = entry.get("signature", chunk.chunk_id)
            chunks.append(chunk)
        return chunks

    def _read_file(self, file: Path) -> str:
        suffix = file.suffix.lower()
        try:
            if suffix in PDF_EXTS:
                return extract_pdf_text(str(file))
            return file.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            return ""

    def _embed(self, texts: list[str]) -> np.ndarray:
        vectors = self.model.encode(texts, convert_to_numpy=True, show_progress_bar=False)
        norms = np.linalg.norm(vectors, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        return vectors / norms

    def _persist_cache(self) -> None:
        if not self.cache_dir or self.embeddings is None or not self.chunks:
            return
        metadata = {
            "model": self.model_name,
            "chunks": [chunk.__dict__ for chunk in self.chunks],
        }
        self.metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
        np.save(self.vectors_path, self.embeddings)

    def _try_load_cache(self) -> tuple[list[Chunk], np.ndarray] | None:
        if not self.metadata_path or not self.metadata_path.exists():
            return None
        if not self.vectors_path or not self.vectors_path.exists():
            return None
        try:
            metadata = json.loads(self.metadata_path.read_text(encoding="utf-8"))
            if metadata.get("model") != self.model_name:
                return None
            chunks = [Chunk(**chunk_data) for chunk_data in metadata.get("chunks", [])]
            vectors = np.load(self.vectors_path)
            if len(chunks) != len(vectors):
                return None
            return chunks, vectors
        except Exception:
            return None

    def list_documents(self) -> list[DocumentSummary]:
        docs: dict[str, DocumentSummary] = {}
        for chunk in self.chunks:
            if chunk.doc_id not in docs:
                docs[chunk.doc_id] = DocumentSummary(
                    doc_id=chunk.doc_id,
                    path=chunk.path,
                    title=chunk.title,
                    chunk_count=0,
                )
            docs[chunk.doc_id].chunk_count += 1
        return list(docs.values())

    def vector_search(self, query: str, limit: int) -> list[SearchResult]:
        if self.embeddings is None or not self.chunks:
            return []
        vector = self._embed([query])[0]
        scores = np.dot(self.embeddings, vector)
        order = np.argsort(-scores)[:limit]
        results: list[SearchResult] = []
        for idx in order:
            chunk = self.chunks[int(idx)]
            snippet = textwrap.shorten(chunk.text, width=320, placeholder=" … ")
            results.append(
                SearchResult(
                    doc_id=chunk.doc_id,
                    chunk_id=chunk.chunk_id,
                    path=chunk.path,
                    title=chunk.title,
                    snippet=snippet,
                    score=float(scores[int(idx)]),
                )
            )
        return results

    def add_snippet(self, payload: AddSnippetInput) -> SnippetResult:
        chunk = Chunk(
            doc_id=f"manual:{uuid.uuid4()}",
            chunk_id=f"manual:{uuid.uuid4()}",
            path=payload.path_hint or "manual",
            title=payload.title,
            text=payload.text,
            signature=f"manual:{uuid.uuid4()}",
        )
        vector = self._embed([chunk.text])[0]
        if self.embeddings is None:
            self.embeddings = vector.reshape(1, -1)
        else:
            self.embeddings = np.vstack([self.embeddings, vector])
        self.chunks.append(chunk)
        self._update_manual_file(chunk)
        self._persist_cache()
        return SnippetResult(
            id=chunk.chunk_id,
            doc_id=chunk.doc_id,
            title=chunk.title,
            path=chunk.path,
        )

    def _update_manual_file(self, chunk: Chunk) -> None:
        if not self.manual_snippets_path:
            return
        payload = []
        if self.manual_snippets_path.exists():
            try:
                payload = json.loads(self.manual_snippets_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                payload = []
        payload.append(
            {
                "doc_id": chunk.doc_id,
                "chunk_id": chunk.chunk_id,
                "path": chunk.path,
                "title": chunk.title,
                "text": chunk.text,
                "signature": chunk.signature,
            }
        )
        self.manual_snippets_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _segment_text(text: str) -> list[str]:
    buf: list[str] = []
    chunks: list[str] = []
    length = 0
    for line in text.splitlines():
        line_len = len(line)
        if length + line_len > MAX_CHUNK_CHARS and buf:
            chunks.append("\n".join(buf).strip())
            buf = []
            length = 0
        buf.append(line)
        length += line_len + 1
    if buf:
        chunks.append("\n".join(buf).strip())
    return [chunk for chunk in chunks if chunk]


def _chunk_signature(file: Path, idx: int) -> str:
    try:
        stat = file.stat()
        stamp = f"{stat.st_mtime_ns}:{stat.st_size}"
    except OSError:
        stamp = ""
    return hashlib.sha1(f"{file}:{idx}:{stamp}".encode()).hexdigest()


async def serve(
    *,
    paths: list[str],
    cache_dir: Path | None,
    model_name: str,
    include_globs: list[str],
) -> None:
    if not paths:
        raise McpError("No knowledge paths configured; set MCP_KNOWLEDGE_PATHS")
    catalog = KnowledgeCatalog(
        paths=paths,
        include_globs=include_globs,
        cache_dir=cache_dir,
        model_name=model_name,
    )
    server = Server("knowledge-vector")

    schemas = {
        "search": SearchInput.model_json_schema(),
        "snippet": AddSnippetInput.model_json_schema(),
    }

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="list_documents",
                description="List indexed documents",
            ),
            Tool(
                name="vector_search",
                description="Semantic search across embedded snippets",
                inputSchema=schemas["search"],
            ),
            Tool(
                name="add_manual_snippet",
                description="Add an ad-hoc snippet to the knowledge base",
                inputSchema=schemas["snippet"],
            ),
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> Sequence[TextContent]:
        try:
            if name == "list_documents":
                docs = catalog.list_documents()
                payload = json.dumps([doc.model_dump() for doc in docs], indent=2)
            elif name == "vector_search":
                data = SearchInput.model_validate(arguments)
                results = catalog.vector_search(data.query, data.limit)
                payload = json.dumps([r.model_dump() for r in results], indent=2)
            elif name == "add_manual_snippet":
                data = AddSnippetInput.model_validate(arguments)
                entry = catalog.add_snippet(data)
                payload = entry.model_dump_json(indent=2)
            else:
                raise McpError(f"Unknown tool: {name}")
            return [TextContent(type="text", text=payload)]
        except ValidationError as exc:
            raise McpError(str(exc)) from exc
        except McpError:
            raise
        except Exception as exc:
            raise McpError(str(exc)) from exc

    async with stdio_server() as (read_stream, write_stream):
        options = server.create_initialization_options()
        await server.run(read_stream, write_stream, options)
