from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

# Make sure app/ is importable when alembic is run from Backend/.
from app.core.config import settings
from app.core.database import Base
import app.models  # noqa: F401 - populates Base.metadata

# this is the Alembic Config object, which provides access to values
# within the .ini file in use.
config = context.config

# Override the URL from alembic.ini with the one from our own settings
# (DATABASE_URL env var / .env), so there's a single source of truth.
config.set_main_option("sqlalchemy.url", settings.database_url)

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
