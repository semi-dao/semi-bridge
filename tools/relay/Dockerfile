FROM dart:stable AS build
WORKDIR /app
COPY bridge_relay.dart .
RUN dart compile exe bridge_relay.dart -o /bridge_relay

FROM debian:bookworm-slim
COPY --from=build /bridge_relay /usr/local/bin/bridge_relay
EXPOSE 8791
ENTRYPOINT ["bridge_relay"]
