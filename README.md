# Qwen3-TTS-Mac-GeneLab

Apple Silicon Mac に最適化された Qwen3-TTS フォーク。
MLX ネイティブ推論と PyTorch MPS のデュアルエンジンアーキテクチャにより、
Mac 上で最高のTTS体験を提供します。

## 特徴

- **デュアルエンジン**: MLX (Apple 最適化) と PyTorch MPS を自動切替
- **日本語GUI**: 完全日本語対応の Gradio Web UI
- **Whisper連携**: Voice Clone 時に参照音声を自動書き起こし
- **メモリ最適化**: Unified Memory 管理、4bit/8bit 量子化対応
- **ワンコマンドセットアップ**: setup_mac.sh で環境構築完了

## 動作環境

| 項目 | 要件 |
|------|------|
| チップ | Apple Silicon (M1/M2/M3/M4) |
| RAM | 16GB以上（1.7Bモデル推奨: 32GB+） |
| OS | macOS 14 Sonoma 以降 |
| Python | 3.10〜3.12 |

## クイックスタート

```bash
# リポジトリをクローン
git clone https://github.com/hiroki-abe-58/Qwen3-TTS-Mac-GeneLab.git
cd Qwen3-TTS-Mac-GeneLab

# セットアップ（初回のみ）
chmod +x setup_mac.sh && ./setup_mac.sh

# Web UI を起動
./run.sh
```

ブラウザで http://localhost:7860 を開く。

## Web UI の機能

### 1. カスタムボイス
9種類のプリセットスピーカーから選択して音声を生成。感情指示も可能。

| スピーカー | 説明 |
|-----------|------|
| チェルシー (Chelsie) | 明るい若い女性の声 |
| イーサン (Ethan) | 穏やかな若い男性の声 |
| エイデン (Aiden) | 渋みのある男性の声 |
| ベラ (Bella) | 温かみのある女性の声 |
| ヴィヴィアン (Vivian) | エネルギッシュな女性の声 |
| ルーカス (Lucas) | 明るい若い男性の声 |
| エレノア (Eleanor) | 上品な女性の声 |
| アレクサンダー (Alexander) | 力強い男性の声 |
| セレナ (Serena) | 癒やしの女性の声 |

### 2. ボイスデザイン
テキストで声の特徴を説明し、その特徴に合った声を生成。

```
例: "A calm middle-aged male voice with a warm, reassuring tone."
```

### 3. ボイスクローン
わずか3秒の参照音声から、その声で新しいテキストを読み上げ。
Whisper による自動書き起こし機能搭載。

### 4. 設定
エンジン選択、メモリモニター、モデル管理。

## MLX vs PyTorch MPS

| 項目 | MLX (デフォルト) | PyTorch MPS |
|------|-----------------|-------------|
| 推論速度 | 高速 | 中速 |
| メモリ効率 | 優秀 (量子化対応) | 普通 |
| Voice Clone | 対応 | float32必須だが安定 |
| 量子化 | 4bit/8bit | 非対応 |

## ディレクトリ構造

```
Qwen3-TTS-Mac-GeneLab/
├── setup_mac.sh          # セットアップスクリプト
├── run.sh                # 起動スクリプト
├── mac/                  # Mac 固有のコード
│   ├── engine.py         # デュアルエンジン管理
│   ├── device_utils.py   # デバイス検出
│   ├── memory_manager.py # メモリ管理
│   ├── whisper_transcriber.py # Whisper 書き起こし
│   └── benchmark.py      # パフォーマンス計測
├── ui/                   # Gradio Web UI
│   ├── app.py            # メインアプリ
│   ├── components/       # タブコンポーネント
│   └── i18n/             # 多言語対応
├── qwen_tts/             # 元の TTS コード
└── examples/             # サンプルコード
```

## CLI での使用

```python
from mac import DualEngine, TaskType

# エンジン初期化
engine = DualEngine()

# CustomVoice で生成
result = engine.generate(
    text="こんにちは、今日はいい天気ですね。",
    task_type=TaskType.CUSTOM_VOICE,
    language="Japanese",
    speaker="Vivian",
)

# 音声を保存
import soundfile as sf
sf.write("output.wav", result.audio, result.sample_rate)
```

## 技術的な注意事項

### MPS の既知の制約

1. **Voice Clone は float32 必須**: float16 だと `RuntimeError: probability tensor contains either inf, nan or element < 0`
2. **FlashAttention 2 は Mac 非対応**: 常に SDPA を使用
3. **BFloat16**: M1/M2 では不安定な場合あり → float16 推奨

### 環境変数

セットアップスクリプトが自動設定しますが、手動で設定する場合:

```bash
export PYTORCH_ENABLE_MPS_FALLBACK=1
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.7
export TOKENIZERS_PARALLELISM=false
```

### トラブルシューティング

| 問題 | 解決策 |
|------|--------|
| SoX エラー | `brew install sox` |
| メモリ不足 | 他のアプリを閉じるか、8bit/4bit 量子化モデルを使用 |
| 生成が遅い | MLX エンジンを使用（設定タブで AUTO を選択） |
| Voice Clone エラー | PyTorch MPS エンジンが自動選択されていることを確認 |

## メモリ使用量の目安

| モデル | dtype | サイズ |
|--------|-------|--------|
| 1.7B | bf16 | ~3.4 GB |
| 1.7B | 8bit | ~1.7 GB |
| 1.7B | 4bit | ~0.9 GB |
| 0.6B | bf16 | ~1.2 GB |

## 謝辞

- [QwenLM/Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) — 元リポジトリ
- [Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio) — MLX 音声ライブラリ
- [mlx-community](https://huggingface.co/mlx-community) — 量子化済みモデル

## ライセンス

Apache License 2.0（元リポジトリと同一）

---

## English

For English documentation, see [README_EN.md](README_EN.md).
