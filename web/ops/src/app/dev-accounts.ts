import { DevAccount } from '@hbh/shared/config/app-config';

/**
 * Sign-in shortcuts, for development only.
 *
 * These are working credentials in a file the browser downloads. They exist
 * because a console tested as the administrator alone hides every permission
 * bug in it - clicking between roles is how the difference becomes visible.
 *
 * THIS FILE IS REPLACED IN A PRODUCTION BUILD by dev-accounts.prod.ts, which
 * exports an empty list. That replacement is declared in angular.json under
 * the `production` configuration, and it is the reason the password below
 * never reaches a shipped bundle.
 *
 * IT USED NOT TO BE. The comment that stood here claimed two protections -
 * a production config that omitted the list, and a screen that refuses to
 * draw it off a local address. Only the second existed. So the string was
 * compiled into every build, including the one served at ops.hbhskills.com,
 * where it was found by searching the public main-*.js for it:
 *
 *	"dev_admin" · "dev_reception" · "dev_therapist" · "hbh-dev-console-2026"
 *
 * `isLocal()` hides the BUTTONS. It cannot hide a string the bundler has
 * already written into the file. A comment describing a guard that was never
 * built is worse than no comment: it is the reason nobody looked.
 *
 * AND THE PASSWORD STILL SHOULD NOT BE HERE. db/dev/staff_accounts.sql makes
 * the argument in its own header - "a staff account with a password sitting
 * in the repository is not a seed, it is a door" - and takes its value from
 * the environment. This file contradicted that. Removing it from the
 * production bundle closes the hole that fired; taking it out of the
 * repository altogether is the next step and is the owner's call, because it
 * means every developer sets an environment variable before the shortcuts
 * work.
 *
 * The accounts themselves come from db/dev/staff_accounts.sql, which
 * `db.sh migrate` does not run:
 *
 *	DEV_STAFF_PASSWORD='...' bash scripts/db.sh dev-user
 *
 * THE VALUE BELOW MUST MATCH WHAT THAT COMMAND WAS GIVEN. It did not, for a
 * while, and the two never meet: the buttons sent one string, the database
 * held another, and every press counted as a failed attempt until the
 * account locked itself for fifteen minutes. The screen then said "locked",
 * which reads as a fault and is in fact the protection working exactly as
 * designed - and hides the real cause completely.
 *
 * The centre has four roles - CENTER_ADMIN, RECEPTION, THERAPIST, GUARDIAN -
 * and there is no separate "admin" above them: CENTER_ADMIN is the highest.
 * GUARDIAN belongs to the parent portal and cannot sign in here at all.
 */
const DEV_PASSWORD = 'hbh-dev-console-2026';

export const DEV_ACCOUNTS: readonly DevAccount[] = [
  { username: 'dev_admin', password: DEV_PASSWORD, roleKey: 'role.CENTER_ADMIN' },
  { username: 'dev_reception', password: DEV_PASSWORD, roleKey: 'role.RECEPTION' },
  // The therapist account carries a row in hbh.therapists as well as a
  // user. Without it the account is a role with no caseload - caseload,
  // appointments and sessions all key on therapist_id, never on user_id -
  // so it would sign in owning nothing, and test the permission map
  // against an empty day.
  { username: 'dev_therapist', password: DEV_PASSWORD, roleKey: 'role.THERAPIST' },
  /*
   * "Admin", asked for by name and wired to work.
   *
   * It signs in as dev_admin, and that is not a shortcut - it is what the
   * word means in this system. db/seed/0002_rbac.sql gives the username
   * `admin` the CENTER_ADMIN role, the same nineteen permissions dev_admin
   * holds. There is no higher role to reach.
   */
  { username: 'dev_admin', password: DEV_PASSWORD, roleKey: 'role.ADMIN' },
];
