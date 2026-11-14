# TapCopy commercial portal + license API (Node 22, PostgreSQL 17)
FROM node:22-alpine

ENV NODE_ENV=production \
    PORT=3000 \
    STORAGE_DIR=/app/storage

WORKDIR /app

COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi

COPY . .

RUN mkdir -p /app/storage && addgroup -S app && adduser -S app -G app \
    && chown -R app:app /app
USER app

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD wget -qO- http://127.0.0.1:3000/api/health >/dev/null || exit 1

CMD ["node", "server.mjs"]
