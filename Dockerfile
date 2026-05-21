FROM steamcmd/steamcmd:latest

RUN apt-get update && apt-get install -y \
    gettext-base \
    wine64 \
    xvfb \
    dotnet-sdk-8.0 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /steamworks_sdk && steamcmd +force_install_dir /steamworks_sdk +login anonymous +@sSteamCmdForcePlatformType windows +app_update 1007 +quit

# To reduce image size and speed up builds, it is advised to to mount /game/ folder from the host machine.
# IMPORTANT: it is NOT an option for WSL hosts, since it breaks wine. On WSL, you have to build /game/ into the image.
COPY ["Risk of Rain 2/", "/game/"]
COPY mods/ /game/

WORKDIR /app
COPY RoR2Patcher/ /app/RoR2Patcher/
COPY config.cfg /app/config.cfg

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV MAX_PLAYERS=4
ENV STEAM_HEARTBEAT=1
ENV SERVER_HOSTNAME="Dedicated Server by EPecherkin/RoR2Server"
ENV PORT=27015
ENV STEAM_QUERY_PORT=27016
ENV STEAM_SERVER_PORT=0
ENV SERVER_PASSWORD=""
ENV SERVER_CUSTOM_TAGS=""
ENV GAMEMODE="ClassicRun"
ENV EXTRA_ARGS=""

EXPOSE ${PORT}/udp ${STEAM_QUERY_PORT}/udp

ENTRYPOINT ["/app/entrypoint.sh"]
