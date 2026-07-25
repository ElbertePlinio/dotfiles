{{- if not (hasKey . "grokSelector") }}{{ fail "model-table.md: grokSelector is required" }}{{ end -}}
{{- if not (hasKey . "glmStart") }}{{ fail "model-table.md: glmStart is required" }}{{ end -}}
| Model | Selector | Start | Cost | Intelligence | Taste | Calibration | Vision |
|---|---|---:|---:|---:|---:|---:|---|
| GPT-5.6 Sol | `openai-codex/gpt-5.6-sol` | medium | 4 | 9 | 6 | 8 | yes |
| Fable 5 | `anthropic/claude-fable-5` | high | 6 | 9 | 9 | 9 | yes |
| Opus 5 | `anthropic/claude-opus-5` | high | 5 | 9 | 8 | 9 | yes |
| Grok 4.5 | `{{ .grokSelector }}` | high | 3 | 7 | 5 | 3 | yes |
| GLM-5.2 | `ollama/glm-5.2:cloud` | {{ .glmStart }} | 2 | 7 | 6 | 4 | no |
| Kimi K3 | _pending — see routing reference_ | provider default | 3 | 7 | 8 | 5 | yes |
