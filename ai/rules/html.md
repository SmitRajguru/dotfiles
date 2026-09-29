# HTML output

Every HTML page that is generated or updated, including visual-explainer pages,
data visualisations and standalone pages, needs a light and dark theme toggle:

- a visible control that switches between the two themes;
- an initial theme taken from `prefers-color-scheme`, which the control then
  overrides;
- colours defined once, as CSS custom properties, so that both themes stay
  legible;
- inline CSS and script only, so that the toggle works offline.

Add the toggle even when the template of the generating skill has none.
