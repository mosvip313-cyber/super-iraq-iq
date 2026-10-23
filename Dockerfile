FROM node:20-alpine
WORKDIR /app/server
COPY server/package*.json ./
RUN npm install --omit=dev
COPY server/src ./src
COPY apps/admin-web ../apps/admin-web
ENV NODE_ENV=production
EXPOSE 8787
CMD ["npm","start"]
