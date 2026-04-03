# Design System

## Identity

FALCON's visual identity draws from the MCU — specifically Sam Wilson's Falcon suit and Tony Stark's Iron Man tech aesthetic. The result is a dark, futuristic HUD feel with purple and teal as the core palette.

The name FALCON comes from Iron Man's Falcon. The arc reactor motif appears throughout the UI as a teal glow element — loading states, active indicators, and the logo's chest piece.

## Color Palette

### Dark Theme (Default)

| Role | Color | OKLCH | Hex Approx | Usage |
|---|---|---|---|---|
| Base 100 | Deep blue-gray | `oklch(18% 0.02 280)` | `#1a1625` | Main background |
| Base 200 | Darker blue-gray | `oklch(14.5% 0.025 280)` | `#13101f` | Sidebar, cards |
| Base 300 | Darkest | `oklch(11% 0.03 280)` | `#0d0a18` | Borders, dividers |
| Primary | Purple | `oklch(58% 0.24 280)` | `#7C3AED` | Buttons, user messages, active states |
| Secondary | Teal | `oklch(72% 0.15 175)` | `#14B8A6` | Streaming indicators, tool badges |
| Accent | Bright teal | `oklch(78% 0.16 175)` | `#2DD4BF` | Glows, highlights, arc reactor |

### Light Theme

Same purple/teal accent colors on clean near-white backgrounds. Available via the theme toggle (system/light/dark).

## Logo

Two SVG versions:

- **`logo.svg`** (512x512) — Full falcon with spread wings, arc reactor chest piece, HUD arc frame
- **`falcon-icon.svg`** (64x64) — Compact version for sidebar and small contexts

### Logo Elements

- **Wings**: Purple-to-teal gradient sweep with teal detail lines (flight feather structure)
- **Body**: Purple gradient (lighter at head, darker at tail)
- **Head crest**: Sharp angular point, light purple
- **Eye visor**: Teal diamond shape with glow filter (Stark-tech inspired)
- **Arc reactor**: Concentric teal circles on chest with white hot center and directional tick marks
- **Tail feathers**: Angular, tech-styled in dark purple
- **HUD arc**: Subtle curved line below the figure, purple-teal-purple gradient

## Custom CSS Classes

### Glow Effects

| Class | Effect |
|---|---|
| `falcon-glow` | Dual purple/teal box shadow — use on modals, hero elements |
| `falcon-glow-teal` | Teal-only glow — streaming states, tool indicators |
| `falcon-glow-purple` | Purple-only glow — primary actions |
| `falcon-pulse` | Arc reactor pulsing animation — loading states, active streaming |
| `falcon-border-glow` | Border that transitions to glow on hover/focus — inputs, cards |

### Text & Typography

| Class | Effect |
|---|---|
| `falcon-gradient-text` | Purple-to-teal gradient text — "FALCON" branding only |
| `falcon-prose` | Styled markdown content — code blocks get dark bg, inline code is teal |
| `falcon-cursor` | Appends blinking teal block cursor — streaming response text |

### Layout & Animation

| Class | Effect |
|---|---|
| `falcon-scrollbar` | Thin custom scrollbar matching dark theme |
| `falcon-sidebar-item` | Left-border highlight: transparent idle, purple hover, teal active |
| `falcon-message-in` | Slide-up fade-in animation for new messages |
| `falcon-input` | Focus style: purple border + teal outer glow ring |

## UI Components

### Sidebar

- **Collapsible**: Click falcon icon to toggle between 72px (collapsed) and 288px (expanded)
- **Logo area**: Falcon icon + gradient "FALCON" text + theme toggle
- **New Chat button**: Primary purple, full-width, scales on hover
- **Thread list**: Each thread shows title, model name, folder-scope indicator. Archive button appears on hover. Active thread has teal left border
- **User footer**: Avatar circle (first letter of email, purple bg), email, logout icon

### Chat Area

- **Header**: Thread title, model badge (purple pill with CPU icon), scoped paths badge (teal pill with folder icon), system prompt badge (accent pill), streaming indicator (pulsing teal dot)
- **Messages**: Max-width 768px centered
  - **User**: Right-aligned purple bubble with rounded corners (bottom-right less rounded)
  - **Assistant**: Left-aligned, falcon icon avatar + gray bubble (top-left less rounded)
  - **Tool**: Left-aligned, wrench icon + monospace pre block in darker card
  - **System**: Centered, italic, low opacity
- **Streaming**: Bouncing teal dots while waiting, then content with blinking cursor. Falcon avatar pulses with arc reactor animation
- **Input**: Rounded pill container with glow-on-focus border. Send button is purple circle that scales on hover/press. Disabled state is low opacity

### Empty State

- Full logo with purple/teal blur behind it
- Gradient "FALCON" text
- Description paragraph
- Two quick-start cards with hover glow: "New Chat" (purple icon) and "Code Agent" (teal icon)
- Available model count with pills showing first 6 model names

### Auth Pages

- Full-page centered layout with floating gradient orbs (purple top-left, teal bottom-right)
- Logo + gradient text header
- Glassmorphism content card: semi-transparent background, blurred backdrop, subtle border with glow
- Consistent across login, register, confirm, and settings pages
- "Powered by FALCON AI" footer text

### New Thread Modal

- Backdrop blur overlay
- Card with `falcon-glow` shadow
- Header with purple plus icon
- Model selector dropdown
- System prompt textarea
- Scoped paths textarea (monospace, with shield icon helper text)
- Collapsible advanced parameters (temperature, max tokens, top P)
- Cancel (ghost) + Create Chat (primary with sparkles icon) buttons

## Animations

| Animation | Duration | Easing | Usage |
|---|---|---|---|
| `messageIn` | 200ms | ease-out | New messages appearing |
| `cursorBlink` | 800ms | step | Streaming text cursor |
| `reactorPulse` | 2s | ease-in-out | Loading indicators, active streaming avatar |
| Sidebar toggle | 300ms | ease-in-out | Sidebar collapse/expand |
| Button scale | 200ms | default | Hover: 1.02x, Active: 0.98x |

## Theme Toggle

Three options: System (auto-detect), Light, Dark. Persisted to `localStorage` under `phx:theme`. Default is dark. The toggle uses the existing DaisyUI theme toggle component with system/sun/moon icons.
