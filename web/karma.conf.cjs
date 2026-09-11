// Karma, for all three Angular projects.
//
// Deliberately minimal: the @angular/build:karma builder supplies the
// framework, the plugins and the entry point. Everything set here is
// something the builder's defaults get wrong for THIS environment, and
// nothing else - a config that restates defaults is a second place to
// keep them in step.
//
// IT EXISTS FOR TWO REASONS, AND THE SECOND IS THE IMPORTANT ONE.
//
// 1. CHROME WILL NOT RUN AS ROOT WITHOUT --no-sandbox, and every one of
//    these containers runs as root. Without the flag the launcher prints
//
//        Running as root without --no-sandbox is not supported
//        ChromeHeadless failed 2 times. Giving up.
//
//    and the command still exits 0. So `npm test` reported "passed"
//    three times in a row having run no test at all. The flag belongs
//    here, in the configuration every project loads, and not in a shell
//    wrapper - a wrapper lives in one person's terminal and leaves with
//    the session that wrote it.
//
// 2. A RUN THAT RUNS NOTHING IS A FAILURE. That is what let the first
//    problem hide: an empty result and a green result looked identical.
//    failOnEmptyTestSuite makes zero specs an error - which is how the
//    operations console, with no .spec.ts file anywhere in it, has been
//    reported as passing for as long as it has existed.
//
//    Same shape as three other tools in two days: a stamping script that
//    matched no files and exited 0, a grep that answered a question
//    nobody asked, and this one. THE TOOL ANSWERS WHAT IT WAS ASKED and
//    does not know what was meant, so the check has to be that something
//    actually happened - not that nothing complained.
//
// 3. And it runs INSIDE the web container. node_modules there is a Linux
//    build in a named volume; running the suite from the host reaches an
//    esbuild binary for the wrong platform.
module.exports = function (config) {
  config.set({
    // Declared because supplying a karmaConfig replaces the builder's
    // defaults rather than adding to them: without this the browser
    // connects, loads the specs, and every one of them dies on
    // "describe is not defined" - which reads as broken tests rather
    // than as a missing framework.
    frameworks: ['jasmine'],
    browsers: ['ChromeHeadlessNoSandbox'],
    customLaunchers: {
      ChromeHeadlessNoSandbox: {
        base: 'ChromeHeadless',
        // --no-sandbox: root, as above.
        // --disable-dev-shm-usage: /dev/shm is 64 MB in a default
        //   container and Chrome dies part-way through a suite when it
        //   fills - which reads as a flaky test rather than a full disk.
        flags: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
      },
    },
    // Zero specs is a failure, not a pass. See (2) above.
    failOnEmptyTestSuite: true,
  });
};
