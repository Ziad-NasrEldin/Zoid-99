FROM node:22.22.0-alpine AS build
WORKDIR /app
COPY packages/contracts/package.json packages/contracts/package-lock.json packages/contracts/tsconfig.json packages/contracts/tsconfig.build.json ./packages/contracts/
COPY packages/contracts/src ./packages/contracts/src
RUN npm --prefix /app/packages/contracts ci --ignore-scripts --workspaces=false
RUN npm --prefix /app/packages/contracts run build
COPY backend/package.json backend/package-lock.json ./backend/
WORKDIR /app/backend
RUN npm ci --ignore-scripts
COPY backend/tsconfig.json ./
COPY backend/src ./src
RUN npm run build
RUN npm --prefix /app/packages/contracts prune --omit=dev
RUN npm prune --omit=dev

FROM node:22.22.0-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app/backend
RUN addgroup -S zoid99 && adduser -S -G zoid99 zoid99
COPY --from=build --chown=zoid99:zoid99 /app/backend/package.json /app/backend/package-lock.json ./
COPY --from=build --chown=zoid99:zoid99 /app/backend/node_modules ./node_modules
COPY --from=build --chown=zoid99:zoid99 /app/backend/dist ./dist
COPY --from=build --chown=zoid99:zoid99 /app/packages/contracts/package.json /app/packages/contracts/package.json
COPY --from=build --chown=zoid99:zoid99 /app/packages/contracts/dist /app/packages/contracts/dist
COPY --from=build --chown=zoid99:zoid99 /app/packages/contracts/node_modules/zod /app/packages/contracts/node_modules/zod
COPY --chown=zoid99:zoid99 backend/migrations ./migrations
USER zoid99
EXPOSE 8099
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -q -O - http://127.0.0.1:8099/health >/dev/null || exit 1
CMD ["node", "dist/src/main.js"]
