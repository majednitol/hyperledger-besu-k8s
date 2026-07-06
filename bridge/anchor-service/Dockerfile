# Dockerfile for Healthcare Bridge Anchor Service.
# Uses Node 20 alpine image for secure non-root footprint.

FROM node:20-alpine

USER node
WORKDIR /home/node/app

# Copy package dependency manifests
COPY --chown=node:node bridge/anchor-service/package*.json ./bridge/anchor-service/
COPY --chown=node:node bridge/anchor-service/tsconfig.json ./bridge/anchor-service/

WORKDIR /home/node/app/bridge/anchor-service
RUN npm ci

# Copy source code and build
COPY --chown=node:node bridge/anchor-service/src ./src
RUN npm run build

ENV NODE_ENV=production
CMD [ "npm", "start" ]
