---
name: Accessible Workforce
colors:
  surface: '#f8f9ff'
  surface-dim: '#cfdbec'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#eef4ff'
  surface-container: '#e4efff'
  surface-container-high: '#dde9fb'
  surface-container-highest: '#d7e4f5'
  on-surface: '#101d29'
  on-surface-variant: '#42474e'
  inverse-surface: '#25313f'
  inverse-on-surface: '#e9f1ff'
  outline: '#72777e'
  outline-variant: '#c2c7ce'
  surface-tint: '#396285'
  primary: '#013758'
  on-primary: '#ffffff'
  primary-container: '#234e70'
  on-primary-container: '#97bfe6'
  inverse-primary: '#a2cbf3'
  secondary: '#526070'
  on-secondary: '#ffffff'
  secondary-container: '#d5e4f7'
  on-secondary-container: '#586676'
  tertiary: '#003c23'
  on-tertiary: '#ffffff'
  tertiary-container: '#005634'
  on-tertiary-container: '#7eca9d'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#cde5ff'
  primary-fixed-dim: '#a2cbf3'
  on-primary-fixed: '#001d32'
  on-primary-fixed-variant: '#1e4a6c'
  secondary-fixed: '#d5e4f7'
  secondary-fixed-dim: '#b9c8da'
  on-secondary-fixed: '#0e1d2a'
  on-secondary-fixed-variant: '#3a4857'
  tertiary-fixed: '#a6f3c4'
  tertiary-fixed-dim: '#8ad7a9'
  on-tertiary-fixed: '#002111'
  on-tertiary-fixed-variant: '#005231'
  background: '#f8f9ff'
  on-background: '#101d29'
  surface-variant: '#d7e4f5'
typography:
  headline-lg:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  title-lg:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 30px
    letterSpacing: 0em
  title-md:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: 0em
  title-sm:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 26px
    letterSpacing: 0.01em
  body-lg:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
    letterSpacing: 0.01em
  body-md:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: 0.01em
  label-lg:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 22px
    letterSpacing: 0.02em
  label-md:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.03em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1.25rem
  space-xs: 0.5rem
  space-sm: 0.75rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system targets an operational workforce demographic, specifically prioritizing mature and elderly field workers who require unambiguous visual hierarchy, immediate touch legibility, and physical ease of interaction. The aesthetic balances utilitarian corporate clarity with radical accessibility. 

The core visual style is **High-Contrast Utilitarianism**:
- Zero superficial decoration, optical blur, or distracting micro-gradients.
- Immediate readability under varying lighting conditions (e.g., outdoor direct sun, harsh industrial indoor lighting).
- Direct, predictable interactive signifiers designed to reduce cognitive fatigue and eliminate motor-control errors.
- Purposeful sizing optimized for Android handheld viewports (393x852) with high-density physical tap feedback.

## Colors

The palette enforces strict WCAG AAA contrast compliance across all text and state boundaries against a pale, glare-reducing canvas.

- **Primary Canvas**: `#F5F6F8` provides a low-strain, soft background that prevents display glare without dropping contrast.
- **Surface / Card Background**: Pure `#FFFFFF`, delivering clean isolation from the canvas.
- **Main Text**: `#202C39` (Deep Charcoal Blue) provides exceptional contrast (> 11:1 on white surfaces) without the harsh optical vibrating effect of pure `#000000`.
- **Secondary / Supporting Text**: `#526070`, calibrated to meet AAA compliance for large text and robust AA (over 5.5:1) for standard text.
- **Structural Outlines**: `#E3E7EB` sets clear bounding boxes for interactive containers.
- **Functional Semantics (WCAG Verified against `#FFFFFF` / `#F5F6F8`)**:
  - **Status Approved**: `#26734D` (Deep Green)
  - **Status Pending**: `#9A6500` (High-Density Amber)
  - **Status Rejected**: `#B42332` (Crimson Red)
  - **Status Locked**: `#7D3038` (Deep Maroon)

Never rely on color alone to convey status. Every semantic state must pair a badge color with an explicit textual label and high-contrast icon.

## Typography

The design system exclusively adopts **Atkinson Hyperlegible Next** across all text hierarchies. Its letterforms feature distinctive shapes for easily confused glyphs (such as '1', 'l', and 'I', or '0' and 'O'), reducing reading friction for mature eyes and users with low visual acuity.

