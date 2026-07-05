# Dockerfile for RIR API Gateway and static dashboards.
# Uses Node 20 alpine image for secure non-root footprint.

FROM node:20-alpine

# Set non-root context parameters
USER node
WORKDIR /home/node/app

# Copy package dependency manifests
COPY --chown=node:node package*.json ./
RUN npm ci --only=production

# Copy application layers
COPY --chown=node:node 10.api/src ./10.api/src
COPY --chown=node:node 11.ui ../11.ui
COPY --chown=node:node 12.explorer ../12.explorer

EXPOSE 3000

ENV NODE_ENV=production
CMD [ "node", "10.api/src/server.js" ]
