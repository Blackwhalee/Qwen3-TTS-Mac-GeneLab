#!/bin/bash
# Qwen3-TTS-Mac-GeneLab セットアップスクリプト
# Apple Silicon Mac 専用

set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ヘッダー表示
echo ""
echo "=================================================="
echo "  Qwen3-TTS-Mac-GeneLab セットアップ"
echo "  Apple Silicon Mac 最適化"
echo "=================================================="
echo ""

# アーキテクチャ検証
log_info "アーキテクチャを確認中..."
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    log_error "このスクリプトは Apple Silicon Mac (arm64) 専用です。"
    log_error "検出されたアーキテクチャ: $ARCH"
    exit 1
fi
log_success "Apple Silicon (arm64) を検出しました。"

# macOS バージョン確認
log_info "macOS バージョンを確認中..."
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [ "$MACOS_MAJOR" -lt 14 ]; then
    log_warning "macOS $MACOS_VERSION を検出。macOS 14 (Sonoma) 以降を推奨します。"
else
    log_success "macOS $MACOS_VERSION を検出しました。"
fi

# Homebrew 確認・インストール
log_info "Homebrew を確認中..."
if ! command -v brew &> /dev/null; then
    log_warning "Homebrew が見つかりません。インストールします..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
log_success "Homebrew が利用可能です。"

# Homebrew パッケージインストール
log_info "必要なシステムパッケージをインストール中..."
BREW_PACKAGES="sox ffmpeg portaudio"
for pkg in $BREW_PACKAGES; do
    if ! brew list "$pkg" &> /dev/null; then
        log_info "$pkg をインストール中..."
        brew install "$pkg"
    else
        log_success "$pkg は既にインストールされています。"
    fi
done

# Miniforge/Conda 確認
log_info "Conda/Miniforge を確認中..."
CONDA_FOUND=false

# conda コマンドの存在確認
if command -v conda &> /dev/null; then
    CONDA_FOUND=true
    log_success "Conda が見つかりました。"
elif [ -f "$HOME/miniforge3/bin/conda" ]; then
    CONDA_FOUND=true
    eval "$($HOME/miniforge3/bin/conda shell.bash hook)"
    log_success "Miniforge3 が見つかりました。"
elif [ -f "$HOME/mambaforge/bin/conda" ]; then
    CONDA_FOUND=true
    eval "$($HOME/mambaforge/bin/conda shell.bash hook)"
    log_success "Mambaforge が見つかりました。"
elif [ -f "/opt/homebrew/Caskroom/miniforge/base/bin/conda" ]; then
    CONDA_FOUND=true
    eval "$(/opt/homebrew/Caskroom/miniforge/base/bin/conda shell.bash hook)"
    log_success "Homebrew Miniforge が見つかりました。"
fi

if [ "$CONDA_FOUND" = false ]; then
    log_warning "Conda/Miniforge が見つかりません。Miniforge をインストールします..."
    brew install miniforge
    eval "$(/opt/homebrew/Caskroom/miniforge/base/bin/conda shell.bash hook)"
    conda init zsh
    log_success "Miniforge をインストールしました。"
fi

# 仮想環境名
ENV_NAME="qwen3-tts-mac-genelab"

# 既存環境の確認
log_info "仮想環境 '$ENV_NAME' を確認中..."
if conda env list | grep -q "^$ENV_NAME "; then
    log_warning "環境 '$ENV_NAME' は既に存在します。"
    read -p "既存の環境を削除して再作成しますか？ (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "環境を削除中..."
        conda env remove -n "$ENV_NAME" -y
    else
        log_info "既存の環境を使用します。"
    fi
fi

# 仮想環境作成
if ! conda env list | grep -q "^$ENV_NAME "; then
    log_info "Python 3.11 仮想環境を作成中..."
    conda create -n "$ENV_NAME" python=3.11 -y
fi

# 仮想環境をアクティベート
log_info "仮想環境をアクティベート中..."
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$ENV_NAME"

# pip アップグレード
log_info "pip をアップグレード中..."
pip install --upgrade pip

# PyTorch (MPS 対応版) インストール
log_info "PyTorch (Apple Silicon MPS 対応) をインストール中..."
pip install torch torchvision torchaudio

# MLX 関連パッケージインストール
log_info "MLX 関連パッケージをインストール中..."
pip install mlx mlx-lm

# mlx-audio インストール
log_info "mlx-audio をインストール中..."
pip install mlx-audio

# メインパッケージの依存関係インストール
log_info "qwen-tts 依存関係をインストール中..."
pip install transformers accelerate librosa soundfile einops

# Mac 固有の依存関係インストール
log_info "Mac 固有の依存関係をインストール中..."
pip install psutil gradio>=4.0

# numpy バージョン固定（互換性のため）
log_info "numpy バージョンを調整中..."
pip install "numpy<2"

# onnxruntime インストール（Python 3.11 対応）
log_info "onnxruntime をインストール中..."
pip install onnxruntime

# プロジェクトを開発モードでインストール
log_info "qwen-tts をインストール中..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pip install -e "$SCRIPT_DIR"

# 環境変数の設定ファイル作成
log_info "環境変数設定ファイルを作成中..."
cat > "$SCRIPT_DIR/.env" << 'EOF'
# Qwen3-TTS-Mac-GeneLab 環境変数
export PYTORCH_ENABLE_MPS_FALLBACK=1
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.7
export TOKENIZERS_PARALLELISM=false
export HF_HOME="${HOME}/.cache/huggingface"
EOF

log_success "環境変数設定ファイルを作成しました: $SCRIPT_DIR/.env"

# 動作確認テスト
log_info "動作確認テストを実行中..."

python << 'PYTEST'
import sys
print(f"Python バージョン: {sys.version}")

# PyTorch MPS 確認
try:
    import torch
    print(f"PyTorch バージョン: {torch.__version__}")
    if torch.backends.mps.is_available():
        print("MPS (Metal Performance Shaders): 利用可能")
    else:
        print("MPS: 利用不可 (CPU にフォールバック)")
except ImportError as e:
    print(f"PyTorch インポートエラー: {e}")
    sys.exit(1)

# MLX 確認
try:
    import mlx.core as mx
    print(f"MLX: 利用可能")
except ImportError:
    print("MLX: 利用不可")

# mlx-audio 確認
try:
    import mlx_audio
    print(f"mlx-audio: 利用可能")
except ImportError:
    print("mlx-audio: 利用不可")

# Gradio 確認
try:
    import gradio as gr
    print(f"Gradio バージョン: {gr.__version__}")
except ImportError:
    print("Gradio: 利用不可")

print("\n動作確認テスト完了!")
PYTEST

echo ""
echo "=================================================="
log_success "セットアップ完了!"
echo "=================================================="
echo ""
echo "使い方:"
echo "  1. 仮想環境をアクティベート:"
echo "     conda activate $ENV_NAME"
echo ""
echo "  2. Web UI を起動:"
echo "     ./run.sh"
echo ""
echo "  3. ブラウザで http://localhost:7860 を開く"
echo ""
