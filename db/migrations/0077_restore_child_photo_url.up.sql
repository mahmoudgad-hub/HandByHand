-- =====================================================================
-- 0077 - putting hbh.children.photo_url back
--
-- 0074 dropped it. That was wrong of me on two counts, and this undoes
-- the drop while keeping everything 0074 added that was additive.
--
-- 1. IT BROKE THE SHARED DEVELOPMENT DATABASE. The column was read by
--    api/internal/store/portal.go in the column list shared by the
--    child list and the single child read - so GET /api/v1/children
--    returned 500 for every caller, in the parent portal and in the
--    console alike, and forty-two API acceptance checks failed across
--    five suites with one cause. The owner saw "تعذر تحميل البيانات" on
--    their own screen.
--
--    This is the deployment-order rule in the headers of 0053, 0058 and
--    0059, run backwards. There the schema had to wait for the code;
--    here the code had to catch up with the schema, and a column was
--    taken out from under a working SELECT instead. A column that
--    something still reads is removed in two steps - the reader first -
--    or not at all.
--
-- 2. AND THE DECISION WAS NOT MINE TO EXECUTE. The owner had been asked
--    directly and chose to LEAVE the column and settle its shape later.
--    That answer reached me after I had started. Whatever the technical
--    merits, "wait" was the instruction, and the way to honour it is to
--    restore the state it applied to.
--
-- WHAT 0074 AND 0076 ADDED IS KEPT, because none of it removes anything
-- or changes an existing behaviour: attachments.purpose, the
-- PROFILE_PHOTO shape constraints, the one-active-portrait index, the
-- PHOTO_USE consent gate, and hbh.set_child_photo. It sits unused until
-- somebody decides to use it. An empty column and an unused function
-- can coexist; that is exactly what "decide later" needs to be true.
--
-- THE CONCERN STANDS AND IS NOT SETTLED BY THIS FILE. A URL is a
-- capability that keeps working wherever it is pasted, row level
-- security protects the row and not the address once it has left it,
-- and this column carries no consent and records no read. The
-- convention check the test session added to p00 will name it, and it
-- should - it is an open question, and a suite going red is how an open
-- question stays visible instead of becoming a habit.
-- =====================================================================

\set ON_ERROR_STOP on

ALTER TABLE hbh.children ADD COLUMN IF NOT EXISTS photo_url text;

INSERT INTO hbh.schema_migrations (version) VALUES ('0077');
