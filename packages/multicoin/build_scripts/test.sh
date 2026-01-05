PUBLISH_SCRIPT="./build_scripts/publish_local.sh"
PKG_DIR="packages/contracts"

sui move build > build_artifacts.json 2> build_err.log;
if [ $? -eq 0 ]; then
    echo Build succeeded;
else
    echo Build failed;
    return 1;
fi

if ! bash "$PUBLISH_SCRIPT" "$PKG_DIR"; then
    echo "[watch] Publish failed." >&2
    return 0
  fi