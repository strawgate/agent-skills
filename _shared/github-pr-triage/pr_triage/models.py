from __future__ import annotations

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class CheckResult(BaseModel):
    name: str
    state: str
    bucket: str
    link: str
    workflow: str


class ReviewComment(BaseModel):
    author_login: str = Field(alias="author", default="")
    body: str = ""
    created_at: datetime = Field(alias="createdAt")


class Review(BaseModel):
    state: str
    author_login: str = Field(alias="author", default="")
    body: str = ""


class ThreadComment(BaseModel):
    id: str
    database_id: Optional[int] = Field(alias="databaseId")
    body: str
    created_at: datetime = Field(alias="createdAt")
    author_login: str = Field(alias="author", default="")


class ReviewThreadDetail(BaseModel):
    id: str
    is_resolved: bool = Field(alias="isResolved", default=False)
    is_outdated: bool = Field(alias="isOutdated", default=False)
    is_collapsed: bool = Field(alias="isCollapsed", default=False)
    path: str
    line: Optional[int] = None
    start_line: Optional[int] = Field(alias="startLine")
    comments_nodes: list[ThreadComment] = Field(alias="comments", default_factory=list)

    def author(self) -> str:
        if self.comments_nodes:
            return self.comments_nodes[0].author_login or "unknown"
        return "unknown"


class PRDetails(BaseModel):
    number: int
    title: str
    body: str = ""
    state: str
    is_draft: bool = Field(alias="isDraft", default=False)
    mergeable: str
    author_login: str = Field(default="")
    additions: int = 0
    deletions: int = 0
    changed_files: int = Field(alias="changedFiles", default=0)
    commits_count: int = Field(alias="commits", default=0)
    created_at: datetime = Field(alias="createdAt")
    updated_at: datetime = Field(alias="updatedAt")
    base_ref_name: str = Field(alias="baseRefName", default="")
    head_ref_name: str = Field(alias="headRefName", default="")
    checks: list[CheckResult] = Field(default_factory=list)
    comments: list[ReviewComment] = Field(default_factory=list)
    reviews: list[Review] = Field(default_factory=list)
    threads: list[ReviewThreadDetail] = Field(default_factory=list)
    diff_lines: int = 0
    files_count: int = 0

    def checks_failed(self) -> int:
        return sum(1 for c in self.checks if c.state in ("FAILURE", "ERROR"))

    def unresolved_threads(self) -> int:
        return sum(1 for t in self.threads if not t.is_resolved)
