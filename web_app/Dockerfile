# Railway deploy image for the React (Vite) web app.
#
# Two stages: build the static bundle with Node, then serve it with nginx
# — nginx never needs the Node toolchain at runtime, keeping the final
# image small. The SPA-fallback config (nginx.default.conf.template) is
# what actually fixes context/pre-deployment-checklist.md item 6 — see
# that file's own comments for why it's needed.
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
# VITE_API_BASE_URL is a build-time value — Vite statically inlines
# import.meta.env.VITE_* into the bundle at `vite build` time (see
# src/core/appConfig.js), so it has to be a real build ARG here, not just
# a runtime `docker run -e`, which `npm run build` below would never see.
# Railway auto-forwards any service variable whose name matches a
# declared ARG as a build arg for the Dockerfile builder — set
# VITE_API_BASE_URL as a variable on this service once the backend's real
# deployed URL exists (see context/pre-deployment-checklist.md item 5 for
# the exact command/value), and Railway wires it in automatically. Left
# unset (empty string default) is fine until then: it falls back to
# appConfig.js's own '' default, same as local dev — same behavior as
# before this ARG was added, just now actually configurable.
ARG VITE_API_BASE_URL=""
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
RUN npm run build

FROM nginx:1.29-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.default.conf.template /etc/nginx/templates/default.conf.template
# Default so the image still runs locally (`docker run -p 8080:8080 ...`)
# without needing -e PORT — Railway overrides this at deploy time exactly
# like the backend's own $PORT handling.
ENV PORT=8080
EXPOSE 8080
