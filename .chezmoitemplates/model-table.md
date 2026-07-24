{{- if not (hasKey . "grokSelector") }}{{ fail "model-table.md: grokSelector is required" }}{{ end -}}
{{- if not (hasKey . "glmStart") }}{{ fail "model-table.md: glmStart is required" }}{{ end -}}
| Model | Selector | Start | Cost | Intelligence | Taste | Vision |
|---|---|---:|---:|---:|---:|---|
| GPT-5.6 Sol | `openai-codex/gpt-5.6-sol` | medium | 4 | 9 | 6 | yes |
| Fable 5 | `anthropic/claude-fable-5` | high | 5 | 9 | 9 | yes |
| Opus 5 | `anthropic/claude-opus-5` | high | 5 | 8 | 8 | yes |
| Sonnet 5 | `anthropic/claude-sonnet-5` | medium | 5 | 5 | 7 | yes |
| Grok 4.5 | `{{ .grokSelector }}` | high | 3 | 7 | 6 | yes |
| GLM-5.2 | `ollama/glm-5.2:cloud` | {{ .glmStart }} | 2 | 6 | 7 | no |
