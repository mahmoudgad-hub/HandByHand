/* =====================================================================
   Hand By Hand - Ops console, prototype behaviour
   File: html/hbh-ops.js

   Two jobs, and no third:
     1. sign in from the staff login page and land on the dashboard
     2. show each role only the menu entries its permissions allow

   NOTHING HERE IS A SECURITY CONTROL.

   Hiding a menu entry is not permission - it is tidiness. The real refusal
   is hbh.has_permission() and the row level security policies, and it
   happens on the server whether or not this file ran. A console user who
   types a URL by hand reaches the same server that would have refused them
   anyway. See CLAUDE.md: "إخفاء زر ليس ضابطًا".

   The role/permission map below is copied from db/seed/0002_rbac.sql and
   is the only copy of it outside the database. It exists because this is a
   static prototype with no /api/v1/me to ask. In the real console the
   permissions array from that endpoint replaces it, and this constant is
   deleted - it must never become a second definition of who may do what.
   ===================================================================== */
(function () {
  'use strict';

  var STORE = 'hbh.ops.role';

  /* Roles as seeded, with their Arabic labels from the same file. */
  var ROLES = {
    CENTER_ADMIN: {
      label: 'مدير المركز',
      user: 'م. محمد جاد',
      permissions: [
        'PORTAL.VIEW', 'CHILD.VIEW_ALL', 'CHILD.CREATE', 'CHILD.EDIT',
        'GUARDIAN.MANAGE', 'APPOINTMENT.BOOK', 'APPOINTMENT.CANCEL',
        'SESSION.START', 'SESSION.COMPLETE', 'REPORT.VIEW', 'REPORT.PUBLISH',
        'LIVE.VIEW', 'BILLING.VIEW', 'BILLING.MANAGE', 'REQUEST.MANAGE',
        'PLAN.MANAGE', 'CATALOG.MANAGE', 'STAFF.MANAGE'
      ]
    },
    RECEPTION: {
      label: 'استقبال',
      user: 'أ. مروة سعيد',
      permissions: [
        'PORTAL.VIEW', 'CHILD.VIEW_ALL', 'CHILD.CREATE', 'CHILD.EDIT',
        'GUARDIAN.MANAGE', 'APPOINTMENT.BOOK', 'APPOINTMENT.CANCEL',
        'BILLING.VIEW', 'REQUEST.MANAGE'
      ]
    },
    THERAPIST: {
      label: 'أخصائي',
      user: 'أ. سارة عبد الرحمن',
      permissions: [
        'PORTAL.VIEW', 'CHILD.VIEW_ALL', 'SESSION.START', 'SESSION.COMPLETE',
        'SESSION.NOTES.EDIT', 'REPORT.VIEW', 'REPORT.PUBLISH', 'LIVE.VIEW',
        'PLAN.MANAGE', 'GOAL.MEASURE', 'NOTE.PUBLISH'
      ]
    }
  };

  function currentRole() {
    var key;
    try { key = sessionStorage.getItem(STORE); } catch (e) { key = null; }
    return ROLES[key] ? key : null;
  }

  /* -------------------------------------------------------------------
     Sign in
     ------------------------------------------------------------------- */
  var form = document.getElementById('signinForm');
  if (form) {
    var err = document.getElementById('err');
    var chosen = 'CENTER_ADMIN';

    // The demo buttons fill the form and choose which role signs in. In the
    // real console the role comes back from the server with the session.
    [].forEach.call(document.querySelectorAll('[data-role]'), function (b) {
      b.addEventListener('click', function () {
        chosen = b.dataset.role;
        document.getElementById('f-user').value = b.dataset.role.toLowerCase();
        document.getElementById('f-pass').value = 'demo-password';
        [].forEach.call(document.querySelectorAll('[data-role]'), function (o) {
          o.classList.toggle('is-on', o === b);
        });
        err.hidden = true;
      });
    });

    var peek = document.getElementById('peek');
    if (peek) {
      peek.addEventListener('click', function () {
        var input = document.getElementById('f-pass');
        var shown = input.type === 'text';
        input.type = shown ? 'password' : 'text';
        peek.setAttribute('aria-pressed', shown ? 'false' : 'true');
      });
    }

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var user = document.getElementById('f-user').value.trim();
      var pass = document.getElementById('f-pass').value;

      // Shape only. Whether the credentials are right is hbh.verify_password's
      // answer, and this prototype has no server to ask - so an empty field is
      // the one thing it can honestly refuse.
      //
      // It names the missing field and puts the cursor in it. "Enter your
      // username and password" in front of a form where one of them is
      // already filled makes the person re-read both to find which.
      if (!user || !pass) {
        var missing = !user
          ? { el: document.getElementById('f-user'), text: 'أدخل اسم المستخدم.' }
          : { el: document.getElementById('f-pass'), text: 'أدخل كلمة المرور.' };
        err.textContent = missing.text;
        err.hidden = false;
        missing.el.focus();
        return;
      }

      try { sessionStorage.setItem(STORE, chosen); } catch (e2) { /* ignore */ }
      window.location.href = 'admin-dashboard.html';
    });
  }

  /* -------------------------------------------------------------------
     The menu follows the permissions
     ------------------------------------------------------------------- */
  var nav = document.querySelector('.hbh-nav');
  if (nav) {
    var key = currentRole();

    // Reached without signing in: send them to the login page rather than
    // showing a console with an empty menu. This is convenience, not a
    // guard - the server is what refuses an unauthenticated request.
    if (!key) {
      window.location.replace('staff-login.html');
      return;
    }

    var role = ROLES[key];
    var hidden = 0;

    [].forEach.call(nav.querySelectorAll('[data-perm]'), function (item) {
      var needed = item.dataset.perm;
      if (role.permissions.indexOf(needed) === -1) {
        item.hidden = true;
        hidden++;
      }
    });

    // Name the signed-in user and their role in the sidebar.
    var who = document.querySelector('.hbh-side__user b');
    var what = document.querySelector('.hbh-side__user small');
    if (who) { who.textContent = role.user; }
    if (what) { what.textContent = role.label; }

    // Signing out clears the role and returns to the login page. In the real
    // console it also revokes the session on the server - closing the tab is
    // not signing out.
    var out = document.querySelector('[data-signout]');
    if (out) {
      out.addEventListener('click', function (e) {
        e.preventDefault();
        try { sessionStorage.removeItem(STORE); } catch (e3) { /* ignore */ }
        window.location.href = 'staff-login.html';
      });
    }

    // A screen this role cannot reach from the menu was still opened, by a
    // typed URL or an old bookmark. Say so plainly instead of drawing a page
    // that the server would have refused to fill.
    var page = document.body.getAttribute('data-page-perm');
    if (page && role.permissions.indexOf(page) === -1) {
      var main = document.querySelector('.hbh-main');
      if (main) {
        main.innerHTML =
          '<div class="hbh-denied">' +
          '<svg class="hbh-i" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
          'stroke-linecap="round" stroke-linejoin="round"><use href="#ic-shield"/></svg>' +
          '<p class="hbh-denied__t">لا تسمح صلاحيتك بفتح هذه الشاشة</p>' +
          '<p class="hbh-denied__s">لو كنت تحتاجها في عملك، اطلبها من إدارة المركز. ' +
          'المحاولة مسجَّلة باسمك ووقتها.</p>' +
          '<a class="hbh-btn hbh-btn--ghost" href="admin-dashboard.html">العودة للوحة التحكم</a>' +
          '</div>';
      }
    }

    if (hidden) {
      // Left for whoever demonstrates this: it says the filter ran.
      console.info('[hbh] hid ' + hidden + ' menu entries for role ' + key);
    }
  }
}());
