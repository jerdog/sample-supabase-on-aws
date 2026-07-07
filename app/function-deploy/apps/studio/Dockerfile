# To be run in the root of the turbo monorepo
# NOTE: It's highly recommended to use the new builder, Buildkit. https://docs.docker.com/build/buildkit/
## USAGE:
# Build:        docker build . -f apps/studio/Dockerfile --target production -t studio:latest
# Run:          docker run -p 3000:3000 supabase/studio
# Deploy:       docker push supabase/studio:latest
# Clean build:
#    docker builder prune
#    docker build . -f apps/studio/Dockerfile --target production -t studio:latest --no-cache

FROM node:22-slim AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Fixes issues with Sentry CLI and SSL certificates during build
# TODO: Git is added because it's needed to build libpg, remove it once they publish a binary on the S3 bucket
RUN apt-get update -qq && \
  apt-get install -y --no-install-recommends \
  git \
  python3 \
  ca-certificates \
  build-essential && \
  rm -rf /var/lib/apt/lists/* && \
  update-ca-certificates

RUN npm install -g pnpm@10.16.1

WORKDIR /app

# Dependency-install and compile stages run on BUILDPLATFORM (the build
# host's native arch) instead of inheriting the outer --platform target.
# Next.js's native Rust compiler (SWC/Turbopack) reliably segfaults under
# QEMU when cross-building linux/amd64 on Apple Silicon; running it natively
# avoids emulation entirely. Only `production` below stays pinned to the
# deploy target platform.
FROM --platform=$BUILDPLATFORM node:22-slim AS native-base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN apt-get update -qq && \
  apt-get install -y --no-install-recommends \
  git \
  python3 \
  ca-certificates \
  build-essential && \
  rm -rf /var/lib/apt/lists/* && \
  update-ca-certificates

RUN npm install -g pnpm@10.16.1

WORKDIR /app

# Prune unneeded dependencies with turbo (from apps/ for example)
FROM native-base AS turbo
COPY . .

RUN pnpm dlx turbo@2.3.3 prune studio --docker

# Install dev dependencies (only if needed)
FROM native-base AS deps
COPY --from=turbo /app/out/json ./
COPY --from=turbo /app/out/pnpm-lock.yaml ./

# No need to clean cache because production uses standalone build
RUN pnpm install --frozen-lockfile

# dev contains dependencies and source code not compiled
FROM deps AS dev
COPY --from=turbo /app/out/full ./
ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 8082
CMD ["pnpm", "dev:studio"]

# Compile Next.js
FROM dev AS builder

# Optimize Node.js build performance
ENV NODE_OPTIONS="--max-old-space-size=8192"
# Disable telemetry to save resources
ENV NEXT_TELEMETRY_DISABLED=1
# Limit worker count for page data collection (Next.js 14+)
ENV NEXT_PRIVATE_WORKER_THREADS=8
# Disable source maps to save memory and build time
ENV NEXT_DISABLE_SOURCEMAPS=1
# Skip type checking during build (already done in CI)
ENV SKIP_TYPE_CHECK=1
# Skip linting during build
ENV SKIP_LINT=1
# Skip asset upload during build
ENV SKIP_ASSET_UPLOAD=1
# Use SWC minifier (faster than Terser)
ENV NEXT_PRIVATE_STANDALONE=true

# Build with optimizations
# Disable Turbopack to use webpack which supports externals configuration for AWS SDK
RUN TURBOPACK=0 pnpm --filter studio exec next build

# `sharp` is an optional runtime dependency of `next` (see pnpm-lock.yaml)
# used for production image optimization -- unlike the build-only SWC/
# Turbopack binaries, it must match the *deploy target* platform. The
# `builder` stage above ran on BUILDPLATFORM, so its bundled sharp binary
# (under .next/standalone/node_modules) won't match a cross-built image.
# Fetch a target-platform sharp here (bare FROM = inherits the deploy
# target, e.g. linux/amd64) to swap in below.
FROM node:22-slim AS sharp-target
WORKDIR /sharp
RUN npm install --no-save sharp@0.34.5

# Copy only compiled code and dependencies
FROM base AS production
COPY certs/global-bundle.pem /etc/ssl/certs/rds-global-bundle.pem
COPY --from=builder /app/apps/studio/public ./apps/studio/public
COPY --from=builder /app/apps/studio/.next/standalone ./
COPY --from=builder /app/apps/studio/.next/static ./apps/studio/.next/static
RUN rm -rf node_modules/sharp node_modules/@img
# Merge in sharp's full dependency closure (sharp, @img, and sharp's own
# small JS deps like detect-libc/semver/@emnapi) -- sharp-target is an
# isolated install with nothing else in it, so copying its whole
# node_modules is safe and avoids missing a hoisted sibling dependency.
COPY --from=sharp-target /sharp/node_modules/ ./node_modules/
EXPOSE 3000
ENTRYPOINT ["docker-entrypoint.sh"]
HEALTHCHECK --interval=5s --timeout=5s --retries=3 CMD node -e "fetch('http://localhost:3000/api/platform/profile').then((r) => {if (r.status !== 200) throw new Error(r.status)})"
CMD ["node", "apps/studio/server.js"]
