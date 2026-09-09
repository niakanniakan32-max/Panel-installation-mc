#!/bin/sh
# Universal Modpack Installer (POSIX sh - runs under /bin/ash in the installer image)
# Supports: Modrinth (PROJECT_ID/VERSION_ID), CurseForge direct URL, manual upload (MODPACK_ZIP)
# Server Files: /mnt/server

: "${SERVER_DIR:=/mnt/server}"
: "${PROJECT_ID:=}"
: "${VERSION_ID:=}"
: "${MODPACK_ZIP:=}"
: "${PROVIDER:=modrinth}"
: "${MC_VERSION:=}"
: "${LOADER:=}"

cd "$SERVER_DIR" || { echo "Cannot cd to $SERVER_DIR"; exit 1; }

# Mojang EULA: accept up-front so a fresh server can start with no manual step.
echo "eula=true" > eula.txt

echo "Installing required packages..."
apt update > /dev/null 2>&1
apt install -y wget jq unzip > /dev/null 2>&1

# ---------- loader installers ----------

is_new_forge() {
  case "$1" in
    1.17*|1.18*|1.19*|1.2*|1.3*) echo yes ;;
    *) echo no ;;
  esac
}

forge_latest_for_mc() {
  # newest Forge build for a given MC version, e.g. 1.12.2 -> 14.23.5.2860
  mc="$1"
  wget -qO- "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml" 2>/dev/null \
    | grep -o "<version>[^<]*</version>" | sed 's/<[^>]*>//g' \
    | grep "^${mc}-" | sed "s/^${mc}-//" | sort -V | tail -1
}

install_forge() {
  mc="$1"; forge_ver="$2"
  echo "Installing Forge $forge_ver for MC $mc..."
  FORGE_VER="${mc}-${forge_ver}"
  case "$mc" in
    1.7.10|1.8.9) FORGE_VER="${FORGE_VER}-${mc}" ;;
  esac
  if ! wget -q "https://maven.minecraftforge.net/net/minecraftforge/forge/${FORGE_VER}/forge-${FORGE_VER}-installer.jar" -O forge-installer.jar; then
    echo "ERROR: Failed to download Forge installer ${FORGE_VER}"
    return 1
  fi
  rm -rf libraries/net/minecraftforge/forge 2>/dev/null
  rm -f unix_args.txt user_jvm_args.txt
  if ! java -jar forge-installer.jar --installServer > /dev/null 2>&1; then
    echo "ERROR: Forge install failed for ${FORGE_VER}"
    return 1
  fi
  if [ "$(is_new_forge "$mc")" = "yes" ]; then
    ln -sf libraries/net/minecraftforge/forge/*/unix_args.txt unix_args.txt 2>/dev/null
  else
    FORGE_JAR="forge-${FORGE_VER}.jar"
    if [ "$mc" = "1.7.10" ]; then
      FORGE_JAR="forge-${FORGE_VER}-universal.jar"
    fi
    mv "$FORGE_JAR" forge-server-launch.jar 2>/dev/null
    echo "forge-server-launch.jar" > .serverjar
  fi
  rm -f forge-installer.jar
  echo "Forge installed successfully"
}

install_fabric() {
  mc="$1"; fabric_ver="$2"
  echo "Installing Fabric $fabric_ver for MC $mc..."
  INSTALLER_URL=$(wget -qO- "https://meta.fabricmc.net/v2/versions/installer" | jq -r '.[0].url // empty')
  if [ -z "$INSTALLER_URL" ]; then
    echo "ERROR: Could not get Fabric installer URL"
    return 1
  fi
  wget -q "$INSTALLER_URL" -O fabric-installer.jar
  if ! java -jar fabric-installer.jar server -mcversion "$mc" -loader "$fabric_ver" -downloadMinecraft; then
    echo "ERROR: Fabric install failed"
    return 1
  fi
  echo "fabric-server-launch.jar" > .serverjar
  rm -f fabric-installer.jar
  echo "Fabric installed successfully"
}

install_neoforge() {
  mc="$1"; neo_ver="$2"
  echo "Installing NeoForge $neo_ver for MC $mc..."
  case "$neo_ver" in
    1.20.1-*) DL_URL="https://maven.neoforged.net/releases/net/neoforged/forge/${neo_ver}/forge-${neo_ver}" ;;
    *) DL_URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/${neo_ver}/neoforge-${neo_ver}" ;;
  esac
  wget -q "${DL_URL}-installer.jar" -O installer.jar
  rm -rf libraries/net/neoforged 2>/dev/null
  rm -f unix_args.txt
  if ! java -jar installer.jar --installServer; then
    echo "ERROR: NeoForge install failed"
    return 1
  fi
  ln -sf libraries/net/neoforged/*/unix_args.txt unix_args.txt 2>/dev/null
  rm -f installer.jar
  echo "NeoForge installed successfully"
}

