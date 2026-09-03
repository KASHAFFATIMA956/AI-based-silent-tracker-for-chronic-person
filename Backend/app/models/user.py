"""
users — shared login table for all roles (patient/attendant/doctor/admin).

Schema doc 4.1. A single table for every role rather than separate login
tables per role — simpler auth, matches the prototype's single
role-switch model (see context/decisions-log.md).
"""

from datetime import datetime

from sqlalchemy import Enum as PgEnum
from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base
from app.models.enums import LanguagePreference, UserRole


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)

    name: Mapped[str] = mapped_column(String, nullable=False)
    role: Mapped[UserRole] = mapped_column(
        PgEnum(UserRole, name="user_role"), nullable=False
    )
    # Login identifier — phone number or email.
    phone_or_email: Mapped[str] = mapped_column(String, nullable=False, unique=True)
    password_hash: Mapped[str] = mapped_column(String, nullable=False)
    language_preference: Mapped[LanguagePreference] = mapped_column(
        PgEnum(LanguagePreference, name="language_preference"),
        nullable=False,
        default=LanguagePreference.english,
    )

    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    def __repr__(self) -> str:
        return f"<User id={self.id} name={self.name!r} role={self.role}>"