- Headings (`headline-lg`, `headline-md`) are restricted to primary view titles and large modal headers.
- Section titles (`title-lg`, `title-md`) establish clear modular boundaries.
- Task items (`title-sm`) provide bold, immediate scannability.
- Body text is set at a generous base size (`body-lg` at 18px and `body-md` at 16px) with an open 1.5x proportional line height.
- Minimum allowed font size anywhere in the UI is 14px (`label-md`), used strictly for auxiliary metadata, timestamps, and input hints.

## Layout & Spacing

Layouts are optimized for the Android viewport base width of **393dp** (e.g., 393x852).

- **Grid Architecture**: Single-column vertical stack. Multi-column layouts on mobile viewports are strictly prohibited to avoid horizontal scanning strain and accidental clicks.
- **Touch Target Integrity**: Primary action elements must satisfy a minimum height and width of **56dp** (surpassing the standard 48dp Android requirement) with a physical separation gap of at least 8dp (`space-xs`) between adjacent targets.
- **Canvas Margins**: Fixed `1.25rem` (20dp) margins ensure interactive elements do not clash with hardware edges or Android gesture zones.
- **Component Breathing Room**: Stacked elements use `space-md` (16dp) standard gaps. Major sections separate using `space-lg` (24dp) or `space-xl` (32dp).

## Elevation & Depth

To maintain visual clarity, this design system avoids diffuse shadows and multi-layered skeuomorphic illusions:

- **Flat Container Architecture**: Hierarchy is established through background value differences (`#F5F6F8` canvas versus `#FFFFFF` container) paired with explicit `1.5px` solid borders in `#E3E7EB`.
- **Active State Elevation**: When an item receives focus or elevation is required (such as sticky bottom action sheets), use a single, high-contrast, low-spread drop shadow:
  - `box-shadow: 0 4px 12px rgba(32, 44, 57, 0.08);`
- **Modal Overlays**: Backdrop scrim uses `rgba(32, 44, 57, 0.60)` to provide a stark focus filter over background clutter.

## Shapes

The design uses a **Soft (Level 1)** corner radius philosophy. 

- Interactive inputs, cards, and buttons use a controlled `4px` to `8px` corner radius.
- Excessively rounded corners and pill shapes are deliberately avoided: sharp, structured forms help elderly users discern the true boundaries of clickable surfaces.

## Components

### Buttons
- **Primary Buttons**: Fixed minimum height of **56dp**. Background `#234E70`, text `#FFFFFF`, font `label-lg` (16px bold). Border radius `6px`. Full-width layout within cards and bottom sheets.
- **Secondary Buttons**: 56dp height. Background `#FFFFFF`, border `2px solid #234E70`, text `#234E70`.
- **Destructive Buttons**: 56dp height. Background `#B42332`, text `#FFFFFF`.
- **Disabled State**: Background `#E3E7EB`, text `#526070`. Contrast must remain legible even when inactive.

### Cards & Work Items
- Background `#FFFFFF`, border `1.5px solid #E3E7EB`, radius `8px`, padding `1.25rem` (20dp).
- Contains three distinct zones:
  1. Top metadata row: Task ID + Status Chip.
  2. Main body: Task title (`title-sm`, 18px-20px), secondary descriptive text (`body-md`, 16px).
  3. Action footer: Direct 56dp action trigger.

### Status Chips & Badges
- Minimum height **32dp** with `8px` horizontal padding.
- Built using high-contrast solid backgrounds with white text, or pale tint backgrounds (12% opacity) paired with a bold `1.5px` border matching the status color and `#202C39` bold text.
- Must include both an icon glyph (e.g., checkmark, clock, cross, padlock) and textual status copy.

### Text Inputs
- Fixed height **56dp**, background `#FFFFFF`, border `2px solid #526070` (resting) and `2.5px solid #234E70` (focused).
- Input labels must remain permanently anchored above the field in `label-md` (14px) and never use floating placeholder patterns that vanish upon interaction.

### Checkboxes & Radio Controls
- Target frame minimum size **28x28dp**, centered within a **56x56dp** invisible touch capture zone.
- Border `2px solid #202C39`. When checked, fully filled with `#234E70` and a high-contrast white glyph.

### Lists
- Separator line `1.5px solid #E3E7EB`.
- Vertical row padding minimum `16dp` above and below content to guarantee target height of at least 64dp per row.