install_quilt() {
  mc="$1"; quilt_ver="$2"
  echo "Installing Quilt $quilt_ver for MC $mc..."
  INSTALLER_URL=$(wget -qO- "https://meta.quiltmc.org/v3/versions/installer" | jq -r '.[0].url // empty')
  if [ -z "$INSTALLER_URL" ]; then
    echo "ERROR: Could not get Quilt installer URL"
    return 1
  fi
  wget -q "$INSTALLER_URL" -O quilt-installer.jar
  if ! java -jar quilt-installer.jar install server "$mc" "$quilt_ver" --download-server --install-dir=./; then
    echo "ERROR: Quilt install failed"
    return 1
  fi
  echo "quilt-server-launch.jar" > .serverjar
  rm -f quilt-installer.jar
  echo "Quilt installed successfully"
}

install_loader_base() {
  # Install a bare loader (used for plain server packs like RLCraft that ship no jar).
  # Args: mc_version loader [loader_version] (loader_version optional for forge -> latest)
  mc="$1"; loader="$2"; ver="$3"
  case "$loader" in
    forge*|Forge*)
      if [ -z "$ver" ] || [ "$ver" = "unknown" ]; then
        echo "Resolving latest Forge for MC $mc..."
        ver="$(forge_latest_for_mc "$mc")"
      fi
      if [ -z "$ver" ]; then
        echo "ERROR: Could not determine a Forge version for MC $mc"
        return 1
      fi
      install_forge "$mc" "$ver"
      ;;
    fabric*)
      if [ -z "$ver" ] || [ "$ver" = "unknown" ]; then
        echo "ERROR: Fabric loader version is required"
        return 1
      fi
      install_fabric "$mc" "$ver"
      ;;
    neoforge*|NeoForge*)
      if [ -z "$ver" ] || [ "$ver" = "unknown" ]; then
        echo "ERROR: NeoForge version is required"
        return 1
      fi
      install_neoforge "$mc" "$ver"
      ;;
    quilt*)
      if [ -z "$ver" ] || [ "$ver" = "unknown" ]; then
        echo "ERROR: Quilt loader version is required"
        return 1
      fi
      install_quilt "$mc" "$ver"
      ;;
    *)
      echo "ERROR: Unknown loader: $loader"
      return 1
      ;;
  esac
}

# ---------- manual upload ----------

if [ -n "$MODPACK_ZIP" ] && [ -f "$MODPACK_ZIP" ]; then
  echo "Installing manual modpack from: $MODPACK_ZIP"
  cp "$MODPACK_ZIP" ./manual-modpack.zip
  rm -rf tmp_extract
  mkdir -p tmp_extract
  if ! unzip -q manual-modpack.zip -d tmp_extract; then
    echo "ERROR: Could not unzip manual modpack"
    exit 1
  fi
  MANIFEST=""
  for f in modrinth.index.json manifest.json minecraftinstance.json; do
    if [ -f "tmp_extract/$f" ]; then
      MANIFEST="tmp_extract/$f"
      break
    fi
  done
  if [ -z "$MANIFEST" ]; then
    echo "No manifest found. Extracting as plain modpack..."
    if [ -d tmp_extract/server ]; then
      cp -r tmp_extract/server/* . 2>/dev/null || true
    else
      cp -r tmp_extract/* . 2>/dev/null || true
    fi
    JAR=$(find . -maxdepth 1 -name "*.jar" ! -name "minecraft_server*.jar" ! -name "*-installer.jar" ! -name "installer.jar" | head -1)
    if [ -n "$JAR" ]; then
      echo "${JAR##*/}" > .serverjar
      echo "Plain modpack installed. Server jar: $JAR"
      rm -rf tmp_extract manual-modpack.zip
      echo "Modpack installation complete!"
      exit 0
    fi
    if [ -n "$MC_VERSION" ] && [ -n "$LOADER" ]; then
      install_loader_base "$MC_VERSION" "$LOADER" "" || exit 1
      rm -rf tmp_extract manual-modpack.zip
      echo "Modpack installation complete!"
      exit 0
    fi
    echo "ERROR: No server jar found and no loader info given"
    exit 1
  fi
  echo "Found manifest: $MANIFEST"
  cp "$MANIFEST" ./modpack-manifest.json
  MANIFEST="./modpack-manifest.json"
  FORMAT="manual"
fi

# ---------- CurseForge (PROJECT_ID is the direct download URL) ----------

