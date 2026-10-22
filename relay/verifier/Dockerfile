FROM node:24-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY server.mjs ./
USER node
CMD ["node", "server.mjs"]
