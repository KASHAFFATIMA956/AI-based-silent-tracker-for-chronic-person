from pydantic import BaseModel


class AiSummaryOut(BaseModel):
    available: bool
    summary_text: str | None = None
    # Shown by the caller when available=False — the Claude API was
    # unreachable/unconfigured/errored. Never a 500; rule-based data is
    # unaffected either way.
    fallback_message: str | None = None
