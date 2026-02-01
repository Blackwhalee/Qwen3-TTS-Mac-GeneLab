#!/bin/bash
# Qwen3-TTS-Mac-GeneLab 起動スクリプト

set -e

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# カラー定義
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}Qwen3-TTS-Mac-GeneLab を起動中...${NC}"
echo ""

# 環境変数設定
export PYTORCH_ENABLE_MPS_FALLBACK=1
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.7
export TOKENIZERS_PARALLELISM=false

# .env ファイルがあれば読み込み
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

# Conda 環境をアクティベート
ENV_NAME="qwen3-tts-mac-genelab"

# conda の初期化
if [ -f "/opt/homebrew/Caskroom/miniforge/base/etc/profile.d/conda.sh" ]; then
    source "/opt/homebrew/Caskroom/miniforge/base/etc/profile.d/conda.sh"
elif [ -f "$HOME/miniforge3/etc/profile.d/conda.sh" ]; then
    source "$HOME/miniforge3/etc/profile.d/conda.sh"
elif [ -f "$HOME/mambaforge/etc/profile.d/conda.sh" ]; then
    source "$HOME/mambaforge/etc/profile.d/conda.sh"
elif command -v conda &> /dev/null; then
    eval "$(conda shell.bash hook)"
else
    echo "エラー: conda が見つかりません。"
    exit 1
fi

# 環境をアクティベート
conda activate "$ENV_NAME" 2>/dev/null || {
    echo "エラー: 仮想環境 '$ENV_NAME' が見つかりません。"
    echo "先に ./setup_mac.sh を実行してください。"
    exit 1
}

# 引数のパース
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-7860}"
SHARE="${SHARE:-false}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            HOST="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --share)
            SHARE="true"
            shift
            ;;
        *)
            echo "不明なオプション: $1"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}設定:${NC}"
echo "  ホスト: $HOST"
echo "  ポート: $PORT"
echo "  共有リンク: $SHARE"
echo ""

# Web UI を起動
cd "$SCRIPT_DIR"
python -m ui.app --host "$HOST" --port "$PORT" $([ "$SHARE" = "true" ] && echo "--share")
