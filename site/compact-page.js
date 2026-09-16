(function () {
  'use strict';
  // Deep links retain access to details that are collapsed by default.
  function reveal() {
    var target = document.getElementById(location.hash.slice(1));
    if (!target) return;
    var ancestor = target.parentElement;
    while (ancestor) {
      if (ancestor.tagName === 'DETAILS') ancestor.open = true;
      ancestor = ancestor.parentElement;
    }
    requestAnimationFrame(function () { target.scrollIntoView({ block: 'start' }); });
  }
  window.addEventListener('hashchange', reveal);
  window.addEventListener('load', reveal, { once: true });
  if (location.hash) reveal();
}());
