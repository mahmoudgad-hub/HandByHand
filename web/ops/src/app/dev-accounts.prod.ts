import { DevAccount } from '@hbh/shared/config/app-config';

/**
 * No sign-in shortcuts in a production build. This file replaces
 * dev-accounts.ts through `fileReplacements` in angular.json.
 *
 * IT IS A FILE RATHER THAN A FLAG ON PURPOSE. A flag still compiles the
 * credentials into the bundle and then decides not to draw them - which is
 * what the console did until now, and why `hbh-dev-console-2026` was
 * readable in the JavaScript served from ops.hbhskills.com. A reader who
 * cannot see the button downloads the file.
 *
 * The replacement removes the string from the artefact. There is nothing to
 * hide, because there is nothing there.
 *
 * The login screen renders no shortcut block for an empty list, and that
 * check stays - it is what makes this file enough on its own.
 */
export const DEV_ACCOUNTS: readonly DevAccount[] = [];