if [ "$PROVIDER" = "curseforge" ] && [ -n "$PROJECT_ID" ]; then
  echo "Downloading CurseForge modpack..."
  rm -f cf-modpack.zip
  if ! wget "$PROJECT_ID" -O cf-modpack.zip; then
    echo "ERROR: CF download failed"
    exit 1
  fi
  if [ ! -s cf-modpack.zip ]; then
    echo "ERROR: CF download produced an empty file"
    exit 1
  fi
  rm -rf tmp_extract
  mkdir -p tmp_extract
  if ! unzip -q cf-modpack.zip -d tmp_extract; then
    echo "ERROR: Could not unzip CurseForge modpack"
    exit 1
  fi
  MANIFEST=""
  for f in minecraftinstance.json manifest.json modrinth.index.json; do
    if [ -f "tmp_extract/$f" ]; then
      MANIFEST="tmp_extract/$f"
      break
    fi
  done
  if [ -n "$MANIFEST" ]; then
    echo "Found CF manifest: $MANIFEST"
    cp "$MANIFEST" ./modpack-manifest.json
    MANIFEST="./modpack-manifest.json"
    FORMAT="curseforge"
  else
    # Plain server pack (e.g. RLCraft Server Pack): mods + configs, no jar.
    echo "No manifest: treating as plain server pack..."
    if [ -d tmp_extract/server ]; then
      cp -r tmp_extract/server/* . 2>/dev/null || true
    else
      cp -r tmp_extract/* . 2>/dev/null || true
    fi
    # Only a top-level jar counts as a server jar (mods/ jars don't).
    JAR=$(find . -maxdepth 1 -name "*.jar" ! -name "minecraft_server*.jar" ! -name "*-installer.jar" ! -name "installer.jar" | head -1)
    if [ -n "$JAR" ]; then
      echo "${JAR##*/}" > .serverjar
      echo "Server jar found: $JAR"
      rm -rf tmp_extract cf-modpack.zip
      echo "Modpack installation complete!"
      exit 0
    fi
    if [ -z "$MC_VERSION" ] || [ -z "$LOADER" ]; then
      echo "ERROR: Server pack has no jar and no MC version/loader was provided"
      exit 1
    fi
    install_loader_base "$MC_VERSION" "$LOADER" "" || exit 1
    rm -rf tmp_extract cf-modpack.zip
    echo "Modpack installation complete!"
    exit 0
  fi
fi

# ---------- Modrinth (PROJECT_ID is the Modrinth project id) ----------

if [ "$PROVIDER" != "curseforge" ] && [ -n "$PROJECT_ID" ]; then
  echo "Installing Modrinth modpack: $PROJECT_ID"
  MODRINTH_API="https://api.modrinth.com/v2"
  PROJECT_DATA=$(wget -qO- "$MODRINTH_API/project/$PROJECT_ID")
  PRIMARY_LOADER=$(echo "$PROJECT_DATA" | jq -r '(.loaders // [])[0] // "unknown"')
  if [ -z "$VERSION_ID" ] || [ "$VERSION_ID" = "latest" ]; then
    VERSION_ID=$(wget -qO- "$MODRINTH_API/project/$PROJECT_ID/version" | jq -r '.[0].id // empty')
  fi
  if [ -z "$VERSION_ID" ]; then
    echo "ERROR: Could not determine Modrinth version"
    exit 1
  fi
  VERSION_DATA=$(wget -qO- "$MODRINTH_API/version/$VERSION_ID")
  PRIMARY_FILE_URL=$(echo "$VERSION_DATA" | jq -r '.files[0].url // empty')
  PRIMARY_FILE_NAME=$(echo "$VERSION_DATA" | jq -r '.files[0].filename // "modpack.zip"')
  case "$PRIMARY_FILE_NAME" in
    *[Ss][Ee][Rr][Vv][Ee][Rr]*) ;;
    *)
      SERVER_URL=$(echo "$VERSION_DATA" | jq -r '[.files[] | select(.filename | test("server"; "i"))] | .[0].url // empty')
      if [ -n "$SERVER_URL" ]; then
        PRIMARY_FILE_URL="$SERVER_URL"
        echo "Using server pack"
      fi
      ;;
  esac
  if [ -z "$PRIMARY_FILE_URL" ]; then
    echo "ERROR: No downloadable file for Modrinth version $VERSION_ID"
    exit 1
  fi
  rm -f modpack.zip
  if ! wget "$PRIMARY_FILE_URL" -O modpack.zip; then
    echo "ERROR: Modrinth download failed"
    exit 1
  fi
  rm -rf tmp_extract
  mkdir -p tmp_extract
  if ! unzip -q modpack.zip -d tmp_extract; then
    echo "ERROR: Could not unzip Modrinth modpack"
    exit 1
  fi
  MANIFEST=""
  for f in modrinth.index.json manifest.json; do
    if [ -f "tmp_extract/$f" ]; then
      MANIFEST="tmp_extract/$f"
      break
    fi
  done
  if [ -z "$MANIFEST" ]; then
    echo "ERROR: No manifest in Modrinth pack"
    exit 1
  fi
  cp "$MANIFEST" ./modpack-manifest.json
  MANIFEST="./modpack-manifest.json"
  FORMAT="modrinth"
