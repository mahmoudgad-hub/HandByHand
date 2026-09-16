# Staff screen template

The shared layout is implemented in `web/ops/src/styles/ops-page-template.css`, loaded after the existing reference styles in both the ops build and test targets.

## Placement

- Page identity is at the right in RTL; page actions are grouped at the left.
- Tabs and search/filter controls follow the page header, before results.
- Form save/confirm and cancel actions appear in a footer after the fields. Use primary action then cancel in DOM order. Modal footers remain outside their scrolling body.
- Record actions remain beside the affected record. Publishing, consent, archive and other contextual workflows keep their existing permission checks.
- On small screens, page actions wrap below the identity and form buttons expand to fit.

## Reuse

Existing screens use `hbh-pagehead`, `hbh-pagehead__left`, `hbh-pagehead__title`, `hbh-pagehead__sub` and `hbh-pagehead__actions`. ResourceScreen and DayScreen provide this structure for their configured routes.

Custom details use `ops-page-header`, `ops-page-breadcrumb`, `ops-page-identity`, `ops-page-title` and `ops-page-actions`. Use `ops-filterbar` for custom filter rows, and `ops-form-actions` for inline form footers. Dialogs retain `hbh-sheet__foot` and receive the same footer styling.

```html
<header class="ops-page-header">
  <div class="ops-page-identity">
    <h1 class="ops-page-title">{{ titleKey | t }}</h1>
    <p class="hbh-pagehead__sub">{{ subtitleKey | t }}</p>
  </div>
  <div class="ops-page-actions"><!-- Page actions --></div>
</header>
<!-- Tabs, filters, results or form fields -->
<footer class="ops-form-actions"><!-- Save/confirm, then cancel --></footer>
```

Do not use page action classes for field grids. Do not move buttons visually with CSS order: keyboard and reading order must follow the DOM. Login, public/parent pages and printable child cards have separate layouts.
