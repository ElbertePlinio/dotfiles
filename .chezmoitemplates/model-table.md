{{- if not (hasKey . "grokSelector") }}{{ fail "model-table.md: grokSelector is required" }}{{ end -}}
| Model | Selector | Start | Cost | Intelligence | Taste | Calibration | Vision |
|---|---|---:|---:|---:|---:|---:|---|
| GPT-5.6 Sol | `openai-codex/gpt-5.6-sol` | medium | 4 | 9 | 6 | 8 | yes |
| Fable 5 | `anthropic/claude-fable-5` | high | 6 | 9 | 9 | 9 | yes |
| Opus 5 | `anthropic/claude-opus-5` | high | 5 | 9 | 8 | 9 | yes |
| Grok 4.5 | `{{ .grokSelector }}` | high | 3 | 7 | 5 | 3 | yes |
| Kimi K3 | `ollama/kimi-k3:cloud` | provider default | 4 | 8 | 8 | 4 | yes |
