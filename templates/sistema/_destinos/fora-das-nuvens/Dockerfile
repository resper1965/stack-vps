FROM node:22-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["npx", "tsx", "src/server.ts"]
