# Development image: Elixir, a C compiler (bcrypt_elixir) and the Tailwind standalone CLI.
FROM elixir:1.18-otp-27-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential curl ca-certificates \
    && curl -fsSL --retry 6 --retry-all-errors --retry-delay 5 -o /usr/local/bin/tailwindcss \
       https://github.com/tailwindlabs/tailwindcss/releases/download/v4.3.3/tailwindcss-linux-x64 \
    && chmod +x /usr/local/bin/tailwindcss \
    && rm -rf /var/lib/apt/lists/*
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} app && useradd -m -u ${UID} -g app app
USER app
ENV MIX_HOME=/home/app/.mix HEX_HOME=/home/app/.hex
RUN mkdir -p /home/app/.hex && mix local.hex --force && mix local.rebar --force
WORKDIR /app
EXPOSE 8000
CMD ["bin/dev"]
