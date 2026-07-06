# Dockerfile for Healthcare API Gateway and static dashboards.
# Uses Node 20 alpine image for secure non-root footprint.

FROM node:20-alpine

USER node
WORKDIR /home/node/app

# Copy package dependency manifests
COPY --chown=node:node 10.api/package*.json ./10.api/
WORKDIR /home/node/app/10.api
RUN npm ci --only=production

# Copy application layers
COPY --chown=node:node 10.api/src ./src
WORKDIR /home/node/app
COPY --chown=node:node 11.ui ./11.ui
COPY --chown=node:node 12.explorer ./12.explorer

EXPOSE 3000

ENV NODE_ENV=production
CMD [ "node", "10.api/src/server.js" ]
