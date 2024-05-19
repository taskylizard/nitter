# this is our first build stage, it will not persist in the final image
FROM node:20.11.0-buster-slim as intermediate

# installation required packages
RUN apt-get update && apt-get install -y --no-install-recommends ssh git python python3 build-essential
RUN npm install -g pnpm@9.1.1
RUN mkdir -p /opt
WORKDIR /opt

COPY tsconfig.json /opt
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY ./src /opt/src

RUN pnpm run build

# copy just the package form the previous image
FROM node:20.11.0-buster-slim
COPY --from=intermediate /opt /opt
ENTRYPOINT ["node", "/opt/build/index.js"]