fi

# ---------- common: process manifest ----------

if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  echo "ERROR: No modpack manifest found"
  exit 1
fi

echo "Processing manifest: $MANIFEST"

if jq -e '.minecraft.modLoaders' "$MANIFEST" > /dev/null 2>&1; then
  FORMAT="curseforge"
  MC_VERSION=$(jq -r '.minecraft.version // "unknown"' "$MANIFEST")
  LOADER_ID=$(jq -r '.minecraft.modLoaders[0].id // "unknown"' "$MANIFEST")
  LOADER="$(echo "$LOADER_ID" | cut -d- -f1)"
  LOADER_VERSION="$(echo "$LOADER_ID" | cut -d- -f2-)"
elif jq -e '.dependencies' "$MANIFEST" > /dev/null 2>&1; then
  if [ -z "$FORMAT" ]; then
    FORMAT="modrinth"
  fi
  MC_VERSION=$(jq -r '.gameVersion // .dependencies.minecraft // "unknown"' "$MANIFEST" | head -1)
  LOADER=""
  if [ "$FORMAT" = "modrinth" ]; then
    LOADER=$(jq -r '.dependencies | keys[] | select(. != "minecraft")' "$MANIFEST" 2>/dev/null | head -1)
  fi
  if [ -z "$LOADER" ] || [ "$LOADER" = "unknown" ]; then
    LOADER="$PRIMARY_LOADER"
  fi
  case "$LOADER" in
    forge) LOADER_VERSION=$(jq -r '.dependencies.forge // empty' "$MANIFEST") ;;
    fabric*) LOADER_VERSION=$(jq -r '.dependencies."fabric-loader" // empty' "$MANIFEST") ;;
    neoforge*) LOADER_VERSION=$(jq -r '.dependencies.neoforge // empty' "$MANIFEST") ;;
    quilt*) LOADER_VERSION=$(jq -r '.dependencies."quilt-loader" // empty' "$MANIFEST") ;;
    *) LOADER_VERSION="" ;;
  esac
else
  echo "ERROR: Unknown modpack manifest format"
  exit 1
fi

echo "MC: $MC_VERSION, Loader: $LOADER, Version: $LOADER_VERSION"

if [ -d tmp_extract/overrides ]; then
  echo "Applying overrides..."
  cp -r tmp_extract/overrides/* . 2>/dev/null || true
fi

echo "Downloading mods..."
mkdir -p mods
if [ "$FORMAT" = "modrinth" ]; then
  jq -c '.files[]?' "$MANIFEST" | while read -r file; do
    # Skip client-only files (they crash or waste space on servers)
    SERVER_SIDE=$(echo "$file" | jq -r '.env.server // "required"')
    if [ "$SERVER_SIDE" = "unsupported" ]; then
      continue
    fi
    # Modrinth index carries direct download URLs plus the target path
    DL=$(echo "$file" | jq -r '.downloads[0] // empty')
    DEST=$(echo "$file" | jq -r '.path // empty')
    if [ -z "$DL" ] || [ -z "$DEST" ]; then
      continue
    fi
    mkdir -p "$(dirname "$DEST")"
    if [ ! -f "$DEST" ]; then
      wget -q "$DL" -O "$DEST" 2>/dev/null || echo "WARN: failed $DEST"
    fi
  done
else
  jq -c '.files[]?' "$MANIFEST" | while read -r file; do
    MOD_PROJECT=$(echo "$file" | jq -r '.projectID // .project // empty')
    MOD_FILE=$(echo "$file" | jq -r '.fileID // .file // empty')
    if [ -z "$MOD_PROJECT" ] || [ -z "$MOD_FILE" ]; then
      continue
    fi
    P1=$(printf %s "$MOD_FILE" | cut -c1-4)
    P2=$(printf %s "$MOD_FILE" | cut -c5-7)
    if ! wget -q "https://edge.forgecdn.net/files/${P1}/${P2}/${MOD_PROJECT}-${MOD_FILE}.jar" -P mods 2>/dev/null; then
      wget -q "https://mediafilez.forgecdn.net/files/${P1}/${P2}/${MOD_PROJECT}-${MOD_FILE}.jar" -P mods 2>/dev/null || echo "WARN: failed mod $MOD_PROJECT $MOD_FILE"
    fi
  done
fi

install_loader_base "$MC_VERSION" "$LOADER" "$LOADER_VERSION" || exit 1

rm -rf tmp_extract modpack.zip manual-modpack.zip modpack-manifest.json cf-modpack.zip 2>/dev/null

echo "Modpack installation complete!"
