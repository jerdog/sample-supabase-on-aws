# Base stage for shared environment setup
FROM node:24-alpine3.23 AS base
# wget is added on top of the upstream base so ECS task health checks can hit
# the /health endpoint without baking a Node-only probe into the runtime.
RUN apk add --no-cache g++ make python3 wget
WORKDIR /app
COPY package.json package-lock.json ./
COPY scripts/ensure-npm-version.cjs ./scripts/ensure-npm-version.cjs
RUN node scripts/ensure-npm-version.cjs

# Dependencies stage - install and cache all dependencies (deploy target
# platform). This is what ships in the final image via production-deps
# below, so any native addons match the deploy target's architecture.
FROM base AS dependencies
RUN npm ci
# Cache the installed node_modules for later stages
RUN cp -R node_modules /node_modules_cache

# Native-arch base + deps: esbuild (invoked by `npm run build`) bundles its
# own native Go binary, which reliably corrupts memory under QEMU when
# cross-building linux/amd64 on Apple Silicon (Go's GC hits a `fatal error:
# lfstack.push` from garbage pointer values -- the same class of bug as
# Next.js's native Rust compiler segfaulting under the same emulation).
# Install and build entirely on BUILDPLATFORM (native, no emulation)
# instead; the build output below (`dist`) is plain JS and isn't
# architecture-specific, so it's safe to build on a different arch than
# the final image -- it never ships this stage's node_modules.
FROM --platform=$BUILDPLATFORM node:24-alpine3.23 AS native-base
RUN apk add --no-cache g++ make python3 wget
WORKDIR /app
COPY package.json package-lock.json ./
COPY scripts/ensure-npm-version.cjs ./scripts/ensure-npm-version.cjs
RUN node scripts/ensure-npm-version.cjs

FROM native-base AS native-dependencies
RUN npm ci

# Build stage - use natively-installed dependencies to run the build
FROM native-base AS build
COPY --from=native-dependencies /app/node_modules ./node_modules
COPY . .
RUN npm run build

# Production dependencies stage - prune dev dependencies from cached node_modules
FROM base AS production-deps
COPY --from=dependencies /node_modules_cache ./node_modules
# Use npm prune to remove dev dependencies while keeping compiled native modules
RUN npm prune --omit=dev

# Final stage - for the production build
FROM base AS final
ARG VERSION
ENV VERSION=$VERSION
COPY migrations migrations

# supabase-on-aws fork: ship the AWS RDS global CA bundle so Node.js can
# verify Aurora's certificate when DATABASE_MULTITENANT_URL/DATABASE_URL is
# set with sslmode=verify-ca&sslrootcert=/etc/ssl/certs/rds-global-bundle.pem.
# build-and-push.sh stages the file into ./certs/ at build time (deleted
# after push). NODE_EXTRA_CA_CERTS is honoured by the storage runtime.
COPY certs/global-bundle.pem /etc/ssl/certs/rds-global-bundle.pem

# Copy production node_modules from the production dependencies stage
COPY --from=production-deps /app/node_modules node_modules
# Copy build artifacts from the build stage
COPY --from=build /app/dist dist
COPY --from=build /app/watt.json /app


EXPOSE 5000
CMD ["node", "dist/start/server.js"]
