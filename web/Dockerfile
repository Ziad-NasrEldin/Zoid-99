FROM node:22.22.0-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
COPY packages/contracts/package.json packages/contracts/package-lock.json ./packages/contracts/
COPY web/package.json ./web/package.json
RUN npm ci --ignore-scripts

COPY packages/contracts ./packages/contracts
COPY web ./web
RUN npm --workspace @zoid99/contracts run build
RUN npm --workspace @zoid-99/web run build

FROM node:22.22.0-alpine AS runtime

ENV NODE_ENV=production
ENV PORT=3100

WORKDIR /app
RUN addgroup -S zoid99 && adduser -S -G zoid99 zoid99

COPY --from=build --chown=zoid99:zoid99 /app/package.json /app/package-lock.json ./
COPY --from=build --chown=zoid99:zoid99 /app/node_modules ./node_modules
COPY --from=build --chown=zoid99:zoid99 /app/packages/contracts ./packages/contracts
COPY --from=build --chown=zoid99:zoid99 /app/web ./web

USER zoid99
EXPOSE 3100

CMD ["npm", "--workspace", "@zoid-99/web", "run", "start"]
