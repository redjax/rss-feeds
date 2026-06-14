ARG UV_BASE=${UV_IMG_VER:-0.11.21}
ARG PYTHON_BASE=${PYTHON_IMG_VER:-3.14-slim}

FROM ghcr.io/astral-sh/uv:${UV_BASE} AS uv
FROM python:${PYTHON_BASE} AS base

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    build-essential \
    libmemcached-dev \
    zlib1g-dev \
    curl \
    ca-certificates \
    apt-transport-https \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

RUN mkdir -p /work

FROM base AS stage

COPY --from=base /work /work

WORKDIR /work

COPY scripts/ /work/scripts

FROM stage AS build

COPY --from=stage /work /work
COPY --from=uv /uv /usr/bin/uv
COPY --from=stage /work /work

WORKDIR /work

COPY pyproject.toml uv.lock README.md ./

RUN uv sync --all-extras \
    && uv build \
    && uv pip install -e .

FROM stage AS run

COPY --from=uv /uv /usr/bin/uv
COPY --from=base /work /work

WORKDIR /project

CMD ["uv", "run", "scripts/parse_feeds.py"]
