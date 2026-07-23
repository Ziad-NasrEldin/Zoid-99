FROM node:22.22.0-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build
RUN npm prune --omit=dev

FROM node:22.22.0-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
RUN addgroup -S zoid99 && adduser -S -G zoid99 zoid99
COPY --from=build --chown=zoid99:zoid99 /app/package.json /app/package-lock.json ./
COPY --from=build --chown=zoid99:zoid99 /app/node_modules ./node_modules
COPY --from=build --chown=zoid99:zoid99 /app/dist ./dist
COPY --chown=zoid99:zoid99 migrations ./migrations
USER zoid99
EXPOSE 8099
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -q -O - http://127.0.0.1:8099/health >/dev/null || exit 1
CMD ["node", "dist/src/main.js"]
