FROM node:22-slim
WORKDIR /app
COPY --chown=node:node package*.json ./
RUN npm install --omit=dev
COPY --chown=node:node . .
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node_modules/.bin/tsx", "src/server.ts"]
