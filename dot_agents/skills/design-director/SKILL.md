---
name: design-director
description: Direct significant user-facing UI and UX work with one accountable aesthetic owner. Use when creating or materially changing an app, site, screen, flow, component system, interaction, motion, responsive layout, or visual design; when starting a greenfield project; when improving an unfamiliar or inconsistent interface; or when reproducing references. Covers product UI, desktop/mobile apps, dashboards, marketing surfaces, redesigns, and focused feature work. Skip pure backend work and tiny token-aligned fixes with no design judgment.
---

# Design Director

Give one model clear responsibility for the design direction, then keep implementation and review anchored to a written contract.

## Scale the process

- **Light:** A small UI fix already determined by the repo's tokens or components. Inspect the local pattern, make the change, and capture narrow proof. Do not create ceremony.
- **Directed:** Any work with meaningful hierarchy, layout, interaction, motion, responsive, or aesthetic choices. Use the complete workflow below.

If a more specific design skill applies, whether repo-local or surface-specific, use it as an overlay. It supplies specialized constraints; this skill still owns the general workflow and prompt contract.

## Directed workflow

### 1. Audit before proposing

Read the brief and inspect the actual product surface. For greenfield work, inspect the closest useful analogues and platform conventions instead. Gather the relevant screenshots or recordings, current components and tokens, nearby flows, content, platform constraints, accessibility expectations, and validation setup.

For external references, describe both:

- **Take:** the useful principles, such as hierarchy, pacing, density, spatial rhythm, or interaction behavior.
- **Reject:** elements that conflict with the product, brand, platform, or user job.

Do not reduce a reference to colors and rounded corners. Do not copy distinctive brand assets or protected expression.

Classify the task using [modes.md](references/modes.md).

For landing pages, portfolios, and marketing redesigns, also apply the anti-slop guardrails in [marketing-antislop.md](references/marketing-antislop.md); pull only what fits the brief.

### 2. Appoint one design lead

For directed work, select exactly one model as the **design lead** for this task. When model orchestration is available, choose from the available models based on the task's visual, product, vision, context, and tool needs. Do not permanently assign UI work to one model.

Design-lead selection ranks taste above intelligence above cost, inverting the general preference order — this is the one seat where the artifact's quality is the whole deliverable. Weigh taste against the actual surface: a candidate whose taste is strongest on greenfield visual work is not automatically the lead for a change inside an established design system.

The design lead must be able to inspect rendered output. Never select a text-only model as design lead.

The design lead owns:

- information hierarchy and composition;
- interaction and motion character;
- visual language inside existing brand constraints;
- aesthetic tradeoffs and reference interpretation;
- approval of the final visual result.

Other models may implement or review correctness, but they do not form an aesthetic committee. If orchestration is unavailable, the active model is the design lead. Record the owner in the contract. If ownership must change, name the replacement and re-lock the contract explicitly.

### 3. Prototype before locking (optional)

When the visual direction is genuinely unresolved — no dominant reference, conflicting product goals, or the user asks to explore — the design lead may produce 2–4 structurally different, time-boxed throwaway variants before locking the contract. Rules:

- Variants are throwaway and clearly marked as such; one command to run, no persistence, no polish, no tests.
- Variants must differ in structure (hierarchy, layout, information order), not only in decoration.
- The same design lead judges the variants against the brief and picks a direction; the user gets a short comparison, not a menu of screenshots to art-direct.
- Fold the chosen direction into the contract, then delete the variants or park them out of main.

Skip this step whenever the direction is already determined by the repo's system or the brief. Do not use it to defer accountability.

### 4. Lock the prompt contract

Read and fill [prompt-contract.md](references/prompt-contract.md). Keep it in the task plan, issue, or implementation handoff; do not add it to the product repo unless it has durable value.

The design lead makes aesthetic decisions without asking the user to art-direct every detail. Ask only when missing product intent, brand direction, or scope would materially change the result. Mark the contract `locked` before implementation begins.

### 5. Implement without reinterpretation

Give the implementer the locked contract, relevant source files, references, and validation targets. Preserve the repo's architecture and component patterns.

Implementation may solve technical details, but it must not silently change hierarchy, density, motion, typography, composition, or interaction intent. Route necessary design deviations back to the design lead and update the contract.

### 6. Prove the result

Exercise the real surface, not an isolated happy-path component. Capture the important states and target sizes. For interaction or motion work, inspect the transition in motion as well as static endpoints. Respect reduced motion.

Use [acceptance.md](references/acceptance.md) proportionally. Functional tests do not replace visual inspection.

### 7. Return to the same design lead

The design lead compares the implementation with the locked contract and references, identifies the few highest-impact gaps, answers "could this be less?" explicitly (`accepted` requires "no" or a named reason), and returns one of:

- `accepted`;
- `accepted with named follow-up`;
- `revise` with concrete visual changes.

Iterate until accepted or a real blocker is documented. A different reviewer may check accessibility, regressions, or code quality, but final aesthetic acceptance remains with the named design lead.

## Guardrails

- Existing product systems beat generic taste. Improve deliberately; do not erase coherent local character.
- Design the information and interaction before decorating the container.
- Motion must explain change, preserve orientation, confirm action, or establish intentional pacing.
- Include empty, loading, error, disabled, focus, hover, and destructive states when applicable.
- Prefer a few strong decisions over many ornamental effects.
- Minimal by default: one element per job; run a subtraction pass; nothing empty on screen; silent transitions.
- Never claim visual acceptance without viewing representative rendered output.
