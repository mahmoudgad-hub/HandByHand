(function () {
  'use strict';
  // Reuse the rendered, normalized business contacts.
  [['whatsapp','contactWhatsapp'],['phone','contactPhone']].forEach(function (pair) {
    var source = document.getElementById(pair[1]);
    var link = document.querySelector('[data-mobile-contact="' + pair[0] + '"]');
    if (source && link && source.getAttribute('href')) {
      link.href = source.href;
      link.hidden = false;
    }
  });
  var apply = document.querySelector('.mobile-evaluate');
  var source = document.querySelector('header [data-portal="apply"]');
  if (apply && source) apply.href = source.href;
}());
